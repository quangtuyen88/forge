import Foundation
import RevenueCat
import Observation

enum SubStatus: Equatable {
  case none
  case trial(ends: Date)
  case active(renews: Date?)
  case grace
  case expired
}

@MainActor @Observable final class Store {
  static let monthlyID = "app.regulift.monthly"
  static let annualID = "app.regulift.annual"
  nonisolated static var notConfiguredMessage: String { String(localized: "Purchases are not configured in this build", bundle: L10n.bundle) }

static var revenueCatKey: String? {
    AppConfig.value("REVENUECAT_API_KEY")
  }

  static var usesTestStore: Bool {
  revenueCatKey?.hasPrefix("test_") == true
  }

  private enum StoreError: LocalizedError {
    case notConfigured
    var errorDescription: String? { Store.notConfiguredMessage }
  }

  private(set) var isConfigured = false
  var products: [Package] = []
  var isSubscribed = false
  var status: SubStatus = .none
  /// Whether the active entitlement was purchased on the App Store (not granted as a promo).
  private var activeEntitlementFromAppStore = false

  var monthly: Package? {
    products.first { $0.storeProduct.productIdentifier == Self.monthlyID }
      ?? products.first { $0.packageType == .monthly }
  }
  var annual: Package? {
    products.first { $0.storeProduct.productIdentifier == Self.annualID }
      ?? products.first { $0.packageType == .annual }
  }

  init() {
    #if !DEBUG
    precondition(!Self.usesTestStore, "A RevenueCat Test Store key must never ship in Release")
    #endif
    guard let key = Self.revenueCatKey else { return }
    #if DEBUG
    Purchases.logLevel = .debug
    #endif
    Purchases.configure(with: .builder(withAPIKey: key).with(storeKitVersion: .storeKit2).build())
    isConfigured = true
  }

  func priceText(for package: Package?) -> String? {
    guard let p = package else { return nil }
    return "\(p.storeProduct.localizedPriceString)/\(p.storeProduct.subscriptionPeriod?.unit == .year ? "yr" : "mo")"
  }

  func load() async {
    guard isConfigured else { return }
    if let offerings = try? await Purchases.shared.offerings(), let current = offerings.current {
      products = current.availablePackages
    }
    await refresh()
  }

  func refresh() async {
    guard isConfigured, let info = try? await Purchases.shared.customerInfo() else { return }
    apply(info)
  }

  private func apply(_ info: CustomerInfo) {
    var next: SubStatus = .none
    var subscribed = false
    var fromAppStore = false
    let activeEntitlement = info.entitlements.active["regulift_pro"]
      ?? info.entitlements.active["pro"]
    let entitlement = activeEntitlement
      ?? info.entitlements.all["regulift_pro"]
      ?? info.entitlements.all["pro"]
    if let entitlement {
      if activeEntitlement != nil || entitlement.isActive {
        subscribed = true
        fromAppStore = entitlement.store == RevenueCat.Store.appStore
        if entitlement.periodType == .trial {
          next = .trial(ends: entitlement.expirationDate ?? .now)
        } else if entitlement.billingIssueDetectedAt != nil {
          next = .grace
        } else {
          next = .active(renews: entitlement.expirationDate)
        }
      } else {
        next = .expired
      }
    }
    status = next
    isSubscribed = subscribed
    activeEntitlementFromAppStore = fromAppStore
  }

  func purchase(_ package: Package) async throws -> Bool {
    guard isConfigured else { throw StoreError.notConfigured }
    let result = try await Purchases.shared.purchase(package: package)
    if result.userCancelled { return false }
    apply(result.customerInfo)
    return isSubscribed
  }

  enum RestoreOutcome {
    case restored
    case nothingToRestore
    case failed(String)
  }

  /// True while the App Store sheet stays useful: an active, trial or billing-grace subscription.
  var canManageSubscription: Bool {
    switch status {
    case .trial, .active, .grace: return activeEntitlementFromAppStore
    case .none, .expired: return false
    }
  }

  func isEligibleForIntroOffer(on package: Package) async -> Bool {
    guard isConfigured else { return true }
    let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(product: package.storeProduct)
    return eligibility != .ineligible && eligibility != .noIntroOfferExists
  }

  @discardableResult func restore() async -> RestoreOutcome {
    guard isConfigured else {
      return .failed(String(localized: "Purchases aren't available in this build.", bundle: L10n.bundle))
    }
    do {
      let info = try await Purchases.shared.restorePurchases()
      apply(info)
      return isSubscribed ? .restored : .nothingToRestore
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  func listen() -> Task<Void, Never> {
    guard isConfigured else { return Task {} }
    return Task {
      for await info in Purchases.shared.customerInfoStream {
        apply(info)
      }
    }
  }

  func logIn(userID: String) async {
    guard isConfigured else { return }
    _ = try? await Purchases.shared.logIn(userID)
    await refresh()
  }

  func logOut() async {
    guard isConfigured else { return }
    _ = try? await Purchases.shared.logOut()
    await refresh()
  }

  func setAttributes(referralCode: String?, promoCode: String?) {
    guard isConfigured else { return }
    var attrs: [String: String] = [:]
    if let referralCode { attrs["referral_code"] = referralCode }
    if let promoCode { attrs["promo_code"] = promoCode }
    guard !attrs.isEmpty else { return }
    Purchases.shared.attribution.setAttributes(attrs)
  }
}
