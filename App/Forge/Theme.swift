import SwiftUI
import UIKit
import ForgeCore

enum Theme {
  static let accent = Color(hex: 0x3866D6)
  static let coachServer = "https://forge-coach.quangtuyen88.workers.dev"
  static let legacyCoachServer = "http://localhost:8787"
  static let privacyPolicyURL = URL(string: "https://vnbnode.com/forge/privacy")!
  static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

  // radius hierarchy
  static let radiusCard: CGFloat = 20      // cards 18–22
  static let radiusRow: CGFloat = 12       // rows / inner surfaces 8–14
  static let radiusChip: CGFloat = 10      // chips
  static let radiusControl: CGFloat = 14   // buttons, text fields

  // spacing
  static let margin: CGFloat = 26          // page horizontal margin
  static let groupGap: CGFloat = 18        // between card groups (16–22)
  static let inner: CGFloat = 10           // inside components (8–12)

  // semantic colors, light / dark
  static let page = Color(light: 0xF3F4F8, dark: 0x0B0C10)
  static let card = Color(light: 0xFFFFFF, dark: 0x16181F)
  static let innerSurface = Color(light: 0xF1F3F8, dark: 0x1F222B)
  static let track = Color(light: 0xE3E7F0, dark: 0x2A2E3A)
  static let ring = Color(light: 0x000000, dark: 0xFFFFFF, lightOpacity: 0.06, darkOpacity: 0.08)
  static let highlight = Color(light: 0xFFFFFF, dark: 0xFFFFFF, lightOpacity: 0.9, darkOpacity: 0.07)
  static let shadow = Color(light: 0x1B2B5A, dark: 0x000000, lightOpacity: 0.08, darkOpacity: 0.45)
  static let text = Color(light: 0x111318, dark: 0xF4F5F8)
  static let textSecondary = Color(light: 0x5C6270, dark: 0xA3A8B5)
  static let textTertiary = Color(light: 0x9096A4, dark: 0x6B7180)
  static let onAccent = Color.white
  static let positive = Color(hex: 0x2FA36B)
  static let negative = Color(hex: 0xD9534F)

  /// 5-step ramp, muted track → deep blue. Used by charts, heat grids, rings.
  static let ramp: [Color] = [
    track,
    Color(light: 0xC5D3F5, dark: 0x2B3D6E),
    Color(light: 0x8FAAEC, dark: 0x3A5AA8),
    Color(light: 0x5A82E0, dark: 0x3866D6),
    Color(light: 0x2B54C4, dark: 0x6E93F0),
  ]

  /// fraction 0…1 → ramp step (0 stays track, >0 maps to steps 1…4)
  static func rampColor(_ fraction: Double) -> Color {
    guard fraction > 0 else { return ramp[0] }
    return ramp[min(4, max(1, Int(ceil(fraction * 4))))]
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
    font(.forge(26, .bold)).tracking(-0.9).foregroundColor(Theme.text)
  }

  func forgeTitle() -> some View {
    font(.forge(22, .bold)).tracking(-0.8).foregroundColor(Theme.text)
  }

  func forgeSection() -> some View {
    font(.forge(18, .semibold)).tracking(-0.7).foregroundColor(Theme.text)
  }

  func forgeNumber() -> some View {
    font(.forge(22, .bold).monospacedDigit()).tracking(-0.7).foregroundColor(Theme.text)
  }

  func forgeBody() -> some View {
    font(.forge(15, .regular)).foregroundColor(Theme.text)
  }

  func forgeBodyStrong() -> some View {
    font(.forge(15, .medium)).foregroundColor(Theme.text)
  }

  func forgeLabel() -> some View {
    font(.forge(13, .medium)).foregroundColor(Theme.textSecondary)
  }

  func forgeCaption() -> some View {
    font(.forge(12, .medium)).foregroundColor(Theme.textTertiary)
  }
}

extension View {
  /// Card surface: card fill, continuous 20pt corners, soft shadow on the shape only,
  /// inset top highlight, 1pt ring.
  func card(padding: CGFloat = 16, fill: Color = Theme.card) -> some View {
    self
      .padding(padding)
      .background {
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .fill(fill)
          .shadow(color: Theme.shadow, radius: 16, y: 6)
      }
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .strokeBorder(
            LinearGradient(colors: [Theme.highlight, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.4)),
            lineWidth: 1))
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .strokeBorder(Theme.ring, lineWidth: 1))
  }

  /// Inner surface: recessed row fill, 12pt corners, no shadow, no ring.
  func innerSurface(padding: CGFloat = Theme.inner) -> some View {
    self
      .padding(padding)
      .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
  }
}

struct PillButtonStyle: ButtonStyle {
  var minHeight: CGFloat = 52

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .forge(16, .semibold)
      .foregroundColor(Theme.onAccent)
      .frame(maxWidth: .infinity, minHeight: minHeight)
      .background {
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
          .fill(Theme.accent)
          .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
              .strokeBorder(
                LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom),
                lineWidth: 1))
      }
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct PillSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .forge(16, .semibold)
      .foregroundColor(Theme.text)
      .frame(maxWidth: .infinity, minHeight: 52)
      .background(
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
          .fill(Theme.innerSurface))
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
          .strokeBorder(Theme.ring, lineWidth: 1))
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct IconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(width: 40, height: 40)
      .background(Circle().fill(Theme.card))
      .overlay(Circle().strokeBorder(Theme.ring, lineWidth: 1))
      .shadow(color: Theme.shadow, radius: 8, y: 3)
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct IconCircleButton: View {
  let symbol: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(Theme.text)
    }
    .buttonStyle(IconButtonStyle())
  }
}

struct SelectCard: View {
  let title: String
  var subtitle: String? = nil
  let symbol: String
  let selected: Bool
  let action: () -> Void
  var badge: String? = nil

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(selected ? Theme.accent : Theme.textSecondary)
          .frame(width: 40, height: 40)
          .background(Circle().fill(selected ? Theme.accent.opacity(0.12) : Theme.innerSurface))
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 8) {
            Text(title)
              .forgeBodyStrong()
            if let badge {
              Text(badge)
                .forge(11, .semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.accent))
            }
          }
          if let subtitle {
            Text(subtitle)
              .forgeLabel()
          }
        }
        Spacer()
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .foregroundColor(selected ? Theme.accent : Theme.textTertiary)
      }
      .card(padding: 14, fill: selected ? Theme.accent.opacity(0.10) : Theme.card)
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5))
      .contentShape(Rectangle())
    }
    .buttonStyle(CardPressStyle())
    .sensoryFeedback(.selection, trigger: selected)
    .accessibilityLabel([title, subtitle].compactMap { $0 }.joined(separator: ", "))
    .accessibilityAddTraits(selected ? .isSelected : [])
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
      .overlay(Circle().stroke(Theme.card, lineWidth: 2))
      .overlay(Circle().strokeBorder(Theme.ring, lineWidth: 1))
      .accessibilityHidden(true)
  }
}

struct CoachPickCard: View {
  let coach: Coach
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack(alignment: .bottomLeading) {
        Color.clear
          .frame(height: 190)
          .overlay(Image(coach.wave).resizable().scaledToFill())
          .clipped()
        LinearGradient(colors: [.black.opacity(0), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
        VStack(alignment: .leading, spacing: 2) {
          Text(coach.name)
            .forge(18, .bold, tracking: -0.6)
            .foregroundColor(.white)
          Text(coach.tagline)
            .forge(12, .medium)
            .foregroundColor(.white.opacity(0.8))
        }
        .padding(12)
      }
      .frame(height: 190)
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .strokeBorder(selected ? Theme.accent : Theme.ring, lineWidth: selected ? 2.5 : 1))
      .overlay(alignment: .topTrailing) {
        if selected {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 22))
            .foregroundStyle(.white, Theme.accent)
            .padding(10)
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
      .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1))
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

/// Square-ish photo action tile with gradient scrim, glass symbol chip and caption.
struct PhotoTile: View {
  let image: String
  let title: String
  let subtitle: String
  let symbol: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack(alignment: .bottomLeading) {
        Image(image).resizable().scaledToFill()
          .frame(maxWidth: .infinity)
          .frame(height: 132)
          .clipped()
        LinearGradient(colors: [.black.opacity(0), .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .forge(15, .semibold, tracking: -0.3)
            .foregroundColor(.white)
          Text(subtitle)
            .forge(12, .medium)
            .foregroundColor(.white.opacity(0.75))
        }
        .padding(12)
      }
      .frame(height: 132)
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
      .overlay(alignment: .topLeading) {
        Image(systemName: symbol)
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(.white)
          .frame(width: 28, height: 28)
          .background(Circle().fill(.ultraThinMaterial))
          .padding(10)
      }
      .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1))
      .contentShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
    .buttonStyle(CardPressStyle())
    .accessibilityLabel("\(title), \(subtitle)")
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
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      .overlay(alignment: .leading) {
        Circle().fill(tint)
          .frame(width: 12, height: 12)
          .offset(x: -5, y: 6)
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
    VStack(alignment: .leading, spacing: 4) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(Theme.accent)
        .frame(width: 28, height: 28)
        .background(Circle().fill(Theme.accent.opacity(0.12)))
      Spacer(minLength: 2)
      MetricValue(value: value, unit: unit, size: 22, color: tint, numeric: numeric)
      Text(label)
        .forgeCaption()
    }
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
    .card(padding: 14)
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
      .accessibilityHidden(true)
  }
}

struct RowPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .opacity(configuration.isPressed ? 0.85 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct Reveal: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let index: Int
  let appeared: Bool

  func body(content: Content) -> some View {
    content
      .opacity(appeared ? 1 : 0)
      .offset(y: reduceMotion ? 0 : (appeared ? 0 : 8))
      .animation(.easeOut(duration: 0.25).delay(Double(index) * 0.04), value: appeared)
  }
}

extension View {
  func reveal(_ index: Int, appeared: Bool) -> some View {
    modifier(Reveal(index: index, appeared: appeared))
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
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

/// Spoken muscle name for VoiceOver labels: "sideDelts" → "Side delts".
extension Muscle {
  var a11yName: String {
    let spaced = rawValue.replacingOccurrences(of: "Delts", with: " delts")
    return spaced.prefix(1).uppercased() + spaced.dropFirst()
  }
}
