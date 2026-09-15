import StoreKit
import Observation

enum SubStatus: Equatable {
  case none
  case trial(ends: Date)
  case active(renews: Date?)
  case grace
  case expired
}

@MainActor @Observable final class Store {
  static let monthlyID = "com.vnbnode.forge.monthly"
  static let annualID = "com.vnbnode.forge.annual"
  var products: [Product] = []
  var isSubscribed = false
  var status: SubStatus = .none

  private var productIDs: Set<String> { [Self.monthlyID, Self.annualID] }

  func load() async {
    products = (try? await Product.products(for: [Self.monthlyID, Self.annualID])) ?? []
    await refresh()
  }

  func refresh() async {
    var next: SubStatus = .none
    var subscribed = false
    var owned = false
    for await entitlement in Transaction.currentEntitlements {
      guard case .verified(let t) = entitlement, productIDs.contains(t.productID), t.revocationDate == nil else { continue }
      owned = true
      subscribed = true
      var introductory = false
      if #available(iOS 17.2, *) { introductory = t.offer?.type == .introductory }
      next = introductory
        ? .trial(ends: t.expirationDate ?? .now)
        : .active(renews: t.expirationDate)
    }
    if !owned {
      for await record in Transaction.all {
        if case .verified(let t) = record, productIDs.contains(t.productID), t.revocationDate == nil,
           let expiration = t.expirationDate, expiration < .now {
          next = .expired
        }
      }
    }
    for product in products {
      guard let subscription = product.subscription,
            let statuses = try? await subscription.status else { continue }
      if statuses.contains(where: { $0.state == .inGracePeriod }) {
        next = .grace
        subscribed = true
      }
    }
    status = next
    isSubscribed = subscribed
  }

  func purchase(_ p: Product) async throws -> Bool {
    let result = try await p.purchase()
    guard case .success(let verification) = result, case .verified(let t) = verification else { return false }
    await t.finish()
    await refresh()
    return isSubscribed
  }

  func restore() async {
    try? await AppStore.sync()
    await refresh()
  }

  func listen() -> Task<Void, Never> {
    Task {
      for await update in Transaction.updates {
        if case .verified(let t) = update { await t.finish() }
        await refresh()
      }
    }
  }
}
