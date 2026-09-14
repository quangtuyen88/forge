import SwiftUI

enum Coach: String, CaseIterable, Identifiable {
  case nova, kai
  static let storageKey = "coachID"
  var id: String { rawValue }
  var name: String { self == .nova ? "Nova" : "Kai" }
  var tagline: String { self == .nova ? "Calm, precise, relentless." : "Big energy, bigger lifts." }
  var avatar: String { self == .nova ? "coach-avatar" : "kai-avatar" }
  var hero: String { self == .nova ? "coach-hero" : "kai-hero" }
  var wave: String { self == .nova ? "coach-wave" : "kai-wave" }
  var point: String { self == .nova ? "coach-point" : "kai-point" }
  var flex: String { self == .nova ? "coach-flex" : "kai-flex" }
  var bench: String { self == .nova ? "coach-bench" : "kai-bench" }
  static func from(_ id: String) -> Coach { Coach(rawValue: id) ?? .nova }
}
