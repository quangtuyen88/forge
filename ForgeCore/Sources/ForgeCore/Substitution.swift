public enum InjuryFlag: String, CaseIterable, Codable, Sendable {
  case shoulder, knee, back

  public var name: String {
    switch self {
    case .shoulder: return String(localized: "Shoulder", bundle: ForgeCoreResources.bundle)
    case .knee: return String(localized: "Knee", bundle: ForgeCoreResources.bundle)
    case .back: return String(localized: "Back", bundle: ForgeCoreResources.bundle)
    }
  }
}

public enum Substitution {
  private static let map: [InjuryFlag: [String: String]] = [
    .shoulder: ["barbell_bench": "db_bench_neutral", "overhead_press": "landmine_press", "dips": "cable_fly"],
    .knee: ["back_squat": "leg_press", "lunge": "leg_extension"],
    .back: ["deadlift": "hip_thrust", "bent_row": "chest_supported_row"],
  ]

  public static func replacement(for exerciseID: String, flags: Set<InjuryFlag>) -> String? {
    for flag in [InjuryFlag.shoulder, .knee, .back] where flags.contains(flag) {
      if let sub = map[flag]?[exerciseID] { return sub }
    }
    return nil
  }

  public static func resolve(_ exercise: Exercise, flags: Set<InjuryFlag>) -> Exercise {
    guard let id = replacement(for: exercise.id, flags: flags) else { return exercise }
    return ExerciseDB.find(id) ?? exercise
  }
}
