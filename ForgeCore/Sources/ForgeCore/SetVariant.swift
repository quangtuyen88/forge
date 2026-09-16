public enum SetVariant: String, Codable, Sendable, CaseIterable {
  case straight, drop, restPause, myo

  public var label: String {
    switch self {
    case .straight: return String(localized: "Straight", bundle: .module)
    case .drop: return String(localized: "Drop set", bundle: .module)
    case .restPause: return String(localized: "Rest-pause", bundle: .module)
    case .myo: return String(localized: "Myo-reps", bundle: .module)
    }
  }

  public var hint: String {
    switch self {
    case .straight: return String(localized: "Same load and reps on every set.", bundle: .module)
    case .drop: return String(localized: "Cut the load 20–30 % after failure and keep going.", bundle: .module)
    case .restPause: return String(localized: "Rest 15–20 seconds, then squeeze out more reps at the same load.", bundle: .module)
    case .myo: return String(localized: "One activation set, then 20–30 % load with 5 breaths between mini-sets.", bundle: .module)
    }
  }
}
