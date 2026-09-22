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
  @State private var adjustmentsOpen = false
  /// Set once the ScrollViewReader exists, so the brief card can scroll to the card it opens.
  @State private var scrollToAdjustments: (() -> Void)?
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue

  private var coach: Coach { Coach.from(coachID) }

  private var profile: UserProfile? { profiles.first }

  /// The accepted week plan, resolved against `now`. Nil means the lifter never saved a
  /// plan, and Today is the generated schedule exactly as it was before.
  private var planStatus: WeekPlanTodayStatus? {
    profile?.weekPlan.map { WeekPlanTodayStatus(plan: $0, now: .now) }
  }

  private var openSession: WorkoutSession? {
    sessions.last { !$0.completed && Calendar.current.isDateInToday($0.date) }
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
    return decisionLog.filter { $0.date >= blockStart }.flatMap { entry -> [WeekBriefFact] in
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
      guard let owedID = status.owed?.plannedSessionID,
        let planned = days.first(where: { $0.id == owedID })
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

  private var completedThisWeek: Int {
    guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
    return sessions.filter { $0.completed && week.contains($0.date) }.count
  }

  private var daysLeftInWeek: Int {
    guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
    let end = Calendar.current.startOfDay(for: week.end)
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
        injuries: injuries)
      {
        return finding
      }
    }
    return nil
  }

  private func weeklySets(for muscle: Muscle) -> Double {
    guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
    var total = 0.0
    for s in sessions where s.completed && week.contains(s.date) {
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
      .card()
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
      .card()
    }
  }

  private var weekHeader: String {
    week == Mesocycle.deloadWeek
      ? String(localized: "Deload week", bundle: L10n.bundle)
      : String(localized: "Week \(week) of \(Mesocycle.weeks)", bundle: L10n.bundle)
  }

  var body: some View {
    ScrollViewReader { scroll in
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        if let day = plannedDay {
          if isForceRest && !trainAnyway && openSession == nil {
            headerRow
            restDayCard(day).reveal(0, appeared: appeared)
            weekSnapshotCard.reveal(1, appeared: appeared)
            WeekStrip(
              sessions: sessions, plannedDays: profile?.daysPerWeek ?? 0,
              todayProgress: todayProgress(day)
            )
            .padding(.horizontal, 6)
            .reveal(2, appeared: appeared)
            if let status = planStatus {
              acceptedPlanCard(status).reveal(3, appeared: appeared)
            }
            if offersEarlyDeload {
              earlyDeloadCard.reveal(4, appeared: appeared)
            }
          } else {
            let fit = effectiveDay ?? day
            headerRow
            heroCard(fit).reveal(0, appeared: appeared)
            weekSnapshotCard.reveal(1, appeared: appeared)
            WeekStrip(
              sessions: sessions, plannedDays: profile?.daysPerWeek ?? 0,
              todayProgress: todayProgress(day)
            )
            .padding(.horizontal, 6)
            .reveal(2, appeared: appeared)
            if let status = planStatus {
              acceptedPlanCard(status).reveal(3, appeared: appeared)
            }
            adjustmentsCard(fit).reveal(4, appeared: appeared).id("adjustments")
            if !weekBrief.isEmpty {
              nextWeekBriefCard.reveal(5, appeared: appeared)
            }
            if showWeekReview {
              weekReviewCard.reveal(6, appeared: appeared)
            }
            if offersEarlyDeload {
              earlyDeloadCard.reveal(7, appeared: appeared)
            }
            missedWorkoutCard.reveal(8, appeared: appeared)
            plateauCard.reveal(9, appeared: appeared)
            statTiles.reveal(10, appeared: appeared)
            quickActions().reveal(11, appeared: appeared)
            if fatigue == nil {
              compactCheckInCard.reveal(12, appeared: appeared)
            } else {
              planCard(fit).reveal(12, appeared: appeared)
            }
          }
        } else if let status = planStatus {
          // An accepted plan with nothing left to point at: today is rest, never a
          // generated session the lifter did not agree to.
          headerRow
          acceptedPlanCard(status).reveal(0, appeared: appeared)
          if status.owed == nil {
            planRestCard(status: status).reveal(1, appeared: appeared)
          }
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 8)
      .padding(.bottom, 24)
      .sheet(isPresented: $showCheckIn) { checkInSheet }
    }
    .background(Theme.page)
    .safeAreaInset(edge: .bottom) { bottomBar }
    .sensoryFeedback(.success, trigger: savedCheckInCount)
    .task { await loadHealthSignals() }
    .onAppear {
      if timeBox == nil { timeBox = profile?.trainingConstraints.sessionBudgetMinutes }
      withAnimation(.easeOut(duration: 0.4)) { appeared = true }
      writeSnapshot()
      scrollToAdjustments = { scroll.scrollTo("adjustments", anchor: .top) }
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
  }

  private var greeting: String {
    let hour = Calendar.current.component(.hour, from: .now)
    if hour < 12 { return String(localized: "Good morning", bundle: L10n.bundle) }
    if hour < 17 { return String(localized: "Good afternoon", bundle: L10n.bundle) }
    return String(localized: "Good evening", bundle: L10n.bundle)
  }

  private var headerRow: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(greeting).forgeGreeting()
        Text(
          "\(weekHeader) · \(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(L10n.locale)))"
        )
        .forgeLabel()
      }
      Spacer()
      CoachAvatar(size: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach \(coach.name)")
      IconCircleButton(symbol: "gearshape.fill") { showSettings = true }
        .accessibilityLabel("Settings")
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
  }

  private var coachLine: String {
    if openSession != nil {
      return String(
        localized: "You have a session open. Pick up where you left off.", bundle: L10n.bundle)
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

  private var cardioLine: String {
    var parts: [String] = []
    if let hrv = cardio?.hrv {
      parts.append(String(localized: "HRV \(Int(hrv.rounded())) ms", bundle: L10n.bundle))
    }
    if let rhr = cardio?.rhr {
      parts.append(String(localized: "Resting HR \(Int(rhr.rounded()))", bundle: L10n.bundle))
    }
    return parts.joined(separator: " · ")
  }

  private var usesLb: Bool { profile?.usesLb ?? false }
  private var unit: String { usesLb ? "lb" : "kg" }

  private var readiness: Int? {
    fatigue.map { 100 - $0.score }
  }

  private var readinessColor: Color {
    switch fatigue?.action {
    case .proceed: Theme.positive
    case .forceRest: Theme.negative
    case .reduceOptionalSets, .lightSession: Theme.metricEffort
    case nil: Theme.track
    }
  }

  /// Hero overline: the real readiness state. Unscored days and rest days never read READY.
  private var readinessStateLabel: String {
    switch fatigue?.action {
    case .proceed, .reduceOptionalSets: return String(localized: "READY", bundle: L10n.bundle)
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
      Image(coach.hero)
        .resizable()
        .scaledToFill()
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipped()
        .overlay(alignment: .bottom) {
          LinearGradient(colors: [.clear, Theme.card], startPoint: .top, endPoint: .bottom)
            .frame(height: 140)
        }
        .contentShape(Rectangle())

      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 16) {
          ZStack {
            RingView(progress: Double(readiness ?? 0) / 100, lineWidth: 8, color: Theme.negative)
            MetricValue(value: "\(readiness ?? 0)", size: 24)
          }
          .frame(width: 72, height: 72)
          .breathing()

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
    }
    .card(padding: 0)
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Rest day. Readiness \(readiness ?? 0). Nothing to log. \(coachLine)")
  }

  private func heroCard(_ day: PlannedDay) -> some View {
    return VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Today's session").forgeLabel()
        Spacer()
        Button {
          showRoadmap = true
        } label: {
          HStack(spacing: 4) {
            Text(weekHeader.uppercased())
            Image(systemName: "chevron.right")
          }
          .lineLimit(1)
          .forge(10, .semibold, tracking: 0.7)
          .foregroundStyle(Theme.textSecondary)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(Capsule().fill(Theme.innerSurface))
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("Program roadmap, \(weekHeader)")
      }

      Text(localizedDayName(day.name))
        .forge(30, .bold, tracking: -1.0)
        .foregroundStyle(Theme.text)
      Text(heroFacts(day))
        .forgeLabel()
        .monospacedDigit()

      HStack(alignment: .top, spacing: 10) {
        CoachAvatar(size: 28)
        Text(coachLine).forgeBody()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .innerSurface(padding: 12)
    }
    .card()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(heroA11yLabel(day))
  }

  private var weekSnapshotCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("This week").forgeSection()
      HStack(spacing: 0) {
        heroStat(
          String(localized: "SESSIONS", bundle: L10n.bundle),
          "\(sessionsDoneThisWeek)/\(sessionsTargetThisWeek)", Theme.text
        )
        .frame(maxWidth: .infinity)
        Rectangle().fill(Theme.ring).frame(width: 1, height: 36)
        heroStat(
          String(localized: "SETS", bundle: L10n.bundle), "\(weekSets)/\(weekTarget)",
          Theme.text
        )
        .frame(maxWidth: .infinity)
        Rectangle().fill(Theme.ring).frame(width: 1, height: 36)
        heroStat(
          String(localized: "READY", bundle: L10n.bundle),
          readiness.map(String.init) ?? "--", readiness == nil ? Theme.text : readinessColor
        )
        .frame(maxWidth: .infinity)
      }
      // Drawn, not ProgressView: the UIKit-backed bar escapes the card's combined label and
      // surfaces to VoiceOver and UI tests as a bare "Progress".
      let fraction = min(1, Double(weekSets) / Double(max(weekTarget, 1)))
      Capsule()
        .fill(Theme.track)
        .frame(height: 4)
        .overlay(alignment: .leading) {
          GeometryReader { geo in
            Capsule().fill(Theme.accent).frame(width: geo.size.width * fraction)
          }
        }
    }
    .card(padding: 16)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(weekSnapshotA11yLabel)
  }

  private func heroFacts(_ day: PlannedDay) -> String {
    let sets = day.exercises.reduce(0) { $0 + $1.sets }
    var seen: Set<Muscle> = []
    let muscles =
      day.exercises.compactMap { planned -> String? in
        guard seen.insert(planned.exercise.primary).inserted else { return nil }
        return planned.exercise.primary.a11yName
      }
      .prefix(3)
      .joined(separator: " · ")
    return [
      String(localized: "≈ \(planEstimate(day)) min", bundle: L10n.bundle),
      String(localized: "\(sets) sets", bundle: L10n.bundle),
      muscles,
    ].joined(separator: " · ")
  }

  private func heroStat(_ label: String, _ value: String, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      MetricValue(value: value, size: 22, color: color)
      Text(label).forgeOverline()
    }
  }

  private func heroA11yLabel(_ day: PlannedDay) -> String {
    String(
      localized: "\(weekHeader). \(localizedDayName(day.name)). \(heroFacts(day)). \(coachLine)",
      bundle: L10n.bundle)
  }

  private var weekSnapshotA11yLabel: String {
    let score = readiness.map(String.init) ?? String(localized: "unknown", bundle: L10n.bundle)
    let state: String
    switch fatigue?.action {
    case .proceed: state = String(localized: "ready to train", bundle: L10n.bundle)
    case .reduceOptionalSets:
      state = String(localized: "fatigue elevated, optional sets trimmed", bundle: L10n.bundle)
    case .lightSession: state = String(localized: "light session", bundle: L10n.bundle)
    case .forceRest: state = String(localized: "rest day", bundle: L10n.bundle)
    case nil: state = String(localized: "check in to score", bundle: L10n.bundle)
    }
    let progress = String(
      localized:
        "\(sessionsDoneThisWeek) of \(sessionsTargetThisWeek) sessions done this week, \(weekSets) of \(weekTarget) sets.",
      bundle: L10n.bundle)
    return String(localized: "Readiness \(score), \(state). \(progress)", bundle: L10n.bundle)
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
    .card(fill: Theme.negative.opacity(0.06))
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
    .card()
    .task(id: finishedWeek) { await loadReviewVoice() }
  }

  private var nextWeekBriefCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        CoachAvatar(size: 28)
        Text(String(localized: "Your next week", bundle: L10n.bundle)).forgeSection()
        Spacer()
      }
      ForEach(weekBrief.statements) { statement in
        VStack(alignment: .leading, spacing: 2) {
          Text(statement.kind.label.uppercased())
            .forge(10, .semibold, tracking: 0.7)
            .foregroundStyle(Theme.textSecondary)
          Text(statement.text).forgeBody()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      Button {
        // The adjustments card sits above this one, so opening it alone leaves the lifter
        // looking at unchanged copy. Scroll to what the tap just expanded.
        withAnimation(reduceMotion ? nil : .snappy) {
          adjustmentsOpen = true
          scrollToAdjustments?()
        }
      } label: {
        HStack(spacing: 6) {
          Text(String(localized: "Review actual changes", bundle: L10n.bundle))
          Image(systemName: "arrow.up")
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .foregroundStyle(Theme.accent)
      .accessibilityLabel(String(localized: "Review actual changes", bundle: L10n.bundle))
      .accessibilityHint(String(localized: "Opens this week's adjustments", bundle: L10n.bundle))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
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

  private func adjustmentsCard(_ day: PlannedDay) -> some View {
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

    return VStack(alignment: .leading, spacing: 12) {
      Button {
        withAnimation(reduceMotion ? nil : .snappy) { adjustmentsOpen.toggle() }
      } label: {
        HStack(spacing: 10) {
          CoachAvatar(size: 28)
          VStack(alignment: .leading, spacing: 1) {
            Text("\(coach.name)'s adjustments").forgeBodyStrong()
            Text(changeText).forgeCaption()
          }
          Spacer()
          Image(systemName: adjustmentsOpen ? "chevron.up" : "chevron.down")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.textTertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(coach.name)'s adjustments, \(changeText)")
      .accessibilityValue(
        adjustmentsOpen
          ? String(localized: "Expanded", bundle: L10n.bundle)
          : String(localized: "Collapsed", bundle: L10n.bundle)
      )
      .accessibilityHint(
        adjustmentsOpen
          ? String(localized: "Double tap to collapse", bundle: L10n.bundle)
          : String(localized: "Double tap to expand", bundle: L10n.bundle))

      if adjustmentsOpen {
        Text(
          weekLine(week: week, earlyDeload: profile?.deloadStartedAt != nil)
            + (day.trimmedSets > 0
              ? String(
                localized: " · \(day.trimmedSets) sets cut to fit \(sessionMinutes) min",
                bundle: L10n.bundle) : "")
        )
        .forgeCaption()
        if firstSession {
          Text(
            "First session. Your loads come from your numbers. Log RPE honestly and I tune every lift from here."
          ).forgeLabel()
        } else {
          ForEach(all) { a in
            if let decision = a.decision {
              decisionCard(a, decision)
            }
          }
          ForEach(volumes) { v in
            adjustmentRow(
              symbol: "square.stack.3d.up.fill",
              tint: v.delta > 0 ? Theme.positive : Theme.negative,
              title: v.title,
              detail: v.detail)
          }
          if all.isEmpty && volumes.isEmpty {
            Text("Everything repeats. Hit the same numbers cleaner.").forgeLabel()
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func decisionCard(_ a: Adjustment, _ decision: Decision) -> some View {
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
        decisionDetail(a, decision)
      }
    }
    .innerSurface(padding: 10)
  }

  @ViewBuilder
  private func decisionDetail(_ a: Adjustment, _ decision: Decision) -> some View {
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
          explaining = a
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

  /// Supporting controls only: the persistent bottom CTA owns start/resume.
  private func quickActions() -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Quick actions").forgeSection()
      VStack(spacing: 0) {
        quickActionRow(
          symbol: "bed.double.fill",
          title: String(localized: "Check-in", bundle: L10n.bundle),
          subtitle: fatigue == nil
            ? String(localized: "15 seconds", bundle: L10n.bundle)
            : String(localized: "Done today", bundle: L10n.bundle)
        ) {
          showCheckIn = true
        }
        quickActionDivider
        quickActionRow(
          symbol: "bubble.left.fill",
          title: String(localized: "Ask \(coach.name)", bundle: L10n.bundle),
          subtitle: String(localized: "Swap, deload, why", bundle: L10n.bundle)
        ) {
          selection = 1
        }
        quickActionDivider
        quickActionRow(
          symbol: "fork.knife",
          title: String(localized: "Log food", bundle: L10n.bundle),
          subtitle: String(localized: "Tap a food, done", bundle: L10n.bundle)
        ) {
          logFoodMeal = Meal.current
        }
      }
      .card(padding: 0)
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    }
  }

  private var quickActionDivider: some View {
    Rectangle()
      .fill(Theme.ring)
      .frame(height: 1)
      .padding(.leading, 56)
  }

  private func quickActionRow(
    symbol: String,
    title: String,
    subtitle: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        ZStack {
          Circle().fill(Theme.accentTint)
          Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
        .frame(width: 28, height: 28)
        VStack(alignment: .leading, spacing: 1) {
          Text(title).forgeBodyStrong()
          Text(subtitle).forgeCaption()
        }
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(Theme.textTertiary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title), \(subtitle)")
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
    return ActiveWorkout(day: day, resume: open, planDayID: planDayID(for: day))
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

  private var statTiles: some View {
    VStack(alignment: .leading, spacing: 12) {
      if cardio?.hrv != nil || cardio?.rhr != nil {
        Text(cardioLine).forgeCaption().monospacedDigit()
      }
      // Today counts every set the lifter logged. The labels name the scope so the
      // numbers here are never confused with Progress's analysis-eligible totals.
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        StatTile(
          symbol: "flame.fill", value: "\(streakWeeks)", unit: "wk",
          label: String(localized: "streak", bundle: L10n.bundle), tint: Theme.metricTime)
        StatTile(
          symbol: "scalemass", value: weekTonnageText, unit: unit,
          label: String(localized: "this week · all recorded", bundle: L10n.bundle),
          tint: Theme.metricLoad)
        StatTile(
          symbol: "dumbbell", value: "\(sessions.filter(\.completed).count)",
          label: String(localized: "workouts · all recorded", bundle: L10n.bundle),
          tint: Theme.metricSets)
        StatTile(
          symbol: "trophy.fill", value: bestE1RMNumber, unit: unit,
          label: String(localized: "best e1RM · analysis eligible", bundle: L10n.bundle),
          tint: Theme.metricLoad)
      }
      if let qualifier = MetricScopePolicy.qualifier(
        scope: .analysisEligible, recordedSetCount: weekSets,
        analysisEligibleSetCount: weekEligibleSets)
      {
        Text(qualifier).forgeCaption().foregroundStyle(Theme.textTertiary)
      }
    }
  }

  private var weekTonnageText: String {
    guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return "0" }
    let tonnage = sessions.filter { $0.completed && week.contains($0.date) }
      .flatMap(\.sets)
      .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    return Fmt.grouped(usesLb ? Plates.kgToLb(tonnage) : tonnage)
  }

  private var bestE1RMNumber: String {
    let best = sessions.trustedSets
      .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
      .max()
    guard let best else { return "—" }
    let value = usesLb ? Plates.kgToLb(best) : best
    return "\(Int(value.rounded()))"
  }

  private var streakWeeks: Int {
    let cal = Calendar(identifier: .iso8601)
    guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
    let weeks = Set(
      sessions.filter(\.completed).compactMap {
        cal.dateInterval(of: .weekOfYear, for: $0.date)?.start
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
    guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
    return sessions.filter { $0.completed && week.contains($0.date) }.reduce(0) {
      $0 + $1.sets.count
    }
  }

  /// Sets the plausibility guard kept this week — the scope Progress analyses.
  private var weekEligibleSets: Int {
    guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
    return sessions.filter { week.contains($0.date) }.reduce(0) { $0 + $1.trustedSets.count }
  }

  private var weekTarget: Int {
    let length = profile.map { SessionLength(rawValue: $0.sessionMinutes) ?? .m60 } ?? .m60
    return (profile?.daysPerWeek ?? 0) * Program.setBudget(for: length)
  }

  private var checkedInToday: Bool {
    checkIns.contains { Calendar.current.isDateInToday($0.date) }
  }

  private func writeSnapshot() {
    WidgetBridgeWriter.write(
      day: plannedDay, streakWeeks: streakWeeks, weekSets: weekSets, weekTarget: weekTarget,
      checkedIn: checkedInToday)
  }

  private var compactCheckInCard: some View {
    HStack(spacing: 12) {
      Image(systemName: "sparkles")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Theme.accent)
      Text("Check in to unlock today's plan").forgeBodyStrong()
      Spacer()
      Button("Check in") { showCheckIn = true }
        .buttonStyle(PillButtonStyle(minHeight: 40))
        .frame(width: 110)
    }
    .card()
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
          Text("SLEPT").forge(11, .semibold, tracking: 0.8).foregroundStyle(Theme.textTertiary)
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
      Button {
        showMusclePreview = true
      } label: {
        HStack(spacing: 10) {
          Text("Planned emphasis").forgeBodyStrong()
          Spacer()
          ForEach(SessionMusclePreviewView.breakdown(day).prefix(2)) { item in
            Text("\(item.muscle.a11yName) \(Int((item.fraction * 100).rounded()))%")
              .forgeCaption()
              .monospacedDigit()
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Capsule().fill(Theme.innerSurface))
          }
          Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())

      VStack(spacing: 8) {
        ForEach(day.exercises, id: \.exercise.id) { planned in
          planRow(planned, rotatedIn: rotatedIn.contains(planned.exercise.id))
        }
      }
    }
    .card()
  }

  private func planRow(_ planned: PlannedExercise, rotatedIn: Bool) -> some View {
    let kg = suggestedStartKg(
      for: planned, last: lastSets(planned.exercise.id, in: sessions), profile: profile)
    let display = usesLb ? Plates.kgToLb(kg) : kg
    return HStack(spacing: 12) {
      ExerciseArt(exercise: planned.exercise, size: 40)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 8) {
          Text(planned.exercise.localizedName).forgeBodyStrong()
          if rotatedIn {
            Text("New variant")
              .forge(11, .semibold)
              .foregroundStyle(Theme.accent)
              .padding(.horizontal, 8).padding(.vertical, 2)
              .background(RoundedRectangle(cornerRadius: Theme.radiusChip).fill(Theme.accentTint))
          }
        }
        Text(
          "\(planned.sets) × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound) · \(Fmt.kg(display, lb: usesLb))"
        )
        .forgeLabel()
        .monospacedDigit()
      }
      Spacer()
      Text("RPE \(planned.targetRPE, specifier: "%.0f")")
        .foregroundStyle(Theme.textSecondary)
        .forgeCaption()
        .monospacedDigit()
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Theme.track))
    }
    .innerSurface(padding: 10)
    .contentShape(Rectangle())
  }

  @ViewBuilder private var bottomBar: some View {
    if let day = plannedDay {
      let fit = effectiveDay ?? day
      Group {
        if let open = openSession {
          Button("Resume \(localizedDayName(open.dayName)) · \(open.sets.count) sets logged") {
            active = resumeWorkout(for: open, fallback: day)
          }
          .buttonStyle(PillButtonStyle())
        } else if fatigue == nil {
          Button("Check in") { showCheckIn = true }
            .buttonStyle(PillButtonStyle())
        } else if isForceRest && !trainAnyway {
          Button("Rest day · Train anyway") { trainAnyway = true }
            .buttonStyle(PillSecondaryButtonStyle())
        } else {
          let lead =
            planStatus?.owedIsToday == false
            ? String(localized: " · next up", bundle: L10n.bundle) : ""
          Button("Start \(localizedDayName(day.name))\(lead) · ≈ \(planEstimate(fit)) min") {
            beginWorkout(fit)
          }
          .buttonStyle(PillButtonStyle())
        }
      }
      .padding(.horizontal, Theme.barMargin)
      .padding(.vertical, 10)
      .background(Theme.page.opacity(0.92))
      .background(.ultraThinMaterial)
    } else if let status = planStatus {
      // The accepted plan owes nothing here, so say that instead of offering a session
      // the lifter never planned.
      HStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Theme.positive)
        Text(WeekPlanTodayStatus.countsLine(status.evaluation.counts)).forgeLabel()
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Theme.barMargin)
      .padding(.vertical, 14)
      .frame(minHeight: 44)
      .background(Theme.page.opacity(0.92))
      .background(.ultraThinMaterial)
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
  return (score, Fatigue.action(forScore: score))
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

// MARK: - Accepted plan card

extension TodayView {
  /// What the accepted plan chose, spelled out where the lifter decides whether to train.
  /// Only rendered when a plan was saved; without one, Today is the generated schedule.
  func acceptedPlanCard(_ status: WeekPlanTodayStatus) -> some View {
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
        VStack(alignment: .leading, spacing: 3) {
          Text(localizedDayName(focus.day.sessionName)).forgeBodyStrong()
          Text(planFocusLine(status)).forgeCaption()
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

      Button("Review or regenerate the week") { showRoadmap = true }
        .buttonStyle(PillSecondaryButtonStyle())
        .frame(minHeight: 44)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
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
    .card()
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
