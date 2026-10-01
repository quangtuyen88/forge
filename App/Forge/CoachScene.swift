import SwiftUI
import ForgeCore

/// Flat illustration of the chosen coach: one scene per lift family plus story scenes for Today and voice.
enum CoachScene: String, CaseIterable {
  case deadlift, ohp, pullup, curl, calf, squat, bench, row, lateral, legraise
  case plan, last, why, recovered, rest, record, wave, flex

  /// The lift family scene that best shows an exercise (mood art, not form instruction).
  static func forExercise(_ e: Exercise) -> CoachScene {
    switch e.pattern {
    case .hinge, .carry: return .deadlift
    case .squat, .lunge: return .squat
    case .horizontalPush: return .bench
    case .verticalPush: return .ohp
    case .horizontalPull: return .row
    case .verticalPull: return .pullup
    case .core: return .legraise
    case .isolation:
      switch e.primary {
      case .biceps, .forearms: return .curl
      case .triceps, .chest: return .bench
      case .frontDelts, .sideDelts, .rearDelts: return .lateral
      case .calves: return .calf
      case .abs: return .legraise
      case .quads: return .squat
      case .hamstrings, .glutes: return .deadlift
      case .back: return .row
      }
    }
  }

  /// Lift families ship a wide 3:2 photo (`<coach>-wide-<scene>`) for the Today session card.
  var hasWidePhoto: Bool {
    switch self {
    case .deadlift, .ohp, .pullup, .curl, .calf, .squat, .bench, .row, .lateral, .legraise: true
    default: false
    }
  }

  /// Standing and hanging lifts crop the wide photo from the top, so the head and the bar stay in frame.
  var wideCropsFromTop: Bool {
    switch self {
    case .ohp, .pullup, .curl, .lateral, .legraise: true
    default: false
    }
  }
}

/// A coach scene clipped to a rounded tile. Decorative: hidden from VoiceOver.
struct CoachSceneTile: View {
  let scene: CoachScene
  var size: CGFloat = 44
  var radius: CGFloat = Theme.radiusRow
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  var body: some View {
    Image(Coach.from(coachID).scene(scene)).resizable().scaledToFill()
      .frame(width: size, height: size)
      .background(Theme.innerSurface)
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.imageOutline, lineWidth: 1))
      .accessibilityHidden(true)
  }
}
