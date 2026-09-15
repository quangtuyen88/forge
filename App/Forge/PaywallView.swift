import SwiftUI
import SwiftData
import RevenueCat

struct PaywallView: View {
  @Environment(Store.self) private var store
  @Query private var profiles: [UserProfile]
  @State private var annual = true
  @State private var buying = false
  @State private var errorText: String?
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue

  private var coach: Coach { Coach.from(coachID) }
  private var copy: PaywallCopy { RemoteConfig.shared.paywall }
  private var variant: String { copy.variant }

  private var heroSubtitle: String {
    switch store.status {
    case .expired: return "Your access lapsed. Pick a plan to keep the coach."
    case .grace: return "Payment issue. Update it to keep training."
    default: return copy.subline
    }
  }

  private var ctaTitle: String {
    store.status == .expired || store.status == .grace ? "Continue" : "Start free trial"
  }

  private var price: String {
    priceText(annual ? store.annual : store.monthly, annual ? "$119.99/yr" : "$19.99/mo")
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        VStack(spacing: 8) {
          CoachPhoto(name: coach.point, height: 260)
          Text(variant == "B" ? copy.headline : "Train with \(coach.name)").forgeGreeting()
          Text(heroSubtitle)
            .forgeLabel()
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        if let profile = profiles.first {
          let lines = Array(Personalization.lines(for: profile.profileInput).prefix(4))
          if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              Text("Built for you").forgeSection()
              ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                  Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.accent)
                  Text(line).forgeBody()
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
          }
        }
        VStack(spacing: 8) {
          benefit("Auto-regulated loads", "Loads adapt every set", symbol: "slider.horizontal.3")
          benefit("Coach in your pocket", "Ask, swap, understand", symbol: "message.fill")
        }
        .card()
        VStack(spacing: 8) {
          SelectCard(
            title: "Annual",
            subtitle: priceText(store.annual, "$119.99/yr"),
            symbol: "calendar",
            selected: annual,
            action: { withAnimation(.snappy) { annual = true } },
            badge: copy.annualBadge)
          SelectCard(
            title: "Monthly",
            subtitle: priceText(store.monthly, "$19.99/mo"),
            symbol: "clock",
            selected: !annual,
            action: { withAnimation(.snappy) { annual = false } })
        }
      }
      .padding(Theme.margin)
    }
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 8) {
        if let errorText {
          Text(errorText).foregroundStyle(Theme.negative).forgeCaption()
        }
        Button {
          buy()
        } label: {
          HStack(spacing: 8) {
            if buying { ProgressView() }
            Text(ctaTitle)
          }
        }
        .buttonStyle(PillButtonStyle())
        .disabled(buying)
        Text("7 days free, then \(price) · Cancel anytime")
          .forgeCaption()
        HStack(spacing: 16) {
          Button("Restore purchases") {
            Analytics.track("paywall_restore")
            Task {
              await store.restore()
              if store.isSubscribed { profiles.first?.trialStartedAt = .now }
            }
          }
          Link("Privacy Policy", destination: Theme.privacyPolicyURL)
          Link("Terms", destination: Theme.termsURL)
        }
        .forgeCaption()
        #if DEBUG
        Button("Continue without purchase") {
          profiles.first?.trialStartedAt = .now
        }
        .forgeCaption()
        #endif
      }
      .padding(.horizontal, Theme.margin)
      .padding(.vertical, 10)
      .background(Theme.page.opacity(0.92))
      .background(.ultraThinMaterial)
    }
    .background(Theme.page)
    .task {
      await store.load()
      await RemoteConfig.shared.refresh()
      Analytics.track("paywall_shown", ["variant": variant])
    }
  }

  private func benefit(_ title: String, _ subtitle: String, symbol: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(Theme.accent)
        .frame(width: 36, height: 36)
        .background(Circle().fill(Theme.accent.opacity(0.12)))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeBodyStrong()
        Text(subtitle).forgeCaption()
      }
      Spacer()
    }
    .innerSurface()
  }

  private func priceText(_ package: Package?, _ fallback: String) -> String {
    store.priceText(for: package) ?? fallback
  }

  private func buy() {
    guard let package = annual ? store.annual : store.monthly else {
      if !store.isConfigured { errorText = Store.notConfiguredMessage }
      return
    }
    buying = true
    errorText = nil
    Task {
      defer { buying = false }
      do {
        if try await store.purchase(package) {
          profiles.first?.trialStartedAt = .now
          Analytics.track("trial_started")
        }
      } catch {
        errorText = error.localizedDescription
      }
    }
  }
}
