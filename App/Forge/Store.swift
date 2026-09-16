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
  static let notConfiguredMessage = "Purchases are not configured in this build"

  static var revenueCatKey: String? {
    let v = (Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (v?.isEmpty ?? true) ? nil : v
  }

  private enum StoreError: LocalizedError {
    case notConfigured
    var errorDescription: String? { Store.notConfiguredMessage }
  }

  private(set) var isConfigured = false
  var products: [Package] = []
  var isSubscribed = false
  var status: SubStatus = .none

  var monthly: Package? {
    products.first { $0.storeProduct.productIdentifier == Self.monthlyID }
      ?? products.first { $0.packageType == .monthly }
  }
  var annual: Package? {
    products.first { $0.storeProduct.productIdentifier == Self.annualID }
      ?? products.first { $0.packageType == .annual }
  }

  init() {
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
    if let entitlement = info.entitlements["pro"] {
      if entitlement.isActive {
        subscribed = true
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
  }

  func purchase(_ package: Package) async throws -> Bool {
    guard isConfigured else { throw StoreError.notConfigured }
    let result = try await Purchases.shared.purchase(package: package)
    if result.userCancelled { return false }
    await refresh()
    return isSubscribed
  }

  func restore() async {
    guard isConfigured else { return }
    _ = try? await Purchases.shared.restorePurchases()
    await refresh()
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
