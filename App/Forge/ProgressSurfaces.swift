import SwiftUI
import ForgeCore

// Progress components on the Today sky (DESIGN.md §12). No gradient or shadow code here.

/// 1. A white card that floats on the sky; optional full-bleed footer strip
/// shares the card's bottom rounded corners.
struct SkyCard<Content: View, Footer: View>: View {
  private let padding: CGFloat
  private let content: Content
  private let footer: Footer

  init(padding: CGFloat = 16, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
    self.padding = padding
    self.content = content()
    self.footer = footer()
  }

  init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) where Footer == EmptyView {
    self.init(padding: padding, content: content, footer: { EmptyView() })
  }

  var body: some View {
    VStack(spacing: 0) {
      content
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
      footer
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous))
    .todayCard(padding: 0)
  }
}

/// 2. Full-bleed strip that sits flush at the bottom of a SkyCard.
struct FooterStrip: View {
  private let symbol: String
  private let title: LocalizedStringKey
  private let detail: String?
  private let showsChevron: Bool

  init(symbol: String, title: LocalizedStringKey, detail: String? = nil, showsChevron: Bool = true) {
    self.symbol = symbol
    self.title = title
    self.detail = detail
    self.showsChevron = showsChevron
  }

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: symbol)
      Text(title)
      Spacer(minLength: 8)
      if let detail {
        Text(detail)
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
      if showsChevron {
        Image(systemName: "chevron.forward")
      }
    }
    .forge(15, .semibold)
    .foregroundStyle(Theme.accentText)
    .todayFooterStrip()
    .contentShape(Rectangle())
  }
}

/// 3. Capsule pill for short facts and states.
struct SkyPill: View {
  enum Style { case neutral, accent, gold, green, orange }

  private let text: String
  private let symbol: String?
  private let style: Style

  init(_ text: String, symbol: String? = nil, style: Style) {
    self.text = text
    self.symbol = symbol
    self.style = style
  }

  private var fill: Color {
    switch style {
    case .neutral: Theme.card
    case .accent: Theme.accentStrong
    case .gold: Theme.recordTint
    case .green: Theme.positiveTint
    case .orange: Theme.metricEffort.opacity(0.14)
    }
  }

  private var ink: Color {
    switch style {
    case .neutral: Theme.text
    case .accent: Theme.onAccent
    case .gold: Theme.recordInk
    case .green: Theme.positive
    case .orange: Theme.metricEffort
    }
  }

  var body: some View {
    HStack(spacing: 6) {
      if let symbol {
        Image(systemName: symbol)
          .scaledSystemFont(13, weight: .semibold)
      }
      Text(text)
        .forge(15, .semibold)
        .monospacedDigit()
    }
    .foregroundStyle(ink)
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(Capsule().fill(fill))
  }
}

/// 4. Round lift token: exercise art on a tinted disc; records get a gold
/// ring and a trophy badge.
struct LiftToken: View {
  private let exercise: Exercise?
  private let size: CGFloat
  private let record: Bool
  private let onSky: Bool
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var cutout: UIImage?

  init(exercise: Exercise?, size: CGFloat, record: Bool = false, onSky: Bool = false) {
    self.exercise = exercise
    self.size = size
    self.record = record
    self.onSky = onSky
  }

  /// Trophy badge whose center sits on the ring, 45° down-right.
  private var trophyBadge: some View {
    let badge = size * 0.30
    return Circle()
      .fill(Theme.recordRing)
      .frame(width: badge, height: badge)
      .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
      .overlay(
        Image(systemName: "trophy.fill")
          .font(.system(size: size * 0.14))
          .foregroundStyle(.white))
      .offset(x: size * 0.3536, y: size * 0.3536)
  }

  /// Dark-mode art: the cutout figure on a dark disc, framed like the light-mode disc.
  private func darkArt(for exercise: Exercise) -> some View {
    ZStack {
      Circle().fill(Theme.track)
      if let cutout {
        Image(uiImage: cutout)
          .resizable()
          .scaledToFill()
          .scaleEffect(1.25)
          .frame(width: size, height: size)
          .clipShape(Circle())
      }
    }
    .overlay(Circle().strokeBorder(Theme.imageOutline, lineWidth: 1))
    .task(id: exercise.id) {
      guard let image = await ArtCutout.image(named: "ex-\(exercise.id)") else { return }
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
        cutout = image
      }
    }
  }

  var body: some View {
    ZStack {
      if onSky {
        Circle().fill(Theme.card)
      }
      if let exercise {
        if colorScheme == .dark, UIImage(named: "ex-\(exercise.id)") != nil {
          darkArt(for: exercise)
        } else {
          ExerciseArtCircle(exercise: exercise, size: size)
        }
      } else {
        Circle().fill(Theme.accentTint)
      }
      if record {
        Circle().strokeBorder(Theme.recordRing, lineWidth: max(3, size * 0.045))
        trophyBadge
      }
    }
    .frame(width: size, height: size)
    .compositingGroup()
    .accessibilityHidden(true)
  }
}

/// 5. Placeholder token for exercises the plan hasn't revealed yet.
struct LockedToken: View {
  private let size: CGFloat

  init(size: CGFloat) {
    self.size = size
  }

  var body: some View {
    ZStack {
      Circle().fill(Theme.track)
      Image(systemName: "lock.fill")
        .font(.system(size: size * 0.22))
        .foregroundStyle(Theme.textTertiary)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// 6. Medal art: the earned illustration, or a locked disc with a progress ring.
struct MedalArt: View {
  private let badge: Badge
  private let earned: Bool
  private let fraction: Double
  private let size: CGFloat

  init(badge: Badge, earned: Bool, fraction: Double, size: CGFloat) {
    self.badge = badge
    self.earned = earned
    self.fraction = fraction
    self.size = size
  }

  static func assetName(_ badge: Badge) -> String {
    switch badge {
    case .firstSession: "medal-first-session"
    case .tenSessions: "medal-ten-sessions"
    case .fiftySessions: "medal-fifty-sessions"
    case .hundredSessions: "medal-hundred-sessions"
    case .fourWeekStreak: "medal-four-week-streak"
    case .twelveWeekStreak: "medal-twelve-week-streak"
    case .tonnage100k: "medal-tonnage-100k"
    case .tonnage1M: "medal-tonnage-1m"
    case .firstPR: "medal-first-pr"
    case .tenPRs: "medal-ten-prs"
    }
  }

  var body: some View {
    Group {
      if earned {
        Image(Self.assetName(badge))
          .resizable()
          .scaledToFit()
          .frame(width: size, height: size)
      } else {
        ZStack {
          Circle().fill(Theme.track).padding(size * 0.08)
          Image(systemName: "lock.fill")
            .font(.system(size: size * 0.24, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
          Circle().stroke(Theme.track, lineWidth: 3)
          Circle().trim(from: 0, to: max(0.02, min(1, fraction)))
            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
      }
    }
    .accessibilityHidden(true)
  }
}

/// 7. Section header on the sky. Callers wrap it in a NavigationLink when it navigates.
struct SkySectionHeader: View {
  private let title: LocalizedStringKey
  private let trailing: String?

  init(_ title: LocalizedStringKey, trailing: String? = nil) {
    self.title = title
    self.trailing = trailing
  }

  var body: some View {
    HStack {
      Text(title).forgeSection().accessibilityAddTraits(.isHeader)
      Spacer()
      if let trailing {
        HStack(spacing: 4) {
          Text(trailing).forge(17, .regular).monospacedDigit()
          Image(systemName: "chevron.forward").scaledSystemFont(14, weight: .semibold)
        }
        .foregroundStyle(Theme.accentText)
      }
    }
  }
}

extension View {
  /// Pushed-screen chrome for `ProgressLargeTitle`: keeps the navigation title (back button,
  /// VoiceOver) but inline and visually hidden, so the system large title never duplicates
  /// the custom one. Existing toolbar items keep working.
  func progressTitleNavigation(_ title: LocalizedStringKey) -> some View {
    navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
        }
      }
  }

  /// Same, for titles already localized by the caller.
  func progressTitleNavigation(_ title: String) -> some View {
    navigationTitle(Text(title))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
        }
      }
  }
}

/// 8. Large-title header for pushed Progress screens: bold title, optional subtitle,
/// and optional decorative clay art beside the title at the trailing side.
/// The art's top edge sits 6 pt above the title's top; text gets 88 pt trailing
/// padding so it never runs under the image. No shadow, no gradient.
struct ProgressLargeTitle: View {
  private let title: LocalizedStringKey
  private let subtitle: String?
  private let art: String?

  init(title: LocalizedStringKey, subtitle: String? = nil, art: String? = nil) {
    self.title = title
    self.subtitle = subtitle
    self.art = art
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.forge(30, .bold, relativeTo: .largeTitle))
          .tracking(-0.9)
          .foregroundStyle(Theme.text)
          .accessibilityAddTraits(.isHeader)
        if let subtitle {
          Text(subtitle)
            .forgeLabel()
        }
      }
      .padding(.trailing, art == nil ? 0 : 88)
      .frame(maxWidth: .infinity, alignment: .leading)
      if let art {
        Image(art)
          .resizable()
          .scaledToFit()
          .frame(width: 68, height: 68)
          .offset(y: -6)
          .accessibilityHidden(true)
      }
    }
  }
}


/// v6: a Progress screen's top block on the peach field.
struct FieldSection<Content: View>: View {
  private let bottom: CGFloat
  private let content: Content

  init(bottom: CGFloat = 24, @ViewBuilder content: () -> Content) {
    self.bottom = bottom
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      content
    }
    .padding(.horizontal, Theme.margin)
    .padding(.bottom, bottom)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.field)
  }
}

/// The Review capsule that opens an approval sheet: one shared pill on Muscles, Balance
/// and Plan audit (mock `.review`).
struct ReviewPill: View {
  let accessibilityLabel: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(String(localized: "Review", bundle: L10n.bundle))
        .forge(15, .semibold)
        .foregroundStyle(Theme.onAccent)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Capsule().fill(Theme.accentStrong))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(ControlPressStyle())
    .accessibilityLabel(accessibilityLabel)
  }
}

/// v6: rounded illustration thumbnail, decorative.
struct ArtThumb: View {
  let name: String
  var size: CGFloat = 36

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
    Image(name)
      .resizable()
      .scaledToFill()
      .frame(width: size, height: size)
      .clipShape(shape)
      .overlay(shape.strokeBorder(Theme.ring, lineWidth: 1))
      .contentShape(shape)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

extension View {
  /// v6 page chrome for a ScrollView: white page, peach behind the nav bar and the top overscroll,
  /// inline navigation title. Content below the FieldSection must sit on `Theme.page`.
  func progressFieldPage(_ title: String) -> some View {
    background(
      VStack(spacing: 0) {
        Theme.field.frame(height: 420)
        Theme.page
      }
      .ignoresSafeArea()
    )
    .toolbarBackground(Theme.field, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .navigationTitle(Text(title))
    .navigationBarTitleDisplayMode(.inline)
  }
}
