import StoreKit
import Observation

@MainActor @Observable final class Store {
  static let monthlyID = "com.vnbnode.forge.monthly"
  static let annualID = "com.vnbnode.forge.annual"
  var products: [Product] = []
  var isSubscribed = false

  func load() async {
    products = (try? await Product.products(for: [Self.monthlyID, Self.annualID])) ?? []
    await refresh()
  }

  func refresh() async {
    for await entitlement in Transaction.currentEntitlements {
      if case .verified(let t) = entitlement, t.productID == Self.monthlyID || t.productID == Self.annualID {
        isSubscribed = true
        return
      }
    }
    isSubscribed = false
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
