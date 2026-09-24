import ForgeCore
import Foundation
import SwiftData

@Model
final class UserProfile {
  var goal: String
  var experience: String
  var daysPerWeek: Int
  var sessionMinutes: Int
  var equipment: [String]
  var injuryFlags: [String]
  var recoveryReduced: Bool
  var bodyweightKg: Double
  var usesLb: Bool
  var startingLoads: [String: Double]
  var mesoStart: Date
  var trialStartedAt: Date?
  var nextDayIndex: Int
  var restCompoundSeconds: Int = 180
  var restIsolationSeconds: Int = 90
  var restOverrides: [String: Int] = [:]
  var deloadStartedAt: Date? = nil
  var unitOverrides: [String: Bool] = [:]
  var barKg: Double = 20
  var barLb: Double = 45
  var platesKg: [Double] = Plates.defaultKg
  var platesLb: [Double] = Plates.defaultLb
  var exerciseNotes: [String: String] = [:]
  var exerciseOverrides: [String: String] = [:]
  var split: String = "auto"
  var gymPreset: String = "commercial"
  var setDeltas: [String: Int] = [:]
  var repRangeOverrides: [String: String] = [:]
  var mesoSessionOffset: Int = 0
  var theme: String = "system"
  var reminderHour: Int? = nil
  var reminderMinute: Int = 0
  var constraintsJSON: String = ""
  var experimentJSON: String = ""
  // Feature-contract payloads. Each is a JSON string in its own column so a build that
  // *does* model the field can read a payload another build wrote and forward it opaquely.
  // A build whose model predates a field does not preserve it: SwiftData carries only the
  // columns the running model declares, and sync carries only keys named in `syncData`.
  // See `ProductFeatureStorage.swift`.
  var equipmentPassportJSON: String = ""
  var weekPlanJSON: String = ""
  var goalRecordsJSON: String = ""
  var recommendationLedgerJSON: String = ""
  var importedProgramJSON: String = ""
  var activeProgramVersionJSON: String = ""
  var shareTokensJSON: String = ""
  // Saved (copy/import) routine library and routines applied to accepted plan days.
  // Migration-safe feature payloads like the ones above; see `ProductFeatureStorage.swift`.
  var routineLibraryJSON: String = ""
  var appliedRoutinesJSON: String = ""
  // Exercise/variant → equipment-instance bindings, `[String: String]` JSON. Migration-safe
  // like the other payloads: an unreadable value reads back as an empty map and is never
  // overwritten. See `ProductFeatureStorage.swift` for the typed accessor.
  var equipmentBindingsJSON: String = ""
  // Device-local Journey namespace. Never synced; account ids are tracked separately so a
  // sign-in can bind initial local notes once without leaking one account's notes to another.
  var journeyLocalOwnerID: String = ""
  var journeyBoundAccountID: String = ""
  var remoteID: String = ""
  var updatedAt: Date = Date.now

  init(
    goal: Goal, experience: Experience, daysPerWeek: Int, sessionMinutes: Int,
    equipment: Set<Equipment>, injuryFlags: Set<InjuryFlag>, recoveryReduced: Bool,
    bodyweightKg: Double, usesLb: Bool, startingLoads: [String: Double],
    restCompoundSeconds: Int = 180, restIsolationSeconds: Int = 90,
    restOverrides: [String: Int] = [:]
  ) {
    self.goal = goal.rawValue
    self.experience = experience.rawValue
    self.daysPerWeek = daysPerWeek
    self.sessionMinutes = sessionMinutes
    self.equipment = equipment.map(\.rawValue).sorted()
    self.injuryFlags = injuryFlags.map(\.rawValue).sorted()
    self.recoveryReduced = recoveryReduced
    self.bodyweightKg = bodyweightKg
    self.usesLb = usesLb
    self.startingLoads = startingLoads
    self.mesoStart = .now
    self.trialStartedAt = nil
    self.nextDayIndex = 0
    self.restCompoundSeconds = restCompoundSeconds
    self.restIsolationSeconds = restIsolationSeconds
    self.restOverrides = restOverrides
  }

  var trainingConstraints: TrainingConstraints {
    get {
      if let data = constraintsJSON.data(using: .utf8),
        let decoded = try? JSONDecoder().decode(TrainingConstraints.self, from: data)
      {
        return decoded
      }
      let baseEquipment = Set(equipment.compactMap(Equipment.init(rawValue:)))
      let current = GymProfileConfig(
        id: gymPreset,
        name: gymPreset == "commercial" ? "Commercial gym" : gymPreset.capitalized,
        equipment: baseEquipment)
      let defaults = [current] + GymProfileConfig.defaults.filter { $0.id != current.id }
      return TrainingConstraints(gymProfiles: defaults, activeGymProfileID: current.id)
    }
    set {
      guard let data = try? JSONEncoder().encode(newValue),
        let json = String(data: data, encoding: .utf8)
      else { return }
      constraintsJSON = json
      gymPreset = newValue.activeGymProfileID
      if let active = newValue.activeGymProfile {
        equipment = active.equipment.map(\.rawValue).sorted()
      }
      updatedAt = .now
    }
  }

  var trainingExperiment: TrainingExperiment? {
    get {
      guard let data = experimentJSON.data(using: .utf8) else { return nil }
      return try? JSONDecoder().decode(TrainingExperiment.self, from: data)
    }
    set {
      guard let newValue,
        let data = try? JSONEncoder().encode(newValue),
        let json = String(data: data, encoding: .utf8)
      else {
        experimentJSON = ""
        updatedAt = .now
        return
      }
      experimentJSON = json
      updatedAt = .now
    }
  }

  var profileInput: ProfileInput { profileInput(plateaued: []) }

  func profileInput(plateaued: Set<String>) -> ProfileInput {
    profileInput(plateaued: plateaued, constraints: trainingConstraints)
  }

  /// Same profile, viewed through one specific constraint set — the destination-aware
  /// adaptation preview uses the accepted session's gym, minute budget and mode.
  func profileInput(plateaued: Set<String>, constraints: TrainingConstraints) -> ProfileInput {
    let baseEquipment = Set(equipment.compactMap(Equipment.init(rawValue:)))
    return ProfileInput(
      goal: Goal(rawValue: goal) ?? .hypertrophy,
      experience: Experience(rawValue: experience) ?? .intermediate,
      daysPerWeek: daysPerWeek,
      sessionLength: SessionLength(rawValue: sessionMinutes) ?? .m60,
      equipment: TrainingConstraintEngine.effectiveEquipment(
        base: baseEquipment, constraints: constraints),
      injuryFlags: Set(injuryFlags.compactMap(InjuryFlag.init(rawValue:))),
      recoveryReduced: recoveryReduced,
      plateauedExerciseIDs: plateaued,
      split: SplitStyle(rawValue: split) ?? .auto,
      exerciseOverrides: exerciseOverrides,
      setDeltas: setDeltas,
      repRangeOverrides: repRangeOverrides.compactMapValues(ProfileInput.repRange),
      lockedExerciseIDs: constraints.lockedExerciseIDs,
      excludedExerciseIDs: constraints.excludedExerciseIDs,
      sessionBudgetMinutes: constraints.sessionBudgetMinutes,
      minimumEffectiveWorkout: constraints.minimumEffectiveWorkout)
  }

  func startNewBlock() {
    appliedRoutines = []
    mesoStart = .now
    nextDayIndex = 0
    deloadStartedAt = nil
    mesoSessionOffset = 0
    setDeltas = [:]
    repRangeOverrides = [:]
    updatedAt = .now
  }

  func mesoSessions(_ sessions: [WorkoutSession]) -> Int {
    sessions.filter { $0.completed && $0.date >= mesoStart }.count
  }

  func currentWeek(sessions: [WorkoutSession]) -> Int {
    if deloadStartedAt != nil { return Mesocycle.deloadWeek }
    let counted = max(0, mesoSessions(sessions) + mesoSessionOffset)
    return min(Mesocycle.weeks, counted / max(daysPerWeek, 1) + 1)
  }

  /// Changes days per week without moving the program week.
  func setDaysPerWeek(_ days: Int, sessions: [WorkoutSession]) {
    guard days != daysPerWeek else { return }
    mesoSessionOffset = Mesocycle.rebasedOffset(
      sessionsDone: mesoSessions(sessions), offset: mesoSessionOffset,
      fromDays: daysPerWeek, toDays: days)
    daysPerWeek = days
    updatedAt = .now
  }

  /// The four plan settings as one value, defaulting any unknown raw string.
  var planSettings: PlanSettings {
    PlanSettings(
      goal: Goal(rawValue: goal) ?? .hypertrophy,
      split: SplitStyle(rawValue: split) ?? .auto,
      daysPerWeek: daysPerWeek,
      sessionMinutes: sessionMinutes)
  }

  /// The current week's plan revised for the program as it stands now, or nil when `base` is not this week's plan.
  func revisedWeekPlan(
    _ base: WeekPlan, sessions: [WorkoutSession], input: ProfileInput? = nil,
    now: Date = .now
  ) -> WeekPlan? {
    let adjusted = input ?? profileInput
    let calendar = base.resolvedCalendar(.current)
    guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: base.weekStart),
      now >= base.weekStart, now < weekEnd
    else { return nil }
    let hasOpenWorkoutToday = sessions.contains {
      !$0.completed && calendar.isDate($0.date, inSameDayAs: now)
    }
    let today = calendar.startOfDay(for: now)
    let from = calendar.date(byAdding: .day, value: hasOpenWorkoutToday ? 1 : 0, to: today) ?? today
    return WeekPlanBuilder.revise(
      base,
      program: Program.week(currentWeek(sessions: sessions), profile: adjusted),
      nextDayIndex: nextDayIndex,
      profile: adjusted,
      constraints: trainingConstraints,
      from: from,
      now: now,
      calendar: .current)
  }

  /// Applies the revised current-week plan after a program change in Settings.
  func reviseWeekPlan(sessions: [WorkoutSession], now: Date = .now) {
    if let plan = weekPlan, let revised = revisedWeekPlan(plan, sessions: sessions, now: now),
      revised != plan
    {
      weekPlan = revised
      updatedAt = .now
    }
  }

  /// Applies a Coach-approved adjustment exactly like Settings → Training: days rebase the block, then the current week is revised.
  func applyPlanAdjustment(_ adjustment: PlanAdjustment, sessions: [WorkoutSession], now: Date = .now) {
    if let days = adjustment.daysPerWeek { setDaysPerWeek(days, sessions: sessions) }
    if let minutes = adjustment.sessionMinutes { sessionMinutes = minutes }
    if let adjustedGoal = adjustment.goal { goal = adjustedGoal.rawValue }
    if let adjustedSplit = adjustment.split { split = adjustedSplit.rawValue }
    updatedAt = now
    reviseWeekPlan(sessions: sessions, now: now)
  }

  /// The workouts an adjustment would produce, without changing anything.
  func previewProgram(_ adjustment: PlanAdjustment, sessions: [WorkoutSession]) -> [PlannedDay] {
    Program.week(currentWeek(sessions: sessions), profile: adjustment.applied(to: profileInput))
  }

  /// The current week's accepted plan revised with the adjusted input, or nil when there is no plan for this week.
  func previewWeekPlan(
    _ adjustment: PlanAdjustment, sessions: [WorkoutSession], now: Date = .now
  ) -> WeekPlan? {
    guard let plan = weekPlan else { return nil }
    return revisedWeekPlan(
      plan, sessions: sessions, input: adjustment.applied(to: profileInput), now: now)
  }

  var isSubscribed: Bool { trialStartedAt != nil }
}

@Model
final class CheckIn {
  var date: Date
  var sleep: Int
  var soreness: Int
  var energy: Int
  /// Objective sleep duration. Device-local: it may be entered by hand or come from
  /// HealthKit, so it is never uploaded. `CheckIn.syncData` omits it and
  /// `server/migrations/0003_remove_synced_sleep_hours.sql` strips it from stored records.
  var sleepHours: Double
  var motivation: Int = 3
  var soreMuscles: [String] = []
  var remoteID: String = ""
  var updatedAt: Date = Date.now
  @Attribute(originalName: "deleted") var tombstoned: Bool = false

  init(date: Date, sleep: Int, soreness: Int, energy: Int, sleepHours: Double) {
    self.date = date
    self.sleep = sleep
    self.soreness = soreness
    self.energy = energy
    self.sleepHours = sleepHours
  }
}

@Model
final class WorkoutSession {
  var date: Date
  var dayName: String
  var week: Int
  var completed: Bool
  var notes: String = ""
  var order: [String] = []
  var supersets: [String] = []
  var extraExerciseIDs: [String] = []
  var removedExerciseIDs: [String] = []
  var setCounts: [String: Int] = [:]
  /// The prescription actually started, independent of later plan edits or completion.
  var routinePrescriptionJSON: String = ""
  var plannedDayID: String = ""
  var plannedPlanID: String? = nil
  var plannedAcceptanceID: String? = nil
  @Relationship(deleteRule: .cascade, inverse: \LoggedSet.session) var sets: [LoggedSet]
  var remoteID: String = ""
  var updatedAt: Date = Date.now
  @Attribute(originalName: "deleted") var tombstoned: Bool = false
  var heartRateSeen: Bool = false
  /// Planned sets when the session was finished; 0 = unknown (older or synced session).
  var plannedSetCount: Int = 0

  init(date: Date, dayName: String, week: Int, completed: Bool) {
    self.date = date
    self.dayName = dayName
    self.week = week
    self.completed = completed
    self.sets = []
  }

  /// False when the session looks fabricated; such sessions stay in history but do not feed PRs, badges or Crew.
  var verified: Bool {
    if heartRateSeen { return true }
    if sets.contains(where: \.suspect) { return false }
    let times = sets.map(\.loggedAt).sorted()
    return !Plausibility.isShortSession(setCount: sets.count, first: times.first, last: times.last)
  }

  /// Sets that may drive charts, PRs and trends: everything the plausibility guard did not flag,
  /// minus sets the lifter withheld from *any* named analysis. A caller that knows which named
  /// analysis it feeds asks for that scope precisely, via `analysisSets(_:)`.
  var trustedSets: [LoggedSet] { analysisSets(in: Set(SetAnalysisScope.allCases)) }

  /// Sets eligible for the named analysis scopes, honouring both the plausibility guard and any
  /// set-limiter feedback. Excluded sets stay in the session — they are simply not read here.
  func analysisSets(in scopes: Set<SetAnalysisScope>) -> [LoggedSet] {
    guard verified else { return [] }
    return sets.filter { set in
      !set.suspect && scopes.allSatisfy { set.isEligibleForAnalysis($0) }
    }
  }

  func analysisSets(_ scope: SetAnalysisScope) -> [LoggedSet] { analysisSets(in: [scope]) }
}

extension Array where Element == WorkoutSession {
  /// The sessions every "eligible" count must mean.
  ///
  /// There were two definitions: Balance counted `completed` sessions while Progress counted
  /// `verified` ones, and both printed the word "eligible" — so a session the plausibility
  /// guard had excluded still raised Balance's session count while contributing no sets, and
  /// the two screens disagreed about the same week. One predicate, one meaning: a session is
  /// eligible when it finished AND its sets can actually be read.
  var analysisEligibleSessions: [WorkoutSession] {
    filter { $0.completed && $0.verified }
  }

  /// Every set from completed sessions that the plausibility guard trusts.
  var trustedSets: [LoggedSet] {
    filter(\.completed).flatMap(\.trustedSets)
  }

  /// Completed-session sets eligible for one named analysis scope.
  func analysisSets(_ scope: SetAnalysisScope) -> [LoggedSet] {
    filter(\.completed).flatMap { $0.analysisSets(scope) }
  }

  /// How many trusted sets the lifter's own feedback keeps out of `scope` — what the "left out"
  /// explanation counts. Nothing is removed from the sessions themselves.
  func excludedSetCount(_ scope: SetAnalysisScope) -> Int {
    filter { $0.completed && $0.verified }
      .flatMap(\.sets)
      .filter { !$0.suspect && !$0.isEligibleForAnalysis(scope) }
      .count
  }
}

/// One engine decision, kept so the coach can explain a real change instead of guessing.
@Model
final class DecisionLogEntry {
  var journeyID: String = ""
  var date: Date
  var type: String
  var exerciseID: String?
  var muscle: String?
  var fromValue: Double?
  var toValue: Double?
  var reasonCodes: [String]
  var evidence: [String]
  var humanSummary: String
  /// Stable identity for one committed decision on one session start: intent + resource +
  /// content. A retried start recomputes the same fingerprint, so the ledger writes once.
  /// Empty on rows written before the trace existed; those stay exactly as recorded.
  var operationFingerprint: String = ""

  init(_ record: DecisionRecord, operationFingerprint: String = "") {
    journeyID = UUID().uuidString
    date = record.date
    type = record.type
    exerciseID = record.exerciseID
    muscle = record.muscle
    fromValue = record.fromValue
    toValue = record.toValue
    reasonCodes = record.reasonCodes
    evidence = record.evidence
    humanSummary = record.humanSummary
    self.operationFingerprint = operationFingerprint
  }

  /// Whether this committed decision may leave the device, by the lineage of its reason codes.
  var isCloudExportable: Bool { DecisionProvenance.isCloudExportable(record) }

  var record: DecisionRecord {
    DecisionRecord(
      id: "\(type)-\(exerciseID ?? muscle ?? "session")-\(Int(date.timeIntervalSince1970))",
      date: date,
      type: type,
      exerciseID: exerciseID,
      muscle: muscle,
      fromValue: fromValue,
      toValue: toValue,
      reasonCodes: reasonCodes,
      evidence: evidence,
      humanSummary: humanSummary)
  }
}

func plateauedExerciseIDs(sessions: [WorkoutSession], now: Date = .now) -> Set<String> {
  var history: [String: [E1RMPoint]] = [:]
  for session in sessions where session.completed {
    let bestPerExercise = Dictionary(grouping: session.sets, by: \.exerciseID)
      .mapValues { sets in
        sets.map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max() ?? 0
      }
    for (id, best) in bestPerExercise where best > 0 {
      history[id, default: []].append(E1RMPoint(date: session.date, e1rm: best))
    }
  }
  return Set(history.filter { Strength.isPlateaued($0.value, asOf: now) }.keys)
}

@Model
final class LoggedSet {
  var exerciseID: String
  var setIndex: Int
  var weightKg: Double
  var reps: Int
  var rpe: Double
  var targetRPE: Double
  var variant: String = "straight"
  var loggedAt: Date
  var suspect: Bool = false
  var session: WorkoutSession?
  var originalLoadValue: String = ""
  var originalLoadUnit: String = "kg"
  var loadDomain: String = LoadDomain.externalMass.rawValue
  var loadingConvention: String = LoadingConvention.unknown.rawValue
  var equipmentInstanceID: String? = nil
  var loadModelRevision: Int? = nil
  var loadSide: String = LoadSide.unspecified.rawValue
  var loadNormalizationStatus: String = LoadNormalizationStatus.ambiguous.rawValue
  /// True only when the lifter gave an effort rating: a typed, voice or Watch payload that
  /// carried an explicit RPE, or a manual tap on the RPE stepper. Rows persisted before this
  /// flag existed decode as `false`, which reads as "effort unknown" rather than as the target.
  var effortReported: Bool = false
  /// Set-limiter feedback as JSON. A string so a build that does not know a newer reason code
  /// round-trips it untouched; an unreadable payload reads as "no feedback" and is never
  /// overwritten. See `SetFeedback.swift` and `SetFeedbackSheet.swift`.
  var feedbackJSON: String = ""

  init(
    exerciseID: String,
    setIndex: Int,
    weightKg: Double,
    reps: Int,
    rpe: Double,
    targetRPE: Double,
    variant: String = "straight",
    loggedAt: Date,
    loadDescriptor: LoadDescriptor? = nil,
    effortReported: Bool = false
  ) {
    self.exerciseID = exerciseID
    self.setIndex = setIndex
    self.weightKg = weightKg
    self.reps = reps
    self.rpe = rpe
    self.targetRPE = targetRPE
    self.variant = variant
    self.loggedAt = loggedAt
    self.effortReported = effortReported
    let descriptor =
      loadDescriptor ?? Self.inferredDescriptor(exerciseID: exerciseID, weightKg: weightKg)
    apply(descriptor)
  }

  var descriptor: LoadDescriptor {
    LoadDescriptor(
      originalValue: originalLoadValue.isEmpty ? String(weightKg) : originalLoadValue,
      originalUnit: originalLoadUnit,
      domain: LoadDomain(rawValue: loadDomain) ?? .externalMass,
      convention: LoadingConvention(rawValue: loadingConvention) ?? .unknown,
      equipmentInstanceID: equipmentInstanceID,
      loadModelRevision: loadModelRevision,
      side: LoadSide(rawValue: loadSide) ?? .unspecified,
      normalizationStatus: LoadNormalizationStatus(rawValue: loadNormalizationStatus) ?? .ambiguous)
  }

  var comparisonContext: ComparisonContext {
    ComparisonContext(
      exerciseID: exerciseID,
      variantID: variant,
      equipmentInstanceID: equipmentInstanceID,
      loadModelRevision: loadModelRevision,
      convention: descriptor.convention,
      side: descriptor.side,
      normalizationStatus: descriptor.normalizationStatus)
  }

  /// Whether this set may serve as a baseline for `reference` (PRs, progression, charts).
  ///
  /// When the reference carries a *verified* passport context, only another verified and
  /// compatible context may be compared: two different machines, or a machine and a legacy
  /// unknown, must never merge into one baseline. When the reference has no verified context,
  /// the pre-passport behaviour (everything is comparable) holds so legacy history keeps
  /// working. Old sets are never rewritten — this only governs which records are compared.
  func isComparableForBaseline(to reference: LoggedSet) -> Bool {
    guard reference.comparisonContext.normalizationStatus == .verified else { return true }
    let mine = comparisonContext
    guard mine.normalizationStatus == .verified else { return false }
    return mine.isComparable(to: reference.comparisonContext)
  }

  /// The lifter-reported effort, or nil when `rpe` is only the target/default placeholder.
  var reportedRPE: Double? { effortReported ? rpe : nil }

  /// The effort value to reason with. Unknown stays unknown: callers must hold load rather
  /// than treat the target or the default as something the lifter reported.
  var effortForProgression: Double? { reportedRPE }

  /// User-facing effort text that never claims an RPE the lifter did not give.
  var effortText: String {
    guard let reported = reportedRPE else {
      return String(localized: "Not entered", bundle: L10n.bundle)
    }
    return Fmt.num(reported)
  }

  // MARK: set-limiter feedback

  /// Identity this set's feedback binds to: which set, in which session, at which revision.
  var feedbackSetID: String { String(describing: persistentModelID) }

  /// Revision derived from the recorded content, so an edit to the load, reps, index or variant
  /// makes older feedback recognisable as stale without any edit site having to bump a counter.
  var feedbackRevision: SetRevision {
    SetRevisionBuilder.revision(
      setID: feedbackSetID,
      loadValue: originalLoadValue.isEmpty ? String(weightKg) : originalLoadValue,
      loadUnit: originalLoadUnit,
      reps: reps,
      setIndex: setIndex,
      variant: variant)
  }

  var feedbackIdentity: SetIdentity {
    SetIdentity(
      setID: feedbackSetID,
      sessionID: session.map { String(describing: $0.persistentModelID) } ?? "",
      exerciseID: exerciseID,
      setIndex: setIndex,
      revision: feedbackRevision,
      loggedAt: loggedAt)
  }

  /// The stored statement, or `nil` when absent or unreadable. Reading never rewrites the payload.
  var setFeedback: SetLimiterEvent? { SetLimiterEventCodec.decode(feedbackJSON) }

  /// True when the lifter's own feedback leaves this set out of the named analysis.
  func isEligibleForAnalysis(_ scope: SetAnalysisScope) -> Bool {
    SetFeedbackAnalysisPolicy.isEligible(setFeedback, for: scope)
  }

  /// True when this set is withheld from at least one named analysis.
  var isExcludedFromAnalysis: Bool {
    guard let feedback = setFeedback, !feedback.isDeleted else { return false }
    return !SetFeedbackAnalysisPolicy.excludedScopes(feedback).isEmpty
  }

  /// Stores, edits or clears feedback. Clearing keeps the set and its data exactly as recorded.
  func storeFeedback(_ event: SetLimiterEvent?) {
    if let event {
      let encoded = SetLimiterEventCodec.encode(event)
      guard !encoded.isEmpty else { return }
      feedbackJSON = encoded
    } else {
      feedbackJSON = ""
    }
    session?.updatedAt = .now
  }

  func apply(_ descriptor: LoadDescriptor) {
    originalLoadValue = descriptor.originalValue
    originalLoadUnit = descriptor.originalUnit
    loadDomain = descriptor.domain.rawValue
    loadingConvention = descriptor.convention.rawValue
    equipmentInstanceID = descriptor.equipmentInstanceID
    loadModelRevision = descriptor.loadModelRevision
    loadSide = descriptor.side.rawValue
    loadNormalizationStatus = descriptor.normalizationStatus.rawValue
  }

  /// Conservative, pre-passport inference used whenever no equipment instance resolves.
  static func inferredDescriptor(exerciseID: String, weightKg: Double) -> LoadDescriptor {
    guard let exercise = ExerciseDB.find(exerciseID) else { return .legacy(weightKg: weightKg) }
    switch exercise.equipment {
    case .barbell:
      return LoadDescriptor(
        originalValue: String(weightKg), originalUnit: "kg", domain: .externalMass,
        convention: .totalIncludingBar, side: .bilateral, normalizationStatus: .verified)
    case .dumbbell:
      return LoadDescriptor(
        originalValue: String(weightKg), originalUnit: "kg", domain: .externalMass,
        convention: .perHand, side: .bilateral, normalizationStatus: .verified)
    case .bodyweight:
      return LoadDescriptor(
        originalValue: String(weightKg), originalUnit: "kg", domain: .bodyweight,
        convention: .notApplicable, side: .bilateral, normalizationStatus: .verified)
    case .machine, .cable:
      return LoadDescriptor(
        originalValue: String(weightKg), originalUnit: "kg", domain: .machineScale,
        convention: .unknown, normalizationStatus: .ambiguous)
    case .bands:
      return LoadDescriptor(
        originalValue: String(weightKg), originalUnit: "kg", domain: .externalMass,
        convention: .unknown, normalizationStatus: .unsupported)
    }
  }
}

extension UserProfile {
  func isLb(for exerciseID: String) -> Bool {
    unitOverrides[exerciseID] ?? usesLb
  }

  func unit(for exerciseID: String) -> String {
    isLb(for: exerciseID) ? "lb" : "kg"
  }

  func display(kg: Double, for exerciseID: String) -> Double {
    isLb(for: exerciseID) ? Plates.kgToLb(kg) : kg
  }

  /// Sensible default load side for an apparatus kind. Bilateral for the apparatus a lifter
  /// loads on both sides at once; machines stay unspecified because their halves are not
  /// independently loaded.
  static func defaultSide(for kind: EquipmentKind) -> LoadSide {
    switch kind {
    case .barbell, .dumbbell, .bodyweight, .bands: return .bilateral
    case .machine, .cable, .plateLoaded, .unknown: return .unspecified
    }
  }
}
