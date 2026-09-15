import Foundation

public enum Goal: String, CaseIterable, Codable, Sendable {
  case hypertrophy, strength, both
}

public enum Experience: String, CaseIterable, Codable, Sendable {
  case postBeginner, intermediate, advanced
}

public enum SessionLength: Int, CaseIterable, Codable, Sendable {
  case m45 = 45, m60 = 60, m90 = 90

  public var maxExercises: Int {
    switch self {
    case .m45: return 4
    case .m60: return 6
    case .m90: return 8
    }
  }
}

public struct ProfileInput: Sendable {
  public var goal: Goal
  public var daysPerWeek: Int
  public var sessionLength: SessionLength
  public var equipment: Set<Equipment>
  public var injuryFlags: Set<InjuryFlag>
  public var recoveryReduced: Bool
  public var plateauedExerciseIDs: Set<String> = []

  public init(goal: Goal, daysPerWeek: Int, sessionLength: SessionLength, equipment: Set<Equipment>, injuryFlags: Set<InjuryFlag> = [], recoveryReduced: Bool = false, plateauedExerciseIDs: Set<String> = []) {
    self.goal = goal
    self.daysPerWeek = daysPerWeek
    self.sessionLength = sessionLength
    self.equipment = equipment
    self.injuryFlags = injuryFlags
    self.recoveryReduced = recoveryReduced
    self.plateauedExerciseIDs = plateauedExerciseIDs
  }
}

public struct PlannedExercise: Hashable, Sendable {
  public let exercise: Exercise
  public let sets: Int
  public let repRange: ClosedRange<Int>
  public let targetRPE: Double

  public init(exercise: Exercise, sets: Int, repRange: ClosedRange<Int>, targetRPE: Double) {
    self.exercise = exercise
    self.sets = sets
    self.repRange = repRange
    self.targetRPE = targetRPE
  }
}

public struct PlannedDay: Hashable, Sendable {
  public let name: String
  public let exercises: [PlannedExercise]
  public let trimmedSets: Int

  public init(name: String, exercises: [PlannedExercise], trimmedSets: Int = 0) {
    self.name = name
    self.exercises = exercises
    self.trimmedSets = trimmedSets
  }
}

public enum Program {
  private struct Slot {
    let muscle: Muscle
    var patterns: [MovementPattern] = []
    var compound: Bool?
    var preferredIDs: [String] = []

    init(_ muscle: Muscle, _ patterns: MovementPattern..., compound: Bool? = nil, preferredIDs: [String] = []) {
      self.muscle = muscle
      self.patterns = patterns
      self.compound = compound
      self.preferredIDs = preferredIDs
    }
  }

  private static let templates: [String: [Slot]] = [
    "Push": [
      Slot(.chest, .horizontalPush, compound: true),
      Slot(.frontDelts, .verticalPush),
      Slot(.chest, compound: false),
      Slot(.sideDelts),
      Slot(.triceps),
    ],
    "Pull": [
      Slot(.back, .verticalPull),
      Slot(.back, .horizontalPull),
      Slot(.rearDelts),
      Slot(.biceps),
      Slot(.forearms),
    ],
    "Legs": [
      Slot(.quads, .squat),
      Slot(.hamstrings, .hinge),
      Slot(.quads, .lunge, .isolation),
      Slot(.calves),
      Slot(.abs),
    ],
    "Upper": [
      Slot(.chest, .horizontalPush),
      Slot(.back, .horizontalPull),
      Slot(.frontDelts, .verticalPush),
      Slot(.back, .verticalPull),
      Slot(.sideDelts),
      Slot(.biceps),
      Slot(.triceps),
    ],
    "Lower": [
      Slot(.quads, .squat),
      Slot(.hamstrings, .hinge),
      Slot(.glutes),
      Slot(.quads, .isolation, compound: false),
      Slot(.hamstrings, .isolation, compound: false),
      Slot(.calves),
      Slot(.abs),
    ],
    "Full A": [
      Slot(.quads, .squat),
      Slot(.chest, .horizontalPush),
      Slot(.back, .horizontalPull),
      Slot(.sideDelts),
      Slot(.abs),
    ],
    "Full B": [
      Slot(.hamstrings, .hinge),
      Slot(.frontDelts, .verticalPush),
      Slot(.back, .verticalPull),
      Slot(.biceps),
      Slot(.calves),
    ],
    "Full C": [
      Slot(.quads, .lunge, .squat),
      Slot(.chest, .horizontalPush, preferredIDs: ["incline_db_press", "incline_barbell_press", "db_bench_neutral"]),
      Slot(.back, .horizontalPull),
      Slot(.triceps),
      Slot(.rearDelts),
    ],
  ]

  private static let dbOrder: [String: Int] = Dictionary(uniqueKeysWithValues: ExerciseDB.all.enumerated().map { ($1.id, $0) })

  public static func split(daysPerWeek: Int) -> [String] {
    switch daysPerWeek {
    case 3: return ["Full A", "Full B", "Full C"]
    case 4: return ["Upper", "Lower", "Upper", "Lower"]
    case 5: return ["Upper", "Lower", "Push", "Pull", "Legs"]
    default: return ["Push", "Pull", "Legs", "Push", "Pull", "Legs"]
    }
  }

  public static func setBudget(for length: SessionLength) -> Int { length.rawValue * 2 / 5 }

  public static func week(_ week: Int, profile: ProfileInput, volumeDelta: [Muscle: Int] = [:]) -> [PlannedDay] {
    if week == Mesocycle.deloadWeek {
      return self.week(Mesocycle.weeks - 1, profile: profile).map { day in
        PlannedDay(name: day.name, exercises: day.exercises.map {
          PlannedExercise(exercise: $0.exercise, sets: max(2, Int((Double($0.sets) * Mesocycle.deloadVolumeMultiplier).rounded())), repRange: $0.repRange, targetRPE: Mesocycle.deloadRPECap)
        })
      }
    }
    let names = split(daysPerWeek: profile.daysPerWeek)
    let days = names.compactMap { templates[$0] }
    var daySlots: [[Slot]] = days.map { Array($0.prefix(profile.sessionLength.maxExercises)) }
    var slotsPerMuscle: [Muscle: Int] = [:]
    for day in daySlots {
      for slot in day { slotsPerMuscle[slot.muscle, default: 0] += 1 }
    }
    let needs = slotsPerMuscle.compactMap { m, slots -> (muscle: Muscle, peak: Int, slots: Int, extra: Int)? in
      guard let peak = Mesocycle.targetSets(muscle: m, week: Mesocycle.weeks - 1, recoveryReduced: profile.recoveryReduced) else { return nil }
      let extra = Int(ceil(Double(peak) / Double(Mesocycle.maxSetsPerSlot))) - slots
      return extra > 0 ? (m, peak, slots, extra) : nil
    }.sorted {
      let l = Double($0.peak) / Double($0.slots), r = Double($1.peak) / Double($1.slots)
      return l != r ? l > r : $0.muscle.rawValue < $1.muscle.rawValue
    }
    planning: for need in needs {
      for _ in 0..<need.extra {
        guard let lastDay = daySlots.lastIndex(where: { $0.contains { $0.muscle == need.muscle } }) else { break planning }
        var firstWithRoom: Int?
        var placed: Int?
        for offset in daySlots.indices {
          let d = (lastDay + 1 + offset) % daySlots.count
          guard daySlots[d].count < profile.sessionLength.maxExercises else { continue }
          if firstWithRoom == nil { firstWithRoom = d }
          if !daySlots[d].contains(where: { $0.muscle == need.muscle }) { placed = d; break }
        }
        guard let d = placed ?? firstWithRoom else { break planning }
        daySlots[d].append(Slot(need.muscle, compound: false))
        slotsPerMuscle[need.muscle, default: 0] += 1
      }
    }
    var slotIndex: [Muscle: Int] = [:]
    let budget = setBudget(for: profile.sessionLength)
    return zip(names, daySlots).map { name, slots in
      var used: Set<String> = []
      var exercises: [PlannedExercise] = []
      for slot in slots {
        guard let picked = pick(slot, profile: profile, used: used) else { continue }
        used.insert(picked.exercise.id)
        // ponytail: frontDelts/forearms have no landmark rows; default weekly 8 until PRD adds them
        let target = Mesocycle.targetSets(muscle: slot.muscle, week: week, recoveryReduced: profile.recoveryReduced) ?? 8
        let weekly: Int
        if let l = VolumeLandmarks.landmarks(for: slot.muscle, recoveryReduced: profile.recoveryReduced) {
          weekly = min(max(target + (volumeDelta[slot.muscle] ?? 0), l.mev), l.mrv)
        } else {
          weekly = max(2, target + (volumeDelta[slot.muscle] ?? 0))
        }
        // ponytail: budget trims the biggest slot first; a smarter trim would protect compounds explicitly
        let n = max(slotsPerMuscle[slot.muscle] ?? 1, 1)
        let i = slotIndex[slot.muscle, default: 0]
        slotIndex[slot.muscle] = i + 1
        let sets = min(Mesocycle.maxSetsPerSlot, max(2, weekly / n + (i < weekly % n ? 1 : 0)))
        exercises.append(PlannedExercise(exercise: picked.exercise, sets: sets + (picked.bump ? 1 : 0), repRange: repRange(picked.exercise, goal: profile.goal), targetRPE: 8.0))
      }
      var trimmed = 0
      while exercises.reduce(0, { $0 + $1.sets }) > budget {
        guard let i = exercises.indices.filter({ exercises[$0].sets > 2 }).max(by: { (exercises[$0].sets, $0) < (exercises[$1].sets, $1) }) else { break }
        exercises[i] = PlannedExercise(exercise: exercises[i].exercise, sets: exercises[i].sets - 1, repRange: exercises[i].repRange, targetRPE: exercises[i].targetRPE)
        trimmed += 1
      }
      return PlannedDay(name: name, exercises: exercises, trimmedSets: trimmed)
    }
  }

  public static func repRange(_ exercise: Exercise, goal: Goal) -> ClosedRange<Int> {
    switch goal {
    case .strength: return exercise.isCompound ? 4...6 : 8...12
    case .hypertrophy: return exercise.isCompound ? 8...12 : 12...15
    case .both: return exercise.isCompound ? 6...10 : 10...15
    }
  }

  private static func pick(_ slot: Slot, profile: ProfileInput, used: Set<String>) -> (exercise: Exercise, bump: Bool)? {
    func matches(_ ex: Exercise) -> Bool {
      ex.primary == slot.muscle
        && (slot.patterns.isEmpty || slot.patterns.contains(ex.pattern))
        && (slot.compound == nil || ex.isCompound == slot.compound!)
        && !used.contains(ex.id)
    }
    var pool = ExerciseDB.matching(equipment: profile.equipment).filter(matches)
    if pool.isEmpty { pool = ExerciseDB.all.filter(matches) }
    let ranked = pool.sorted { rank($0, slot) < rank($1, slot) }
    let fresh = ranked.filter { !profile.plateauedExerciseIDs.contains($0.id) }
    let allPlateaued = fresh.isEmpty && !ranked.isEmpty
    for candidate in allPlateaued ? [ranked[0]] : fresh {
      let resolved = Substitution.resolve(candidate, flags: profile.injuryFlags)
      if !used.contains(resolved.id) { return (resolved, allPlateaued) }
    }
    return nil
  }

  private static func rank(_ ex: Exercise, _ slot: Slot) -> (Int, Int, Int, Int) {
    (
      slot.preferredIDs.firstIndex(of: ex.id) ?? .max,
      slot.patterns.firstIndex(of: ex.pattern) ?? .max,
      ex.isCompound ? 0 : 1,
      dbOrder[ex.id] ?? .max
    )
  }
}
