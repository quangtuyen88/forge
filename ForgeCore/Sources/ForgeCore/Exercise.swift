import Foundation

public enum Equipment: String, CaseIterable, Codable, Sendable {
  case barbell, dumbbell, machine, cable, bodyweight, bands

  var defaultIncrementKg: Double {
    switch self {
    case .barbell, .machine, .cable: return 2.5
    case .dumbbell, .bodyweight, .bands: return 1.0
    }
  }
}

public enum MovementPattern: String, Codable, Sendable {
  case horizontalPush, verticalPush, horizontalPull, verticalPull, squat, hinge, lunge, isolation, carry, core
}

public enum Difficulty: String, Codable, Sendable, CaseIterable {
  case beginner, intermediate, advanced

  public static func `default`(id: String, pattern: MovementPattern, equipment: Equipment, isCompound: Bool) -> Difficulty {
    let advancedIDs = ["clean", "snatch", "jerk", "pistol", "muscle_up", "handstand", "front_squat", "nordic"]
    if advancedIDs.contains(where: id.contains) { return .advanced }
    if (isCompound && (equipment == .barbell || equipment == .bodyweight)) || pattern == .hinge || pattern == .squat {
      return .intermediate
    }
    return .beginner
  }
}

public struct Exercise: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let name: String
  public let pattern: MovementPattern
  public let primary: Muscle
  public let synergists: [Muscle]
  public let isCompound: Bool
  public let equipment: Equipment
  public let difficulty: Difficulty
  public let smallestIncrementKg: Double

  public var restSeconds: Int { isCompound ? 180 : 90 }

  public var videoURL: URL? { ExerciseDB.videoBaseURL?.appending(path: "\(id).mp4") }

  public init(id: String, name: String, pattern: MovementPattern, primary: Muscle, synergists: [Muscle], isCompound: Bool, equipment: Equipment, difficulty: Difficulty? = nil) {
    self.id = id
    self.name = name
    self.pattern = pattern
    self.primary = primary
    self.synergists = synergists
    self.isCompound = isCompound
    self.equipment = equipment
    self.difficulty = difficulty ?? .default(id: id, pattern: pattern, equipment: equipment, isCompound: isCompound)
    self.smallestIncrementKg = equipment.defaultIncrementKg
  }
}
