import SwiftUI
import ForgeCore

// Reusable crew components (DESIGN.md §1–§11): data-agnostic views with plain parameters,
// no store access. The screens that use them (Progress → Crew, Your lifts) own the data.

/// Round crew avatar: tinted disc with the member's initial. `isYou` flips to the solid
/// accent fill. `border` draws a 2 pt ring outside the disc to separate overlapping avatars
/// and badges; `recordRing` draws a gold one instead (a record this week).
struct CrewAvatar: View {
  let initial: String
  var isYou: Bool = false
  var size: CGFloat = 40
  var border: Color? = nil
  var recordRing: Bool = false

  var body: some View {
    // ast-grep-ignore: design-no-uppercase-text
    Text(String(initial.prefix(1)).uppercased())
      .forge(size * 0.42, .semibold)
      .foregroundStyle(isYou ? Theme.onAccent : Theme.accent)
      .frame(width: size, height: size)
      .background(Circle().fill(isYou ? Theme.accent : Theme.accentTint).background(Circle().fill(Theme.card)))
      .overlay {
        if recordRing {
          Circle().strokeBorder(Theme.recordRing, lineWidth: 2)
            .frame(width: size + 4, height: size + 4)
        } else if let border {
          Circle().strokeBorder(border, lineWidth: 2)
            .frame(width: size + 4, height: size + 4)
        }
      }
      .accessibilityHidden(true)
  }
}

/// Overlapping crew avatars, the first one drawn on top; members with a record this week
/// carry the gold ring. `extra` shows how many more members follow as plain text.
struct CrewAvatarStack: View {
  let members: [(initial: String, record: Bool)]
  var extra: Int
  var size: CGFloat = 22
  let border: Color

  var body: some View {
    HStack(spacing: 6) {
      HStack(spacing: -size / 3) {
        ForEach(members.indices, id: \.self) { index in
          CrewAvatar(
            initial: members[index].initial,
            size: size,
            border: border,
            recordRing: members[index].record)
          .zIndex(Double(members.count - index))
        }
      }
      if extra > 0 {
        Text("+\(extra)")
          .forge(13, .semibold)
          .foregroundStyle(Theme.textSecondary)
      }
    }
  }
}

/// 52 pt avatar with the week's session ring. The ring turns positive when the target is met.
struct CrewRingAvatar: View {
  let initial: String
  let isYou: Bool
  let done: Int
  let target: Int
  var delay: Double = 0
  var size: CGFloat = 52

  var body: some View {
    ZStack {
      RingView(
        progress: target > 0 ? min(1, Double(done) / Double(target)) : 0,
        lineWidth: size * 4 / 52,
        color: done >= target ? Theme.positive : Theme.accent,
        track: Theme.track,
        delay: delay)
      CrewAvatar(initial: initial, isYou: isYou, size: size * 40 / 52)
    }
    .frame(width: size, height: size)
  }
}

/// One day of the crew week row. Rows provide the spoken summary; the stamp stays hidden.
struct CrewDayStamp: View {
  enum State { case trained, rest, today, future }

  let state: State
  var size: CGFloat = 22

  var body: some View {
    ZStack {
      switch state {
      case .trained:
        Circle().fill(Theme.metricEffort)
        Image(systemName: "checkmark")
          .font(.system(size: size * 0.45, weight: .bold))
          .foregroundStyle(Theme.onAccent)
      case .rest:
        Circle().fill(Theme.track)
          .frame(width: 6, height: 6)
      case .today:
        Circle().strokeBorder(Theme.accent, lineWidth: 2)
      case .future:
        Circle()
          .strokeBorder(
            Theme.textTertiary.opacity(0.5),
            style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// Kudos capsule for crew records. The sent state swaps symbol, text and fill together,
/// so every animated change also has a static cue.
struct KudosButton: View {
  enum Style { case onCard, onPage }

  let sent: Bool
  var style: Style = .onCard
  let action: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var fill: Color {
    if sent { return Theme.accentTint }
    return style == .onCard ? Theme.innerSurface : Theme.card
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: sent ? "hands.clap.fill" : "hands.clap")
          .font(.system(size: 15, weight: .semibold))
          .contentTransition(.symbolEffect(.replace))
        Text(sent ? "Sent" : "Kudos")
          .forge(15, .semibold)
      }
      .foregroundStyle(sent ? Theme.accent : Theme.text)
      .padding(.horizontal, 14)
      .frame(height: 36)
      .background(Capsule().fill(fill))
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(ControlPressStyle())
    .sensoryFeedback(.impact(weight: .light), trigger: sent)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: sent)
    .accessibilityLabel("Kudos")
    .accessibilityValue(sent ? "Sent" : "")
    .accessibilityAddTraits(.isButton)
  }
}

/// A member's record on a lift token: the exercise disc with the gold record ring and the
/// owner's avatar badge where `LiftToken` puts its trophy.
struct CrewRecordToken: View {
  let exercise: Exercise?
  var size: CGFloat
  let ownerInitial: String
  let ownerIsYou: Bool
  var onSky: Bool = false

  var body: some View {
    LiftToken(exercise: exercise, size: size, record: false, onSky: onSky)
      .overlay(Circle().strokeBorder(Theme.recordRing, lineWidth: max(3, size * 0.045)))
      .overlay(
        CrewAvatar(initial: ownerInitial, isYou: ownerIsYou, size: size * 0.30, border: Theme.card)
          .offset(x: size * 0.3536, y: size * 0.3536))
      .accessibilityHidden(true)
  }
}

/// Deep-link target for `.sheet(item:)`.
struct CrewLinkTarget: Identifiable {
  let handle: String
  var id: String { handle }
}

/// Opens `regulift://crew/<handle>` in the Crew tab. Anything else is left untouched.
@MainActor @Observable
final class CrewLink {
  static let shared = CrewLink()
  var handle: String?

  @discardableResult
  static func handle(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "regulift",
      url.host?.lowercased() == "crew",
      let first = url.pathComponents.dropFirst().first?.lowercased(),
      first.range(of: "^[a-z0-9_]{3,20}$", options: .regularExpression) != nil
    else { return false }
    shared.handle = first
    return true
  }
}
