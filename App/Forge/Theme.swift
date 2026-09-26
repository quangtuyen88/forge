import SwiftUI
import UIKit
import ForgeCore

enum Theme {
  static let accent = Color(light: 0x0062E6, dark: 0x0A84FF)       // the one accent: buttons, links, active tab, selection, progress
  static let accentValue = Color(light: 0x0062E6, dark: 0x0A84FF)  // same blue: live numerals, chart marks
  static let coachServer = "https://forge-coach.quangtuyen88.workers.dev"
  static let legacyCoachServer = "http://localhost:8787"
  static let privacyPolicyURL = URL(string: "https://regulift.app/privacy")!
  static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

  // radius hierarchy
  static let radiusCard: CGFloat = 16      // cards
  static let radiusRow: CGFloat = 10       // rows / inner surfaces
  static let radiusChip: CGFloat = 8       // chips
  static let radiusControl: CGFloat = 10   // buttons, text fields
  static let radiusToday: CGFloat = 24    // Today elevated cards (DESIGN.md §12)

  // spacing
  static let margin: CGFloat = 20          // page horizontal margin (Fitness 20)
  static let barMargin: CGFloat = 36       // bottom CTA bars (Fitness ~38)
  static let groupGap: CGFloat = 12        // between card groups (Fitness 12)
  static let inner: CGFloat = 10           // inside components (8–12)

  // semantic colors, light / dark (Lyfta-style clean surfaces)
  static let page = Color(light: 0xFFFFFF, dark: 0x000000)
  static let card = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
  static let innerSurface = Color(light: 0xEEF2F4, dark: 0x2C2C2E)
  /// Fixed dark surface for exported share images (not theme-adaptive: the image looks the same everywhere).
  static let shareSurface = Color(red: 15 / 255, green: 15 / 255, blue: 18 / 255)
  /// Accent for text on `shareSurface` (fixed; #0A84FF reads 5.2:1 on it in both appearances).
  static let shareAccent = Color(red: 10 / 255, green: 132 / 255, blue: 255 / 255)
  static let track = Color(light: 0xE1E6EA, dark: 0x3A3A3C)
  // Today atmosphere (DESIGN.md §12): the sky page, glass, elevated card ring, footer strip
  static let todaySkyTop = Color(light: 0x7DB0FF, dark: 0x0B2A5E)
  static let todaySkyMid = Color(light: 0xB7D3FF, dark: 0x071A3A)
  static let todaySkyLow = Color(light: 0xE4EEFF, dark: 0x040B1A)
  static let todayPage = Color(light: 0xF3F7FD, dark: 0x000000)
  static let todayGlass = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.55, darkOpacity: 0.10)
  static let todayCardRing = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.0, darkOpacity: 0.08)
  static let todayFooter = Color(light: 0xEEF4FF, dark: 0x16223A)
  static let ring = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.10, darkOpacity: 0.10)
  static let imageOutline = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.1, darkOpacity: 0.1)  // 1 pt edge on photos and thumbnails
  static let highlight = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.9, darkOpacity: 0.07)
  static let shadow = Color(light: 0x1B2B5A, dark: 0x000000, lightOpacity: 0.08, darkOpacity: 0.45)
  static let text = Color(light: 0x0F0F12, dark: 0xFFFFFF)
  static let textSecondary = Color(light: 0x5F6672, dark: 0x98989F)
  static let textTertiary = Color(light: 0x5F6672, dark: 0x98989F)
  static let onAccent = Color(light: 0xFFFFFF, dark: 0xFFFFFF)  // white label on blue
  static let accentTint = accent.opacity(0.12)     // chip and badge fills
  static let positiveTint = positive.opacity(0.12)
  static let positive = Color(light: 0x1E8E3E, dark: 0x30D158)  // done, logged sets, records
  static let positiveText = Color(light: 0x15703A, dark: 0x30D158)  // green text on white and on the sky (AA at 13 pt)
  static let negative = Color(light: 0xD70015, dark: 0xFF3B30)  // System red: destructive errors, critical warnings

  // metric colors — one fixed hue per role (DESIGN.md §1), light / dark
  static let metricTime   = Color(light: 0x0E7490, dark: 0x22D3EE)   // teal: elapsed time, rest countdowns
  static let metricLoad   = accentValue                               // blue: weight, tonnage, e1RM, volume
  static let metricSets   = Color(light: 0x1E8E3E, dark: 0x30D158)   // green: sets, exercise adherence, active reps
  static let metricEffort = Color(light: 0xC2410C, dark: 0xFF9F0A)   // orange: RPE / intensity
  static let metricHeart  = Color(light: 0xD70015, dark: 0xFF453A)   // red: heart telemetry
  static let metricEnergy = Color(light: 0xC2410C, dark: 0xFF9F0A)   // orange: kcal / nutrition energy
  static let metricRecord = Color(light: 0xB45309, dark: 0xFFD60A)   // gold: records, PRs, trophies

  // Progress records (DESIGN.md §12)
  static let recordRing = Color(light: 0xE8A317, dark: 0xFFC933)       // record ring, trophy badge
  static let recordTint = Color(light: 0xFFF4D6, dark: 0x3A2E10)       // record pill fill
  static let recordInk = Color(light: 0x9A5B00, dark: 0xFFD60A)        // record pill text

  /// 5-step ramp, muted track → full blue. Used by charts, heat grids, rings.
  static let ramp: [Color] = [
    track,
    Color(light: 0xDCE9FF, dark: 0x0A2A55),
    Color(light: 0xA8C8FF, dark: 0x0F4C99),
    Color(light: 0x5A9BFF, dark: 0x1F6FD6),
    Color(light: 0x0062E6, dark: 0x0A84FF),
  ]

  /// fraction 0…1 → ramp step (0 stays track, >0 maps to steps 1…4)
  static func rampColor(_ fraction: Double) -> Color {
    guard fraction > 0 else { return ramp[0] }
    return ramp[min(4, max(1, Int(ceil(fraction * 4))))]
  }

  /// Fitness gold: 15 kg / 25 lb plate and exceptional supporting highlights (DESIGN.md §1).
  static let plateGold = Color(hex: 0xFFD60A)

  /// Plate pill fill (DESIGN.md §6). Vivid hues stay vivid in both appearances;
  /// smaller change plates fall back to neutral track.
  static func plateColor(_ weight: Double, usesLb: Bool) -> Color {
    if usesLb {
      switch weight {
      case 45: return Color(hex: 0xFF2D55)  // electric red
      case 35: return Color(hex: 0x00F0FF)  // electric cyan
      case 25: return plateGold             // fitness gold
      case 10: return Color(hex: 0x00F076)  // workout green
      default: return track
      }
    } else {
      switch weight {
      case 25: return Color(hex: 0xFF2D55)  // electric red
      case 20: return Color(hex: 0x00F0FF)  // electric cyan
      case 15: return plateGold             // fitness gold
      case 10: return Color(hex: 0x00F076)  // workout green
      default: return track
      }
    }
  }

  /// Plate pill label: black on vivid hues, Theme.text on neutral track.
  static func plateLabelColor(_ weight: Double, usesLb: Bool) -> Color {
    let vivid = usesLb ? [45.0, 35.0, 25.0, 10.0].contains(weight)
                       : [25.0, 20.0, 15.0, 10.0].contains(weight)
    return vivid ? .black : text
  }
}

private extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255)
  }

  init(light: UInt32, dark: UInt32, lightOpacity: Double = 1, darkOpacity: Double = 1) {
    func ui(_ v: UInt32, _ a: Double) -> UIColor {
      UIColor(
        red: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: CGFloat(a))
    }
    self.init(UIColor { traits in
      traits.userInterfaceStyle == .dark ? ui(dark, darkOpacity) : ui(light, lightOpacity)
    })
  }
}

extension Font {
  static func forge(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
    let name: String
    switch weight {
    case .regular: name = "InterTight-Regular"
    case .medium: name = "InterTight-Medium"
    case .semibold: name = "InterTight-SemiBold"
    case .bold: name = "InterTight-Bold"
    default: name = "InterTight-ExtraBold"
    }
    return .custom(name, size: size, relativeTo: style)
  }
}

extension Text {
  /// Raw size/weight access to the Inter Tight ramp (no default color). Text-level, beats environment.
  func forge(_ size: CGFloat, _ weight: Font.Weight = .regular, tracking: CGFloat = 0) -> Text {
    font(.forge(size, weight)).tracking(tracking)
  }
}

extension View {
  /// Raw size/weight access to the Inter Tight ramp (no default color).
  func forge(_ size: CGFloat, _ weight: Font.Weight = .regular, tracking: CGFloat = 0) -> some View {
    font(.forge(size, weight)).tracking(tracking)
  }
}

// Colors are environment defaults. To override, apply .foregroundStyle directly on the
// Text *before* the forge modifier (text-level styling beats the environment), e.g.
// Text(x).foregroundStyle(.white).forgeBody().
extension View {
  func forgeGreeting() -> some View {
    font(.forge(26, .bold)).tracking(-0.9).foregroundStyle(Theme.text)
  }

  func forgeTitle() -> some View {
    font(.forge(22, .bold)).tracking(-0.8).foregroundStyle(Theme.text)
  }

  func forgeSection() -> some View {
    font(.forge(18, .semibold)).tracking(-0.7).foregroundStyle(Theme.text)
  }

  func forgeNumber() -> some View {
    font(.forge(22, .bold).monospacedDigit()).tracking(-0.7).foregroundStyle(Theme.text)
  }

  func forgeDisplay() -> some View {
    font(.forge(44, .bold, relativeTo: .largeTitle).monospacedDigit()).tracking(-1.5).foregroundStyle(Theme.text)
  }

  func forgeBody() -> some View {
    font(.forge(15, .regular)).foregroundStyle(Theme.text)
  }

  func forgeBodyStrong() -> some View {
    font(.forge(15, .medium)).foregroundStyle(Theme.text)
  }

  func forgeLabel() -> some View {
    font(.forge(13, .medium)).foregroundStyle(Theme.textSecondary)
  }

  func forgeCaption() -> some View {
    font(.forge(12, .medium)).foregroundStyle(Theme.textTertiary)
  }

  func forgeOverline() -> some View {
    font(.forge(10, .semibold)).tracking(0.8).foregroundStyle(Theme.textTertiary)
  }
}

extension View {
  /// Card surface: flat card fill, continuous `Theme.radiusCard` corners, 1pt ring border.
  /// No shadow and no top highlight — cards read as flat charcoal slabs, Fitness style.
  func card(
    padding: CGFloat = 20, fill: Color = Theme.card, stroke: Color = Theme.ring
  ) -> some View {
    self
      .padding(padding)
      .background {
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .fill(fill)
      }
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .strokeBorder(stroke, lineWidth: 1))
  }

  /// Inner surface: recessed row fill, 12pt corners, no shadow, no ring.
  func innerSurface(padding: CGFloat = Theme.inner) -> some View {
    self
      .padding(padding)
      .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
  }
}

/// Press feedback shared by every button style in the app. Under Reduce Motion the scale is
/// dropped and the press reports itself with a dim instead — the feedback stays, the movement goes.
struct PressFeedback<Content: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let isPressed: Bool
  var scale: CGFloat = 0.96
  var pressedOpacity: Double = 1
  @ViewBuilder var content: () -> Content

  var body: some View {
    content()
      .scaleEffect(isPressed && !reduceMotion ? scale : 1)
      .opacity(isPressed ? (reduceMotion ? 0.72 : pressedOpacity) : 1)
      .animation(.easeOut(duration: 0.12), value: isPressed)
  }
}

struct PillButtonStyle: ButtonStyle {
  var minHeight: CGFloat = 56

  func makeBody(configuration: Configuration) -> some View {
    PressFeedback(isPressed: configuration.isPressed) {
      configuration.label
        .forge(16, .semibold)
        .foregroundStyle(Theme.onAccent)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background {
          Capsule()
            .fill(Theme.accent)
        }
        .clipShape(Capsule())
    }
  }
}

struct PillSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    PressFeedback(isPressed: configuration.isPressed) {
      configuration.label
        .forge(16, .semibold)
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(
          Capsule()
            .fill(Theme.innerSurface))
    }
  }
}

struct IconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    PressFeedback(isPressed: configuration.isPressed) {
      configuration.label
        .frame(width: 44, height: 44)
        .background(Circle().fill(Theme.innerSurface))
    }
  }
}

struct IconCircleButton: View {
  let symbol: String
  var nudgeX: CGFloat = 0
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Theme.text)
        .offset(x: nudgeX)
    }
    .buttonStyle(IconButtonStyle())
  }
}

struct SelectCard: View {
  let title: String
  var subtitle: String? = nil
  let symbol: String
  let selected: Bool
  var art: [String] = []
  let action: () -> Void
  var badge: String? = nil

  private var shownArt: [String] { art.filter { UIImage(named: $0) != nil } }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        if !shownArt.isEmpty {
          ArtTile(names: shownArt)
        } else {
          Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.accent)
            .frame(width: 40, height: 40)
            .background(Circle().fill(selected ? Theme.onAccent : Theme.accentTint))
        }
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 8) {
            Text(title)
              .foregroundStyle(selected ? Theme.onAccent : Theme.text)
              .forgeBodyStrong()
            if let badge {
              Text(badge)
                .forge(11, .semibold)
                .foregroundStyle(selected ? Theme.accent : .white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(selected ? Theme.onAccent : Theme.accent))
            }
          }
          if let subtitle {
            Text(subtitle)
              .foregroundStyle(selected ? Theme.onAccent : Theme.textSecondary)
              .forgeLabel()
          }
        }
        Spacer()
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selected ? Theme.onAccent : Theme.textTertiary)
          .contentTransition(.symbolEffect(.replace))
          .animation(.spring(duration: 0.3, bounce: 0), value: selected)
      }
      .padding(14)
      .background(
        RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
          .fill(selected ? Theme.accent : Theme.innerSurface))
      .contentShape(Rectangle())
    }
    .buttonStyle(CardPressStyle())
    .sensoryFeedback(.selection, trigger: selected)
    .accessibilityLabel([title, subtitle].compactMap { $0 }.joined(separator: ", "))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// Illustration on a card-colored tile, so the art reads the same on a plain and on a selected row.
/// One name fills the tile; more names form rows of two, at most four (a gym preset's inventory).
struct ArtTile: View {
  let names: [String]
  var size: CGFloat = 56

  var body: some View {
    let cells = Array(names.prefix(4))
    let cell = (size - 10) / 2
    Group {
      if cells.count == 1 {
        Image(cells[0]).resizable().scaledToFit().padding(4)
      } else {
        VStack(spacing: 2) {
          ForEach(Array(stride(from: 0, to: cells.count, by: 2)), id: \.self) { row in
            HStack(spacing: 2) {
              ForEach(cells[row..<min(row + 2, cells.count)], id: \.self) { name in
                Image(name).resizable().scaledToFit().frame(width: cell, height: cell)
              }
            }
          }
        }
      }
    }
    .frame(width: size, height: size)
    .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.card))
    .overlay(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).strokeBorder(Theme.imageOutline, lineWidth: 1))
    .accessibilityHidden(true)
  }
}

struct Illustration: View {
  let name: String
  var height: CGFloat = 160
  var body: some View {
    Image(name).resizable().scaledToFit()
      .frame(maxWidth: .infinity).frame(height: height)
      .accessibilityHidden(true)
  }
}

struct CoachAvatar: View {
  var size: CGFloat = 40
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  var body: some View {
    Image(Coach.from(coachID).avatar).resizable().scaledToFill()
      .frame(width: size, height: size).clipShape(Circle())
      .overlay(Circle().strokeBorder(Theme.imageOutline, lineWidth: 1))
      .accessibilityHidden(true)
  }
}

struct CoachPickCard: View {
  let coach: Coach
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(spacing: 0) {
        Color.clear
          .frame(height: 136)
          .overlay(Image(coach.wave).resizable().scaledToFill())
          .clipped()
        VStack(alignment: .leading, spacing: 2) {
          Text(coach.name)
            .forge(18, .bold, tracking: -0.6)
            .foregroundStyle(Theme.text)
          Text(coach.tagline)
            .forge(12, .medium)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(height: 190)
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .strokeBorder(selected ? Theme.accent : Theme.imageOutline, lineWidth: selected ? 2.5 : 1))
      .overlay(alignment: .topTrailing) {
        if selected {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 22))
            .foregroundStyle(.white, Theme.accent)
            .padding(10)
            .transition(.symbolEffect(.appear))
        }
      }
      .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
    .buttonStyle(CardPressStyle())
    .sensoryFeedback(.selection, trigger: selected)
    .accessibilityLabel("\(coach.name), \(coach.tagline)")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// Coach photo clipped to a rounded card.
struct CoachPhoto: View {
  let name: String
  var height: CGFloat = 200
  var radius: CGFloat = Theme.radiusCard

  var body: some View {
    Image(name).resizable().scaledToFill()
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.imageOutline, lineWidth: 1))
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}


/// Rounded speech bubble with a small tail on the leading edge.
struct SpeechBubble<Content: View>: View {
  var tint: Color = Theme.innerSurface
  @ViewBuilder var content: () -> Content
  var body: some View {
    content()
      .padding(12)
      .background(tint)
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
      .overlay(alignment: .topLeading) {
        Circle().fill(tint)
          .frame(width: 12, height: 12)
          .offset(x: -5, y: 12)
      }
  }
}

/// Compact stat tile: symbol chip, big numeral, label under.
struct StatTile: View {
  let symbol: String
  let value: String
  var unit: String? = nil
  let label: String
  var tint: Color = Theme.text
  var numeric: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: symbol)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 28, height: 28)
          .background(Circle().fill(tint.opacity(0.14)))
        Text(label).forgeBodyStrong()
        Spacer(minLength: 0)
      }
      MetricValue(value: value, unit: unit, size: 28, color: tint, numeric: numeric)
    }
    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
    .card()
  }
}

/// Equipment thumbnail: rounded square with the eq-* illustration centered.
struct EquipmentThumb: View {
  let equipment: Equipment
  var size: CGFloat = 44

  var body: some View {
    Image("eq-\(equipment.rawValue)")
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).strokeBorder(Theme.imageOutline, lineWidth: 1))
      .accessibilityHidden(true)
  }
}

/// Press feedback for compact controls that are not rows and not full-width pills — steppers,
/// chips, toggles. Scale only, no dim: these fire dozens of times a set and a flashing dim
/// would read as noise.
struct ControlPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    PressFeedback(isPressed: configuration.isPressed, scale: 0.96) {
      configuration.label
    }
  }
}

struct RowPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    PressFeedback(isPressed: configuration.isPressed, pressedOpacity: 0.85) {
      configuration.label
    }
  }
}

/// Row with a swipe-left-to-delete gesture; the red trash reveals behind it **as it is dragged**.
///
/// The affordance used to be drawn unconditionally under a transparent row, so every row in a
/// list sat on a red tint with a trash glyph printed through its trailing text. It is now gated
/// on the drag and fades in with it, and the row content carries its own opaque fill so nothing
/// behind it can ever show through.
struct SwipeDeleteRow<Content: View>: View {
  let onDelete: () -> Void
  /// Surface the row sits on. Must match the container, or the row reads as a patch.
  var surface: Color = Theme.card
  @ViewBuilder var content: () -> Content
  @State private var offset: CGFloat = 0

  /// 0…1 across the 80pt commit distance. Drives the reveal so the lifter can see the delete
  /// arming rather than discovering it at the end of the gesture.
  private var reveal: Double { min(1, Double(-offset) / 80) }

  var body: some View {
    ZStack(alignment: .trailing) {
      if offset < 0 {
        RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
          .fill(Theme.negative.opacity(0.15 * reveal))
        Image(systemName: "trash.fill")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(Theme.negative)
          .padding(.trailing, 16)
          .opacity(reveal)
          .scaleEffect(0.85 + 0.15 * reveal)
          .accessibilityHidden(true)
      }
      content()
        .background(
          RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(surface)
        )
        .offset(x: offset)
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
    .gesture(
      DragGesture(minimumDistance: 15)
        .onChanged { value in offset = min(0, value.translation.width) }
        .onEnded { value in
          if value.translation.width <= -80 {
            offset = 0
            onDelete()
          } else {
            withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
          }
        })
  }
}

struct Reveal: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let index: Int
  let appeared: Bool
  var stagger: Double = 0.04

  func body(content: Content) -> some View {
    content
      .opacity(appeared ? 1 : 0)
      .offset(y: reduceMotion ? 0 : (appeared ? 0 : 8))
      .animation(
        reduceMotion
          ? .easeOut(duration: 0.2)
          : .easeOut(duration: 0.25).delay(Double(index) * stagger),
        value: appeared)
  }
}

extension View {
  func reveal(_ index: Int, appeared: Bool, stagger: Double = 0.04) -> some View {
    modifier(Reveal(index: index, appeared: appeared, stagger: stagger))
  }
}

extension AnyTransition {
  static var forgeSlideUp: AnyTransition {
    .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity)
  }

  static var forgeFade: AnyTransition { .opacity }
}

private struct CardPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    PressFeedback(isPressed: configuration.isPressed) {
      configuration.label
    }
  }
}

/// Spoken muscle name for VoiceOver labels.
extension Muscle {
  var a11yName: String {
    switch self {
    case .chest: return String(localized: "Chest", bundle: L10n.bundle)
    case .back: return String(localized: "Back", bundle: L10n.bundle)
    case .quads: return String(localized: "Quads", bundle: L10n.bundle)
    case .hamstrings: return String(localized: "Hamstrings", bundle: L10n.bundle)
    case .glutes: return String(localized: "Glutes", bundle: L10n.bundle)
    case .sideDelts: return String(localized: "Side delts", bundle: L10n.bundle)
    case .rearDelts: return String(localized: "Rear delts", bundle: L10n.bundle)
    case .frontDelts: return String(localized: "Front delts", bundle: L10n.bundle)
    case .triceps: return String(localized: "Triceps", bundle: L10n.bundle)
    case .biceps: return String(localized: "Biceps", bundle: L10n.bundle)
    case .calves: return String(localized: "Calves", bundle: L10n.bundle)
    case .abs: return String(localized: "Abs", bundle: L10n.bundle)
    case .forearms: return String(localized: "Forearms", bundle: L10n.bundle)
    }
  }
}
