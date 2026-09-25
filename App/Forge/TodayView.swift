import ForgeCore
import SwiftData
import SwiftUI

struct TodayView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Query private var profiles: [UserProfile]
  @Query(sort: \CheckIn.date) private var checkIns: [CheckIn]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \DecisionLogEntry.date) private var decisionLog: [DecisionLogEntry]
  @Query(sort: \NutritionProfile.updated, order: .reverse) private var nutritionProfiles:
    [NutritionProfile]
  @Query(sort: \FoodEntry.date, order: .reverse) private var foodEntries: [FoodEntry]
  @Binding var selection: Int

  @State private var trainAnyway = false
  @State private var active: ActiveWorkout?
  @State private var activeAction: FatigueAction = .proceed
  @State private var sleepQuality = 3
  @State private var soreness = 3
  @State private var energy = 3
  @State private var motivation = 3
  @State private var soreMuscles: Set<Muscle> = []
  @State private var sleepHours = 7.0
  @State private var sleepPrefilled = false
  @State private var healthBaseline: Double?
  @State private var cardio:
    (hrv: Double?, hrvBaseline: Double?, rhr: Double?, rhrBaseline: Double?)?
  @State private var savedCheckInCount = 0
  @State private var showSettings = false
  @State private var showCheckIn = false
  @State private var showRoadmap = false
  @State private var showMusclePreview = false
  @State private var logFoodMeal: Meal?
  @State private var explaining: Adjustment?
  @State private var appeared = false
  @State private var reviewVoice: String?
  @State private var forceLight = false
  @State private var timeBox: Int?
  @State private var plateauDismissedKey = ""
  @State private var weekRepairDismissedKey = ""
  @State private var overrideTick = 0
  @State private var expandedAdjustment = ""
  @State private var showChanges = false
  @State private var primaryOffscreen = false
  @State private var explainingInChanges: Adjustment?
  @State private var headerCollapsed = false
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue

  private var coach: Coach { Coach.from(coachID) }

  private var profile: UserProfile? { profiles.first }

  /// The accepted week plan, resolved against `now`. Nil means the lifter never saved a
  /// plan, and Today is the generated schedule exactly as it was before.
  private var planStatus: WeekPlanTodayStatus? {
    profile?.weekPlan.map { WeekPlanTodayStatus(plan: $0, now: .now) }
  }

  /// The owed day whose applied routine was stranded by an equipment, constraint or
  /// program-week change: its saved prescription no longer matches the setup, so it must
  /// be re-confirmed before it can start. While set, Today offers no startable session —
  /// never a stale prescription, never a generated fallback.
  private var reviewOwedDay: WeekPlanDay? {
    guard let profile, let owed = planStatus?.owed,
      RoutineAdaptationService.needsReview(owed, profile: profile, sessions: sessions)
    else { return nil }
    return owed
  }

  private var planReviewActionVisible: Bool {
    guard let profile, let owed = reviewOwedDay else { return true }
    guard !RoutineAdaptationService.routineDataUnreadable(profile) else { return false }
    return !profile.appliedRoutines.contains {
      $0.planDayID == owed.id && $0.blockStart == profile.mesoStart
    }
  }

  private var openSession: WorkoutSession? {
    sessions.last { !$0.completed && !$0.tombstoned
      && (Calendar.current.isDateInToday($0.date) || $0.routinePrescription != nil) }
  }

  /// Today's finished session while none is open; Today then leads with the goal card.
  private var doneToday: WorkoutSession? {
    openSession == nil ? TodayGoal.finishedToday(sessions) : nil
  }

  private var fatigue: (score: Int, action: FatigueAction)? {
    fatigueNow(
      profile: profile, sessions: sessions, checkIns: checkIns, healthBaseline: healthBaseline,
      cardio: cardio)
  }

  private var isForceRest: Bool {
    if case .forceRest = fatigue?.action { return true }
    return false
  }

  private var week: Int { profile.map { $0.currentWeek(sessions: sessions) } ?? 1 }

  /// Forward-looking week brief, built from committed plan + decision-log state only.
  private var upcomingWeek: Int { week + 1 }

  private var upcomingIsDeload: Bool {
    profile?.deloadStartedAt != nil || upcomingWeek == Mesocycle.deloadWeek
  }

  private var upcomingDayNames: [String] {
    guard let profile else { return [] }
    return Program.week(upcomingWeek, profile: profile.profileInput, volumeDelta: volumeDelta).map(
      \.name)
  }

  private var briefFacts: [WeekBriefFact] {
    let blockStart = profile?.mesoStart ?? .distantPast
    return decisionLog.filter { $0.date >= blockStart && $0.type != "plan_settings" }.flatMap { entry -> [WeekBriefFact] in
      let record = entry.record
      let codes = record.reasonCodes.isEmpty ? ["type:\(record.type)"] : record.reasonCodes
      let scope: WeekBriefScope
      switch record.type {
      case "weekplan", "session", "plateau", "experiment", "experiment-result",
        "import-plan", "equipmentPassport", "constraints":
        scope = .futureWeek
      default:
        scope = .futureSession
      }
      let base = entry.journeyID.isEmpty ? record.id : entry.journeyID
      return codes.map { code in
        WeekBriefFact(
          id: "\(base):\(code)",
          exerciseID: record.exerciseID,
          muscleID: record.muscle,
          reasonCode: code,
          fromValue: record.fromValue,
          toValue: record.toValue,
          scope: scope)
      }
    }
  }

  private var weekBrief: WeekBriefResult {
    WeekBrief.build(
      WeekBriefInput(
        week: week,
        totalWeeks: Mesocycle.weeks,
        isDeload: upcomingIsDeload,
        upcomingDayNames: upcomingDayNames,
        facts: briefFacts))
  }

  @AppStorage("deloadDismissedDay") private var deloadDismissedDay = ""
  @AppStorage("weekReviewDismissed") private var weekReviewDismissed = 0
  private var todayKey: String { Date.now.formatted(.iso8601.year().month().day()) }

  private var redStreak: Bool {
    guard let today = fatigue?.score else { return false }
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    let prior =
      fatigueNow(
        profile: profile, sessions: sessions, checkIns: checkIns, healthBaseline: healthBaseline,
        cardio: nil, now: yesterday)?.score ?? 0
    return Fatigue.shouldDeloadEarly(recentScores: [prior, today])
  }

  private var offersEarlyDeload: Bool {
    redStreak && profile?.deloadStartedAt == nil && week != Mesocycle.deloadWeek
      && deloadDismissedDay != todayKey
  }

  private var previousMicrocycle: [WorkoutSession] {
    guard let profile else { return [] }
    let days = max(profile.daysPerWeek, 1)
    let done = sessions.filter { $0.completed && $0.date >= profile.mesoStart }.sorted {
      $0.date < $1.date
    }
    let index = done.count / days
    guard index >= 1 else { return [] }
    return Array(done[((index - 1) * days)..<min(index * days, done.count)])
  }

  private var volumeDelta: [Muscle: Int] {
    guard let profile else { return [:] }
    let goal = Goal(rawValue: profile.goal) ?? .hypertrophy
    let performances: [ExercisePerformance] = Dictionary(
      grouping: previousMicrocycle.flatMap(\.sets), by: \.exerciseID
    )
    .compactMap { id, sets in
      guard let exercise = ExerciseDB.find(id), let first = sets.first else { return nil }
      return ExercisePerformance(
        exercise: exercise,
        repRange: Program.repRange(exercise, goal: goal),
        targetRPE: first.targetRPE,
        sets: sets.map {
          SetLog(
            weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe,
            effortReported: $0.effortReported)
        })
    }
    let soreness = checkIns.last(where: { Calendar.current.isDateInToday($0.date) })
    let soreMuscles = Set(soreness?.soreMuscles.compactMap(Muscle.init(rawValue:)) ?? [])
    return Autoregulation.volumeDelta(
      performances, soreness: soreness?.soreness, soreMuscles: soreMuscles)
  }

  private var plannedPair: (day: PlannedDay, base: PlannedDay?)? {
    guard let profile else { return nil }
    guard !RoutineAdaptationService.hasUnreadableOpenSnapshot(sessions) else { return nil }
    if let snapshot = openSession?.routinePrescription.flatMap(RoutineAdaptation.plannedDay) {
      return (snapshot, nil)
    }
    // An accepted week saved in a format this version cannot decode is real, retained
    // data — not an absent plan. It must never surface Start for, or let
    // forge.startWorkout begin, a generated day in its place.
    guard !RoutineAdaptationService.weekPlanUnreadable(profile) else { return nil }
    let days = Program.week(
      week, profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)),
      volumeDelta: volumeDelta)
    guard !days.isEmpty else { return nil }
    let baseDays = Program.week(week, profile: profile.profileInput, volumeDelta: volumeDelta)
    let index = profile.nextDayIndex % days.count
    var day: PlannedDay
    var base: PlannedDay?
    if let status = planStatus {
      // The accepted plan owns today: it names the session by `plannedSessionID`, and
      // when it has nothing left to point at there is no session here — never the
      // generated rotation, which is only today when no plan was ever accepted.
      guard let owed = status.owed,
        // An applied routine the setup change stranded is never swapped for a generated
        // day — it stays behind the review card until it is re-applied and confirmed.
        !RoutineAdaptationService.needsReview(owed, profile: profile, sessions: sessions),
        let planned = RoutineAdaptationService.resolvedDay(owed, profile: profile, sessions: sessions)
          ?? days.first(where: { $0.id == owed.plannedSessionID })
      else { return nil }
      day = planned
      base = baseDays.first { $0.id == planned.name }
    } else {
      day = days[index]
      base = baseDays.indices.contains(index) ? baseDays[index] : nil
    }
    switch fatigue?.action {
    case .reduceOptionalSets:
      day = PlannedDay(
        name: day.name,
        exercises: day.exercises.map {
          PlannedExercise(
            exercise: $0.exercise, sets: max(1, $0.sets - 1), repRange: $0.repRange,
            targetRPE: $0.targetRPE)
        }, trimmedSets: day.trimmedSets)
    case .lightSession:
      day = lightDay(day)
    default:
      break
    }
    return (day, base)
  }

  private var plannedDay: PlannedDay? { plannedPair?.day }

  private func resumeDay(for open: WorkoutSession, fallback: PlannedDay) -> PlannedDay {
    if let snapshot = open.routinePrescription.flatMap(RoutineAdaptation.plannedDay) { return snapshot }
    guard let profile else { return fallback }
    let days = Program.week(
      week, profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)),
      volumeDelta: volumeDelta)
    return days.first { $0.name == open.dayName } ?? fallback
  }

  private var baseDay: PlannedDay? { plannedPair?.base }

  private var effectiveDay: PlannedDay? {
    guard let day = plannedDay else { return nil }
    guard let minutes = timeBox else { return day }
    return TimeBudget.fit(day, minutes: minutes)
  }

  private var readinessScore: Int? {
    // ponytail: fatigue readiness is 0–100 (higher better); DecisionBuilder wants 1–5
    readiness.map { min(5, max(1, ($0 + 19) / 20)) }
  }

  /// The one reporting week every "this week" number on this screen is read from.
  private var reportingWeek: DateInterval {
    TrainingMetrics.reportingWeek(containing: .now, calendar: TrainingMetrics.reportingCalendar())
  }

  private var completedThisWeek: Int {
    sessions.filter { $0.completed && TrainingMetrics.contains(reportingWeek, $0.date) }.count
  }

  private var daysLeftInWeek: Int {
    let end = Calendar.current.startOfDay(for: reportingWeek.end)
    let now = Calendar.current.startOfDay(for: .now)
    let days = Calendar.current.dateComponents([.day], from: now, to: end).day ?? 0
    return max(0, days)
  }

  private var weekStatus: WeekStatusPresentation {
    // A saved plan is the week's own arithmetic: its counts, not the block's target.
    if let plan = profile?.weekPlan { return plan.weekStatusPresentation() }
    guard let profile else {
      return WeekStatusPresentation(recorded: 0, planned: 0, remaining: 0, atRisk: 0)
    }
    return WeekStatusPolicy.presentation(
      planned: profile.daysPerWeek,
      recorded: completedThisWeek,
      daysLeft: daysLeftInWeek,
      enrollmentDate: profile.mesoStart)
  }

  /// Sessions done and owed this week, from the accepted plan when there is one.
  private var sessionsDoneThisWeek: Int {
    planStatus?.evaluation.counts.completed ?? WeekStrip.completed(sessions)
  }

  private var sessionsTargetThisWeek: Int {
    max(1, planStatus?.evaluation.counts.scheduled ?? max(profile?.daysPerWeek ?? 1, 1))
  }

  private var missedThisWeek: Int { weekStatus.atRisk }

  private var repairOptions: [WeekRepair.Option] {
    WeekRepair.options(missed: missedThisWeek, daysLeftInWeek: daysLeftInWeek)
  }

  private var splitNames: [String] { Program.split(daysPerWeek: profile?.daysPerWeek ?? 3) }

  private var nextDayName: String {
    guard let profile else { return "" }
    let names = splitNames
    guard !names.isEmpty else { return "" }
    return localizedDayName(names[(profile.nextDayIndex + 1) % names.count])
  }

  private var lastDayName: String {
    splitNames.last.map(localizedDayName) ?? ""
  }

  private var recentRPEOverTarget: Bool {
    let cutoff = Date.now.addingTimeInterval(-7 * 86400)
    return sessions.filter { $0.completed && $0.date > cutoff }
      .flatMap(\.sets)
      .contains { $0.effortReported && $0.rpe > $0.targetRPE + 1 }
  }

  private var auditSets: [AuditSet] {
    sessions.filter(\.completed).flatMap { s in
      s.sets.map {
        AuditSet(
          exerciseID: $0.exerciseID, date: s.date, weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe
        )
      }
    }
  }

  private var plateauFinding: PlateauFinding? {
    guard let profile, let day = plannedDay else { return nil }
    let equipment = Set(profile.equipment.compactMap { Equipment(rawValue: $0) })
    let injuries = Set(profile.injuryFlags.compactMap { InjuryFlag(rawValue: $0) })
    let sorenessHigh =
      (checkIns.last(where: { Calendar.current.isDateInToday($0.date) })?.soreness ?? 0) >= 4
    for planned in day.exercises {
      let muscle = planned.exercise.primary
      if let finding = PlateauRescue.rescue(
        exerciseID: planned.exercise.id,
        history: auditSets,
        repRange: planned.repRange,
        weeklySets: weeklySets(for: muscle),
        landmarks: VolumeLandmarks.landmarks(for: muscle, recoveryReduced: profile.recoveryReduced),
        sorenessHigh: sorenessHigh,
        recentRPEOverTarget: recentRPEOverTarget,
        equipment: equipment,
        injuries: injuries,
        recoveryReduced: profile.recoveryReduced)
      {
        return finding
      }
    }
    return nil
  }

  private func weeklySets(for muscle: Muscle) -> Double {
    var total = 0.0
    for s in sessions where s.completed && TrainingMetrics.contains(reportingWeek, s.date) {
      for set in s.sets {
        guard let ex = ExerciseDB.find(set.exerciseID) else { continue }
        if ex.primary == muscle {
          total += 1
        } else if ex.isCompound && ex.synergists.contains(muscle) {
          total += 0.5
        }
      }
    }
    return total
  }

  private func recommendation(_ option: WeekRepair.Option) -> String {
    switch option {
    case .shift:
      return String(localized: "Best: keep today's plan and carry on.", bundle: L10n.bundle)
    case .compress:
      return String(
        localized:
          "Best: move \(nextDayName) to today and cut \(lastDayName) by \(missedThisWeek) sets.",
        bundle: L10n.bundle)
    default:
      return option.detail
    }
  }

  private func applyRepair(_ option: WeekRepair.Option) {
    guard let profile else { return }
    switch option {
    case .shift:
      break
    case .compress:
      profile.mesoSessionOffset += missedThisWeek
    case .skip:
      profile.nextDayIndex += 1
    case .light:
      forceLight = true
    case .restart:
      profile.mesoSessionOffset -= (profile.mesoSessions(sessions) % max(profile.daysPerWeek, 1))
      profile.nextDayIndex = 0
    }
    profile.updatedAt = .now
    Analytics.track("week_repair", ["option": option.rawValue])
    weekRepairDismissedKey = todayKey
  }

  private func plateauActionTitle(_ finding: PlateauFinding) -> String {
    switch finding.decision.action {
    case .swapExercise: return String(localized: "Swap exercise", bundle: L10n.bundle)
    case .deload: return String(localized: "Start deload", bundle: L10n.bundle)
    case .addSets: return String(localized: "Add a set", bundle: L10n.bundle)
    case .removeSets: return String(localized: "Remove a set", bundle: L10n.bundle)
    case .changeRepRange: return String(localized: "Change rep range", bundle: L10n.bundle)
    default: return String(localized: "Apply", bundle: L10n.bundle)
    }
  }

  private func applyPlateau(_ finding: PlateauFinding) {
    guard let profile else { return }
    let id = finding.exerciseID
    switch finding.decision.action {
    case .swapExercise(let fromID, let toID):
      profile.exerciseOverrides[fromID] = toID
      Analytics.track("plateau_rescue", ["action": "swapExercise"])
    case .deload:
      profile.deloadStartedAt = .now
      Analytics.track("plateau_rescue", ["action": "deload"])
    case .addSets(let n):
      profile.setDeltas[id, default: 0] += n
      Analytics.track("plateau_rescue", ["action": "addSets"])
    case .removeSets(let n):
      profile.setDeltas[id, default: 0] -= n
      Analytics.track("plateau_rescue", ["action": "removeSets"])
    case .changeRepRange(_, let to):
      profile.repRangeOverrides[id] = "\(to.lowerBound)-\(to.upperBound)"
      Analytics.track("plateau_rescue", ["action": "changeRepRange"])
    default:
      break
    }
    profile.updatedAt = .now
    plateauDismissedKey = todayKey
  }

  @ViewBuilder
  private var missedWorkoutCard: some View {
    // Only the generated schedule gets this repair. With an accepted plan the week is the
    // plan's, and moving a day is the lifter's explicit call in the week designer.
    if planStatus == nil, !repairOptions.isEmpty, weekRepairDismissedKey != todayKey {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          CoachAvatar(size: 28)
          Text(String(localized: "Week needs a repair", bundle: L10n.bundle)).forgeSection()
          Spacer()
        }
        Text(
          "\(weekStatus.remaining) planned session\(L10n.pluralSuffix(weekStatus.remaining)) remain with \(daysLeftInWeek) day\(L10n.pluralSuffix(daysLeftInWeek)) left. \(recommendation(repairOptions[0]))"
        )
        .forgeBodyStrong()
        Button("Apply: \(repairOptions[0].title)") { applyRepair(repairOptions[0]) }
          .buttonStyle(PillButtonStyle(minHeight: 44))
        ForEach(repairOptions.dropFirst(), id: \.self) { option in
          Button {
            applyRepair(option)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(option.title).forgeBodyStrong()
                Text(option.detail).forgeLabel()
              }
              Spacer()
              Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
          }
          .buttonStyle(RowPressStyle())
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .todayCard()
    }
  }

  @ViewBuilder
  private var plateauCard: some View {
    if plateauDismissedKey != todayKey, let finding = plateauFinding {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          CoachAvatar(size: 28)
          Text(
            String(
              localized:
                "\(ExerciseDB.find(finding.exerciseID)?.localizedName ?? finding.exerciseID) has stalled",
              bundle: L10n.bundle)
          ).forgeSection()
          Spacer()
          Button {
            plateauDismissedKey = todayKey
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(Theme.textSecondary)
          }
          .accessibilityLabel("Dismiss")
        }
        Text(finding.decision.reason).forgeBody()
        Button(plateauActionTitle(finding)) { applyPlateau(finding) }
          .buttonStyle(PillButtonStyle(minHeight: 44))
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .todayCard()
    }
  }

  private var weekHeader: String {
    week == Mesocycle.deloadWeek
      ? String(localized: "Deload week", bundle: L10n.bundle)
      : String(localized: "Week \(week) of \(Mesocycle.weeks)", bundle: L10n.bundle)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 14) {
        if let day = plannedDay {
          if isForceRest && !trainAnyway && openSession == nil && doneToday == nil {
            todayHeader.reveal(0, appeared: appeared)
            restDayCard(day).reveal(1, appeared: appeared)
            weekCard.reveal(2, appeared: appeared)
            if let status = planStatus {
              acceptedPlanCard(status).reveal(3, appeared: appeared)
            }
            if offersEarlyDeload {
              earlyDeloadCard.reveal(4, appeared: appeared)
            }
          } else {
            let fit = effectiveDay ?? day
            todayHeader.reveal(0, appeared: appeared)
            nextUpCard(fit).reveal(1, appeared: appeared)
            readinessPills(fit).reveal(2, appeared: appeared)
            coachCall(fit).padding(.top, 8).reveal(3, appeared: appeared).id("adjustments")
            if fatigue != nil && doneToday == nil {
              planCard(fit).todayCard(padding: 16).reveal(4, appeared: appeared)
            }
            weekCard.reveal(5, appeared: appeared)
            if let status = planStatus {
              acceptedPlanCard(status, showsFocusName: false).reveal(6, appeared: appeared)
            }
            if showWeekReview {
              weekReviewCard.reveal(7, appeared: appeared)
            }
            if offersEarlyDeload {
              earlyDeloadCard.reveal(8, appeared: appeared)
            }
            missedWorkoutCard.reveal(9, appeared: appeared)
            plateauCard.reveal(10, appeared: appeared)
            logFoodRow.reveal(11, appeared: appeared)
            recordCard.reveal(12, appeared: appeared)
          }
        } else {
          // No session can start today. An accepted plan with nothing left to point at is
          // rest, never a generated session the lifter did not agree to, and a routine
          // stranded by a setup change is owed a re-confirmation. A saved, unfinished
          // workout this version cannot decode comes first of all: it explains why nothing
          // starts, above every plan or rest card. An accepted week this version cannot
          // decode is the same kind of wall — retained but unreadable, so Today says that
          // instead of falling back to the generated rotation.
          todayHeader.reveal(0, appeared: appeared)
          if RoutineAdaptationService.hasUnreadableOpenSnapshot(sessions) {
            unreadableSnapshotCard.reveal(1, appeared: appeared)
          }
          if let profile, RoutineAdaptationService.weekPlanUnreadable(profile) {
            unreadableWeekCard.reveal(2, appeared: appeared)
          }
          weekCard.reveal(3, appeared: appeared)
          if let status = planStatus {
            if status.evaluation.counts.scheduled > 0 {
              acceptedPlanCard(status, showsReviewAction: planReviewActionVisible)
                .reveal(4, appeared: appeared)
              if let owed = reviewOwedDay {
                routineReviewCard(owed).reveal(5, appeared: appeared)
              } else if status.owed == nil {
                planRestCard(status: status).reveal(5, appeared: appeared)
              }
            } else {
              planRestCard(status: status).reveal(4, appeared: appeared)
            }
          }
          logFoodRow.reveal(6, appeared: appeared)
        }
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)
      .padding(.bottom, 24)
      .background(alignment: .top) {
        TodayBackdrop()
          .frame(height: 1100)
          .offset(y: -300)
          .visualEffect { content, proxy in
            content.offset(y: max(0, -(proxy.frame(in: .scrollView).minY + 300)) * 0.3)
          }
          .allowsHitTesting(false)
      }
      .sheet(isPresented: $showCheckIn) { checkInSheet }
    }
    .background(Theme.todayPage)
    .overlay(alignment: .top) { TodayInlineTitle(visible: headerCollapsed) }
    .safeAreaInset(edge: .bottom) { bottomBar }
    .sensoryFeedback(.success, trigger: savedCheckInCount)
    .task { await loadHealthSignals() }
    .onAppear {
      if timeBox == nil { timeBox = profile?.trainingConstraints.sessionBudgetMinutes }
      withAnimation(.easeOut(duration: 0.4)) { appeared = true }
      writeSnapshot()
    }
    .sheet(item: $active) { workout in
      WorkoutView(
        plannedDay: workout.day, action: workout.resume == nil ? activeAction : .proceed,
        resuming: workout.resume, planDayID: workout.planDayID)
    }
    .sheet(item: $logFoodMeal) { meal in FoodSearchView(meal: meal) }
    .sheet(isPresented: $showRoadmap) {
      NavigationStack { ProgramRoadmapView() }
    }
    .sheet(isPresented: $showMusclePreview) {
      if let day = effectiveDay {
        NavigationStack { SessionMusclePreviewView(day: day) }
      }
    }
    .sheet(item: $explaining) { a in
      AdjustmentExplainSheet(
        adjustment: a,
        coach: coach,
        profile: profile,
        sessions: sessions,
        checkIns: checkIns,
        usesLb: usesLb,
        week: week)
    }
    .sheet(isPresented: $showChanges) { changesSheet }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("forge.startWorkout"))) {
      _ in
      guard let day = plannedDay else { return }
      if let open = openSession {
        active = resumeWorkout(for: open, fallback: day)
        return
      }
      guard !(isForceRest && !trainAnyway) else { return }
      beginWorkout(day)
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("forge.checkIn"))) { _ in
      showCheckIn = true
    }
  }

  private var greeting: String {
    let hour = Calendar.current.component(.hour, from: .now)
    if hour < 12 { return String(localized: "Good morning", bundle: L10n.bundle) }
    if hour < 17 { return String(localized: "Good afternoon", bundle: L10n.bundle) }
    return String(localized: "Good evening", bundle: L10n.bundle)
  }

  private var todayHeader: some View {
    TodayHeader(
      greeting: greeting,
      date: Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(L10n.locale)),
      coachName: coach.name,
      onCoach: { selection = 1 },
      onSettings: { showSettings = true })
      .padding(.horizontal, 4)
      .sheet(isPresented: $showSettings) { SettingsView() }
      .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY < 24 } action: { collapsed in
        withAnimation(.easeOut(duration: 0.2)) { headerCollapsed = collapsed }
      }
  }

  private var coachLine: String {
    if openSession != nil {
      return String(
        localized: "You have a session open. Pick up where you left off.", bundle: L10n.bundle)
    }
    if let status = planStatus, !status.owedIsToday, status.owed != nil {
      return String(localized: "Nothing is scheduled today.", bundle: L10n.bundle)
    }
    guard let fatigue else {
      return String(localized: "Check in and I'll set today's plan.", bundle: L10n.bundle)
    }
    switch fatigue.action {
    case .proceed:
      if let day = plannedDay,
        let up = adjustments(
          for: day, base: baseDay, sessions: sessions, profile: profile, usesLb: usesLb
        ).first(where: { $0.kind == .increase })
      {
        return String(
          localized: "All clear. \(up.exercise.localizedName) goes up today.", bundle: L10n.bundle)
      }
      return String(localized: "All clear. Let's lift.", bundle: L10n.bundle)
    case .reduceOptionalSets:
      if let hours = checkIns.last(where: { Calendar.current.isDateInToday($0.date) })?.sleepHours,
        hours > 0, hours < 6
      {
        return String(localized: "Short night. I dropped your optional sets.", bundle: L10n.bundle)
      }
      return String(localized: "Fatigue's up. I dropped your optional sets.", bundle: L10n.bundle)
    case .lightSession:
      return String(localized: "Light day. Keep RPE under 7.", bundle: L10n.bundle)
    case .forceRest: return String(localized: "Rest today. You've earned it.", bundle: L10n.bundle)
    }
  }

  /// Sleep baseline + HRV / resting HR, read on every appearance of Today.
  ///
  /// These used to load **only** inside the check-in sheet's `.task`. A lifter who had already
  /// checked in — or who relaunched the app later in the day — never reopened that sheet, so
  /// `cardio` stayed nil and `Fatigue.score` silently fell back to its four-term formula and
  /// dropped the 0.20 cardio weight, on a device that had the samples all along.
  ///
  /// Read-only and permission-gated: this never shows the HealthKit sheet. Authorization is
  /// still requested exactly where the App Store description says it is — on first check-in.
  /// The values stay in `@State` and never reach sync, analytics or the Coach prompt
  /// (`ContextField.source == .healthKit` is filtered in `CoachContext`).
  private func loadHealthSignals() async {
    guard Health.isAuthorized else { return }
    async let baseline = Health.averageSleepHours()
    async let signals = Health.cardioSignals()
    let (newBaseline, newCardio) = await (baseline, signals)
    healthBaseline = newBaseline
    if newCardio.hrv != nil || newCardio.rhr != nil { cardio = newCardio }
  }

  private var usesLb: Bool { profile?.usesLb ?? false }
  private var unit: String { usesLb ? "lb" : "kg" }

  private var readiness: Int? {
    fatigue.map { 100 - $0.score }
  }

  /// Hero overline: the real readiness state. Unscored days and rest days never read READY.
  private var readinessStateLabel: String {
    switch fatigue?.action {
    case .proceed, .reduceOptionalSets: return String(localized: "Ready", bundle: L10n.bundle)
    case .lightSession: return String(localized: "Light", bundle: L10n.bundle)
    case .forceRest: return String(localized: "Rest", bundle: L10n.bundle)
    case nil: return String(localized: "Check-in", bundle: L10n.bundle)
    }
  }

  private var weekComplete: Bool {
    sessionsDoneThisWeek >= sessionsTargetThisWeek
  }

  private var finishedWeek: Int { max(1, week - 1) }

  private var showWeekReview: Bool {
    weekComplete && weekReviewDismissed != finishedWeek
  }

  private var weeklyReview: WeeklyReview? {
    guard let profile else { return nil }
    let days = max(profile.daysPerWeek, 1)
    let done = sessions.filter { $0.completed && $0.date >= profile.mesoStart }.sorted {
      $0.date < $1.date
    }
    guard done.count >= days else { return nil }
    let thisWeek = Array(done.suffix(days))
    let priorWeek = Array(done.dropLast(days).suffix(days))
    let tonnage = thisWeek.flatMap(\.sets).reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    let priorTonnage =
      priorWeek.isEmpty
      ? nil : priorWeek.flatMap(\.sets).reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }

    let weekStart = thisWeek.map(\.date).min() ?? .now
    let before = sessions.filter { $0.completed && $0.date < weekStart }.flatMap(\.sets)
    let weekSets = thisWeek.flatMap(\.sets)
    var prNames: [String] = []
    for id in Set(weekSets.map(\.exerciseID)) {
      guard let exercise = ExerciseDB.find(id) else { continue }
      let best =
        weekSets.filter { $0.exerciseID == id }
        .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max() ?? 0
      let previous = before.filter { $0.exerciseID == id }
        .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max()
      if let previous, best > previous { prNames.append(exercise.localizedName) }
    }

    return WeeklyReview(
      week: finishedWeek,
      sessionsDone: thisWeek.count,
      sessionsPlanned: days,
      tonnageKg: tonnage,
      priorTonnageKg: priorTonnage,
      prs: prNames.sorted(),
      nextWeekNote: nextWeekNoteText(week: finishedWeek))
  }

  private func nextWeekNoteText(week: Int) -> String {
    let nextWeek = week + 1
    if nextWeek == Mesocycle.deloadWeek {
      return String(
        localized: "Week \(nextWeek) is the deload: volume drops, loads stay.", bundle: L10n.bundle)
    }
    let parts = volumeDelta.filter { $0.value != 0 }
      .sorted { $0.key.rawValue < $1.key.rawValue }
      .map { "\($0.key.a11yName) \($0.value > 0 ? "+1 set" : "−1 set")" }
    if parts.isEmpty {
      return String(localized: "Week \(nextWeek): volume held.", bundle: L10n.bundle)
    }
    return String(
      localized: "Week \(nextWeek): \(parts.joined(separator: ", ")).", bundle: L10n.bundle)
  }

  private func todayProgress(_ day: PlannedDay) -> Double? {
    guard let open = openSession else { return nil }
    let planned = day.exercises.reduce(0) { $0 + $1.sets }
    return planned > 0 ? Double(open.sets.count) / Double(planned) : nil
  }

  private func restDayCard(_ day: PlannedDay) -> some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 16) {
          ZStack {
            RingView(progress: Double(readiness ?? 0) / 100, lineWidth: 8, color: Theme.accent)
            MetricValue(value: "\(readiness ?? 0)", size: 24)
          }
          .frame(width: 72, height: 72)

          VStack(alignment: .leading, spacing: 4) {
            Text("Rest day.").forgeTitle()
            Text("Readiness \(readiness ?? 0). Nothing to log.")
              .forgeBody()
              .foregroundStyle(Theme.textSecondary)
          }
        }
        Text(coachLine).forgeBody()
      }
      .padding(16)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Rest day. Readiness \(readiness ?? 0). Nothing to log. \(coachLine)")
      Button(String(localized: "Train anyway", bundle: L10n.bundle)) { trainAnyway = true }
        .buttonStyle(TodayButtonStyle(kind: .secondary, fullWidth: true))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous))
    .todayCard(padding: 0)
  }

  private func nextUpCard(_ day: PlannedDay) -> some View {
    let name = localizedDayName(day.name)
    let sets = day.exercises.reduce(0) { $0 + $1.sets }
    let offered = doneToday != nil || planStatus?.owedIsToday == false
    let badge: String
    let badgeSymbol: String
    if openSession != nil {
      badge = String(localized: "In progress", bundle: L10n.bundle)
      badgeSymbol = "play.circle.fill"
    } else if offered {
      badge = String(localized: "Next session", bundle: L10n.bundle)
      badgeSymbol = "flame.fill"
    } else {
      badge = readinessStateLabel
      badgeSymbol = "heart.fill"
    }
    var meta: [String] = []
    if let status = planStatus, !status.owedIsToday {
      meta.append(planFocusLine(status))
    } else {
      meta.append(weekHeader)
    }
    meta.append(String(localized: "\(day.exercises.count) exercises", bundle: L10n.bundle))
    meta.append(String(localized: "\(sets) sets", bundle: L10n.bundle))

    let primary: NextUpAction?
    if let open = openSession {
      primary = NextUpAction(
        title: String(
          localized: "Resume \(localizedDayName(open.dayName)) · \(open.sets.count) set\(L10n.pluralSuffix(open.sets.count)) logged",
          bundle: L10n.bundle),
        kind: .primary,
        identifier: "today.resume",
        action: { active = resumeWorkout(for: open, fallback: day) })
    } else if fatigue == nil && doneToday == nil {
      primary = NextUpAction(
        title: String(localized: "Check in", bundle: L10n.bundle),
        kind: .primary,
        identifier: "today.checkIn",
        action: { showCheckIn = true })
    } else {
      primary = NextUpAction(
        title: String(localized: "Start \(name)", bundle: L10n.bundle),
        kind: offered ? .secondary : .primary,
        identifier: "today.start",
        action: { beginWorkout(day) })
    }

    return NextUpCard(
      badge: badge,
      badgeSymbol: badgeSymbol,
      minutes: planEstimate(day),
      title: name,
      meta: meta.joined(separator: " · "),
      exercises: day.exercises.map(\.exercise),
      appeared: appeared,
      primary: primary,
      onPlan: { showRoadmap = true },
      onExercises: { showMusclePreview = true },
      onPrimaryVisible: { visible in
        withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0)) {
          primaryOffscreen = !visible
        }
      })
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(doneToday != nil ? "today.nextSession" : "today.hero")
  }

  @ViewBuilder
  private func readinessPills(_ day: PlannedDay) -> some View {
    let checkIn = checkIns.last { Calendar.current.isDateInToday($0.date) }
    let overlap: String? = doneToday.flatMap { done in
      let worked = TodayGoal.primaryMuscles(
        done.sets.sorted { $0.loggedAt < $1.loggedAt }.map(\.exerciseID))
      let nextMuscles = Set(day.exercises.map(\.exercise.primary))
      let again = worked.filter { nextMuscles.contains($0) }
      guard !again.isEmpty else { return nil }
      return String(
        localized: "\(localizedDayName(day.name)) trains \(TodayGoal.list(again)) again.",
        bundle: L10n.bundle)
    }
    if checkIn != nil || doneToday != nil || overlap != nil {
      VStack(alignment: .leading, spacing: 8) {
        if checkIn != nil {
          ReadinessPill(
            kind: .checkedIn(
              sleepHours: (checkIn?.sleepHours ?? 0) > 0 ? checkIn?.sleepHours : nil)
          ) { showCheckIn = true }
        } else if doneToday != nil {
          ReadinessPill(kind: .checkInFirst(dayName: localizedDayName(day.name))) {
            showCheckIn = true
          }
        }
        if let overlap {
          ReadinessPill(kind: .overlap(overlap))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var weekCard: some View {
    WeekStampCard(
      done: sessionsDoneThisWeek, target: sessionsTargetThisWeek, streakWeeks: streakWeeks,
      sessions: sessions, todayProgress: plannedDay.flatMap { todayProgress($0) }, appeared: appeared,
      summary: sessionSummary,
      footerTitle: weekBrief.isEmpty
        ? nil
        : String(localized: "Next week's plan changed", bundle: L10n.bundle),
      onFooter: { showChanges = true })
  }

  private var sessionSummary: TodaySessionSummary? {
    guard let session = doneToday else { return nil }
    let logged = session.sets.count
    let planned = session.plannedSetCount
    let percent = TodayGoal.percent(logged: logged, planned: planned)
    let name = localizedDayName(session.dayName)
    let title = (percent ?? 100) >= 100
      ? String(localized: "\(name) · complete", bundle: L10n.bundle)
      : String(localized: "\(name) · ended early", bundle: L10n.bundle)
    var parts: [String] = []
    if planned > 0 {
      parts.append(String(localized: "\(logged) of \(planned) sets", bundle: L10n.bundle))
    } else {
      parts.append(String(localized: "\(logged) sets", bundle: L10n.bundle))
    }
    parts.append(SessionMath.tonnageText([session], usesLb: usesLb) + " " + unit)
    parts.append(
      TodayGoal.list(
        TodayGoal.primaryMuscles(session.sets.sorted { $0.loggedAt < $1.loggedAt }.map(\.exerciseID))))
    return TodaySessionSummary(title: title, detail: parts.joined(separator: " · "), percent: percent)
  }

  private var proteinToday: Double {
    foodEntries.filter { !$0.tombstoned && Calendar.current.isDateInToday($0.date) }
      .reduce(0) { $0 + $1.proteinG }
  }

  private var earlyDeloadCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        CoachAvatar(size: 28)
        Text("Two red days in a row").forgeSection()
        Spacer()
      }
      Text(
        "Fatigue has been in the red two days running. I'm moving your deload up: half the sets, RPE ≤ 6 for the next \(profile?.daysPerWeek ?? 3) sessions, then a fresh block."
      ).forgeBody()
      HStack(spacing: 8) {
        Button("Start deload now") { withAnimation(.snappy) { profile?.deloadStartedAt = .now } }
          .buttonStyle(PillButtonStyle(minHeight: 44))
        Button("Keep the plan") { withAnimation(.snappy) { deloadDismissedDay = todayKey } }
          .buttonStyle(PillSecondaryButtonStyle())
          .frame(maxWidth: 150)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .todayCard(tint: Theme.negative.opacity(0.06))
  }

  private var weekReviewCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        CoachAvatar(size: 28)
        Text("Week \(finishedWeek) review").forgeSection()
        Spacer()
        Button {
          weekReviewDismissed = finishedWeek
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityLabel("Dismiss week review")
      }
      if let review = weeklyReview {
        Text(WeeklyReviewBuilder.headline(review, usesLb: usesLb)).forgeBodyStrong()
        if let voice = reviewVoice {
          Text(voice).forgeLabel()
        } else {
          ForEach(WeeklyReviewBuilder.lines(review, usesLb: usesLb), id: \.self) { line in
            Text(line).forgeLabel()
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .todayCard()
    .task(id: finishedWeek) { await loadReviewVoice() }
  }

  private var changesSheet: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if !weekBrief.isEmpty {
            Text(String(localized: "Your next week", bundle: L10n.bundle)).forgeSection()
            ForEach(weekBrief.statements) { statement in
              VStack(alignment: .leading, spacing: 2) {
                Text(statement.kind.label).forgeLabel()
                  .foregroundStyle(Theme.textSecondary)
                Text(statement.text).forgeBody()
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          if let day = effectiveDay ?? plannedDay {
            let facts = coachCallFacts(day)
            Text(weekCaption(day, sessionMinutes: facts.sessionMinutes)).forgeCaption()
            if facts.firstSession {
              Text(
                String(
                  localized:
                    "First session. Your loads come from your numbers. Log RPE honestly and I tune every lift from here.",
                  bundle: L10n.bundle)
              ).forgeLabel()
            } else {
              ForEach(facts.all) { a in
                if let decision = a.decision {
                  decisionCard(a, decision) { explainingInChanges = $0 }
                }
              }
              ForEach(facts.volumes) { v in
                adjustmentRow(
                  symbol: "square.stack.3d.up.fill",
                  tint: v.delta > 0 ? Theme.positive : Theme.negative,
                  title: v.title,
                  detail: v.detail)
              }
              if facts.all.isEmpty && facts.volumes.isEmpty {
                Text(
                  String(
                    localized: "Everything repeats. Hit the same numbers cleaner.",
                    bundle: L10n.bundle)
                ).forgeLabel()
              }
            }
          }
        }
        .padding(16)
      }
      .navigationTitle(String(localized: "\(coach.name)'s adjustments", bundle: L10n.bundle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: "Done", bundle: L10n.bundle)) { showChanges = false }
        }
      }
      .sheet(item: $explainingInChanges) { a in
        AdjustmentExplainSheet(
          adjustment: a,
          coach: coach,
          profile: profile,
          sessions: sessions,
          checkIns: checkIns,
          usesLb: usesLb,
          week: week)
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func weekCaption(_ day: PlannedDay, sessionMinutes: Int) -> String {
    weekLine(week: week, earlyDeload: profile?.deloadStartedAt != nil)
      + (day.trimmedSets > 0
        ? String(
          localized: " · \(day.trimmedSets) sets cut to fit \(sessionMinutes) min",
          bundle: L10n.bundle) : "")
      + (profile?.recoveryReduced == true
        ? String(
          localized: " · recovery-limited: about 15 % fewer weekly sets",
          bundle: L10n.bundle) : "")
  }

  private struct CoachCallFacts {
    let all: [Adjustment]
    let volumes: [VolumeNote]
    let firstSession: Bool
    let changeCount: Int
    let changeText: String
    let sessionMinutes: Int
  }

  private func coachCallFacts(_ day: PlannedDay) -> CoachCallFacts {
    let all = adjustments(
      for: day, base: baseDay, sessions: sessions, profile: profile, usesLb: usesLb,
      readiness: readinessScore, soreMuscles: soreMuscles)
    let volumes = volumeNotes(volumeDelta, day: day, soreMuscles: soreMuscles)
    let firstSession = !sessions.contains(where: { $0.completed })
    let changeCount =
      all.filter { a in
        guard let decision = a.decision, a.kind != .repeatLoad else { return false }
        if case .holdLoad = decision.action { return false }
        return true
      }.count + volumes.count
    // The reduced-sets note quotes the duration actually in play, including a picked time box.
    let sessionMinutes = timeBox ?? profile?.sessionMinutes ?? 60
    let changeText: String
    if firstSession {
      changeText = String(localized: "First session", bundle: L10n.bundle)
    } else if changeCount == 0 {
      changeText = String(localized: "No changes", bundle: L10n.bundle)
    } else if changeCount == 1 {
      changeText = String(localized: "1 change", bundle: L10n.bundle)
    } else {
      changeText = String(localized: "\(changeCount) changes", bundle: L10n.bundle)
    }
    return CoachCallFacts(
      all: all, volumes: volumes, firstSession: firstSession, changeCount: changeCount,
      changeText: changeText, sessionMinutes: sessionMinutes)
  }

  private func coachCall(_ day: PlannedDay) -> some View {
    let facts = coachCallFacts(day)
    let _ = overrideTick
    let featured = facts.all.first { a in
      guard let decision = a.decision, decision.overridable, a.kind != .repeatLoad else { return false }
      if case .holdLoad = decision.action { return false }
      return true
    }
    let decision = featured.flatMap { a in a.decision.map { coachCallDecision(a, $0) } }
    let note: String?
    if facts.firstSession {
      note = String(
        localized:
          "First session. Your loads come from your numbers. Log RPE honestly and I tune every lift from here.",
        bundle: L10n.bundle)
    } else if doneToday == nil {
      note = coachLine
    } else if featured == nil {
      note = weekCaption(day, sessionMinutes: facts.sessionMinutes)
    } else {
      note = nil
    }
    return CoachCallCard(
      coachName: coach.name,
      changesText: facts.firstSession ? nil : facts.changeText,
      note: note,
      decision: decision,
      onChanges: { showChanges = true },
      onSelect: { override in
        guard let featured else { return }
        DecisionOverrides.set(override, for: featured.exercise.id)
        Analytics.track("decision_override", ["override": override.rawValue])
        overrideTick += 1
      },
      onWhy: { explaining = featured })
      .id("adjustments")
  }

  private func coachCallDecision(_ a: Adjustment, _ decision: Decision) -> CoachCallDecision {
    let badge: String?
    let badgeTint: Color
    switch a.kind {
    case .firstTime:
      badge = String(localized: "First time", bundle: L10n.bundle)
      badgeTint = Theme.metricEffort
    case .newVariant:
      badge = String(localized: "New variant", bundle: L10n.bundle)
      badgeTint = Theme.accent
    default:
      badge = nil
      badgeTint = Theme.accent
    }
    let value: String
    if case .firstTime(let kg) = decision.action {
      value = String(localized: "starts at \(weightFormatter(a.exercise)(kg))", bundle: L10n.bundle)
    } else {
      value = decision.shortValue(weight: weightFormatter(a.exercise))
    }
    let whyTitle: String
    switch decision.action {
    case .increaseLoad, .decreaseLoad, .holdLoad, .addReps, .firstTime:
      whyTitle = String(localized: "Why this weight?", bundle: L10n.bundle)
    default:
      whyTitle = String(localized: "Why this change?", bundle: L10n.bundle)
    }
    return CoachCallDecision(
      exercise: a.exercise,
      badge: badge,
      badgeTint: badgeTint,
      value: value,
      valueTint: a.kind == .firstTime ? Theme.textSecondary : a.tint,
      reason: a.kind == .firstTime ? nil : decision.reason,
      overridable: decision.overridable,
      selection: DecisionOverrides.get(a.exercise.id) ?? .keepOriginal,
      whyTitle: whyTitle)
  }

  @MainActor
  private func loadReviewVoice() async {
    reviewVoice = nil
    guard let review = weeklyReview else { return }
    let lines = WeeklyReviewBuilder.lines(review, usesLb: usesLb)
    guard !lines.isEmpty else { return }
    do {
      let text = try await CoachAPI.review(
        headline: WeeklyReviewBuilder.headline(review, usesLb: usesLb),
        lines: lines,
        coach: coach.name)
      let needed = numbers(in: lines.joined(separator: " "))
      if !needed.isEmpty && needed.allSatisfy({ text.contains($0) }) {
        reviewVoice = text
      }
    } catch {
      // keep the deterministic lines
    }
  }

  private func numbers(in text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: #"\d[\d,.]*%?"#) else { return [] }
    let ns = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
      .map { ns.substring(with: $0.range) }
  }

  private func decisionCard(
    _ a: Adjustment, _ decision: Decision, onWhy: @escaping (Adjustment) -> Void
  ) -> some View {
    let open = expandedAdjustment == a.exercise.id
    return VStack(alignment: .leading, spacing: open ? 8 : 0) {
      Button {
        withAnimation(.snappy) { expandedAdjustment = open ? "" : a.exercise.id }
      } label: {
        HStack(spacing: 8) {
          Text(a.exercise.localizedName).forgeBodyStrong()
          Spacer(minLength: 8)
          Text(decision.shortValue(weight: weightFormatter(a.exercise)))
            .forge(13, .semibold)
            .monospacedDigit()
            .foregroundStyle(a.tint)
          Image(systemName: open ? "chevron.up" : "chevron.down")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.textTertiary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      if open {
        decisionDetail(a, decision, onWhy: onWhy)
      }
    }
    .innerSurface(padding: 10)
  }

  @ViewBuilder
  private func decisionDetail(
    _ a: Adjustment, _ decision: Decision, onWhy: @escaping (Adjustment) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(decision.reason)
        .forgeLabel()
        .monospacedDigit()
      HStack(spacing: 8) {
        if decision.overridable {
          ForEach(DecisionOverride.allCases, id: \.self) { o in
            let selected = DecisionOverrides.get(a.exercise.id) == o
            Button {
              let next: DecisionOverride? = selected ? nil : o
              DecisionOverrides.set(next, for: a.exercise.id)
              Analytics.track("decision_override", ["override": next?.rawValue ?? "clear"])
              overrideTick += 1
            } label: {
              Text(o.title)
                .forge(11, .semibold)
                .foregroundStyle(selected ? Theme.onAccent : Theme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Theme.accent : Theme.innerSurface))
            }
            .buttonStyle(RowPressStyle())
          }
        }
        Button("Why?") {
          onWhy(a)
        }
        .foregroundStyle(Theme.accent)
        .forge(12, .semibold)
      }
    }
  }

  private func adjustmentRow(symbol: String, tint: Color, title: String, detail: String)
    -> some View
  {
    HStack(spacing: 10) {
      ZStack {
        Circle().fill(tint.opacity(0.12))
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(tint)
      }
      .frame(width: 28, height: 28)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).forgeBodyStrong()
        Text(detail).forgeLabel().monospacedDigit()
      }
      Spacer()
    }
    .innerSurface(padding: 10)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(title), \(detail)")
  }

  private var logFoodRow: some View {
    LogFoodRow(
      detail: nutritionProfiles.first.flatMap { profile in
        let target = profile.proteinG
        guard target > 0 else { return nil }
        return String(
          localized: "\(Fmt.grouped(proteinToday)) of \(target) g protein today",
          bundle: L10n.bundle)
      }
    ) { logFoodMeal = Meal.current }
  }

  @ViewBuilder
  private func accessoryBar(_ day: PlannedDay) -> some View {
    if let open = openSession {
      StartAccessoryBar(
        title: localizedDayName(open.dayName),
        subtitle: String(localized: "≈ \(planEstimate(day)) min", bundle: L10n.bundle),
        actionTitle: String(localized: "Resume", bundle: L10n.bundle)
      ) {
        active = resumeWorkout(for: open, fallback: day)
      }
    } else if fatigue == nil && doneToday == nil {
      StartAccessoryBar(
        title: localizedDayName(day.name),
        subtitle: String(localized: "≈ \(planEstimate(day)) min", bundle: L10n.bundle),
        actionTitle: String(localized: "Check in", bundle: L10n.bundle)
      ) {
        showCheckIn = true
      }
    } else if !(isForceRest && !trainAnyway)
      && !(doneToday != nil || planStatus?.owedIsToday == false)
    {
      StartAccessoryBar(
        title: localizedDayName(day.name),
        subtitle: String(localized: "≈ \(planEstimate(day)) min", bundle: L10n.bundle),
        actionTitle: String(localized: "Start", bundle: L10n.bundle)
      ) {
        beginWorkout(effectiveDay ?? day)
      }
    }
  }

  private func planEstimate(_ day: PlannedDay) -> Int {
    TimeBudget.estimatedMinutes(day)
  }

  private func lightDay(_ day: PlannedDay) -> PlannedDay {
    PlannedDay(
      name: day.name,
      exercises: day.exercises.map {
        PlannedExercise(
          exercise: $0.exercise, sets: max(1, Int((Double($0.sets) * 0.7).rounded())),
          repRange: $0.repRange, targetRPE: min($0.targetRPE, 7))
      }, trimmedSets: day.trimmedSets)
  }

  private func beginWorkout(_ day: PlannedDay) {
    writeDecisionLedger(day)
    if forceLight {
      forceLight = false
      activeAction = .lightSession(volumeMultiplier: 0.7, rpeCap: 7)
      active = ActiveWorkout(day: lightDay(day), planDayID: planDayID(for: day))
    } else {
      activeAction = fatigue?.action ?? .proceed
      active = ActiveWorkout(day: day, planDayID: planDayID(for: day))
    }
  }

  /// The accepted plan day this session satisfies, while the plan still owes it. Only days
  /// the plan has not already settled are ever offered, so finishing can never rewrite a
  /// completed, moved or skipped day.
  private func planDayID(for day: PlannedDay) -> String? {
    guard let status = planStatus, let owed = status.owed,
      owed.plannedSessionID == day.name,
      owed.state == .planned || owed.state == .remaining
    else { return nil }
    return owed.id
  }

  private func resumeWorkout(for open: WorkoutSession, fallback: PlannedDay) -> ActiveWorkout {
    let day = resumeDay(for: open, fallback: fallback)
    return ActiveWorkout(day: day, resume: open,
      planDayID: open.plannedDayID.isEmpty ? nil : open.plannedDayID)
  }

  /// Writes one DecisionLogEntry per adjustment with a decision, once per workout start.
  /// The WorkoutSession itself is created in WorkoutView.setup; this runs on the start action,
  /// not on render, so it fires exactly once per start.
  private func writeDecisionLedger(_ day: PlannedDay) {
    let records = adjustments(
      for: day, base: baseDay, sessions: sessions, profile: profile, usesLb: usesLb,
      readiness: readinessScore, soreMuscles: soreMuscles
    )
    .compactMap { a -> DecisionRecord? in
      guard let decision = a.decision else { return nil }
      return DecisionRecord.from(
        decision, date: .now, name: a.exercise.localizedName, weight: weightFormatter(a.exercise))
    }
    // The engine still decides every load; the trace only commits what it decided, once.
    // Starting the same planned day twice — a second tap, a resumed session after a crash —
    // recomputes the same fingerprint, so one change is never explained twice.
    DecisionTrace.commit(
      records: records,
      sessionKey: "\(planDayID(for: day))#\(todayKey)",
      context: modelContext)
  }

  private func weightFormatter(_ exercise: Exercise) -> (Double) -> String {
    let lb = profile?.isLb(for: exercise.id) ?? usesLb
    return { kg in
      let v = lb ? Plates.kgToLb(kg) : kg
      return Fmt.kg(v, lb: lb)
    }
  }

  @ViewBuilder private var recordCard: some View {
    if bestE1RM != nil {
      RecordCard(label: bestE1RMLabel, value: bestE1RMNumber, unit: unit) { selection = 2 }
    }
  }

  /// The best analysis-eligible estimate of all time, so the tile can name its lift.
  private var bestE1RM: TrainingMetrics.LiftEstimate? {
    TrainingMetrics.bestEstimate(
      sessions.metricSets(), scope: .analysisEligible, in: nil, exerciseID: nil)
  }

  private var bestE1RMNumber: String {
    guard let best = bestE1RM else { return "—" }
    let value = usesLb ? Plates.kgToLb(best.e1RM) : best.e1RM
    return "\(Int(value.rounded()))"
  }

  /// Names the lift the estimate belongs to; the plain label when nothing qualifies yet.
  private var bestE1RMLabel: String {
    guard
      let estimate = bestE1RM,
      let name = ExerciseDB.find(estimate.exerciseID)?.localizedName
    else {
      return String(localized: "Best e1RM · analysis eligible", bundle: L10n.bundle)
    }
    return String(localized: "\(name) · best e1RM", bundle: L10n.bundle)
  }

  private var streakWeeks: Int {
    let cal = TrainingMetrics.reportingCalendar()
    let thisWeek = TrainingMetrics.reportingWeek(containing: .now, calendar: cal).start
    let weeks = Set(
      sessions.filter(\.completed).map {
        TrainingMetrics.reportingWeek(containing: $0.date, calendar: cal).start
      })
    var streak = 0
    var week = thisWeek
    while weeks.contains(week) {
      streak += 1
      week = cal.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
    }
    return streak
  }

  private var weekSets: Int {
    TrainingMetrics.sets(sessions.metricSets(), in: reportingWeek, scope: .allRecorded).count
  }

  /// This week's planned working sets, summed the way the roadmap sums a week row.
  private var weekTarget: Int {
    if let plan = profile?.weekPlan {
      return plan.days.filter { TrainingMetrics.contains(reportingWeek, $0.date) }
        .reduce(0) { $0 + $1.plannedSetCount }
    }
    guard let profile else {
      let length = SessionLength.m60
      return (profile?.daysPerWeek ?? 0) * Program.setBudget(for: length)
    }
    let plan = Program.week(week, profile: profile.profileInput)
    return plan.flatMap(\.exercises).reduce(0) { $0 + $1.sets }
  }

  private var checkedInToday: Bool {
    checkIns.contains { Calendar.current.isDateInToday($0.date) }
  }

  private func writeSnapshot() {
    WidgetBridgeWriter.write(
      day: plannedDay, streakWeeks: streakWeeks, weekSets: weekSets, weekTarget: weekTarget,
      checkedIn: checkedInToday)
  }

  private var checkInSheet: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.groupGap) {
        Text("Daily check-in").forgeTitle()
        Text("Fifteen seconds. Sleep and soreness set today's plan.").forgeLabel()
        if !Health.isAuthorized {
          Text(
            "Regulift reads sleep and resting heart rate from Health to score readiness. Optional."
          )
          .forgeLabel()
        }
        pickerRow(String(localized: "Sleep", bundle: L10n.bundle), $sleepQuality)
        pickerRow(String(localized: "Soreness", bundle: L10n.bundle), $soreness)
        pickerRow(String(localized: "Energy", bundle: L10n.bundle), $energy)
        pickerRow(String(localized: "Motivation", bundle: L10n.bundle), $motivation)
        VStack(spacing: 10) {
          Text("Slept").forgeLabel().foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
          HStack {
            sleepButton("minus") { sleepHours = max(0, sleepHours - 0.5) }
            Spacer()
            MetricValue(value: Fmt.num(sleepHours), unit: "hours", size: 56)
            Spacer()
            sleepButton("plus") { sleepHours = min(12, sleepHours + 0.5) }
          }
          Text(
            sleepPrefilled && Health.isAuthorized
              ? String(localized: "From Health · edit if wrong", bundle: L10n.bundle)
              : String(localized: "Tap − / + to set", bundle: L10n.bundle)
          ).forgeCaption()
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slept \(Fmt.num(sleepHours)) hours")
        .accessibilityAdjustableAction { direction in
          switch direction {
          case .increment: sleepHours = min(12, sleepHours + 0.5)
          case .decrement: sleepHours = max(0, sleepHours - 0.5)
          @unknown default: break
          }
        }
        VStack(alignment: .leading, spacing: 8) {
          Text("Sore muscles").forgeBodyStrong()
          MuscleMapView(intensity: [:], selected: soreMuscles, onTap: toggleSore)
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(soreMusclesA11yLabel)
            .accessibilityActions {
              ForEach(Muscle.allCases, id: \.self) { muscle in
                Button(
                  soreMuscles.contains(muscle)
                    ? "Clear \(muscle.a11yName)" : "Mark \(muscle.a11yName) sore"
                ) {
                  toggleSore(muscle)
                }
              }
            }
          Text("Tap what's sore").forgeCaption()
        }
        .innerSurface()
        Button("Save check-in") {
          let checkIn = CheckIn(
            date: .now,
            sleep: sleepQuality,
            soreness: soreness,
            energy: energy,
            sleepHours: sleepHours)
          checkIn.motivation = motivation
          checkIn.soreMuscles = soreMuscles.map(\.rawValue)
          modelContext.insert(checkIn)
          try? modelContext.save()
          savedCheckInCount += 1
          Analytics.track("checkin_saved")
          motivation = 3
          soreMuscles.removeAll()
          showCheckIn = false
          writeSnapshot()
        }
        .buttonStyle(PillButtonStyle())
      }
      .padding(Theme.margin)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Theme.page)
    .presentationDetents([.large])
    .presentationBackground(Theme.page)
    .task {
      guard !sleepPrefilled else { return }
      sleepPrefilled = true
      await Health.requestAuthorization()
      if let hours = await Health.lastNightSleepHours() {
        sleepHours = min(12, max(0, (hours * 2).rounded() / 2))
      }
      healthBaseline = await Health.averageSleepHours()
      cardio = await Health.cardioSignals()
    }
  }

  private func sleepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(Theme.onAccent)
        .frame(width: 44, height: 44)
        .background(Circle().fill(Theme.accent))
    }
    .buttonStyle(RowPressStyle())
  }

  private func toggleSore(_ muscle: Muscle) {
    withAnimation(.snappy) {
      if soreMuscles.contains(muscle) {
        soreMuscles.remove(muscle)
      } else {
        soreMuscles.insert(muscle)
      }
    }
  }

  private var soreMusclesA11yLabel: String {
    let sore = Muscle.allCases.filter(soreMuscles.contains).map(\.a11yName)
    return sore.isEmpty
      ? String(localized: "No sore muscles", bundle: L10n.bundle)
      : String(localized: "Sore muscles: ", bundle: L10n.bundle) + sore.joined(separator: ", ")
  }

  private func pickerRow(_ label: String, _ value: Binding<Int>) -> some View {
    HStack {
      Text(label).forgeBodyStrong()
      Spacer()
      Picker(label, selection: value) {
        ForEach(1...5, id: \.self) { Text("\($0)").forge(13, .medium).tag($0) }
      }
      .pickerStyle(.segmented)
      .frame(width: 200)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(Capsule().fill(Theme.innerSurface))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue("\(value.wrappedValue) of 5")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: value.wrappedValue = min(5, value.wrappedValue + 1)
      case .decrement: value.wrappedValue = max(1, value.wrappedValue - 1)
      @unknown default: break
      }
    }
  }

  private func planCard(_ day: PlannedDay) -> some View {
    let rotatedIn = Set(day.exercises.map(\.exercise.id)).subtracting(
      Set(baseDay?.exercises.map(\.exercise.id) ?? []))
    let goingUp = Set(
      adjustments(for: day, base: baseDay, sessions: sessions, profile: profile, usesLb: usesLb)
        .filter { $0.kind == .increase }
        .map(\.exercise.id))
    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Today's plan").forgeSection()
        Spacer()
        Text("≈ \(planEstimate(day)) min")
          .forgeLabel()
          .monospacedDigit()
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(TimeBudget.options, id: \.self) { minutes in
            let selected = timeBox == minutes
            Button {
              if selected {
                timeBox = nil
              } else {
                timeBox = minutes
                Analytics.track("time_box", ["minutes": "\(minutes)"])
              }
            } label: {
              Text("\(minutes) min")
                .forge(13, .semibold)
                .monospacedDigit()
                .foregroundStyle(selected ? Theme.onAccent : Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(selected ? Theme.accent : Theme.innerSurface))
            }
            .buttonStyle(RowPressStyle())
          }
        }
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: 10) {
          ForEach(Array(day.exercises.enumerated()), id: \.element.exercise.id) { index, planned in
            PlanArtCard(
              exercise: planned.exercise, goesUp: goingUp.contains(planned.exercise.id),
              isNew: rotatedIn.contains(planned.exercise.id), index: index, appeared: appeared)
          }
        }
        .padding(.horizontal, 16)
      }
      .padding(.horizontal, -16)
    }
  }

  @ViewBuilder private var bottomBar: some View {
    if let day = plannedDay {
      if primaryOffscreen {
        accessoryBar(day)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .padding(.bottom, 6)
      }
    } else if let status = planStatus {
      // The accepted plan owes nothing here, so say that instead of offering a session
      // the lifter never planned.
      HStack(spacing: 8) {
        if status.evaluation.counts.scheduled > 0 {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.positive)
        } else {
          Image(systemName: "calendar")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
        }
        Text(WeekPlanTodayStatus.countsLine(status.evaluation.counts)).forgeLabel()
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Theme.barMargin)
      .padding(.vertical, 14)
      .frame(minHeight: 44)
      .background(.regularMaterial)
      .accessibilityElement(children: .combine)
    }
  }
}

struct ActiveWorkout: Identifiable {
  let day: PlannedDay
  var resume: WorkoutSession? = nil
  /// The accepted plan day this session is for, when Today decided one. Carried into the
  /// logger so finishing records the day instead of guessing which session it was.
  var planDayID: String? = nil
  var id: String { resume == nil ? day.name : day.name + "#resume" }
}

func fatigueNow(
  profile: UserProfile?, sessions: [WorkoutSession], checkIns: [CheckIn],
  healthBaseline: Double? = nil,
  cardio: (hrv: Double?, hrvBaseline: Double?, rhr: Double?, rhrBaseline: Double?)? = nil,
  now: Date = .now
) -> (score: Int, action: FatigueAction)? {
  guard let ci = checkIns.last(where: { Calendar.current.isDate($0.date, inSameDayAs: now) }),
    profile != nil
  else { return nil }
  func volume(_ windowDays: Double) -> Double {
    sessions
      .filter { $0.completed && now.timeIntervalSince($0.date) < windowDays * 86400 }
      .reduce(0) { total, session in
        total
          + session.sets.reduce(0) { t, set in
            guard let exercise = ExerciseDB.find(set.exerciseID) else { return t }
            let credit = Volume.credit(
              for: SetLog(
        weightKg: set.weightKg, reps: set.reps, rpe: set.rpe,
        effortReported: set.effortReported),
      exercise: exercise)
            return t + credit.values.reduce(0, +)
          }
      }
  }
  let recentCheckIns = checkIns.filter { now.timeIntervalSince($0.date) < 7 * 86400 }
  let checkinBaseline =
    recentCheckIns.isEmpty
    ? 7.0
    : recentCheckIns.reduce(0.0) { $0 + $1.sleepHours } / Double(recentCheckIns.count)
  let baseline = healthBaseline ?? checkinBaseline
  let completed7 = sessions.filter { $0.completed && now.timeIntervalSince($0.date) < 7 * 86400 }
  let missed = completed7.filter { session in
    session.sets.contains { $0.effortReported && $0.rpe > $0.targetRPE + 1 }
  }.count
  // ponytail: <4 weeks of logged history scales the chronic window; PRD assumes a full 28 days
  let first = sessions.filter(\.completed).map(\.date).min() ?? now
  let historyWeeks = min(4.0, max(1.0, ceil(now.timeIntervalSince(first) / (7 * 86400))))
  let score = Fatigue.score(
    FatigueInputs(
      acuteVolume7d: volume(7),
      avgWeeklyVolume28d: volume(28) / historyWeeks,
      soreness: ci.soreness,
      sleepHoursLastNight: ci.sleepHours,
      sleepBaseline7d: baseline,
      sessionsLast7d: completed7.count,
      missedRPESessionsLast7d: missed,
      hrvLastNight: cardio?.hrv,
      hrvBaseline7d: cardio?.hrvBaseline,
      restingHRLastNight: cardio?.rhr,
      restingHRBaseline7d: cardio?.rhrBaseline))
  return (score, Fatigue.action(forScore: score, sleepHoursLastNight: ci.sleepHours))
}

// MARK: - Accepted week plan on Today

/// The accepted week plan's view of today, resolved once so the whole tab — the hero, the
/// plan card and the week status — reads the same numbers. `owed` is the session the lifter
/// is being pointed at: today's own day while it still owes work, otherwise the next
/// remaining planned day, chosen by `plannedSessionID`. Nothing derived is ever written back.
struct WeekPlanTodayStatus {
  let plan: WeekPlan
  let evaluation: WeekPlanEvaluation
  /// Today's own row, whether or not it still owes work.
  let today: WeekPlanDay?
  let todayEvaluation: WeekPlanDayEvaluation?
  /// The session still owed: today's while it does, otherwise the next remaining one.
  let owed: WeekPlanDay?
  let owedEvaluation: WeekPlanDayEvaluation?
  let owedIsToday: Bool

  init(plan: WeekPlan, now: Date, base: Calendar = .current) {
    let calendar = plan.resolvedCalendar(base)
    let evaluation = WeekPlanStatusPolicy.evaluation(plan: plan, now: now, calendar: calendar)
    self.plan = plan
    self.evaluation = evaluation

    let today = plan.days.first { calendar.isDate($0.date, inSameDayAs: now) }
    self.today = today
    self.todayEvaluation = today.flatMap { day in evaluation.day(day.id) }

    // `remaining` is the policy's word for "still owed". Days it has already settled —
    // completed, moved, skipped — are never offered as something to start.
    let owedRows = evaluation.days
      .filter { $0.state == .remaining && $0.plannedSessionID != nil }
      .sorted { $0.date < $1.date }
    let chosen = owedRows.first { calendar.isDate($0.date, inSameDayAs: now) } ?? owedRows.first
    self.owedEvaluation = chosen
    self.owed = chosen.flatMap { row in plan.days.first { $0.id == row.dayID } }
    self.owedIsToday = chosen.map { calendar.isDate($0.date, inSameDayAs: now) } ?? false
  }

  /// The row the card describes: what is still owed, else today's own row when the plan
  /// has nothing left for it.
  var focus: (day: WeekPlanDay, evaluation: WeekPlanDayEvaluation)? {
    if let owed = owed, let owedEvaluation = owedEvaluation { return (owed, owedEvaluation) }
    if let today = today, let todayEvaluation = todayEvaluation { return (today, todayEvaluation) }
    return nil
  }

  /// The one-line status the lifter reads, with the symbol and tint that carry it.
  static func statusPresentation(_ row: WeekPlanDayEvaluation)
    -> (symbol: String, tint: Color, text: String)
  {
    switch row.state {
    case .completed:
      return (
        "checkmark.circle.fill", Theme.positive, String(localized: "Completed", bundle: L10n.bundle)
      )
    case .skipped:
      return row.reason == .beforeEnrollment
        ? (
          "minus.circle", Theme.textTertiary,
          String(localized: "Before your plan started", bundle: L10n.bundle)
        )
        : (
          "minus.circle", Theme.textSecondary,
          String(localized: "Skipped by you", bundle: L10n.bundle)
        )
    case .moved:
      return row.reason == .beforeEnrollment
        ? (
          "minus.circle", Theme.textTertiary,
          String(localized: "Before your plan started", bundle: L10n.bundle)
        )
        : (
          "arrow.left.arrow.right.circle.fill", Theme.metricTime,
          String(localized: "Moved to another day", bundle: L10n.bundle)
        )
    case .missed:
      return (
        "exclamationmark.circle.fill", Theme.negative,
        String(localized: "Missed · the grace window closed", bundle: L10n.bundle)
      )
    case .remaining:
      switch row.reason {
      case .dueToday:
        return ("circle.dashed", Theme.accent, String(localized: "Due today", bundle: L10n.bundle))
      case .upcoming:
        return (
          "clock", Theme.textSecondary,
          String(localized: "Upcoming · \(dayText(row.date))", bundle: L10n.bundle)
        )
      case .withinGraceWindow:
        return (
          "clock.arrow.circlepath", Theme.metricEffort,
          String(
            localized: "Still open · grace until \(timeText(row.deadline))", bundle: L10n.bundle)
        )
      default:
        return ("clock", Theme.textSecondary, String(localized: "Still owed", bundle: L10n.bundle))
      }
    case .planned:
      return ("circle.dashed", Theme.accent, String(localized: "Planned", bundle: L10n.bundle))
    }
  }

  static func dayText(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(L10n.locale))
  }

  static func timeText(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).hour().minute().locale(L10n.locale))
  }

  static func countsLine(_ counts: WeekPlanCounts) -> String {
    // 0 of 0 is not an achievement. A week with nothing scheduled says so instead of
    // rendering a completed meter, which is what made an empty plan look finished.
    guard counts.scheduled > 0 else {
      return String(localized: "No sessions scheduled this week", bundle: L10n.bundle)
    }
    var parts = [
      String(
        localized: "\(counts.completed) of \(counts.scheduled) planned sessions done",
        bundle: L10n.bundle)
    ]
    if counts.remaining > 0 {
      parts.append(String(localized: "\(counts.remaining) still owed", bundle: L10n.bundle))
    }
    if counts.missed > 0 {
      parts.append(String(localized: "\(counts.missed) missed", bundle: L10n.bundle))
    }
    if counts.moved > 0 {
      parts.append(String(localized: "\(counts.moved) moved", bundle: L10n.bundle))
    }
    if counts.skipped > 0 {
      parts.append(String(localized: "\(counts.skipped) skipped", bundle: L10n.bundle))
    }
    return parts.joined(separator: " · ")
  }
}

/// When a finished session has actually done the work its plan day asked for.
///
/// The day is only marked completed for work the lifter did: everything the session asked
/// for, never more than the plan called for — so a session the app itself trimmed still
/// satisfies its day, while an early partial finish stays recorded as a session but leaves
/// the day owed. The one exception is the app's minimum-effective semantics: when the week
/// was authored as minimum effective and the reduced session still reached the capped
/// working-set budget the constraint engine grants for that mode.
enum WeekPlanCompletionPolicy {
  /// The app's minimum-effective working-set budget: at most the eight sets the
  /// "Minimum effective workout" constraint allows, and never more than the session asked for.
  static func minimumEffectiveSets(scheduledSets: Int, timeBudgetMinutes: Int) -> Int {
    min(
      scheduledSets,
      TrainingConstraintEngine.setBudget(minutes: timeBudgetMinutes, minimumEffective: true))
  }

  /// The bar the finished session has to clear: what the session asked for, capped by what
  /// the plan called for.
  static func requiredSets(plannedSetCount: Int, scheduledSets: Int) -> Int {
    min(plannedSetCount, scheduledSets)
  }

  static func satisfies(
    plannedSetCount: Int,
    scheduledSets: Int,
    loggedSetCount: Int,
    mode: WeekPlanMode,
    timeBudgetMinutes: Int
  ) -> Bool {
    let required = requiredSets(plannedSetCount: plannedSetCount, scheduledSets: scheduledSets)
    guard required > 0 else { return loggedSetCount > 0 }
    if loggedSetCount >= required { return true }
    guard mode == .minimumEffective else { return false }
    return loggedSetCount
      >= minimumEffectiveSets(scheduledSets: required, timeBudgetMinutes: timeBudgetMinutes)
  }

  /// Stable identity for a recorded session, so a plan day points at real evidence even
  /// before the session has synced. Local sessions are named by their start and day.
  static func sessionReference(_ session: WorkoutSession?) -> String {
    guard let session = session else { return "" }
    if !session.remoteID.isEmpty { return session.remoteID }
    return "local-\(Int(session.date.timeIntervalSince1970))-\(session.dayName)"
  }
}

/// Today's goal arithmetic, outside the view so it can be tested.
enum TodayGoal {
  /// The newest session finished on `now`'s day; open and deleted sessions never count.
  static func finishedToday(
    _ sessions: [WorkoutSession], now: Date = .now, calendar: Calendar = .current
  ) -> WorkoutSession? {
    sessions
      .filter { $0.completed && !$0.tombstoned && calendar.isDate($0.date, inSameDayAs: now) }
      .max { $0.date < $1.date }
  }

  /// Logged share of the planned sets in whole percent; nil when the plan is unknown.
  static func percent(logged: Int, planned: Int) -> Int? {
    guard planned > 0 else { return nil }
    return Int((Double(logged) / Double(planned) * 100).rounded())
  }

  /// Primary muscles in training order, each once.
  static func primaryMuscles(_ exerciseIDs: [String]) -> [Muscle] {
    var seen: Set<Muscle> = []
    return exerciseIDs.compactMap { ExerciseDB.find($0)?.primary }.filter {
      seen.insert($0).inserted
    }
  }

  static func list(_ muscles: [Muscle]) -> String {
    muscles.map(\.a11yName).formatted(.list(type: .and).locale(L10n.locale))
  }
}

// MARK: - Accepted plan card

extension TodayView {
  /// What the accepted plan chose, spelled out where the lifter decides whether to train.
  /// Only rendered when a plan was saved; without one, Today is the generated schedule.
  func acceptedPlanCard(_ status: WeekPlanTodayStatus, showsFocusName: Bool = true,
    showsReviewAction: Bool = true) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Text("This week's plan").forgeSection()
        Spacer(minLength: 8)
        Text(status.plan.mode.name)
          .forge(11, .semibold, tracking: 0.4)
          .foregroundStyle(Theme.textSecondary)
          .padding(.horizontal, 9)
          .padding(.vertical, 4)
          .background(Capsule().fill(Theme.innerSurface))
      }

      if let focus = status.focus {
        if showsFocusName {
          VStack(alignment: .leading, spacing: 3) {
            Text(localizedDayName(focus.day.sessionName)).forgeBodyStrong()
            Text(planFocusLine(status)).forgeCaption()
          }
        }
        planStatusRow(focus.evaluation)
        planContextRow(focus.day)
      } else {
        Text(
          "This plan covers no session around today. Its days are the ones you laid out in the week designer."
        )
        .forgeBody()
      }

      Text(WeekPlanTodayStatus.countsLine(status.evaluation.counts))
        .forgeCaption()
        .monospacedDigit()

      if showsReviewAction {
        Button("Review or regenerate the week") { showRoadmap = true }
          .buttonStyle(PillSecondaryButtonStyle())
          .frame(minHeight: 44)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .todayCard()
    .accessibilityElement(children: .combine)
    .accessibilityLabel(planA11yLabel(status))
  }

  private func planFocusLine(_ status: WeekPlanTodayStatus) -> String {
    guard status.owed != nil else {
      return String(localized: "Nothing left to do on this plan.", bundle: L10n.bundle)
    }
    guard !status.owedIsToday, let date = status.focus?.day.date else {
      return String(localized: "Today's session on your plan", bundle: L10n.bundle)
    }
    return String(localized: "Next up · \(WeekPlanTodayStatus.dayText(date))", bundle: L10n.bundle)
  }

  private func planStatusRow(_ evaluation: WeekPlanDayEvaluation) -> some View {
    let presentation = WeekPlanTodayStatus.statusPresentation(evaluation)
    return HStack(spacing: 8) {
      Image(systemName: presentation.symbol)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(presentation.tint)
      Text(presentation.text).forgeLabel()
      Spacer(minLength: 0)
    }
    .frame(minHeight: 20)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(presentation.text)
  }

  private func planContextRow(_ day: WeekPlanDay) -> some View {
    let gym = day.gymProfileName ?? String(localized: "No gym set", bundle: L10n.bundle)
    return HStack(spacing: 8) {
      Image(systemName: "building.2.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
      Text("\(gym) · \(day.timeBudgetMinutes) min · \(day.mode.name)")
        .forge(12, .medium)
        .foregroundStyle(Theme.textSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(gym), \(day.timeBudgetMinutes) minutes, \(day.mode.name)")
  }

  private func planA11yLabel(_ status: WeekPlanTodayStatus) -> String {
    var parts = [
      String(localized: "This week's plan, \(status.plan.mode.name)", bundle: L10n.bundle)
    ]
    if let focus = status.focus {
      parts.append(localizedDayName(focus.day.sessionName))
      parts.append(planFocusLine(status))
      parts.append(WeekPlanTodayStatus.statusPresentation(focus.evaluation).text)
      let gym = focus.day.gymProfileName ?? String(localized: "no gym set", bundle: L10n.bundle)
      parts.append(
        String(localized: "\(gym), \(focus.day.timeBudgetMinutes) minutes", bundle: L10n.bundle))
    }
    parts.append(WeekPlanTodayStatus.countsLine(status.evaluation.counts))
    return parts.joined(separator: ". ")
  }

  /// Shown when the accepted plan has nothing left to point at this week.
  ///
  /// Two different weeks used to share one card: a week whose sessions were all recorded,
  /// and a week that never had any. Calling an empty plan "nothing left" reads as praise for
  /// work that was never scheduled, so the empty case says what is actually true and offers
  /// the action that fixes it.
  func planRestCard(status: WeekPlanTodayStatus) -> some View {
    let isEmpty = status.evaluation.counts.scheduled == 0
    return VStack(alignment: .leading, spacing: 12) {
      Text(isEmpty ? "No sessions planned this week" : "Nothing left on this plan")
        .forgeSection()
      Text(
        isEmpty
          ? "This week has no sessions on it yet. Lay out the days you want in the week designer — nothing is scheduled until you do."
          : "Every session the plan asked for this week is either recorded or explicitly skipped. Regenerate the next week in the week designer when you're ready — nothing here changes on its own."
      )
      .forgeBody()
      Button(isEmpty ? "Plan this week" : "Open the week designer") { showRoadmap = true }
        .buttonStyle(PillButtonStyle(minHeight: 44))
        .accessibilityIdentifier(isEmpty ? "today.planWeek" : "today.openWeekDesigner")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .todayCard()
  }

  /// An unfinished session whose saved snapshot this app version cannot decode. Logged
  /// sets are kept and nothing is rewritten or discarded; no session starts until the
  /// data can be read again — never a generated fallback for a workout in progress.
  var unreadableSnapshotCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        CoachAvatar(size: 28)
        Text("Saved workout can't be read").forgeSection()
        Spacer()
      }
      Text(
        "A workout you started is saved in a format this version of Regulift can't read. Any sets you logged are kept. No workout will start until the saved data can be recovered in a compatible app version — nothing was changed or deleted."
      )
      .forgeBody()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .todayCard(tint: Theme.negative.opacity(0.06))
    .accessibilityElement(children: .combine)
  }

  /// An accepted week whose saved data this app version cannot decode. The week is
  /// real and retained — nothing was changed or deleted — so Today never claims no
  /// plan was configured and never offers regeneration as a workaround: no session
  /// starts until the week is readable again in a compatible version.
  var unreadableWeekCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        CoachAvatar(size: 28)
        Text("Saved week can't be read").forgeSection()
        Spacer()
      }
      Text(
        "Your accepted week is saved in a format this version of Regulift can't read. It has not been changed or deleted. No new session will start until the week is recovered in a compatible app version."
      )
      .forgeBody()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .todayCard(tint: Theme.negative.opacity(0.06))
    .accessibilityElement(children: .combine)
  }

  /// The owed day's applied routine after the training setup or program stage changed,
  /// when its saved application data cannot be read, or when the accepted plan synced a
  /// replaced day this device never applied — copied prescriptions stay device-local.
  /// Either way it is not startable — not canceled, not auto-approved, not logged. A
  /// readable local application starts again only after being picked and confirmed in
  /// the routine library; an unreadable one offers no action, because reapplying from
  /// the library cannot work; a day with no local record points at the Program roadmap,
  /// because this device's library has nothing to pick.
  func routineReviewCard(_ day: WeekPlanDay) -> some View {
    let planDataUnreadable =
      profile.map { RoutineAdaptationService.routineDataUnreadable($0) } ?? false
    // Same predicate needsReview branches on: a record for this day in this block
    // means the routine was applied here and the library is the fix; no record means
    // the replaced day synced from another device that held the prescription.
    let hasLocalAppliedRecord = profile.map { owner in
      owner.appliedRoutines.contains {
        $0.planDayID == day.id && $0.blockStart == owner.mesoStart
      }
    } ?? false
    return VStack(alignment: .leading, spacing: 12) {
      Text("Routine needs review").forgeSection()
      if planDataUnreadable {
        Text(
          "The saved data for \(localizedDayName(day.sessionName)) can't be read in this version, so it can't start here. Nothing was changed or deleted — update Regulift or reopen this plan in a compatible version."
        )
        .forgeBody()
      } else if hasLocalAppliedRecord {
        Text(
          "Something changed since \(localizedDayName(day.sessionName)) was applied — your accepted answers, equipment, constraints, program week or volume. Pick it again in the routine library to preview it against today's setup; it starts only once you confirm."
        )
        .forgeBody()
        Button("Review \(localizedDayName(day.sessionName))") { showRoadmap = true }
          .buttonStyle(PillButtonStyle(minHeight: 44))
          .accessibilityIdentifier("today.reviewRoutine")
      } else {
        Text(
          "This device can't reproduce \(localizedDayName(day.sessionName)) from your accepted plan. The routine may have been adapted elsewhere, or your training setup may have changed. Import the shared routine or regenerate the week; nothing has started or been deleted."
        )
        .forgeBody()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .todayCard()
  }
}

private struct AdjustmentExplainSheet: View {
  let adjustment: Adjustment
  let coach: Coach
  let profile: UserProfile?
  let sessions: [WorkoutSession]
  let checkIns: [CheckIn]
  let usesLb: Bool
  let week: Int

  @State private var answer: String?
  @State private var onDevice = true
  @State private var failed = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.groupGap) {
        Text(adjustment.exercise.localizedName).forgeTitle()
        Text(adjustment.detail).forgeLabel().monospacedDigit()
        if let answer {
          Text(answer).forgeBody()
          Text(
            onDevice
              ? String(localized: "On this iPhone", bundle: L10n.bundle)
              : String(localized: "\(coach.name) via Regulift coach", bundle: L10n.bundle)
          ).forgeCaption()
        } else if failed {
          Text("Couldn't explain right now.").forgeBody()
        } else {
          HStack(spacing: 10) {
            ProgressView()
            Text("Thinking…").forgeLabel()
          }
        }
      }
      .padding(Theme.margin)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Theme.page)
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.page)
    .task { await explain() }
  }

  private func explain() async {
    if OnDeviceCoach.isAvailable {
      if let text = await OnDeviceCoach.explain(
        adjustment,
        coachName: coach.name,
        week: week,
        lastSets: lastSets(adjustment.exercise.id, in: sessions),
        usesLb: usesLb)
      {
        Analytics.track("adjustment_explained", ["source": "device"])
        answer = text
        return
      }
    }
    let verb: String
    switch adjustment.kind {
    case .increase: verb = String(localized: "the load went up", bundle: L10n.bundle)
    case .decrease: verb = String(localized: "the load went down", bundle: L10n.bundle)
    case .addReps: verb = String(localized: "add a rep", bundle: L10n.bundle)
    case .newVariant: verb = String(localized: "a new variant", bundle: L10n.bundle)
    case .firstTime: verb = String(localized: "start at this weight", bundle: L10n.bundle)
    case .repeatLoad: verb = String(localized: "the load repeats", bundle: L10n.bundle)
    }
    do {
      let reply = try await CoachAPI.ask(
        question: String(
          localized: "Why \(verb) on \(adjustment.exercise.localizedName) today?",
          bundle: L10n.bundle),
        context: CoachAPI.dataBlock(
          profile: profile, sessions: sessions, checkIns: checkIns, usesLb: usesLb),
        coach: coach.name,
        history: [])
      Analytics.track("adjustment_explained", ["source": "server"])
      onDevice = false
      answer = reply.answer
    } catch {
      failed = true
    }
  }
}
