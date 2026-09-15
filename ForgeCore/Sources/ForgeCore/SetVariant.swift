public enum SetVariant: String, Codable, Sendable, CaseIterable {
  case straight, drop, restPause, myo

  public var label: String {
    switch self {
    case .straight: return "Straight"
    case .drop: return "Drop set"
    case .restPause: return "Rest-pause"
    case .myo: return "Myo-reps"
    }
  }

  public var hint: String {
    switch self {
    case .straight: return "Same load and reps on every set."
    case .drop: return "Cut the load 20–30 % after failure and keep going."
    case .restPause: return "Rest 15–20 seconds, then squeeze out more reps at the same load."
    case .myo: return "One activation set, then 20–30 % load with 5 breaths between mini-sets."
    }
  }
}
