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

public struct Exercise: Identifiable, Hashable, Codable, Sendable {
  public let id: String
  public let name: String
  public let pattern: MovementPattern
  public let primary: Muscle
  public let synergists: [Muscle]
  public let isCompound: Bool
  public let equipment: Equipment
  public let smallestIncrementKg: Double

  public var restSeconds: Int { isCompound ? 180 : 90 }

  public init(id: String, name: String, pattern: MovementPattern, primary: Muscle, synergists: [Muscle], isCompound: Bool, equipment: Equipment) {
    self.id = id
    self.name = name
    self.pattern = pattern
    self.primary = primary
    self.synergists = synergists
    self.isCompound = isCompound
    self.equipment = equipment
    self.smallestIncrementKg = equipment.defaultIncrementKg
  }
}
