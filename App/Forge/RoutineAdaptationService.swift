import Foundation
import ForgeCore
import SwiftData

@MainActor
enum RoutineAdaptationService {
  enum Failure: LocalizedError, Equatable {
    case noProfile, nothingToSave, sessionNotFound, sessionNoLongerReplaceable
    case destinationBlocked(String), routineNotExecutable, stalePreview, unreadableStorage
    case saveFailed(String)
    var errorDescription: String? {
      switch self {
      case .noProfile: "Your profile is unavailable. Nothing was saved."
      case .nothingToSave: "There are no valid working sets to copy."
      case .sessionNotFound: "That session is no longer in your accepted plan."
      case .sessionNoLongerReplaceable: "That session has started or is no longer available to replace."
      case .destinationBlocked(let reason): reason
      case .routineNotExecutable: "Resolve the routine's constraints before applying it."
      case .stalePreview: "The source, plan or training data changed. Review the updated preview and confirm again."
      case .unreadableStorage: "This saved data cannot be read by this build. It was left untouched."
      case .saveFailed(let reason): "Could not save: \(reason). Nothing was changed."
      }
    }
  }
  enum LoadBasis: Equatable { case history, startingRule, heldNoEffort, userOverride, calibrationRequired }
  struct LoadEstimate: Equatable {
    let kg: Double?
    let basis: LoadBasis
  }
  struct Preview {
    let result: RoutineAdaptationResult
    fileprivate let sourceDay: ProgramDay
    fileprivate let routineID: String?
    fileprivate let destinationID: String
    fileprivate let revision: Data
  }

  static func extractionInputs(from session: WorkoutSession) -> [RoutineSetInput] {
    let chronology = session.sets.sorted {
      if $0.loggedAt != $1.loggedAt { return $0.loggedAt < $1.loggedAt }
      if $0.setIndex != $1.setIndex { return $0.setIndex < $1.setIndex }
      return $0.exerciseID < $1.exerciseID
    }
    var seen = Set<String>()
    return (session.order + chronology.map(\.exerciseID)).filter { seen.insert($0).inserted }.flatMap { id in
      chronology.filter { $0.exerciseID == id }.map {
        RoutineSetInput(exerciseID: id, setIndex: $0.setIndex, reps: $0.reps, targetRPE: $0.targetRPE)
      }
    }
  }
  static func extract(from session: WorkoutSession) -> RoutineExtraction {
    guard session.completed, !session.tombstoned else { return RoutineExtraction(day: nil, notes: []) }
    return RoutineExtractionPolicy.extract(dayName: localizedDayName(session.dayName), sets: extractionInputs(from: session))
  }
  static func defaultName(for session: WorkoutSession) -> String {
    "\(localizedDayName(session.dayName)) · \(session.date.formatted(date: .abbreviated, time: .omitted))"
  }
  private static func requireReadable<T: Decodable>(_ type: T.Type, raw: String) throws {
    guard raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || (try? JSONDecoder().decode(type, from: Data(raw.utf8))) != nil
    else { throw Failure.unreadableStorage }
  }

  /// Never save or roll back the caller's unrelated drafts.
  private static func transaction<T>(profile: UserProfile, context: ModelContext,
    body: (UserProfile, ModelContext) throws -> T) throws -> T {
    let isolated = ModelContext(context.container)
    isolated.autosaveEnabled = false
    guard let owner = try isolated.fetch(FetchDescriptor<UserProfile>()).first(where: {
      $0.persistentModelID == profile.persistentModelID
    }) else { throw Failure.noProfile }
    let library = owner.routineLibraryJSON
    let applied = owner.appliedRoutinesJSON
    let plan = owner.weekPlanJSON
    do {
      let value = try body(owner, isolated)
      try isolated.save()
      if owner.routineLibraryJSON != library { profile.routineLibraryJSON = owner.routineLibraryJSON }
      if owner.appliedRoutinesJSON != applied { profile.appliedRoutinesJSON = owner.appliedRoutinesJSON }
      if owner.weekPlanJSON != plan { profile.weekPlanJSON = owner.weekPlanJSON }
      if owner.routineLibraryJSON != library || owner.appliedRoutinesJSON != applied || owner.weekPlanJSON != plan {
        profile.updatedAt = owner.updatedAt
      }
      return value
    } catch {
      isolated.rollback()
      if let failure = error as? Failure { throw failure }
      throw Failure.saveFailed(error.localizedDescription)
    }
  }

  @discardableResult
  static func saveRoutine(day: ProgramDay, name: String, sourceKind: UserProfile.SavedRoutine.SourceKind,
    sourceName: String?, profile: UserProfile, context: ModelContext,
    sourceSession: WorkoutSession? = nil) throws -> UserProfile.SavedRoutine {
    guard !day.exercises.isEmpty else { throw Failure.nothingToSave }
    guard RoutineAdaptation.plannedDay(day) != nil else { throw Failure.routineNotExecutable }
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= 120 else {
      throw Failure.destinationBlocked("Use a routine name between 1 and 120 characters.")
    }
    return try transaction(profile: profile, context: context) { owner, isolated in
      try requireReadable([UserProfile.SavedRoutine].self, raw: owner.routineLibraryJSON)
      guard profile.routineLibraryJSON == owner.routineLibraryJSON else { throw Failure.stalePreview }
      if let sourceSession {
        guard let live = try isolated.fetch(FetchDescriptor<WorkoutSession>()).first(where: {
          $0.persistentModelID == sourceSession.persistentModelID
        }), extract(from: live).day == day else { throw Failure.stalePreview }
      }
      if let existing = owner.routineLibrary.first(where: { $0.name == name && $0.day.exercises == day.exercises }) {
        return existing
      }
      // The approved name replaces hidden history labels in the reusable copy.
      let routine = UserProfile.SavedRoutine(id: UUID().uuidString, name: name, createdAt: .now,
        sourceKind: sourceKind, sourceName: nil, day: ProgramDay(name: name, exercises: day.exercises))
      owner.routineLibrary = owner.routineLibrary + [routine]
      return routine
    }
  }
  static func deleteRoutine(id: String, profile: UserProfile, context: ModelContext) throws {
    try transaction(profile: profile, context: context) { owner, _ in
      try requireReadable([UserProfile.SavedRoutine].self, raw: owner.routineLibraryJSON)
      guard profile.routineLibraryJSON == owner.routineLibraryJSON else { throw Failure.stalePreview }
      owner.routineLibrary = owner.routineLibrary.filter { $0.id != id }
    }
  }

  static func weeklySetsByMuscle(sessions: [WorkoutSession], now: Date = .now) -> [Muscle: Int] {
    let interval = TrainingMetrics.reportingWeek(containing: now, calendar: TrainingMetrics.reportingCalendar())
    var counts: [Muscle: Int] = [:]
    for session in sessions where session.completed && !session.tombstoned && TrainingMetrics.contains(interval, session.date) {
      for set in session.analysisSets(.trends) {
        if let exercise = ExerciseDB.find(set.exerciseID) { counts[exercise.primary, default: 0] += 1 }
      }
    }
    return counts
  }
  static func input(profile: UserProfile, destination: WeekPlanDay? = nil) -> ProfileInput {
    var input = profile.profileInput
    if let destination {
      var constraints = profile.trainingConstraints
      if let gym = destination.gymProfileID { constraints.activeGymProfileID = gym }
      if destination.mode == .travel { constraints.travelMode = true }
      input.equipment = TrainingConstraintEngine.effectiveEquipment(base: input.equipment, constraints: constraints)
      input.sessionBudgetMinutes = destination.timeBudgetMinutes
      input.minimumEffectiveWorkout = destination.mode == .minimumEffective || input.minimumEffectiveWorkout
      input.recoveryReduced = destination.mode == .reduced || input.recoveryReduced
    }
    return input
  }
  static func generatedDay(_ destination: WeekPlanDay, profile: UserProfile, sessions: [WorkoutSession]) -> PlannedDay? {
    let days = Program.week(profile.currentWeek(sessions: sessions), profile: input(profile: profile, destination: destination))
    let matching = days.filter { $0.name == destination.plannedSessionID }
    let preceding = profile.weekPlan?.days.prefix(while: { $0.id != destination.id })
      .filter { $0.plannedSessionID == destination.plannedSessionID }.count ?? 0
    return matching.isEmpty ? nil : matching[preceding % matching.count]
  }
  private static func volumeBeforeRoutine(profile: UserProfile, sessions: [WorkoutSession],
    toDayID: String? = nil) -> [Muscle: Int] {
    let destination = profile.weekPlan?.days.first { $0.id == toDayID }
    let date = destination?.date ?? .now
    var volume = weeklySetsByMuscle(sessions: sessions, now: date)
    if let plan = profile.weekPlan {
      let interval = TrainingMetrics.reportingWeek(containing: date, calendar: plan.resolvedCalendar())
      for other in plan.days where other.id != toDayID && !other.state.isSettled && TrainingMetrics.contains(interval, other.date) {
        let trained = sessions.contains { !$0.tombstoned && $0.completed && matches($0, day: other, plan: plan) }
        guard !trained, let planned = resolvedDay(other, profile: profile, sessions: sessions,
          validatesVolume: false)
          ?? generatedDay(other, profile: profile, sessions: sessions) else { continue }
        for entry in planned.exercises { volume[entry.exercise.primary, default: 0] += entry.sets }
      }
    }
    return volume
  }
  static func adapt(day: ProgramDay, profile: UserProfile, sessions: [WorkoutSession],
    toDayID: String? = nil) -> RoutineAdaptationResult {
    let destination = profile.weekPlan?.days.first { $0.id == toDayID }
    return RoutineAdaptation.adapt(day, profile: input(profile: profile, destination: destination),
      weeklySetsByMuscle: volumeBeforeRoutine(profile: profile, sessions: sessions, toDayID: toDayID),
      week: profile.currentWeek(sessions: sessions))
  }
  static func loadEstimate(for entry: ProgramExerciseEntry, resolvedID: String,
    profile: UserProfile, sessions: [WorkoutSession]) -> LoadEstimate? {
    guard let exercise = ExerciseDB.find(resolvedID), let range = entry.repRange else { return nil }
    let planned = PlannedExercise(exercise: exercise, sets: entry.sets, repRange: range, targetRPE: entry.targetRPE ?? 8)
    let last = lastSets(resolvedID, in: sessions, profile: profile)
    let kg = resolvedLoadSuggestion(for: planned, sessions: sessions, profile: profile)
    guard kg != nil else { return LoadEstimate(kg: nil, basis: .calibrationRequired) }
    let basis: LoadBasis = DecisionOverrides.get(resolvedID) != nil ? .userOverride
      : last.isEmpty ? .startingRule : last.last?.reportedRPE == nil ? .heldNoEffort : .history
    return LoadEstimate(kg: kg, basis: basis)
  }
  static func matches(_ session: WorkoutSession, day: WeekPlanDay, plan: WeekPlan) -> Bool {
    if !session.plannedDayID.isEmpty { return session.plannedDayID == day.id }
    return session.dayName == day.plannedSessionID && plan.resolvedCalendar().isDate(session.date, inSameDayAs: day.date)
  }
  static func canComplete(_ session: WorkoutSession, dayID: String, in plan: WeekPlan) -> Bool {
    session.plannedDayID == dayID && session.plannedPlanID == plan.id
      && session.plannedAcceptanceID == plan.acceptanceID
  }
  static func eligibleDestinations(profile: UserProfile, now: Date = .now,
    sessions supplied: [WorkoutSession]? = nil) -> [WeekPlanDay] {
    guard let plan = profile.weekPlan else { return [] }
    let sessions = supplied ?? ((try? profile.modelContext?.fetch(FetchDescriptor<WorkoutSession>())) ?? [])
    let evaluation = plan.evaluation(now: now)
    return plan.days.filter { day in
      !day.state.isSettled && day.plannedSessionID != nil && evaluation.day(day.id)?.state == .remaining
        && !sessions.contains { !$0.tombstoned && matches($0, day: day, plan: plan) }
    }.sorted { $0.date < $1.date }
  }
  static func destinationIssues(for day: WeekPlanDay, profile: UserProfile,
    replacingWith replacement: ProgramDay? = nil) -> [RoutineAdaptation.RoutineDestinationIssue] {
    let locked = Set(day.exerciseIDs).intersection(profile.trainingConstraints.lockedExerciseIDs)
    return locked.isSubset(of: Set(replacement?.exerciseIDs ?? [])) ? [] : [.lockedExerciseConflict]
  }
  private static func canonical(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed])
  }
  static func constraintRevision(profile: UserProfile, day: WeekPlanDay) -> String? {
    let object: [String: Any] = [
      "goal": profile.goal, "experience": profile.experience, "days": profile.daysPerWeek,
      "minutes": profile.sessionMinutes, "equipment": profile.equipment.sorted(),
      "injuries": profile.injuryFlags.sorted(), "recovery": profile.recoveryReduced,
      "constraints": profile.constraintsJSON, "swaps": profile.exerciseOverrides,
      "setDeltas": profile.setDeltas, "repRanges": profile.repRangeOverrides,
      "deload": profile.deloadStartedAt?.timeIntervalSince1970 ?? 0,
      "destinationGym": day.gymProfileID ?? "", "destinationMinutes": day.timeBudgetMinutes,
      "mode": day.mode.rawValue,
    ]
    guard let data = try? canonical(object) else { return nil }
    return SetRevision.fingerprint(of: String(decoding: data, as: UTF8.self)).rawValue
  }
  static func volumeRevision(profile: UserProfile, sessions: [WorkoutSession], toDayID: String) -> String? {
    let values = volumeBeforeRoutine(profile: profile, sessions: sessions, toDayID: toDayID)
      .reduce(into: [String: Int]()) { $0[$1.key.rawValue] = $1.value }
    guard let data = try? canonical(values) else { return nil }
    return SetRevision.fingerprint(of: String(decoding: data, as: UTF8.self)).rawValue
  }
  static func preview(day: ProgramDay, routineID: String? = nil, toDayID: String,
    profile: UserProfile, sessions: [WorkoutSession]) throws -> Preview {
    try requireReadable(WeekPlan.self, raw: profile.weekPlanJSON)
    try requireReadable([UserProfile.AppliedRoutine].self, raw: profile.appliedRoutinesJSON)
    if let routineID {
      try requireReadable([UserProfile.SavedRoutine].self, raw: profile.routineLibraryJSON)
      guard profile.routineLibrary.contains(where: { $0.id == routineID && $0.day == day }) else { throw Failure.stalePreview }
    }
    guard let destination = eligibleDestinations(profile: profile, sessions: sessions).first(where: { $0.id == toDayID })
    else { throw Failure.sessionNoLongerReplaceable }
    let result = adapt(day: day, profile: profile, sessions: sessions, toDayID: toDayID)
    guard result.isExecutable else { throw Failure.routineNotExecutable }
    guard destinationIssues(for: destination, profile: profile, replacingWith: result.adaptedDay).isEmpty
    else { throw Failure.destinationBlocked("This replacement would remove a locked exercise.") }
    let sessionValues = try sessions.map { session -> String in
      var value = session.syncData
      value["deleted"] = session.tombstoned
      value["identity"] = String(describing: session.persistentModelID)
      value["sets"] = try (value["sets"] as? [[String: Any]] ?? []).map {
        String(decoding: try canonical($0), as: UTF8.self)
      }.sorted()
      return String(decoding: try canonical(value), as: UTF8.self)
    }.sorted()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let sourceData = try encoder.encode(day)
    let overrides = result.adaptedDay.exerciseIDs.map { [$0, DecisionOverrides.get($0)?.rawValue ?? ""] }
    let revision = try canonical([
      "profile": profile.syncData, "sessions": sessionValues, "destination": toDayID,
      "source": String(decoding: sourceData, as: UTF8.self), "overrides": overrides,
      "routineLibrary": profile.routineLibraryJSON, "appliedRoutines": profile.appliedRoutinesJSON,
    ])
    return Preview(result: result, sourceDay: day, routineID: routineID, destinationID: toDayID, revision: revision)
  }

  @discardableResult
  static func apply(preview confirmed: Preview, sourceName: String,
    profile: UserProfile, context: ModelContext) throws -> RoutineAdaptationResult {
    try transaction(profile: profile, context: context) { owner, isolated in
      let sessions = try isolated.fetch(FetchDescriptor<WorkoutSession>())
      let fresh = try preview(day: confirmed.sourceDay, routineID: confirmed.routineID,
        toDayID: confirmed.destinationID, profile: owner, sessions: sessions)
      guard var plan = owner.weekPlan,
        let index = plan.days.firstIndex(where: { $0.id == confirmed.destinationID }) else { throw Failure.sessionNotFound }
      let destination = plan.days[index]
      let prescription = ProgramDay(name: destination.sessionName, exercises: fresh.result.adaptedDay.exercises)
      if let existing = owner.appliedRoutines.first(where: {
        $0.planDayID == destination.id && $0.acceptanceID == plan.acceptanceID
          && $0.day == prescription && $0.blockStart == owner.mesoStart
      }), destination.routineApplicationID == existing.id,
        existing.constraintRevision == constraintRevision(profile: owner, day: destination),
        existing.programWeek == owner.currentWeek(sessions: sessions),
        existing.volumeRevision == volumeRevision(profile: owner, sessions: sessions,
          toDayID: destination.id) {
        return fresh.result
      }
      guard fresh.revision == confirmed.revision, fresh.result == confirmed.result else { throw Failure.stalePreview }
      if plan.acceptanceID == nil { plan.acceptanceID = UUID().uuidString }
      let applicationID = UUID().uuidString
      plan.days[index].exerciseIDs = prescription.exerciseIDs
      plan.days[index].plannedSetCount = prescription.totalSets
      plan.days[index].routineApplicationID = applicationID
      owner.weekPlan = plan
      owner.appliedRoutines = owner.appliedRoutines.filter { $0.planDayID != destination.id } + [
        UserProfile.AppliedRoutine(id: applicationID, planID: plan.id, planDayID: destination.id,
          sessionName: destination.sessionName, appliedAt: .now, routineID: confirmed.routineID,
          day: prescription, acceptanceID: plan.acceptanceID, blockStart: owner.mesoStart,
          constraintRevision: constraintRevision(profile: owner, day: destination),
          programWeek: owner.currentWeek(sessions: sessions),
          volumeRevision: volumeRevision(profile: owner, sessions: sessions, toDayID: destination.id))
      ]
      isolated.insert(DecisionLogEntry(DecisionRecord(id: UUID().uuidString, date: .now, type: "weekplan",
        exerciseID: nil, muscle: nil, fromValue: Double(destination.plannedSetCount), toValue: Double(prescription.totalSets),
        reasonCodes: [DecisionSignal.userOverride.code, "routine-apply"],
        evidence: ["\(prescription.exercises.count) exercises", "\(prescription.totalSets) working sets"],
        humanSummary: "Replaced \(destination.sessionName) with \(sourceName).")))
      return fresh.result
    }
  }
  /// Resolve by the accepted day, never by a repeated name in a generated week.
  static func resolvedDay(_ destination: WeekPlanDay, profile: UserProfile,
    sessions: [WorkoutSession], now: Date = .now, validatesVolume: Bool = true) -> PlannedDay? {
    guard let plan = profile.weekPlan, !destination.state.isSettled,
      plan.evaluation(now: now).day(destination.id)?.state == .remaining,
      let applied = profile.appliedRoutines.last(where: {
        $0.planID == plan.id
          && (destination.routineApplicationID == nil
            ? $0.planDayID == destination.id : $0.id == destination.routineApplicationID)
          && $0.acceptanceID != nil
          && $0.acceptanceID == plan.acceptanceID && $0.blockStart == profile.mesoStart
          && $0.constraintRevision == constraintRevision(profile: profile, day: destination)
          && $0.programWeek == profile.currentWeek(sessions: sessions)
          && (!validatesVolume || $0.volumeRevision == volumeRevision(
            profile: profile, sessions: sessions, toDayID: destination.id))
      }) else { return nil }
    if destination.id != applied.planDayID {
      let calendar = plan.resolvedCalendar()
      guard let source = plan.days.first(where: { $0.id == applied.planDayID }),
        TrainingMetrics.reportingWeek(containing: source.date, calendar: calendar).start
          == TrainingMetrics.reportingWeek(containing: destination.date, calendar: calendar).start
      else { return nil }
    }
    return RoutineAdaptation.plannedDay(applied.day)
  }
  static func needsReview(_ destination: WeekPlanDay, profile: UserProfile,
    sessions: [WorkoutSession], now: Date = .now) -> Bool {
    guard let plan = profile.weekPlan,
      plan.evaluation(now: now).day(destination.id)?.state == .remaining else { return false }
    if routineDataUnreadable(profile) { return true }
    if destination.routineApplicationID != nil {
      return resolvedDay(destination, profile: profile, sessions: sessions, now: now) == nil
    }
    guard profile.appliedRoutines.contains(where: {
      $0.planDayID == destination.id && $0.blockStart == profile.mesoStart
    }) else {
      // The accepted plan syncs, but copied prescriptions are device-local. On a
      // second device, do not turn a 4-set replacement back into its 19-set template.
      guard !destination.exerciseIDs.isEmpty || destination.plannedSetCount > 0 else { return false }
      guard let generated = generatedDay(destination, profile: profile, sessions: sessions) else { return true }
      return destination.exerciseIDs != generated.exercises.map(\.exercise.id)
        || destination.plannedSetCount != generated.exercises.reduce(0) { $0 + $1.sets }
    }
    return resolvedDay(destination, profile: profile, sessions: sessions, now: now) == nil
  }
  static func routineDataUnreadable(_ profile: UserProfile) -> Bool {
    let raw = profile.appliedRoutinesJSON
    return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && (try? JSONDecoder().decode([UserProfile.AppliedRoutine].self, from: Data(raw.utf8))) == nil
  }
  static func weekPlanUnreadable(_ profile: UserProfile) -> Bool {
    let raw = profile.weekPlanJSON
    return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && profile.weekPlan == nil
  }
  static func hasUnreadableOpenSnapshot(_ sessions: [WorkoutSession]) -> Bool {
    sessions.contains {
      !$0.completed && !$0.tombstoned && !$0.routinePrescriptionJSON.isEmpty
        && $0.routinePrescription.flatMap(RoutineAdaptation.plannedDay) == nil
    }
  }
  static func currentDay(profile: UserProfile, sessions: [WorkoutSession], now: Date = .now) -> PlannedDay? {
    guard !hasUnreadableOpenSnapshot(sessions) else { return nil }
    if let open = sessions.last(where: { !$0.completed && !$0.tombstoned }),
      let saved = open.routinePrescription { return RoutineAdaptation.plannedDay(saved) }
    guard !weekPlanUnreadable(profile) else { return nil }
    if let plan = profile.weekPlan {
      guard let owed = WeekPlanTodayStatus(plan: plan, now: now).owed else { return nil }
      guard !needsReview(owed, profile: profile, sessions: sessions, now: now) else { return nil }
      return resolvedDay(owed, profile: profile, sessions: sessions, now: now)
        ?? generatedDay(owed, profile: profile, sessions: sessions)
    }
    let days = Program.week(profile.currentWeek(sessions: sessions), profile: profile.profileInput)
    return days.isEmpty ? nil : days[profile.nextDayIndex % days.count]
  }
}

extension WorkoutSession {
  var routinePrescription: ProgramDay? {
    get { try? JSONDecoder().decode(ProgramDay.self, from: Data(routinePrescriptionJSON.utf8)) }
    set {
      if let newValue, let data = try? JSONEncoder().encode(newValue) {
        routinePrescriptionJSON = String(decoding: data, as: UTF8.self)
      }
    }
  }
  func rememberPrescription(_ day: PlannedDay, planDayID: String? = nil) {
    plannedDayID = planDayID ?? ""
    routinePrescription = ProgramDay(name: day.name, exercises: day.exercises.map {
      ProgramExerciseEntry(exerciseID: $0.exercise.id, sets: $0.sets,
        repRangeLower: $0.repRange.lowerBound, repRangeUpper: $0.repRange.upperBound, targetRPE: $0.targetRPE)
    })
  }
}
