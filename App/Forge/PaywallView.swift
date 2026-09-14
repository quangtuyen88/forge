import SwiftUI
import SwiftData

struct PaywallView: View {
  @Query private var profiles: [UserProfile]
  @State private var annual = true

  // ponytail: local flag stands in for StoreKit 2/RevenueCat; wire real purchase before TestFlight.
  var body: some View {
    VStack(spacing: 20) {
      Text("Forge Pro")
        .font(.largeTitle.bold())
        .padding(.top, 40)
      planCard(title: "Annual", price: "$119.99/yr", note: "Save 50%", selected: annual) { annual = true }
      planCard(title: "Monthly", price: "$19.99/mo", note: "", selected: !annual) { annual = false }
      Button {
        profiles.first?.trialStartedAt = .now
      } label: {
        Text("Start 7-day free trial")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      Text("7 days free, then billed. Cancel anytime.")
        .font(.footnote)
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding()
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
