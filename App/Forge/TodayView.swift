import SwiftUI
import SwiftData
import ForgeCore

struct TodayView: View {
  @Environment(\.modelContext) private var modelContext
  @Query private var profiles: [UserProfile]
  @Query(sort: \CheckIn.date) private var checkIns: [CheckIn]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
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
  @State private var cardio: (hrv: Double?, hrvBaseline: Double?, rhr: Double?, rhrBaseline: Double?)?
  @State private var savedCheckInCount = 0
  @State private var showSettings = false
  @State private var showCheckIn = false
  @State private var logFoodMeal: Meal?
  @State private var explaining: Adjustment?
  @State private var appeared = false
  @State private var reviewVoice: String?
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue

  private var coach: Coach { Coach.from(coachID) }

  private var profile: UserProfile? { profiles.first }

  private var openSession: WorkoutSession? {
    sessions.last { !$0.completed && Calendar.current.isDateInToday($0.date) }
  }

  private var fatigue: (score: Int, action: FatigueAction)? {
    fatigueNow(profile: profile, sessions: sessions, checkIns: checkIns, healthBaseline: healthBaseline, cardio: cardio)
  }

  private var isForceRest: Bool {
    if case .forceRest = fatigue?.action { return true }
    return false
  }

  private var week: Int { profile.map { $0.currentWeek(sessions: sessions) } ?? 1 }

  @AppStorage("deloadDismissedDay") private var deloadDismissedDay = ""
  @AppStorage("weekReviewDismissed") private var weekReviewDismissed = 0
  private var todayKey: String { Date.now.formatted(.iso8601.year().month().day()) }

  private var redStreak: Bool {
    guard let today = fatigue?.score else { return false }
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    let prior = fatigueNow(profile: profile, sessions: sessions, checkIns: checkIns, healthBaseline: healthBaseline, cardio: nil, now: yesterday)?.score ?? 0
    return Fatigue.shouldDeloadEarly(recentScores: [prior, today])
  }

  private var offersEarlyDeload: Bool {
    redStreak && profile?.deloadStartedAt == nil && week != Mesocycle.deloadWeek && deloadDismissedDay != todayKey
  }

  private var previousMicrocycle: [WorkoutSession] {
    guard let profile else { return [] }
    let days = max(profile.daysPerWeek, 1)
    let done = sessions.filter { $0.completed && $0.date >= profile.mesoStart }.sorted { $0.date < $1.date }
    let index = done.count / days
    guard index >= 1 else { return [] }
    return Array(done[((index - 1) * days)..<min(index * days, done.count)])
  }

  private var volumeDelta: [Muscle: Int] {
    guard let profile else { return [:] }
    let goal = Goal(rawValue: profile.goal) ?? .hypertrophy
    let performances: [ExercisePerformance] = Dictionary(grouping: previousMicrocycle.flatMap(\.sets), by: \.exerciseID)
      .compactMap { id, sets in
        guard let exercise = ExerciseDB.find(id), let first = sets.first else { return nil }
        return ExercisePerformance(
          exercise: exercise,
          repRange: Program.repRange(exercise, goal: goal),
          targetRPE: first.targetRPE,
          sets: sets.map { SetLog(weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe) })
      }
    let soreness = checkIns.last(where: { Calendar.current.isDateInToday($0.date) })
    let soreMuscles = Set(soreness?.soreMuscles.compactMap(Muscle.init(rawValue:)) ?? [])
    return Autoregulation.volumeDelta(performances, soreness: soreness?.soreness, soreMuscles: soreMuscles)
  }

  private var plannedPair: (day: PlannedDay, base: PlannedDay?)? {
    guard let profile else { return nil }
    let days = Program.week(week, profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)), volumeDelta: volumeDelta)
    guard !days.isEmpty else { return nil }
    let index = profile.nextDayIndex % days.count
    var day = days[index]
    switch fatigue?.action {
    case .reduceOptionalSets:
      day = PlannedDay(name: day.name, exercises: day.exercises.map {
        PlannedExercise(exercise: $0.exercise, sets: max(1, $0.sets - 1), repRange: $0.repRange, targetRPE: $0.targetRPE)
      }, trimmedSets: day.trimmedSets)
    case .lightSession:
      day = PlannedDay(name: day.name, exercises: day.exercises.map {
        PlannedExercise(exercise: $0.exercise, sets: max(1, Int((Double($0.sets) * 0.7).rounded())), repRange: $0.repRange, targetRPE: min($0.targetRPE, 7))
      }, trimmedSets: day.trimmedSets)
    default:
      break
    }
    return (day, Program.week(week, profile: profile.profileInput, volumeDelta: volumeDelta)[index])
  }

  private var plannedDay: PlannedDay? { plannedPair?.day }

  private func resumeDay(for open: WorkoutSession, fallback: PlannedDay) -> PlannedDay {
    guard let profile else { return fallback }
    let days = Program.week(week, profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)), volumeDelta: volumeDelta)
    return days.first { $0.name == open.dayName } ?? fallback
  }

  private var baseDay: PlannedDay? { plannedPair?.base }

  private var weekHeader: String {
    week == Mesocycle.deloadWeek ? String(localized: "Deload week", bundle: L10n.bundle) : String(localized: "Week \(week) of \(Mesocycle.weeks)", bundle: L10n.bundle)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        if let day = plannedDay {
          if isForceRest && !trainAnyway && openSession == nil {
            headerRow
            restDayCard(day).reveal(0, appeared: appeared)
            if offersEarlyDeload {
              earlyDeloadCard.reveal(1, appeared: appeared)
            }
            WeekStrip(sessions: sessions, plannedDays: profile?.daysPerWeek ?? 0, todayProgress: todayProgress(day))
              .padding(.horizontal, 6)
              .reveal(2, appeared: appeared)
          } else {
            headerRow
            heroCard(day).reveal(0, appeared: appeared)
            if showWeekReview {
              weekReviewCard.reveal(1, appeared: appeared)
            }
            WeekStrip(sessions: sessions, plannedDays: profile?.daysPerWeek ?? 0, todayProgress: todayProgress(day))
              .padding(.horizontal, 6)
              .reveal(2, appeared: appeared)
            if offersEarlyDeload {
              earlyDeloadCard.reveal(3, appeared: appeared)
            }
            adjustmentsCard(day).reveal(4, appeared: appeared)
            statTiles.reveal(5, appeared: appeared)
            quickActions(day).reveal(6, appeared: appeared)
            if fatigue == nil {
              compactCheckInCard.reveal(7, appeared: appeared)
            } else {
              planCard(day).reveal(7, appeared: appeared)
            }
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
    .onAppear {
      withAnimation(.easeOut(duration: 0.4)) { appeared = true }
      writeSnapshot()
    }
    .sheet(item: $active) { workout in
      WorkoutView(plannedDay: workout.day, action: workout.resume == nil ? activeAction : .proceed, resuming: workout.resume)
    }
    .sheet(item: $logFoodMeal) { meal in FoodSearchView(meal: meal) }
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
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("forge.startWorkout"))) { _ in
      guard let day = plannedDay else { return }
      if let open = openSession {
        active = ActiveWorkout(day: resumeDay(for: open, fallback: day), resume: open)
        return
      }
      guard !(isForceRest && !trainAnyway) else { return }
      activeAction = fatigue?.action ?? .proceed
      active = ActiveWorkout(day: day)
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

  private var headerRow: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(greeting).forgeGreeting()
        Text("\(weekHeader) · \(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(L10n.locale)))")
          .forgeLabel()
      }
      Spacer()
      CoachAvatar(size: 40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach \(coach.name)")
      IconCircleButton(symbol: "gearshape.fill") { showSettings = true }
        .accessibilityLabel("Settings")
        .sheet(isPresented: $showSettings) { SettingsView() }
    }
  }

  private var coachLine: String {
    if openSession != nil { return String(localized: "You have a session open. Pick up where you left off.", bundle: L10n.bundle) }
    guard let fatigue else { return String(localized: "Check in and I'll set today's plan.", bundle: L10n.bundle) }
    switch fatigue.action {
    case .proceed:
      if let day = plannedDay,
         let up = adjustments(for: day, base: baseDay, sessions: sessions, profile: profile, usesLb: usesLb).first(where: { $0.kind == .increase }) {
        return String(localized: "All clear. \(up.exercise.localizedName) goes up today.", bundle: L10n.bundle)
      }
      return String(localized: "All clear. Let's lift.", bundle: L10n.bundle)
    case .reduceOptionalSets: return String(localized: "Fatigue's up. I dropped your optional sets.", bundle: L10n.bundle)
    case .lightSession: return String(localized: "Light day. Keep RPE under 7.", bundle: L10n.bundle)
    case .forceRest: return String(localized: "Rest today. You've earned it.", bundle: L10n.bundle)
    }
  }

  private var cardioLine: String {
    var parts: [String] = []
    if let hrv = cardio?.hrv { parts.append(String(localized: "HRV \(Int(hrv.rounded())) ms", bundle: L10n.bundle)) }
    if let rhr = cardio?.rhr { parts.append(String(localized: "Resting HR \(Int(rhr.rounded()))", bundle: L10n.bundle)) }
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

  private var weekComplete: Bool {
    WeekStrip.completed(sessions) >= max(profile?.daysPerWeek ?? 1, 1)
  }

  private var finishedWeek: Int { max(1, week - 1) }

  private var showWeekReview: Bool {
    weekComplete && weekReviewDismissed != finishedWeek
  }

  private var weeklyReview: WeeklyReview? {
    guard let profile else { return nil }
    let days = max(profile.daysPerWeek, 1)
    let done = sessions.filter { $0.completed && $0.date >= profile.mesoStart }.sorted { $0.date < $1.date }
    guard done.count >= days else { return nil }
    let thisWeek = Array(done.suffix(days))
    let priorWeek = Array(done.dropLast(days).suffix(days))
    let tonnage = thisWeek.flatMap(\.sets).reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    let priorTonnage = priorWeek.isEmpty ? nil : priorWeek.flatMap(\.sets).reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }

    let weekStart = thisWeek.map(\.date).min() ?? .now
    let before = sessions.filter { $0.completed && $0.date < weekStart }.flatMap(\.sets)
    let weekSets = thisWeek.flatMap(\.sets)
    var prNames: [String] = []
    for id in Set(weekSets.map(\.exerciseID)) {
      guard let exercise = ExerciseDB.find(id) else { continue }
      let best = weekSets.filter { $0.exerciseID == id }
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
      return String(localized: "Week \(nextWeek) is the deload: volume drops, loads stay.", bundle: L10n.bundle)
    }
    let parts = volumeDelta.filter { $0.value != 0 }
      .sorted { $0.key.rawValue < $1.key.rawValue }
      .map { "\($0.key.a11yName) \($0.value > 0 ? "+1 set" : "−1 set")" }
    if parts.isEmpty {
      return String(localized: "Week \(nextWeek): volume held.", bundle: L10n.bundle)
    }
    return String(localized: "Week \(nextWeek): \(parts.joined(separator: ", ")).", bundle: L10n.bundle)
  }

  private var heroRings: [RingSpec] {
    [
      RingSpec(id: "sessions", progress: Double(WeekStrip.completed(sessions)) / Double(max(profile?.daysPerWeek ?? 1, 1)), color: Theme.metricLoad),
      RingSpec(id: "sets", progress: Double(weekSets) / Double(max(weekTarget, 1)), color: Theme.metricSets),
      RingSpec(id: "ready", progress: Double(readiness ?? 0) / 100, color: readinessColor),
    ]
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
              .foregroundColor(Theme.textSecondary)
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
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(localizedDayName(day.name)).forgeTitle()
        Spacer()
        Text(weekHeader.uppercased())
          .forge(11, .semibold, tracking: 0.6)
          .foregroundColor(Theme.textSecondary)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Capsule().fill(Theme.innerSurface))
      }
      HStack(spacing: 18) {
        RingsView(rings: heroRings, size: 132, lineWidth: 12)
        VStack(alignment: .leading, spacing: 10) {
          heroStat(String(localized: "SESSIONS", bundle: L10n.bundle), "\(WeekStrip.completed(sessions))/\(profile?.daysPerWeek ?? 0)", Theme.metricLoad)
          heroStat(String(localized: "SETS", bundle: L10n.bundle), "\(weekSets)/\(weekTarget)", Theme.metricSets)
          heroStat(String(localized: "READY", bundle: L10n.bundle), readiness.map(String.init) ?? "--", readinessColor)
        }
      }
      HStack(alignment: .top, spacing: 10) {
        CoachAvatar(size: 28)
        Text(coachLine).forgeBody()
      }
      if cardio?.hrv != nil || cardio?.rhr != nil {
        Text(cardioLine).forgeCaption().monospacedDigit()
      }
    }
    .card()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(heroA11yLabel(day))
  }

  private func heroStat(_ label: String, _ value: String, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(label).forgeOverline()
      MetricValue(value: value, size: 24, color: color)
    }
  }

  private func heroA11yLabel(_ day: PlannedDay) -> String {
    let score = readiness.map(String.init) ?? String(localized: "unknown", bundle: L10n.bundle)
    let state: String
    switch fatigue?.action {
    case .proceed: state = String(localized: "ready to train", bundle: L10n.bundle)
    case .reduceOptionalSets: state = String(localized: "fatigue elevated, optional sets trimmed", bundle: L10n.bundle)
    case .lightSession: state = String(localized: "light session", bundle: L10n.bundle)
    case .forceRest: state = String(localized: "rest day", bundle: L10n.bundle)
    case nil: state = String(localized: "check in to score", bundle: L10n.bundle)
    }
    return String(localized: "Readiness \(score), \(state). \(weekHeader). \(localizedDayName(day.name)). \(coachLine)", bundle: L10n.bundle)
  }

  private var earlyDeloadCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        CoachAvatar(size: 28)
        Text("Two red days in a row").forgeSection()
        Spacer()
      }
      Text("Fatigue has been in the red two days running. I'm moving your deload up: half the sets, RPE ≤ 6 for the next \(profile?.daysPerWeek ?? 3) sessions, then a fresh block.").forgeBody()
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
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        CoachAvatar(size: 28)
        VStack(alignment: .leading, spacing: 1) {
          Text("\(coach.name)'s adjustments").forgeSection()
          Text(weekLine(week: week, earlyDeload: profile?.deloadStartedAt != nil) + (day.trimmedSets > 0 ? " · \(day.trimmedSets) sets cut to fit \(profile?.sessionMinutes ?? 60) min" : "")).forgeCaption()
        }
        Spacer()
      }
      if !sessions.contains(where: { $0.completed }) {
        Text("First session. Your loads come from your numbers. Log RPE honestly and I tune every lift from here.").forgeLabel()
      } else {
        let all = adjustments(for: day, base: baseDay, sessions: sessions, profile: profile, usesLb: usesLb)
        let changed = all.filter { $0.kind != .repeatLoad }
        let volumes = volumeNotes(volumeDelta, day: day)
        ForEach(volumes) { v in
          adjustmentRow(
            symbol: "square.stack.3d.up.fill",
            tint: v.delta > 0 ? Theme.positive : Theme.negative,
            title: v.title,
            detail: v.detail)
        }
        ForEach(changed.prefix(max(0, 4 - volumes.count))) { a in
          Button {
            explaining = a
          } label: {
            adjustmentRow(symbol: a.symbol, tint: a.tint, title: a.exercise.localizedName, detail: a.detail)
          }
          .buttonStyle(RowPressStyle())
          .accessibilityHint("Explains why")
        }
        if volumes.count + changed.count > 4 {
          Text("+\(volumes.count + changed.count - 4) more").forgeCaption()
        }
        let unchanged = all.count - changed.count
        if unchanged > 0 {
          Text(String(localized: "\(unchanged) lifts unchanged", bundle: L10n.bundle)).forgeCaption()
        }
        if volumes.isEmpty && changed.isEmpty {
          Text("Everything repeats. Hit the same numbers cleaner.").forgeLabel()
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func adjustmentRow(symbol: String, tint: Color, title: String, detail: String) -> some View {
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

  private func quickActions(_ day: PlannedDay) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Quick actions").forgeSection()
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        PhotoTile(image: "tile-workout", title: String(localized: "Start workout", bundle: L10n.bundle), subtitle: String(localized: "≈ \(estimatedMinutes(day)) min", bundle: L10n.bundle), symbol: "figure.strengthtraining.traditional") {
          if isForceRest && !trainAnyway {
            trainAnyway = true
            return
          }
          activeAction = fatigue?.action ?? .proceed
          active = ActiveWorkout(day: day)
        }
        PhotoTile(image: "tile-checkin", title: String(localized: "Check-in", bundle: L10n.bundle), subtitle: fatigue == nil ? String(localized: "15 seconds", bundle: L10n.bundle) : String(localized: "Done today", bundle: L10n.bundle), symbol: "bed.double.fill") {
          showCheckIn = true
        }
        PhotoTile(image: coach.point, title: String(localized: "Ask \(coach.name)", bundle: L10n.bundle), subtitle: String(localized: "Swap, deload, why", bundle: L10n.bundle), symbol: "bubble.left.fill") {
          selection = 1
        }
        PhotoTile(image: "tile-progress", title: String(localized: "Log food", bundle: L10n.bundle), subtitle: String(localized: "Tap a food, done", bundle: L10n.bundle), symbol: "fork.knife") {
          logFoodMeal = Meal.current
        }
      }
    }
  }

  private func estimatedMinutes(_ day: PlannedDay) -> Int {
    Int((Double(day.exercises.reduce(0) { $0 + $1.sets }) * 2.5 / 5).rounded() * 5)
  }

  private var statTiles: some View {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
      StatTile(symbol: "flame.fill", value: "\(streakWeeks)", unit: "wk", label: String(localized: "streak", bundle: L10n.bundle), tint: Theme.metricTime)
      StatTile(symbol: "scalemass", value: weekTonnageText, unit: unit, label: String(localized: "this week", bundle: L10n.bundle), tint: Theme.metricLoad)
      StatTile(symbol: "dumbbell", value: "\(sessions.filter(\.completed).count)", label: String(localized: "workouts", bundle: L10n.bundle), tint: Theme.metricSets)
      StatTile(symbol: "trophy.fill", value: bestE1RMNumber, unit: unit, label: String(localized: "best e1RM", bundle: L10n.bundle), tint: Theme.metricLoad)
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
    let best = sessions.filter(\.completed).flatMap(\.sets)
      .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
      .max()
    guard let best else { return "—" }
    let value = usesLb ? Plates.kgToLb(best) : best
    return "\(Int(value.rounded()))"
  }

  private var streakWeeks: Int {
    let cal = Calendar(identifier: .iso8601)
    guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start else { return 0 }
    let weeks = Set(sessions.filter(\.completed).compactMap { cal.dateInterval(of: .weekOfYear, for: $0.date)?.start })
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
    return sessions.filter { $0.completed && week.contains($0.date) }.reduce(0) { $0 + $1.sets.count }
  }

  private var weekTarget: Int {
    let length = profile.map { SessionLength(rawValue: $0.sessionMinutes) ?? .m60 } ?? .m60
    return (profile?.daysPerWeek ?? 0) * Program.setBudget(for: length)
  }

  private var checkedInToday: Bool {
    checkIns.contains { Calendar.current.isDateInToday($0.date) }
  }

  private func writeSnapshot() {
    WidgetBridgeWriter.write(day: plannedDay, streakWeeks: streakWeeks, weekSets: weekSets, weekTarget: weekTarget, checkedIn: checkedInToday)
  }

  private var compactCheckInCard: some View {
    HStack(spacing: 12) {
      Image(systemName: "sparkles")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(Theme.accent)
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
          Text("Regulift reads sleep and resting heart rate from Health to score readiness. Optional.")
            .forgeLabel()
        }
        pickerRow(String(localized: "Sleep", bundle: L10n.bundle), $sleepQuality)
        pickerRow(String(localized: "Soreness", bundle: L10n.bundle), $soreness)
        pickerRow(String(localized: "Energy", bundle: L10n.bundle), $energy)
        pickerRow(String(localized: "Motivation", bundle: L10n.bundle), $motivation)
        VStack(spacing: 10) {
          Text("SLEPT").forge(11, .semibold, tracking: 0.8).foregroundColor(Theme.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
          HStack {
            sleepButton("minus") { sleepHours = max(0, sleepHours - 0.5) }
            Spacer()
            MetricValue(value: Fmt.num(sleepHours), unit: "hours", size: 56)
            Spacer()
            sleepButton("plus") { sleepHours = min(12, sleepHours + 0.5) }
          }
          Text(sleepPrefilled && Health.isAuthorized ? String(localized: "From Health · edit if wrong", bundle: L10n.bundle) : String(localized: "Tap − / + to set", bundle: L10n.bundle)).forgeCaption()
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
              Button(soreMuscles.contains(muscle) ? "Clear \(muscle.a11yName)" : "Mark \(muscle.a11yName) sore") {
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
        .foregroundColor(Theme.onAccent)
        .frame(width: 44, height: 44)
        .background(Circle().fill(Theme.accent))
    }
    .buttonStyle(RowPressStyle())
  }

  private func toggleSore(_ muscle: Muscle) {
    withAnimation(.snappy) {
      if soreMuscles.contains(muscle) { soreMuscles.remove(muscle) } else { soreMuscles.insert(muscle) }
    }
  }

  private var soreMusclesA11yLabel: String {
    let sore = Muscle.allCases.filter(soreMuscles.contains).map(\.a11yName)
    return sore.isEmpty ? String(localized: "No sore muscles", bundle: L10n.bundle) : String(localized: "Sore muscles: ", bundle: L10n.bundle) + sore.joined(separator: ", ")
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
    let rotatedIn = Set(day.exercises.map(\.exercise.id)).subtracting(Set(baseDay?.exercises.map(\.exercise.id) ?? []))
    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Today's plan").forgeSection()
        Spacer()
        Text("≈ \(estimatedMinutes(day)) min")
          .forgeLabel()
          .monospacedDigit()
      }
      MuscleMapView(intensity: plannedIntensity(day))
        .frame(height: 160)
        .frame(maxWidth: .infinity)
      VStack(spacing: 8) {
        ForEach(day.exercises, id: \.exercise.id) { planned in
          planRow(planned, rotatedIn: rotatedIn.contains(planned.exercise.id))
        }
      }
    }
    .card()
  }

  private func plannedIntensity(_ day: PlannedDay) -> [Muscle: Double] {
    var sets: [Muscle: Double] = [:]
    for e in day.exercises { sets[e.exercise.primary, default: 0] += Double(e.sets) }
    guard let max = sets.values.max(), max > 0 else { return [:] }
    return sets.mapValues { $0 / max }
  }

  private func planRow(_ planned: PlannedExercise, rotatedIn: Bool) -> some View {
    let kg = suggestedStartKg(for: planned, last: lastSets(planned.exercise.id, in: sessions), profile: profile)
    let display = usesLb ? Plates.kgToLb(kg) : kg
    return HStack(spacing: 12) {
      EquipmentThumb(equipment: planned.exercise.equipment, size: 40)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 8) {
          Text(planned.exercise.localizedName).forgeBodyStrong()
          if rotatedIn {
            Text("New variant")
              .forge(11, .semibold)
              .foregroundColor(Theme.accent)
              .padding(.horizontal, 8).padding(.vertical, 2)
              .background(RoundedRectangle(cornerRadius: Theme.radiusChip).fill(Theme.accentTint))
          }
        }
        Text("\(planned.sets) × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound) · \(Fmt.kg(display, lb: usesLb))")
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
      Group {
        if let open = openSession {
          Button("Resume \(localizedDayName(open.dayName)) · \(open.sets.count) sets logged") {
            active = ActiveWorkout(day: resumeDay(for: open, fallback: day), resume: open)
          }
          .buttonStyle(PillButtonStyle())
        } else if fatigue == nil {
          Button("Check in") { showCheckIn = true }
            .buttonStyle(PillButtonStyle())
        } else if isForceRest && !trainAnyway {
          Button("Rest day · Train anyway") { trainAnyway = true }
            .buttonStyle(PillSecondaryButtonStyle())
        } else {
          Button("Start \(localizedDayName(day.name)) · ≈ \(estimatedMinutes(day)) min") {
            activeAction = fatigue?.action ?? .proceed
            active = ActiveWorkout(day: day)
          }
          .buttonStyle(PillButtonStyle())
        }
      }
      .padding(.horizontal, Theme.barMargin)
      .padding(.vertical, 10)
      .background(Theme.page.opacity(0.92))
      .background(.ultraThinMaterial)
    }
  }
}

struct ActiveWorkout: Identifiable {
  let day: PlannedDay
  var resume: WorkoutSession? = nil
  var id: String { resume == nil ? day.name : day.name + "#resume" }
}

func fatigueNow(profile: UserProfile?, sessions: [WorkoutSession], checkIns: [CheckIn], healthBaseline: Double? = nil, cardio: (hrv: Double?, hrvBaseline: Double?, rhr: Double?, rhrBaseline: Double?)? = nil, now: Date = .now) -> (score: Int, action: FatigueAction)? {
  guard let ci = checkIns.last(where: { Calendar.current.isDate($0.date, inSameDayAs: now) }), profile != nil else { return nil }
  func volume(_ windowDays: Double) -> Double {
    sessions
      .filter { $0.completed && now.timeIntervalSince($0.date) < windowDays * 86400 }
      .reduce(0) { total, session in
        total + session.sets.reduce(0) { t, set in
          guard let exercise = ExerciseDB.find(set.exerciseID) else { return t }
          let credit = Volume.credit(for: SetLog(weightKg: set.weightKg, reps: set.reps, rpe: set.rpe), exercise: exercise)
          return t + credit.values.reduce(0, +)
        }
      }
  }
  let recentCheckIns = checkIns.filter { now.timeIntervalSince($0.date) < 7 * 86400 }
  let checkinBaseline = recentCheckIns.isEmpty
    ? 7.0
    : recentCheckIns.reduce(0.0) { $0 + $1.sleepHours } / Double(recentCheckIns.count)
  let baseline = healthBaseline ?? checkinBaseline
  let completed7 = sessions.filter { $0.completed && now.timeIntervalSince($0.date) < 7 * 86400 }
  let missed = completed7.filter { session in
    session.sets.contains { $0.rpe > $0.targetRPE + 1 }
  }.count
  // ponytail: <4 weeks of logged history scales the chronic window; PRD assumes a full 28 days
  let first = sessions.filter(\.completed).map(\.date).min() ?? now
  let historyWeeks = min(4.0, max(1.0, ceil(now.timeIntervalSince(first) / (7 * 86400))))
  let score = Fatigue.score(FatigueInputs(
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
          Text(onDevice ? String(localized: "On this iPhone", bundle: L10n.bundle) : String(localized: "\(coach.name) via Regulift coach", bundle: L10n.bundle)).forgeCaption()
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
        usesLb: usesLb) {
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
        question: String(localized: "Why \(verb) on \(adjustment.exercise.localizedName) today?", bundle: L10n.bundle),
        context: CoachAPI.dataBlock(profile: profile, sessions: sessions, checkIns: checkIns, usesLb: usesLb),
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
