import Foundation

public struct GymProfileConfig: Codable, Hashable, Identifiable, Sendable {
  public var id: String
  public var name: String
  public var equipment: Set<Equipment>

  public init(id: String = UUID().uuidString, name: String, equipment: Set<Equipment>) {
    self.id = id
    self.name = name
    self.equipment = equipment
  }

  public static let commercial = GymProfileConfig(
    id: "commercial", name: "Commercial gym", equipment: Set(Equipment.allCases))
  public static let home = GymProfileConfig(
    id: "home", name: "Home gym", equipment: [.barbell, .dumbbell, .bodyweight, .bands])
  public static let hotel = GymProfileConfig(
    id: "hotel", name: "Hotel", equipment: [.dumbbell, .bodyweight, .bands])
  public static let defaults = [commercial, home, hotel]
}

public struct TrainingConstraints: Codable, Equatable, Sendable {
  public var gymProfiles: [GymProfileConfig]
  public var activeGymProfileID: String
  public var lockedExerciseIDs: Set<String>
  public var excludedExerciseIDs: Set<String>
  public var travelMode: Bool
  public var crowdMode: Bool
  public var sessionBudgetMinutes: Int?
  public var minimumEffectiveWorkout: Bool
  public var focusModeDefault: Bool

  public init(
    gymProfiles: [GymProfileConfig] = GymProfileConfig.defaults,
    activeGymProfileID: String = "commercial",
    lockedExerciseIDs: Set<String> = [],
    excludedExerciseIDs: Set<String> = [],
    travelMode: Bool = false,
    crowdMode: Bool = false,
    sessionBudgetMinutes: Int? = nil,
    minimumEffectiveWorkout: Bool = false,
    focusModeDefault: Bool = false
  ) {
    self.gymProfiles = gymProfiles.isEmpty ? GymProfileConfig.defaults : gymProfiles
    self.activeGymProfileID = activeGymProfileID
    self.lockedExerciseIDs = lockedExerciseIDs
    self.excludedExerciseIDs = excludedExerciseIDs
    self.travelMode = travelMode
    self.crowdMode = crowdMode
    self.sessionBudgetMinutes = sessionBudgetMinutes
    self.minimumEffectiveWorkout = minimumEffectiveWorkout
    self.focusModeDefault = focusModeDefault
  }

  public var activeGymProfile: GymProfileConfig? {
    gymProfiles.first { $0.id == activeGymProfileID } ?? gymProfiles.first
  }
}

public enum TrainingConstraintEngine {
  public static func effectiveEquipment(base: Set<Equipment>, constraints: TrainingConstraints)
    -> Set<Equipment>
  {
    var equipment = constraints.activeGymProfile?.equipment ?? base
    if constraints.travelMode {
      equipment.formIntersection([.dumbbell, .bodyweight, .bands])
    }
    if constraints.crowdMode {
      equipment.subtract([.machine, .cable])
    }
    return equipment.isEmpty ? base : equipment
  }

  public static func exerciseLimit(minutes: Int, minimumEffective: Bool) -> Int {
    if minimumEffective { return 3 }
    switch minutes {
    case ..<25: return 3
    case 25..<55: return 4
    case 55..<75: return 6
    default: return 8
    }
  }

  public static func setBudget(minutes: Int, minimumEffective: Bool) -> Int {
    let normal = max(6, minutes * 2 / 5)
    return minimumEffective ? min(normal, 8) : normal
  }
}

public enum TrainingExperimentIntervention: String, Codable, CaseIterable, Sendable {
  case addSet, lowerRepRange

  public var name: String {
    switch self {
    case .addSet: return "Add one set"
    case .lowerRepRange: return "Use a lower rep range"
    }
  }
}

public enum TrainingExperimentStatus: String, Codable, Sendable {
  case active, kept, reverted
}

public struct TrainingExperiment: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var exerciseID: String
  public var intervention: TrainingExperimentIntervention
  public var startedAt: Date
  public var durationWeeks: Int
  public var baselineE1RM: Double
  public var previousSetDelta: Int
  public var previousRepRange: String?
  public var status: TrainingExperimentStatus

  public init(
    id: String = UUID().uuidString,
    exerciseID: String,
    intervention: TrainingExperimentIntervention,
    startedAt: Date = .now,
    durationWeeks: Int = 4,
    baselineE1RM: Double,
    previousSetDelta: Int = 0,
    previousRepRange: String? = nil,
    status: TrainingExperimentStatus = .active
  ) {
    self.id = id
    self.exerciseID = exerciseID
    self.intervention = intervention
    self.startedAt = startedAt
    self.durationWeeks = durationWeeks
    self.baselineE1RM = baselineE1RM
    self.previousSetDelta = previousSetDelta
    self.previousRepRange = previousRepRange
    self.status = status
  }

  public var endsAt: Date {
    Calendar.current.date(byAdding: .day, value: durationWeeks * 7, to: startedAt) ?? startedAt
  }

  public func isReady(asOf date: Date = .now) -> Bool { date >= endsAt }
}

public enum CoachMemoryKind: String, Codable, CaseIterable, Sendable {
  case equipment, injury, schedule, preference, goal, other

  public var name: String { rawValue.capitalized }

  public static func infer(from text: String) -> CoachMemoryKind {
    let value = text.lowercased()
    if value.contains("gym") || value.contains("machine") || value.contains("cable")
      || value.contains("equipment")
    {
      return .equipment
    }
    if value.contains("pain") || value.contains("sore") || value.contains("knee")
      || value.contains("shoulder") || value.contains("back")
    {
      return .injury
    }
    if value.contains("day") || value.contains("schedule") || value.contains("travel")
      || value.contains("week")
    {
      return .schedule
    }
    if value.contains("goal") || value.contains("target") { return .goal }
    if value.contains("prefer") || value.contains("avoid") || value.contains("refuse") {
      return .preference
    }
    return .other
  }
}
