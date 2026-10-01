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
  @State private var trialEligible = true
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue

  private var coach: Coach { Coach.from(coachID) }
  private var copy: PaywallCopy { RemoteConfig.shared.paywall }
  private var variant: String { copy.variant }

  private var heroSubtitle: String {
    switch store.status {
    case .expired: return String(localized: "Your access lapsed. Pick a plan to keep the coach.", bundle: L10n.bundle)
    case .grace: return String(localized: "Payment issue. Update it to keep training.", bundle: L10n.bundle)
    default:
      return showsTrial
        ? copy.subline
        : String(localized: "Week 1 is built. Pick a plan to start lifting.", bundle: L10n.bundle)
    }
  }

  private var selectedPackage: Package? { annual ? store.annual : store.monthly }

  /// The intro offer's length in days; 14 only until the products have loaded.
  private var trialDays: Int {
    guard let period = selectedPackage?.storeProduct.introductoryDiscount?.subscriptionPeriod else { return 14 }
    switch period.unit {
    case .week: return max(1, period.value * 7)
    case .month: return max(1, period.value * 30)
    case .year: return max(1, period.value * 365)
    default: return max(1, period.value)
    }
  }

  /// The free-trial promise is kept only while the person can still claim the intro offer.
  private var showsTrial: Bool {
    store.status != .expired && store.status != .grace && trialEligible
  }

  private var ctaTitle: String {
    showsTrial ? String(localized: "Start free trial", bundle: L10n.bundle) : String(localized: "Continue", bundle: L10n.bundle)
  }

  private var heroHeadline: String {
    if !showsTrial {
      return String(localized: "Train with \(coach.name)", bundle: L10n.bundle)
    }
    return variant == "B" ? copy.headline : String(localized: "Your first \(trialDays) days are free", bundle: L10n.bundle)
  }

  private var showsTrialTimeline: Bool {
    store.status != .expired && store.status != .grace
  }

  private var price: String {
    priceText(annual ? store.annual : store.monthly, annual ? "$79.99/yr" : "$12.99/mo")
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        VStack(spacing: 8) {
          CoachPhoto(name: coach.point, height: 200)
            .accessibilityHidden(true)
          Text(heroHeadline).forgeGreeting().multilineTextAlignment(.center)
          Text(heroSubtitle)
            .forgeLabel()
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        if showsTrialTimeline {
          trialTimeline
        }
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
            if buying {
              ProgressView()
                .accessibilityLabel(showsTrial ? String(localized: "Starting your trial", bundle: L10n.bundle) : String(localized: "Purchasing", bundle: L10n.bundle))
            }
            Text(ctaTitle)
          }
          .accessibilityElement(children: .combine)
        }
        .buttonStyle(PillButtonStyle())
        .disabled(buying)
        Text(showsTrial
          ? String(localized: "\(trialDays) days free, then \(price) · Cancel anytime", bundle: L10n.bundle)
          : String(localized: "\(price) billed today · Cancel anytime", bundle: L10n.bundle))
          .forgeCaption()
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 16) {
            restorePurchasesButton
            privacyPolicyLink
            termsLink
          }
          VStack(alignment: .leading, spacing: 0) {
            restorePurchasesButton
            privacyPolicyLink
            termsLink
          }
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
      await refreshTrialEligibility()
      Analytics.track("paywall_shown", ["variant": variant])
    }
    .task(id: annual) {
      await refreshTrialEligibility()
    }
  }

  private func refreshTrialEligibility() async {
    guard let package = selectedPackage else { return }
    trialEligible = await store.isEligibleForIntroOffer(on: package)
  }

  private var restorePurchasesButton: some View {
    Button {
      Analytics.track("paywall_restore")
      Task {
        switch await store.restore() {
        case .restored:
          errorText = String(localized: "Purchases restored.", bundle: L10n.bundle)
        case .nothingToRestore:
          errorText = String(localized: "No purchases to restore.", bundle: L10n.bundle)
        case .failed(let message):
          errorText = message
        }
        if store.isSubscribed { profiles.first?.trialStartedAt = .now }
      }
    } label: {
      Text("Restore purchases")
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
  }

  private var privacyPolicyLink: some View {
    Link(destination: Theme.privacyPolicyURL) {
      Text("Privacy Policy")
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
  }

  private var termsLink: some View {
    Link(destination: Theme.termsURL) {
      Text("Terms")
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
    }
  }

  /// Lyfta trial timeline: the 2pt connector grows below the first circle to meet the second.
  private var trialTimeline: some View {
    VStack(alignment: .leading, spacing: 0) {
      if showsTrial {
        timelineRow(
          symbol: "lock.open.fill",
          title: String(localized: "Today", bundle: L10n.bundle),
          detail: String(localized: "Full access. Week 1 starts.", bundle: L10n.bundle),
          connectsDown: true)
        timelineRow(
          symbol: "creditcard.fill",
          title: billDateText,
          detail: String(localized: "\(price) billed. Cancel any time before then in Settings.", bundle: L10n.bundle),
          connectsDown: false)
      } else {
        timelineRow(
          symbol: "creditcard.fill",
          title: String(localized: "Today", bundle: L10n.bundle),
          detail: String(localized: "\(price) billed today. Cancel any time in Settings.", bundle: L10n.bundle),
          connectsDown: false)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
    .accessibilityIdentifier("paywall-trial-timeline")
  }

  private func timelineRow(symbol: String, title: String, detail: String, connectsDown: Bool) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(spacing: 0) {
        ZStack {
          Circle().fill(Theme.accent).frame(width: 28, height: 28)
          Image(systemName: symbol)
            .scaledSystemFont(12, weight: .semibold)
            .foregroundStyle(Theme.onAccent)
        }
        if connectsDown {
          Rectangle().fill(Theme.accent).frame(width: 2).frame(maxHeight: .infinity)
        }
      }
      .frame(width: 28)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeBodyStrong()
        Text(detail).forgeLabel().fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    // The rail fills this row's height, so the pad is what carries it down to the next circle.
    .padding(.bottom, connectsDown ? 12 : 0)
    .accessibilityElement(children: .combine)
  }

  private var billDateText: String {
    let date = Calendar.current.date(byAdding: .day, value: trialDays, to: .now) ?? .now
    return date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
  }

  private func benefit(_ title: String, _ subtitle: String, symbol: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .scaledSystemFont(15, weight: .semibold)
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
