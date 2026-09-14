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
  var body: some View {
    VStack(spacing: 20) {
      Text("Forge Pro")
        .font(.largeTitle.bold())
        .padding(.top, 40)
      planCard(title: "Annual", price: priceText(Store.annualID, "$119.99/yr"), note: "Save 50%", selected: annual) { annual = true }
      planCard(title: "Monthly", price: priceText(Store.monthlyID, "$19.99/mo"), note: "", selected: !annual) { annual = false }
      Button { buy() } label: {
        Text(buying ? "Purchasing…" : "Start 7-day free trial")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .disabled(buying)
      Button("Restore purchases") {
        Task {
          await store.restore()
          if store.isSubscribed { profiles.first?.trialStartedAt = .now }
        }
      }
      .font(.subheadline)
      if let errorText {
        Text(errorText).font(.footnote).foregroundStyle(.red)
      }
      Text("7 days free, then billed. Cancel anytime.")
        .font(.footnote)
        .foregroundStyle(.secondary)
      #if DEBUG
      Button("Continue without purchase") {
        profiles.first?.trialStartedAt = .now
      }
      .font(.footnote)
      #endif
      Spacer()
    }
    .padding()
    .task { await store.load() }
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

  private func planCard(title: String, price: String, note: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(title).font(.headline)
            if !note.isEmpty {
              Text(note)
                .font(.caption.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.2))
                .foregroundStyle(.orange)
            }
          }
          Text(price).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selected ? Color.accentColor : Color.secondary)
      }
      .padding()
      .background(selected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
