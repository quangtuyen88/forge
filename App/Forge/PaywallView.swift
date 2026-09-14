import SwiftUI
import SwiftData
import StoreKit

struct PaywallView: View {
  @Environment(Store.self) private var store
  @Query private var profiles: [UserProfile]
  @State private var annual = true
  @State private var buying = false
  @State private var errorText: String?

  // ponytail: StoreKit 2 covers the need; RevenueCat can wrap this later.

  private var price: String {
    priceText(annual ? Store.annualID : Store.monthlyID, annual ? "$119.99/yr" : "$19.99/mo")
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        VStack(spacing: 8) {
          Illustration(name: "art-pro", height: 180)
          Text("Forge Pro").font(.largeTitle.bold())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        VStack(spacing: 16) {
          benefit("Auto-regulated loads", "Loads adapt every set", symbol: "slider.horizontal.3")
          benefit("Fatigue-aware days", "Light days when needed", symbol: "speedometer")
          benefit("Coach in your pocket", "Ask, swap, understand", symbol: "message.fill")
        }
        .padding(.horizontal, 8)
        VStack(spacing: 8) {
          SelectCard(
            title: "Annual",
            subtitle: priceText(Store.annualID, "$119.99/yr"),
            symbol: "calendar",
            selected: annual,
            action: { withAnimation(.snappy) { annual = true } },
            badge: "SAVE 50%")
          SelectCard(
            title: "Monthly",
            subtitle: priceText(Store.monthlyID, "$19.99/mo"),
            symbol: "clock",
            selected: !annual,
            action: { withAnimation(.snappy) { annual = false } })
        }
      }
      .padding(16)
    }
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 8) {
        if let errorText {
          Text(errorText).font(.footnote).foregroundStyle(.red)
        }
        Button {
          buy()
        } label: {
          HStack(spacing: 8) {
            if buying { ProgressView() }
            Text("Start free trial")
          }
        }
        .buttonStyle(PillButtonStyle())
        .disabled(buying)
        Text("7 days free, then \(price) · Cancel anytime")
          .font(.footnote)
          .foregroundStyle(.secondary)
        HStack(spacing: 16) {
          Button("Restore purchases") {
            Task {
              await store.restore()
              if store.isSubscribed { profiles.first?.trialStartedAt = .now }
            }
          }
          Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
        }
        .font(.footnote)
        #if DEBUG
        Button("Continue without purchase") {
          profiles.first?.trialStartedAt = .now
        }
        .font(.caption)
        #endif
      }
      .padding(16)
      .background(.bar)
    }
    .background(Color(.systemGroupedBackground))
    .task { await store.load() }
  }

  private func benefit(_ title: String, _ subtitle: String, symbol: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.title2)
        .foregroundStyle(Theme.accent)
        .frame(width: 32)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline)
        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
      }
      Spacer()
    }
  }

  private func priceText(_ id: String, _ fallback: String) -> String {
    guard let p = store.products.first(where: { $0.id == id }) else { return fallback }
    return "\(p.displayPrice)/\(p.subscription?.subscriptionPeriod.unit == .year ? "yr" : "mo")"
  }

  private func buy() {
    guard let product = store.products.first(where: { $0.id == (annual ? Store.annualID : Store.monthlyID) }) else { return }
    buying = true
    errorText = nil
    Task {
      defer { buying = false }
      do {
        if try await store.purchase(product) { profiles.first?.trialStartedAt = .now }
      } catch {
        errorText = error.localizedDescription
      }
    }
  }
}
