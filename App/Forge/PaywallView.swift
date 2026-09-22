import SwiftUI
import SwiftData
import RevenueCat

struct PaywallView: View {
  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
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
    case .expired: return String(localized: "Your access lapsed. Pick a plan to keep the coach.", bundle: L10n.bundle)
    case .grace: return String(localized: "Payment issue. Update it to keep training.", bundle: L10n.bundle)
    default: return copy.subline
    }
  }

  private var ctaTitle: String {
    store.status == .expired || store.status == .grace ? String(localized: "Continue", bundle: L10n.bundle) : String(localized: "Start free trial", bundle: L10n.bundle)
  }

  private var price: String {
    priceText(annual ? store.annual : store.monthly, annual ? "$79.99/yr" : "$12.99/mo")
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        VStack(spacing: 8) {
          CoachPhoto(name: coach.point, height: 260)
            .accessibilityHidden(true)
          Text(variant == "B" ? copy.headline : String(localized: "Train with \(coach.name)", bundle: L10n.bundle)).forgeGreeting()
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
                  Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                  Text(line).forgeBody()
                }
                .accessibilityElement(children: .combine)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
          }
        }
        VStack(spacing: 8) {
          benefit(String(localized: "Auto-regulated loads", bundle: L10n.bundle), String(localized: "Loads adapt every set", bundle: L10n.bundle), symbol: "slider.horizontal.3")
          benefit(String(localized: "Coach in your pocket", bundle: L10n.bundle), String(localized: "Ask, swap, understand", bundle: L10n.bundle), symbol: "message.fill")
        }
        .card()
        VStack(spacing: 8) {
          SelectCard(
            title: String(localized: "Annual", bundle: L10n.bundle),
            subtitle: priceText(store.annual, "$79.99/yr"),
            symbol: "calendar",
            selected: annual,
            action: { withAnimation(.snappy) { annual = true } },
            badge: copy.annualBadge)
          SelectCard(
            title: String(localized: "Monthly", bundle: L10n.bundle),
            subtitle: priceText(store.monthly, "$12.99/mo"),
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
          .accessibilityElement(children: .combine)
        }
        .buttonStyle(PillButtonStyle())
        .disabled(buying)
        Text("14 days free, then \(price) · Cancel anytime")
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
            try? modelContext.save()
        }
        .forgeCaption()
        #endif
      }
      .padding(.horizontal, Theme.barMargin)
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
        .foregroundStyle(Theme.accent)
        .frame(width: 36, height: 36)
        .background(Circle().fill(Theme.accentTint))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeBodyStrong()
        Text(subtitle).forgeCaption()
      }
      Spacer()
    }
    .innerSurface()
    .accessibilityElement(children: .combine)
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
          try? modelContext.save()
            Analytics.track("trial_started")
          dismiss()
        }
      } catch {
        errorText = error.localizedDescription
      }
    }
  }
}
