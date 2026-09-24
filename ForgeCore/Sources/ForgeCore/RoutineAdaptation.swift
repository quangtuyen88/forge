import Foundation

// MARK: - Copy routine → Adapt to me
//
// Pure, deterministic extraction and adaptation of a reusable, load-free routine
// (`ProgramDay`) against one lifter's `ProfileInput`. No storage, no SwiftData and
// no clock: every function is a pure mapping callers can test directly.
//
// What never happens here:
//   * loads, reported effort, equipment-instance ids and personal notes are never
//     inputs, so they can never reach a saved routine;
//   * an unknown exercise is reported, never silently dropped;
//   * a constraint conflict (excluded lift, irreplaceable equipment) blocks the
//     entry instead of quietly violating the constraint;
//   * the source shape is preserved — entries are swapped, trimmed or blocked in
//     place, never replaced with an unrelated generated plan.

/// One logged set reduced to what copying a routine may keep: the exercise, the set
/// slot, the reps, and the plan's target. Warm-ups never appear — they are computed
/// for display and never persisted as sets.
public struct RoutineSetInput: Codable, Sendable, Equatable {
  public let exerciseID: String
  /// Label for exercises the catalogue cannot resolve; `nil` for known lifts.
  public let exerciseName: String?
  public let setIndex: Int
  public let reps: Int
  /// The plan target the set was logged against — a prescription, never a report.
  public let targetRPE: Double?

  public init(
    exerciseID: String,
    exerciseName: String? = nil,
    setIndex: Int,
    reps: Int,
    targetRPE: Double? = nil
  ) {
    self.exerciseID = exerciseID
    self.exerciseName = exerciseName
    self.setIndex = setIndex
    self.reps = reps
    self.targetRPE = targetRPE
  }
}

// MARK: - Extraction

public enum RoutineExtractionCode: String, Codable, Sendable, CaseIterable {
  /// The session recorded no usable working sets for this exercise.
  case noWorkingSets
  /// The exercise is not in the catalogue. It is kept with its name; it cannot be
  /// machine-planned and adaptation will block it.
  case unknownExercise
  /// The logged working-set count exceeded the validator's bound and was capped.
  case setCountCapped
  /// Sets with invalid reps were not counted.
  case invalidSetsDropped
  /// Working sets disagreed on the plan target, so no target is carried over.
  case targetRPEDropped
}

public struct RoutineExtractionNote: Codable, Sendable, Equatable, Identifiable {
  public let code: RoutineExtractionCode
  public let exerciseName: String
  /// Count behind the note (dropped sets), when there is one.
  public let value: Int?
  public var id: String { "\(code.rawValue):\(exerciseName)" }

  public init(code: RoutineExtractionCode, exerciseName: String, value: Int? = nil) {
    self.code = code
    self.exerciseName = exerciseName
    self.value = value
  }
}

public struct RoutineExtraction: Codable, Sendable, Equatable {
  /// The load-free routine, or `nil` when nothing valid could be extracted.
  public let day: ProgramDay?
  public let notes: [RoutineExtractionNote]

  public init(day: ProgramDay?, notes: [RoutineExtractionNote]) {
    self.day = day
    self.notes = notes
  }
}

public enum RoutineExtractionPolicy {
  /// Sane rep bounds for a copied range. The validator's set bound is reused for counts.
  public static let maxReps = 50

  /// Reduces a finished session's sets to a reusable routine day.
  ///
  /// Order is first appearance in the given set order; a set counts as a working
  /// set when its reps are inside 1…`maxReps` (warm-ups never appear — they are not
  /// logged). The rep range is the min–max of the valid sets. The target RPE is
  /// carried over only when every valid set carries the same valid target — a
  /// missing target is never filled from another set — and the set count is capped
  /// at `ProgramImportValidator.allowedSetRange.upperBound` with a note, never
  /// silently.
  public static func extract(dayName: String, sets: [RoutineSetInput]) -> RoutineExtraction {
    var notes: [RoutineExtractionNote] = []

    var order: [String] = []
    var byExercise: [String: [RoutineSetInput]] = [:]
    var labels: [String: String] = [:]
    for set in sets {
      if byExercise[set.exerciseID] == nil { order.append(set.exerciseID) }
      byExercise[set.exerciseID, default: []].append(set)
      if let name = set.exerciseName, !name.isEmpty { labels[set.exerciseID] = name }
    }

    var entries: [ProgramExerciseEntry] = []
    for id in order {
      let all = byExercise[id] ?? []
      let valid = all.filter { $0.reps >= 1 && $0.reps <= maxReps }
      let known = ExerciseDB.find(id) != nil
      let label = labels[id] ?? ExerciseDB.find(id)?.localizedName ?? id
      guard !valid.isEmpty else {
        notes.append(RoutineExtractionNote(code: .noWorkingSets, exerciseName: label))
        continue
      }
      if !known {
        notes.append(RoutineExtractionNote(code: .unknownExercise, exerciseName: label))
      }
      let dropped = all.count - valid.count
      if dropped > 0 {
        notes.append(RoutineExtractionNote(code: .invalidSetsDropped, exerciseName: label, value: dropped))
      }
      var count = valid.count
      if count > ProgramImportValidator.allowedSetRange.upperBound {
        notes.append(
          RoutineExtractionNote(
            code: .setCountCapped, exerciseName: label,
            value: ProgramImportValidator.allowedSetRange.upperBound))
        count = ProgramImportValidator.allowedSetRange.upperBound
      }
      let lo = valid.map(\.reps).min() ?? 1
      let hi = max(lo, valid.map(\.reps).max() ?? lo)
      // A target survives only when every valid set carries one and they all agree;
      // a missing target on any set is never filled from another set.
      let targets = valid.map { input -> Double? in
        guard let target = input.targetRPE,
          target.isFinite, ProgramImportValidator.allowedRPERange.contains(target)
        else { return nil }
        return target
      }
      var target: Double?
      if let first = targets.first(where: { $0 != nil }) ?? nil,
        targets.allSatisfy({ $0 == first })
      {
        target = first
      } else if targets.contains(where: { $0 != nil }) {
        notes.append(RoutineExtractionNote(code: .targetRPEDropped, exerciseName: label))
      }
      entries.append(
        ProgramExerciseEntry(
          exerciseID: id,
          exerciseName: known ? nil : label,
          sets: count,
          repRangeLower: lo,
          repRangeUpper: hi,
          targetRPE: target))
    }

    let day = entries.isEmpty ? nil : ProgramDay(name: dayName, exercises: entries)
    return RoutineExtraction(day: day, notes: notes)
  }
}

// MARK: - Adaptation

public enum RoutineChangeKind: String, Codable, Sendable, CaseIterable {
  case deload
  case kept
  /// Replaced by the injury-flag substitution for this lifter.
  case injurySwap
  /// Replaced because the lifter's equipment does not include the original's.
  case equipmentSwap
  /// The lifter's own rep-range override replaced the source range.
  case repRangeFromYourOverride
  /// Working sets trimmed so this week's volume stays inside the muscle's MRV.
  case weeklyVolumeTrimmedSets
  /// The exercise was dropped entirely by the weekly-volume cap.
  case weeklyVolumeDroppedExercise
  /// Working sets trimmed to fit the session's time budget.
  case timeBudgetTrimmedSets
  /// The exercise was dropped entirely by the time-budget fit.
  case timeBudgetDroppedExercise
  /// The exercise was beyond the exercise limit for this session length.
  case exerciseLimitDropped
}

public struct RoutineChange: Codable, Sendable, Equatable {
  public let kind: RoutineChangeKind
  /// Machine-readable detail (exercise ids or counts), so reasons stay deterministic.
  public let from: String?
  public let to: String?

  public init(kind: RoutineChangeKind, from: String? = nil, to: String? = nil) {
    self.kind = kind
    self.from = from
    self.to = to
  }
}

public enum RoutineBlockerKind: String, Codable, Sendable, CaseIterable {
  case timeBudgetConflict
  case unknownExercise
  case excludedExercise
  /// Sets, rep range or target RPE outside the bounds the engine can plan; the entry
  /// is never silently repaired into an executable one.
  case invalidPrescription
  /// The same exercise appears twice; the planner and logger could not keep both
  /// prescriptions apart, so the whole routine is refused.
  case duplicateExercise
  /// The injury-flag substitution for this lift is unavailable (missing or not on
  /// this lifter's equipment); a flagged lift is never kept executable instead.
  case injurySubstitutionUnavailable
  case noReplacementEquipment
  /// Locked work could not survive the time budget / volume caps intact.
  case lockedWorkConflict
}

public struct RoutineBlocker: Codable, Sendable, Equatable, Identifiable {
  public let kind: RoutineBlockerKind
  public let exerciseID: String
  public let exerciseName: String
  public var id: String { "\(kind.rawValue):\(exerciseID)" }

  public init(kind: RoutineBlockerKind, exerciseID: String, exerciseName: String) {
    self.kind = kind
    self.exerciseID = exerciseID
    self.exerciseName = exerciseName
  }
}

public struct RoutineEntryAdaptation: Codable, Sendable, Equatable, Identifiable {
  /// Position in the source day, stable across preview and apply.
  public let index: Int
  public let source: ProgramExerciseEntry
  /// The adapted entry, or `nil` when it was blocked or dropped.
  public let adapted: ProgramExerciseEntry?
  /// The exercise the prescription was resolved onto (post-substitution).
  public let resolvedExerciseID: String?
  public let changes: [RoutineChange]
  public var id: Int { index }

  public init(
    index: Int,
    source: ProgramExerciseEntry,
    adapted: ProgramExerciseEntry?,
    resolvedExerciseID: String?,
    changes: [RoutineChange]
  ) {
    self.index = index
    self.source = source
    self.adapted = adapted
    self.resolvedExerciseID = resolvedExerciseID
    self.changes = changes
  }
}

/// A muscle whose weekly sets, counting this routine, pass its maximum recoverable volume.
public struct RoutineVolumeFlag: Codable, Sendable, Equatable, Identifiable {
  public let muscleRaw: String
  public let weeklySetsIncludingRoutine: Int
  public let mrv: Int
  public var id: String { muscleRaw }

  public init(muscleRaw: String, weeklySetsIncludingRoutine: Int, mrv: Int) {
    self.muscleRaw = muscleRaw
    self.weeklySetsIncludingRoutine = weeklySetsIncludingRoutine
    self.mrv = mrv
  }
}

public struct RoutineAdaptationResult: Codable, Sendable, Equatable {
  public let sourceDay: ProgramDay
  public let adaptedDay: ProgramDay
  public let entries: [RoutineEntryAdaptation]
  public let blockers: [RoutineBlocker]
  public let volumeFlags: [RoutineVolumeFlag]
  public let estimatedMinutes: Int

  public init(
    sourceDay: ProgramDay,
    adaptedDay: ProgramDay,
    entries: [RoutineEntryAdaptation],
    blockers: [RoutineBlocker],
    volumeFlags: [RoutineVolumeFlag],
    estimatedMinutes: Int
  ) {
    self.sourceDay = sourceDay
    self.adaptedDay = adaptedDay
    self.entries = entries
    self.blockers = blockers
    self.volumeFlags = volumeFlags
    self.estimatedMinutes = estimatedMinutes
  }

  public var isExecutable: Bool { blockers.isEmpty && !adaptedDay.exercises.isEmpty }
}

public enum RoutineAdaptation {
  /// Adapts one load-free routine day to this lifter's constraints. Deterministic:
  /// same inputs, same output — the preview the user confirmed is the plan that runs.
  ///
  /// Nothing is silently repaired: an entry outside the engine's bounds blocks, an
  /// unavailable injury substitution blocks, and any blocker refuses the whole
  /// routine (`adaptedDay` comes back empty) rather than saving partial success.
  public static func adapt(
    _ day: ProgramDay,
    profile: ProfileInput,
    weeklySetsByMuscle: [Muscle: Int] = [:],
    week: Int = 1
  ) -> RoutineAdaptationResult {
    let minutes = profile.sessionBudgetMinutes ?? profile.sessionLength.rawValue
    let exerciseLimit = TrainingConstraintEngine.exerciseLimit(
      minutes: minutes, minimumEffective: profile.minimumEffectiveWorkout)

    struct Kept {
      var index: Int
      var source: ProgramExerciseEntry
      var exercise: Exercise
      var sets: Int
      var repRange: ClosedRange<Int>
      var targetRPE: Double?
      var changes: [RoutineChange]
    }

    var kept: [Kept] = []
    var entries: [RoutineEntryAdaptation] = []
    var blockers: [RoutineBlocker] = []

    func block(
      _ kind: RoutineBlockerKind, id: String, label: String,
      index: Int, source: ProgramExerciseEntry, changes: [RoutineChange] = []
    ) {
      blockers.append(RoutineBlocker(kind: kind, exerciseID: id, exerciseName: label))
      entries.append(
        RoutineEntryAdaptation(
          index: index, source: source, adapted: nil, resolvedExerciseID: nil,
          changes: changes))
    }

    // The same exercise twice cannot keep two prescriptions apart downstream — the
    // planner and logger key on exercise id — so the whole routine is refused.
    var seen = Set<String>()
    var duplicates = Set<String>()
    for entry in day.exercises {
      if !seen.insert(entry.exerciseID).inserted { duplicates.insert(entry.exerciseID) }
    }

    for (index, entry) in day.exercises.enumerated() {
      let label =
        entry.exerciseName ?? ExerciseDB.find(entry.exerciseID)?.localizedName ?? entry.exerciseID
      if let original = ExerciseDB.find(entry.exerciseID) {
        if duplicates.contains(original.id) {
          block(.duplicateExercise, id: original.id, label: label, index: index, source: entry)
          continue
        }
      } else {
        if duplicates.contains(entry.exerciseID) {
          block(.duplicateExercise, id: entry.exerciseID, label: label, index: index, source: entry)
          continue
        }
      }

      // Bounds are hard: a malformed prescription is never repaired into an
      // executable one.
      let setsValid = ProgramImportValidator.allowedSetRange.contains(entry.sets)
      let rangeValid = entry.repRangeLower >= 1
        && entry.repRangeUpper >= entry.repRangeLower
        && entry.repRangeUpper <= RoutineExtractionPolicy.maxReps
      let targetValid: Bool
      if let target = entry.targetRPE {
        targetValid = target.isFinite && ProgramImportValidator.allowedRPERange.contains(target)
      } else {
        targetValid = true
      }
      guard setsValid, rangeValid, targetValid else {
        block(.invalidPrescription, id: entry.exerciseID, label: label, index: index, source: entry)
        continue
      }

      guard let original = ExerciseDB.find(entry.exerciseID) else {
        block(.unknownExercise, id: entry.exerciseID, label: label, index: index, source: entry)
        continue
      }
      if profile.excludedExerciseIDs.contains(original.id) {
        block(.excludedExercise, id: original.id, label: label, index: index, source: entry)
        continue
      }

      var resolved = original
      var changes: [RoutineChange] = []
      if let subID = Substitution.replacement(for: original.id, flags: profile.injuryFlags) {
        if let sub = ExerciseDB.find(subID),
          sub.id != original.id,
          profile.equipment.contains(sub.equipment),
          !profile.excludedExerciseIDs.contains(sub.id)
        {
          changes.append(RoutineChange(kind: .injurySwap, from: original.id, to: sub.id))
          resolved = sub
        } else {
          // A lift flagged for this lifter's injury is never kept executable merely
          // because its substitute happens to be unavailable.
          block(
            .injurySubstitutionUnavailable, id: original.id, label: label, index: index,
            source: entry)
          continue
        }
      }
      if !profile.equipment.contains(resolved.equipment) {
        if let replacement = ExerciseDB.replacements(
          for: resolved, equipment: profile.equipment, injuries: profile.injuryFlags)
          .first(where: { !profile.excludedExerciseIDs.contains($0.id) })
        {
          changes.append(RoutineChange(kind: .equipmentSwap, from: resolved.id, to: replacement.id))
          resolved = replacement
        } else {
          block(
            .noReplacementEquipment, id: original.id, label: label, index: index, source: entry,
            changes: changes)
          continue
        }
      }

      let repRange: ClosedRange<Int>
      if let override = profile.repRangeOverrides[resolved.id] {
        changes.append(
          RoutineChange(
            kind: .repRangeFromYourOverride, from: repRangeText(entry),
            to: "\(override.lowerBound)-\(override.upperBound)"))
        repRange = override
      } else {
        repRange = entry.repRangeLower...entry.repRangeUpper
      }

      if kept.contains(where: { $0.exercise.id == resolved.id }) {
        block(.duplicateExercise, id: original.id, label: label, index: index, source: entry)
        continue
      }
      let sets = week == Mesocycle.deloadWeek
        ? max(1, Int((Double(entry.sets) * Mesocycle.deloadVolumeMultiplier).rounded())) : entry.sets
      let target = week == Mesocycle.deloadWeek ? Mesocycle.deloadRPECap : (entry.targetRPE ?? 8)
      if week == Mesocycle.deloadWeek {
        changes.append(RoutineChange(kind: .deload, from: String(entry.sets), to: String(sets)))
      }
      if changes.isEmpty { changes.append(RoutineChange(kind: .kept)) }
      kept.append(
        Kept(
          index: index, source: entry, exercise: resolved, sets: sets, repRange: repRange,
          targetRPE: target, changes: changes))
    }

    func recordDropped(_ item: Kept, kind: RoutineChangeKind) {
      entries.append(
        RoutineEntryAdaptation(
          index: item.index, source: item.source, adapted: nil,
          resolvedExerciseID: item.exercise.id,
          changes: item.changes + [RoutineChange(kind: kind)]))
    }

    // Weekly volume: this routine's per-muscle sets on top of the week already
    // logged must stay inside the muscle's recovery maximum — the prescription is
    // trimmed, not merely warned about.
    var volumeTrimmed: [(item: Kept, from: Int, to: Int)] = []
    for muscle in Muscle.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
      guard let landmarks = VolumeLandmarks.landmarks(
        for: muscle, recoveryReduced: profile.recoveryReduced)
      else { continue }
      let cap = max(0, landmarks.mrv - (weeklySetsByMuscle[muscle] ?? 0))
      func total() -> Int {
        kept.filter { $0.exercise.primary == muscle }.reduce(0) { $0 + $1.sets }
      }
      while total() > cap {
        // Trim the largest slot of this muscle first (ties: earliest index), one set
        // at a time, never below one set.
        if let index = kept.indices
          .filter({ kept[$0].exercise.primary == muscle && kept[$0].sets > 1 })
          .max(by: { kept[$0].sets < kept[$1].sets })
        {
          volumeTrimmed.append((kept[index], kept[index].sets, kept[index].sets - 1))
          kept[index].sets -= 1
          continue
        }
        // Below the one-set floor the lowest-priority (last) slot of the muscle goes.
        if let index = kept.lastIndex(where: { $0.exercise.primary == muscle }) {
          recordDropped(kept.remove(at: index), kind: .weeklyVolumeDroppedExercise)
          continue
        }
        break
      }
    }
    for trim in volumeTrimmed {
      if let index = kept.firstIndex(where: { $0.index == trim.item.index }) {
        kept[index].changes.append(
          RoutineChange(
            kind: .weeklyVolumeTrimmedSets, from: String(trim.from), to: String(trim.to)))
      }
    }

    // Exercise limit: keep the source order's head, drop the tail — never reorder.
    if kept.count > exerciseLimit {
      let dropCount = kept.count - exerciseLimit
      for item in kept.suffix(dropCount) {
        recordDropped(item, kind: .exerciseLimitDropped)
      }
      kept.removeLast(dropCount)
    }

    // Time budget: reuse the planner's own fit so a routine and a generated session
    // agree about what a minute holds.
    let planned = kept.map {
      PlannedExercise(
        exercise: $0.exercise, sets: $0.sets, repRange: $0.repRange, targetRPE: $0.targetRPE ?? 8)
    }
    let fitted = TimeBudget.fit(PlannedDay(name: day.name, exercises: planned), minutes: minutes)
    var remaining = fitted.exercises
    var finalKept: [Kept] = []
    for var item in kept {
      guard let pos = remaining.firstIndex(where: { $0.exercise.id == item.exercise.id }) else {
        recordDropped(item, kind: .timeBudgetDroppedExercise)
        continue
      }
      let fit = remaining.remove(at: pos)
      if fit.sets < item.sets {
        item.changes.append(
          RoutineChange(kind: .timeBudgetTrimmedSets, from: String(item.sets), to: String(fit.sets)))
        item.sets = fit.sets
      }
      finalKept.append(item)
    }

    if TimeBudget.estimatedMinutes(fitted) > minutes {
      blockers.append(RoutineBlocker(kind: .timeBudgetConflict, exerciseID: "", exerciseName: day.name))
    }

    // Locked work must survive intact. Locked exercises that were dropped or trimmed,
    // or a day whose locked work still cannot fit the time budget, block the routine.
    let lockedIDs = profile.lockedExerciseIDs
    if lockedIDs.contains(where: { id in
      finalKept.contains(where: { $0.source.exerciseID == id || $0.exercise.id == id })
        || entries.contains {
          $0.source.exerciseID == id && $0.adapted == nil
            && $0.changes.contains { $0.kind == .weeklyVolumeDroppedExercise || $0.kind == .exerciseLimitDropped || $0.kind == .timeBudgetDroppedExercise }
        }
    }) {
      let lockedKept = finalKept.filter {
        lockedIDs.contains($0.source.exerciseID) || lockedIDs.contains($0.exercise.id)
      }
      let lockedTrimmed = lockedKept.contains { item in
        item.changes.contains {
          $0.kind == .weeklyVolumeTrimmedSets || $0.kind == .timeBudgetTrimmedSets
        }
      }
      let overMinutes = !lockedKept.isEmpty
        && TimeBudget.estimatedMinutes(
          PlannedDay(
            name: day.name,
            exercises: finalKept.map {
              PlannedExercise(
                exercise: $0.exercise, sets: $0.sets, repRange: $0.repRange,
                targetRPE: $0.targetRPE ?? 8)
            })) > minutes
      let lockedDropped = entries.contains {
        lockedIDs.contains($0.source.exerciseID) && $0.adapted == nil
          && $0.changes.contains {
            $0.kind == .weeklyVolumeDroppedExercise || $0.kind == .exerciseLimitDropped
              || $0.kind == .timeBudgetDroppedExercise
          }
      }
      if lockedDropped || lockedTrimmed || overMinutes {
        let id = lockedKept.first?.exercise.id ?? lockedIDs.sorted().first ?? ""
        blockers.append(
          RoutineBlocker(
            kind: .lockedWorkConflict,
            exerciseID: id,
            exerciseName: ExerciseDB.find(id)?.localizedName ?? id))
      }
    }

    // Adapted entries and their per-entry previews are built in one pass over
    // finalKept, so a day that legitimately repeats one exercise keeps each slot's own
    // set count instead of matching the first duplicate.
    var adaptedEntries: [ProgramExerciseEntry] = []
    for item in finalKept {
      let adapted = ProgramExerciseEntry(
        exerciseID: item.exercise.id,
        exerciseName: nil,
        sets: item.sets,
        repRangeLower: item.repRange.lowerBound,
        repRangeUpper: item.repRange.upperBound,
        targetRPE: item.targetRPE)
      adaptedEntries.append(adapted)
      entries.append(
        RoutineEntryAdaptation(
          index: item.index,
          source: item.source,
          adapted: adapted,
          resolvedExerciseID: item.exercise.id,
          changes: item.changes))
    }
    entries.sort { $0.index < $1.index }

    // Any blocker refuses the whole routine: nothing is saved or applied as partial
    // success. The per-entry previews above still show what the adaptation would
    // have been, so the preview can explain the refusal.
    let adaptedDay: ProgramDay
    if blockers.isEmpty {
      adaptedDay = ProgramDay(name: day.name, exercises: adaptedEntries)
    } else {
      adaptedDay = ProgramDay(name: day.name, exercises: [])
    }

    // Volume flags record what could not be brought inside the recovery maximum
    // even after trimming (everything trimmed lands at or below MRV, so a flag means
    // the week was already over on its own).
    var dayByMuscle: [Muscle: Int] = [:]
    for item in finalKept {
      dayByMuscle[item.exercise.primary, default: 0] += item.sets
    }
    let volumeFlags = dayByMuscle
      .compactMap { muscle, sets -> RoutineVolumeFlag? in
        guard let landmarks = VolumeLandmarks.landmarks(
          for: muscle, recoveryReduced: profile.recoveryReduced)
        else { return nil }
        let total = (weeklySetsByMuscle[muscle] ?? 0) + sets
        return total > landmarks.mrv
          ? RoutineVolumeFlag(
            muscleRaw: muscle.rawValue, weeklySetsIncludingRoutine: total, mrv: landmarks.mrv)
          : nil
      }
      .sorted { $0.muscleRaw < $1.muscleRaw }

    let minutesEstimate = TimeBudget.estimatedMinutes(
      PlannedDay(
        name: day.name,
        exercises: finalKept.map {
          PlannedExercise(
            exercise: $0.exercise, sets: $0.sets, repRange: $0.repRange,
            targetRPE: $0.targetRPE ?? 8)
        }))

    return RoutineAdaptationResult(
      sourceDay: day,
      adaptedDay: adaptedDay,
      entries: entries,
      blockers: blockers,
      volumeFlags: volumeFlags,
      estimatedMinutes: minutesEstimate)
  }

  // MARK: Destination eligibility

  public enum RoutineDestinationIssue: String, Codable, Sendable, Equatable, CaseIterable {
    /// Replacing this session would remove work the lifter explicitly locked.
    case lockedExerciseConflict
  }

  /// Hard conflicts between an accepted plan day and replacing it with a routine.
  public static func destinationIssues(
    for day: WeekPlanDay,
    lockedExerciseIDs: Set<String>
  ) -> [RoutineDestinationIssue] {
    guard day.exerciseIDs.contains(where: { lockedExerciseIDs.contains($0) }) else { return [] }
    return [.lockedExerciseConflict]
  }

  // MARK: Shared execution path

  /// Validates persisted/input prescriptions before they can enter any execution path.
  public static func plannedDay(_ day: ProgramDay) -> PlannedDay? {
    guard !day.exercises.isEmpty, day.exercises.count <= 30,
      Set(day.exerciseIDs).count == day.exercises.count else { return nil }
    var exercises: [PlannedExercise] = []
    for entry in day.exercises {
      guard let exercise = ExerciseDB.find(entry.exerciseID),
        ProgramImportValidator.allowedSetRange.contains(entry.sets),
        entry.repRangeLower >= 1, entry.repRangeUpper <= RoutineExtractionPolicy.maxReps,
        let range = entry.repRange else { return nil }
      let target = entry.targetRPE ?? 8
      guard target.isFinite, ProgramImportValidator.allowedRPERange.contains(target) else { return nil }
      exercises.append(PlannedExercise(exercise: exercise, sets: entry.sets, repRange: range, targetRPE: target))
    }
    return PlannedDay(name: day.name, exercises: exercises)
  }

  private static func repRangeText(_ entry: ProgramExerciseEntry) -> String? {
    guard entry.repRangeLower >= 1, entry.repRangeUpper >= entry.repRangeLower else { return nil }
    return "\(entry.repRangeLower)-\(entry.repRangeUpper)"
  }
}
