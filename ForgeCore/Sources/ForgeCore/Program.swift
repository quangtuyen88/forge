import Foundation

public enum Goal: String, CaseIterable, Codable, Sendable {
  case hypertrophy, strength, both

  public var name: String {
    switch self {
    case .hypertrophy: return String(localized: "Hypertrophy", bundle: ForgeCoreResources.bundle)
    case .strength: return String(localized: "Strength", bundle: ForgeCoreResources.bundle)
    case .both: return String(localized: "Both", bundle: ForgeCoreResources.bundle)
    }
  }
}

public enum Experience: String, CaseIterable, Codable, Sendable {
  case postBeginner, intermediate, advanced

  public var name: String {
    switch self {
    case .postBeginner: return String(localized: "Post-beginner", bundle: ForgeCoreResources.bundle)
    case .intermediate: return String(localized: "Intermediate", bundle: ForgeCoreResources.bundle)
    case .advanced: return String(localized: "Advanced", bundle: ForgeCoreResources.bundle)
    }
  }
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

public enum SplitStyle: String, Codable, Sendable, CaseIterable {
  case auto, fullBody, upperLower, pushPullLegs, pushPull, arnold

  public var name: String {
    switch self {
    case .auto: return String(localized: "Auto", bundle: ForgeCoreResources.bundle)
    case .fullBody: return String(localized: "Full body", bundle: ForgeCoreResources.bundle)
    case .upperLower: return String(localized: "Upper / Lower", bundle: ForgeCoreResources.bundle)
    case .pushPullLegs: return String(localized: "Push / Pull / Legs", bundle: ForgeCoreResources.bundle)
    case .pushPull: return String(localized: "Push / Pull", bundle: ForgeCoreResources.bundle)
    case .arnold: return String(localized: "Arnold", bundle: ForgeCoreResources.bundle)
    }
  }
}

public struct ProfileInput: Sendable {
  public var goal: Goal
  public var experience: Experience = .intermediate
  public var daysPerWeek: Int
  public var sessionLength: SessionLength
  public var equipment: Set<Equipment>
  public var injuryFlags: Set<InjuryFlag>
  public var recoveryReduced: Bool
  public var plateauedExerciseIDs: Set<String> = []
  public var split: SplitStyle = .auto
  public var exerciseOverrides: [String: String] = [:]
  public var setDeltas: [String: Int] = [:]
  public var repRangeOverrides: [String: ClosedRange<Int>] = [:]
  public var lockedExerciseIDs: Set<String> = []
  public var excludedExerciseIDs: Set<String> = []
  public var sessionBudgetMinutes: Int? = nil
  public var minimumEffectiveWorkout: Bool = false

  public init(
    goal: Goal,
    experience: Experience = .intermediate,
    daysPerWeek: Int,
    sessionLength: SessionLength,
    equipment: Set<Equipment>,
    injuryFlags: Set<InjuryFlag> = [],
    recoveryReduced: Bool = false,
    plateauedExerciseIDs: Set<String> = [],
    split: SplitStyle = .auto,
    exerciseOverrides: [String: String] = [:],
    setDeltas: [String: Int] = [:],
    repRangeOverrides: [String: ClosedRange<Int>] = [:],
    lockedExerciseIDs: Set<String> = [],
    excludedExerciseIDs: Set<String> = [],
    sessionBudgetMinutes: Int? = nil,
    minimumEffectiveWorkout: Bool = false
  ) {
    self.goal = goal
    self.experience = experience
    self.daysPerWeek = daysPerWeek
    self.sessionLength = sessionLength
    self.equipment = equipment
    self.injuryFlags = injuryFlags
    self.recoveryReduced = recoveryReduced
    self.plateauedExerciseIDs = plateauedExerciseIDs
    self.split = split
    self.exerciseOverrides = exerciseOverrides
    self.setDeltas = setDeltas
    self.repRangeOverrides = repRangeOverrides
    self.lockedExerciseIDs = lockedExerciseIDs
    self.excludedExerciseIDs = excludedExerciseIDs
    self.sessionBudgetMinutes = sessionBudgetMinutes
    self.minimumEffectiveWorkout = minimumEffectiveWorkout
  }

  /// Parses "5-8" / "5–8" (hyphen or en dash). Nil on anything else or low > high.
  public static func repRange(_ string: String) -> ClosedRange<Int>? {
    let parts = string.split(whereSeparator: { $0 == "-" || $0 == "–" }).compactMap { Int(String($0)) }
    guard parts.count == 2, parts[0] <= parts[1] else { return nil }
    return parts[0]...parts[1]
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

extension PlannedExercise: Identifiable { public var id: String { exercise.id } }

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

extension PlannedDay: Identifiable { public var id: String { name } }

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

  private static let templates: [String: [Slot]] = {
    let push: [Slot] = [
      Slot(.chest, .horizontalPush, compound: true),
      Slot(.frontDelts, .verticalPush),
      Slot(.chest, compound: false),
      Slot(.sideDelts),
      Slot(.triceps),
    ]
    let pull: [Slot] = [
      Slot(.back, .verticalPull),
      Slot(.back, .horizontalPull),
      Slot(.rearDelts),
      Slot(.biceps),
      Slot(.forearms),
    ]
    var t: [String: [Slot]] = [
      "Push": push,
      "Pull": pull,
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
    t["Push+"] = push + [
      Slot(.quads, .squat),
      Slot(.quads, .isolation, compound: false),
    ]
    t["Pull+"] = pull + [
      Slot(.hamstrings, .hinge),
      Slot(.glutes),
    ]
    t["Chest+Back"] = [
      Slot(.chest, .horizontalPush),
      Slot(.back, .horizontalPull),
      Slot(.chest, compound: false),
      Slot(.back, .verticalPull),
      Slot(.chest, compound: false, preferredIDs: ["incline_cable_fly", "incline_db_fly"]),
      Slot(.rearDelts),
    ]
    t["Shoulders+Arms"] = [
      Slot(.frontDelts, .verticalPush),
      Slot(.sideDelts),
      Slot(.rearDelts),
      Slot(.biceps),
      Slot(.triceps),
      Slot(.biceps, compound: false),
      Slot(.triceps, compound: false),
    ]
    return t
  }()

  private static let dbOrder: [String: Int] = Dictionary(uniqueKeysWithValues: ExerciseDB.all.enumerated().map { ($1.id, $0) })

  public static func split(daysPerWeek: Int, style: SplitStyle = .auto) -> [String] {
    switch (style, daysPerWeek) {
    case (.fullBody, 3): return ["Full A", "Full B", "Full C"]
    case (.fullBody, 4): return ["Full A", "Full B", "Full C", "Full A"]
    case (.upperLower, 3): return ["Upper", "Lower", "Upper"]
    case (.upperLower, 4): return ["Upper", "Lower", "Upper", "Lower"]
    case (.upperLower, 6): return ["Upper", "Lower", "Upper", "Lower", "Upper", "Lower"]
    case (.upperLower, 2): return ["Upper", "Lower"]
    case (.pushPullLegs, 3): return ["Push", "Pull", "Legs"]
    case (.pushPullLegs, 6): return ["Push", "Pull", "Legs", "Push", "Pull", "Legs"]
    case (.pushPull, 4): return ["Push+", "Pull+", "Push+", "Pull+"]
    case (.pushPull, 6): return ["Push+", "Pull+", "Push+", "Pull+", "Push+", "Pull+"]
    case (.arnold, 3): return ["Chest+Back", "Shoulders+Arms", "Legs"]
    case (.arnold, 6): return ["Chest+Back", "Shoulders+Arms", "Legs", "Chest+Back", "Shoulders+Arms", "Legs"]
    default: break
    }
    switch daysPerWeek {
    case 2: return ["Full A", "Full B"]
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
    let names = split(daysPerWeek: profile.daysPerWeek, style: profile.split)
    let days = names.compactMap { templates[$0] }
    let minutes = profile.sessionBudgetMinutes ?? profile.sessionLength.rawValue
    let exerciseLimit = TrainingConstraintEngine.exerciseLimit(
      minutes: minutes,
      minimumEffective: profile.minimumEffectiveWorkout)
    var daySlots: [[Slot]] = days.map { Array($0.prefix(exerciseLimit)) }
    var slotsPerMuscle: [Muscle: Int] = [:]
    for day in daySlots {
      for slot in day { slotsPerMuscle[slot.muscle, default: 0] += 1 }
    }
    let needs = slotsPerMuscle.compactMap { muscle, slots -> (muscle: Muscle, peak: Int, slots: Int, extra: Int)? in
      guard let peak = Mesocycle.targetSets(muscle: muscle, week: Mesocycle.weeks - 1, recoveryReduced: profile.recoveryReduced) else { return nil }
      let extra = Int(ceil(Double(peak) / Double(Mesocycle.maxSetsPerSlot))) - slots
      return extra > 0 ? (muscle, peak, slots, extra) : nil
    }.sorted {
      let left = Double($0.peak) / Double($0.slots)
      let right = Double($1.peak) / Double($1.slots)
      return left != right ? left > right : $0.muscle.rawValue < $1.muscle.rawValue
    }
    planning: for need in needs {
      for _ in 0..<need.extra {
        guard let lastDay = daySlots.lastIndex(where: { $0.contains { $0.muscle == need.muscle } }) else { break planning }
        var firstWithRoom: Int?
        var placed: Int?
        for offset in daySlots.indices {
          let day = (lastDay + 1 + offset) % daySlots.count
          guard daySlots[day].count < exerciseLimit else { continue }
          if firstWithRoom == nil { firstWithRoom = day }
          if !daySlots[day].contains(where: { $0.muscle == need.muscle }) { placed = day; break }
        }
        guard let day = placed ?? firstWithRoom else { break planning }
        daySlots[day].append(Slot(need.muscle, compound: false))
        slotsPerMuscle[need.muscle, default: 0] += 1
      }
    }
    var slotIndex: [Muscle: Int] = [:]
    let budget = TrainingConstraintEngine.setBudget(
      minutes: minutes,
      minimumEffective: profile.minimumEffectiveWorkout)
    return zip(names, daySlots).map { name, slots in
      var used: Set<String> = []
      var exercises: [PlannedExercise] = []
      for slot in slots {
        guard let picked = pick(slot, profile: profile, used: used) else { continue }
        used.insert(picked.exercise.id)
        let target = Mesocycle.targetSets(muscle: slot.muscle, week: week, recoveryReduced: profile.recoveryReduced) ?? 8
        let weekly: Int
        if let landmarks = VolumeLandmarks.landmarks(for: slot.muscle, recoveryReduced: profile.recoveryReduced) {
          // Recovery-limited lifters may train down to maintenance volume; everyone else keeps MEV.
          weekly = min(max(target + (volumeDelta[slot.muscle] ?? 0), landmarks.floor(recoveryReduced: profile.recoveryReduced)), landmarks.mrv)
        } else {
          weekly = max(2, target + (volumeDelta[slot.muscle] ?? 0))
        }
        let count = max(slotsPerMuscle[slot.muscle] ?? 1, 1)
        let index = slotIndex[slot.muscle, default: 0]
        slotIndex[slot.muscle] = index + 1
        let raw = min(Mesocycle.maxSetsPerSlot, max(2, weekly / count + (index < weekly % count ? 1 : 0))) + (picked.bump ? 1 : 0)
        let sets = min(Mesocycle.maxSetsPerSlot, max(2, raw + (profile.setDeltas[picked.exercise.id] ?? 0)))
        exercises.append(PlannedExercise(
          exercise: picked.exercise,
          sets: sets,
          repRange: profile.repRangeOverrides[picked.exercise.id] ?? repRange(picked.exercise, goal: profile.goal),
          targetRPE: 8.0))
      }
      var trimmed = 0
      while exercises.reduce(0, { $0 + $1.sets }) > budget {
        guard let index = exercises.indices
          .filter({ exercises[$0].sets > 2 })
          .max(by: { (exercises[$0].sets, $0) < (exercises[$1].sets, $1) }) else { break }
        exercises[index] = PlannedExercise(
          exercise: exercises[index].exercise,
          sets: exercises[index].sets - 1,
          repRange: exercises[index].repRange,
          targetRPE: exercises[index].targetRPE)
        trimmed += 1
      }
      while exercises.reduce(0, { $0 + $1.sets }) > budget, exercises.count > 1 {
        let removable = exercises.indices.reversed().first { index in
          let exercise = exercises[index].exercise
          return !profile.lockedExerciseIDs.contains(exercise.id) && !exercise.isCompound
        } ?? exercises.indices.reversed().first { !profile.lockedExerciseIDs.contains(exercises[$0].exercise.id) }
        guard let index = removable else { break }
        trimmed += exercises[index].sets
        exercises.remove(at: index)
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
    func difficultyAllowed(_ difficulty: Difficulty) -> Bool {
      difficulty != .advanced || profile.experience == .advanced
    }
    func safe(_ exercise: Exercise) -> Bool {
      profile.equipment.contains(exercise.equipment)
        && !profile.excludedExerciseIDs.contains(exercise.id)
        && difficultyAllowed(exercise.difficulty)
        && exercise.primary == slot.muscle
        && !used.contains(exercise.id)
    }
    let available = ExerciseDB.matching(equipment: profile.equipment).filter {
      !$0.id.hasPrefix("custom_") && !profile.excludedExerciseIDs.contains($0.id)
    }
    func exact(_ exercise: Exercise) -> Bool {
      exercise.primary == slot.muscle
        && (slot.patterns.isEmpty || slot.patterns.contains(exercise.pattern))
        && (slot.compound == nil || exercise.isCompound == slot.compound!)
        && !used.contains(exercise.id)
        && difficultyAllowed(exercise.difficulty)
    }
    var pool = available.filter(exact)
    if pool.isEmpty {
      pool = available.filter {
        $0.primary == slot.muscle && !used.contains($0.id) && difficultyAllowed($0.difficulty)
      }
    }
    let ranked = pool.sorted { rank($0, slot, profile) < rank($1, slot, profile) }
    let fresh = ranked.filter { !profile.plateauedExerciseIDs.contains($0.id) }
    let allPlateaued = fresh.isEmpty && !ranked.isEmpty
    for candidate in allPlateaued ? [ranked[0]] : fresh {
      let resolved = Substitution.resolve(candidate, flags: profile.injuryFlags)
      guard safe(resolved) else { continue }
      if let overrideID = profile.exerciseOverrides[resolved.id],
         let override = ExerciseDB.find(overrideID),
         safe(override) {
        return (override, allPlateaued)
      }
      return (resolved, allPlateaued)
    }
    return nil
  }

  private static func difficultyRank(_ d: Difficulty, _ experience: Experience) -> Int {
    switch experience {
    case .postBeginner:
      switch d {
      case .beginner: return 0
      case .intermediate: return 1
      case .advanced: return 2
      }
    case .intermediate:
      switch d {
      case .intermediate: return 0
      case .beginner: return 1
      case .advanced: return 2
      }
    case .advanced:
      switch d {
      case .advanced: return 0
      case .intermediate: return 1
      case .beginner: return 2
      }
    }
  }

  private static func rank(_ exercise: Exercise, _ slot: Slot, _ profile: ProfileInput) -> (Int, Int, Int, Int, Int, Int) {
    (
      profile.lockedExerciseIDs.contains(exercise.id) ? 0 : 1,
      slot.preferredIDs.firstIndex(of: exercise.id) ?? .max,
      slot.patterns.firstIndex(of: exercise.pattern) ?? .max,
      difficultyRank(exercise.difficulty, profile.experience),
      exercise.isCompound ? 0 : 1,
      dbOrder[exercise.id] ?? .max
    )
  }
}
