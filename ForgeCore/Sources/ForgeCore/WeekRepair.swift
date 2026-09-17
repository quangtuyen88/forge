import Foundation

public enum WeekRepair {
  public enum Option: String, CaseIterable, Sendable {
    case shift, compress, skip, light, restart

    public var title: String {
      switch self {
      case .shift: return String(localized: "Shift", bundle: ForgeCoreResources.bundle)
      case .compress: return String(localized: "Compress", bundle: ForgeCoreResources.bundle)
      case .skip: return String(localized: "Skip", bundle: ForgeCoreResources.bundle)
      case .light: return String(localized: "Go light", bundle: ForgeCoreResources.bundle)
      case .restart: return String(localized: "Restart week", bundle: ForgeCoreResources.bundle)
      }
    }

    public var detail: String {
      switch self {
      case .shift: return String(localized: "Keep the plan and carry on.", bundle: ForgeCoreResources.bundle)
      case .compress: return String(localized: "Fold the missed sessions into the rest of the week.", bundle: ForgeCoreResources.bundle)
      case .skip: return String(localized: "Drop the next session and move to the one after.", bundle: ForgeCoreResources.bundle)
      case .light: return String(localized: "Do the next session light.", bundle: ForgeCoreResources.bundle)
      case .restart: return String(localized: "Start this week over.", bundle: ForgeCoreResources.bundle)
      }
    }
  }

  public static func missedThisWeek(plannedPerWeek: Int, completedThisWeek: Int, daysLeftInWeek: Int) -> Int {
    max(0, plannedPerWeek - completedThisWeek)
  }

  public static func options(missed: Int, daysLeftInWeek: Int) -> [Option] {
    guard missed > 0 else { return [] }
    if missed <= daysLeftInWeek {
      return [.shift, .light, .skip]
    }
    var out: [Option] = [.compress, .light, .skip]
    if missed >= 2 { out.append(.restart) }
    return out
  }
}
