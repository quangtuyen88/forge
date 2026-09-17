import SwiftUI
import SwiftData
import UserNotifications
import ActivityKit
import ForgeCore

struct WorkoutView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var allSessions: [WorkoutSession]

  let plannedDay: PlannedDay
  let action: FatigueAction
  var resuming: WorkoutSession? = nil

  @State private var session: WorkoutSession?
  @State private var weights: [String: [String]] = [:]
  @State private var reps: [String: [Int]] = [:]
  @State private var rpes: [String: [Double]] = [:]
  @State private var variants: [String: SetVariant] = [:]
  @State private var restEnd: Date?
  @State private var restTotal: TimeInterval = 0
  @State private var showPlates = false
  @State private var focusedKg = 0.0
  @State private var platesLbUnit = false
  @State private var prs: [PRRecord] = []
  @State private var showSummary = false
  @State private var summary: SessionSummary?
  @State private var debrief: [DebriefLine] = []
  @State private var confirmFinish = false
  @State private var restExercise: Exercise?
  @State private var restNextSet = 0
  @State private var restTotalSets = 0
  @State private var restActivity: ActivityKit.Activity<RestActivityAttributes>?
  @State private var hrTask: Task<Void, Never>?
  @State private var heartbeatTask: Task<Void, Never>?
  @State private var swaps: [String: Exercise] = [:]
  @State private var swapTarget: PlannedExercise?
  @State private var currentExerciseID: String?
  @State private var loggedCount = 0
  @State private var finishedCount = 0
  @State private var activeSlot: String?
  @State private var showNotes = false
  @State private var showAddExercise = false
  @State private var noteTarget: PlannedExercise?
  @State private var detailTarget: Exercise?
  @State private var warmUpExpanded: Set<String> = []
  @State private var warmUpDone: Set<String> = []
  @FocusState private var focused: String?
  @State private var quickLogInput = ""
  @State private var quickLogToast: String?
  @State private var quickLogError: String?
  @State private var quickLogParsing = false
  @State private var speech = SpeechInput()
  @State private var quickLogPrefix = ""
  @FocusState private var quickLogFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var profile: UserProfile? { profiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }
  private var equipment: Set<Equipment> {
    Set(profile?.equipment.compactMap { Equipment(rawValue: $0) } ?? [])
  }
  private var goal: Goal { profile.map { Goal(rawValue: $0.goal) ?? .hypertrophy } ?? .hypertrophy }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Theme.groupGap) {
          header
          if action != .proceed {
            fatigueNote
          }
          quickLogRow
          ForEach(exerciseList) { planned in
            let exercise = swaps[planned.exercise.id] ?? planned.exercise
            exerciseCard(planned, exercise)
          }
          Button("Add exercise") { showAddExercise = true }
            .buttonStyle(PillSecondaryButtonStyle())
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
        .padding(.bottom, 24)
      }
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle(plannedDay.name)
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom) { restBar }
      .sensoryFeedback(.success, trigger: loggedCount)
      .sensoryFeedback(.success, trigger: finishedCount)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          HStack(spacing: 14) {
            Button { showNotes = true } label: { Image(systemName: "note.text") }
              .accessibilityLabel("Workout notes")
            Button { showPlates = true } label: { Image(systemName: "circle.grid.2x2") }
              .accessibilityLabel("Plate calculator")
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Finish workout") { finishTapped() }.bold()
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { focused = nil }
        }
      }
      .sheet(isPresented: $showPlates) {
        if let profile {
          PlatesSheet(
            kg: focusedKg,
            usesLb: platesLbUnit,
            bar: platesLbUnit ? profile.barLb : profile.barKg,
            plates: platesLbUnit ? profile.platesLb : profile.platesKg)
        }
      }
      .sheet(item: $swapTarget) { planned in
        let current = swaps[planned.exercise.id] ?? planned.exercise
        SwapSheet(current: current, equipment: equipment) { replacement in
          swaps[planned.exercise.id] = replacement
        }
      }
      .sheet(item: $detailTarget) { exercise in
        ExerciseDetailView(
          exercise: exercise,
          sessions: allSessions,
          usesLb: isLb(for: exercise.id),
          note: Binding(
            get: { profile?.exerciseNotes[exercise.id] ?? "" },
            set: { profile?.exerciseNotes[exercise.id] = $0.isEmpty ? nil : $0 }))
      }
      .sheet(item: $noteTarget) { planned in
        NoteSheet(title: "Exercise note", text: Binding(
          get: { profile?.exerciseNotes[planned.exercise.id] ?? "" },
          set: { profile?.exerciseNotes[planned.exercise.id] = $0.isEmpty ? nil : $0 }))
      }
      .sheet(isPresented: $showNotes) {
        NoteSheet(title: "Workout notes", text: Binding(
          get: { session?.notes ?? "" },
          set: { session?.notes = $0 }))
      }
      .sheet(isPresented: $showAddExercise) {
        AddExerciseSheet(equipment: equipment, exclude: Set(exerciseList.map(\.exercise.id))) { exercise in
          addExercise(exercise)
        }
      }
      .sheet(isPresented: $showSummary, onDismiss: { dismiss() }) {
        if let summary {
          SessionSummaryView(summary: summary, prs: prs, debrief: debrief, usesLb: usesLb) { showSummary = false }
            .interactiveDismissDisabled()
        }
      }
      .onAppear(perform: setup)
      .onReceive(NotificationCenter.default.publisher(for: .forgeSkipRest)) { _ in skipRest() }
      .onReceive(NotificationCenter.default.publisher(for: .forgeLogSet)) { _ in logActiveSet() }
      .confirmationDialog(
        "Finish with \(loggedCount) of \(totalSets) sets logged?",
        isPresented: $confirmFinish,
        titleVisibility: .visible
      ) {
        Button("Finish workout") { finish() }
        Button("Keep going", role: .cancel) {}
      }
      .onDisappear {
        UserDefaults(suiteName: WidgetBridge.suite)?.set(false, forKey: "forge.workout.active")
        hrTask?.cancel()
        heartbeatTask?.cancel()
        cancelRestNotification()
        endRestActivity()
      }
      .overlay(alignment: .top) { quickLogToastView }
      .onChange(of: speech.transcript) { _, value in
        if !value.isEmpty { quickLogInput = quickLogPrefix + value }
      }
    }
    .background(Theme.page)
  }

  // MARK: structure

  private var exerciseList: [PlannedExercise] {
    var list = plannedDay.exercises.filter { !(session?.removedExerciseIDs.contains($0.exercise.id) ?? false) }
    let have = Set(list.map(\.exercise.id))
    list.append(contentsOf: (session?.extraExerciseIDs ?? []).compactMap { id -> PlannedExercise? in
      guard !have.contains(id), let ex = ExerciseDB.find(id) else { return nil }
      return PlannedExercise(exercise: ex, sets: 3, repRange: Program.repRange(ex, goal: goal), targetRPE: 8)
    })
    guard let order = session?.order, !order.isEmpty else { return list }
    var out: [PlannedExercise] = []
    for id in order {
      if let p = list.first(where: { $0.exercise.id == id }) { out.append(p) }
    }
    out.append(contentsOf: list.filter { !order.contains($0.exercise.id) })
    return out
  }

  private func sets(for id: String) -> Int {
    session?.setCounts[id] ?? plannedDay.exercises.first { $0.exercise.id == id }?.sets ?? 3
  }

  private func isLb(for id: String) -> Bool {
    profile?.unitOverrides[id] ?? usesLb
  }

  private func displayUnit(for id: String) -> String {
    isLb(for: id) ? "lb" : "kg"
  }

  private func hasLogged(_ id: String) -> Bool {
    session?.sets.contains { $0.exerciseID == id } ?? false
  }

  private func hasNext(_ id: String) -> Bool {
    let ids = exerciseList.map(\.exercise.id)
    guard let i = ids.firstIndex(of: id) else { return false }
    return i + 1 < ids.count
  }

  private func isSecondOfSuperset(_ id: String) -> Bool {
    let ids = exerciseList.map(\.exercise.id)
    guard let i = ids.firstIndex(of: id), i > 0 else { return false }
    return session?.supersets.contains(ids[i - 1]) == true
  }

  private func inSuperset(_ id: String) -> Bool {
    session?.supersets.contains(id) == true || isSecondOfSuperset(id)
  }

  private func toggleSuperset(_ id: String) {
    var sup = session?.supersets ?? []
    if sup.contains(id) {
      sup.removeAll { $0 == id }
    } else if isSecondOfSuperset(id) {
      let ids = exerciseList.map(\.exercise.id)
      if let i = ids.firstIndex(of: id), i > 0 { sup.removeAll { $0 == ids[i - 1] } }
    } else if hasNext(id) {
      sup.append(id)
    }
    session?.supersets = sup
  }

  private func move(_ id: String, _ delta: Int) {
    var ids = exerciseList.map(\.exercise.id)
    guard let i = ids.firstIndex(of: id) else { return }
    let j = i + delta
    guard ids.indices.contains(j) else { return }
    ids.swapAt(i, j)
    session?.order = ids
  }

  private func addSet(_ planned: PlannedExercise, _ count: Int) {
    let id = planned.exercise.id
    session?.setCounts[id] = count + 1
    let suggestion = formatDisplay(suggestedKg(planned), lb: isLb(for: id))
    var w = weights[id] ?? []
    while w.count < count { w.append(suggestion) }
    w.append(w.last ?? suggestion)
    weights[id] = w
    var r = reps[id] ?? []
    while r.count < count { r.append(planned.repRange.lowerBound) }
    r.append(r.last ?? planned.repRange.lowerBound)
    reps[id] = r
    var e = rpes[id] ?? []
    while e.count < count { e.append(8) }
    e.append(e.last ?? 8)
    rpes[id] = e
  }

  private func removeLastSet(_ id: String, _ count: Int) {
    session?.setCounts[id] = max(1, count - 1)
    if var w = weights[id], w.count >= count { w.removeLast(); weights[id] = w }
    if var r = reps[id], r.count >= count { r.removeLast(); reps[id] = r }
    if var e = rpes[id], e.count >= count { e.removeLast(); rpes[id] = e }
  }

  private func removeExercise(_ id: String) {
    session?.removedExerciseIDs.append(id)
    var sup = session?.supersets ?? []
    sup.removeAll { $0 == id }
    session?.supersets = sup
    session?.order = exerciseList.map(\.exercise.id)
  }

  private func addExercise(_ exercise: Exercise) {
    let id = exercise.id
    session?.extraExerciseIDs.append(id)
    session?.order = exerciseList.map(\.exercise.id)
    let suggestion = suggestedKg(PlannedExercise(exercise: exercise, sets: 3, repRange: Program.repRange(exercise, goal: goal), targetRPE: 8))
    weights[id] = (0..<3).map { _ in formatDisplay(suggestion, lb: isLb(for: id)) }
    reps[id] = [Int](repeating: Program.repRange(exercise, goal: goal).lowerBound, count: 3)
    rpes[id] = [Double](repeating: 8, count: 3)
  }

  private func toggleUnit(_ id: String) {
    let toLb = !isLb(for: id)
    profile?.unitOverrides[id] = toLb
    weights[id] = (weights[id] ?? []).map { text in
      let value = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
      return formatDisplay(value, fromLb: !toLb)
    }
  }

  // MARK: header

  private var header: some View {
    VStack(spacing: 12) {
      progressBar
      HStack(alignment: .top, spacing: 18) {
        elapsedStat
        headerStat(String(localized: "SETS"), "\(loggedCount)/\(totalSets)", color: Theme.metricSets)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(loggedCount) of \(totalSets) sets")
        headerStat(String(localized: "TONNAGE"), loggedTonnageText, unit: unitLabel, color: Theme.metricLoad)
        Spacer(minLength: 0)
        currentMuscleThumb
      }
    }
  }

  private var progressBar: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(Theme.track)
        Capsule().fill(Theme.accent)
          .frame(width: geo.size.width * CGFloat(loggedCount) / CGFloat(max(totalSets, 1)))
      }
    }
    .frame(height: 4)
    .animation(.snappy, value: loggedCount)
  }

  private var fatigueNote: some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.accent)
      Text(actionNote).forgeLabel()
    }
    .innerSurface()
  }

  private var totalSets: Int {
    exerciseList.reduce(0) { $0 + sets(for: $1.exercise.id) }
  }

  private var elapsedStat: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let s = max(0, Int(context.date.timeIntervalSince(session?.date ?? .now)))
      VStack(alignment: .leading, spacing: 2) {
        MetricValue(value: elapsedText(at: context.date), size: 26, color: Theme.metricTime)
        Text(WatchSync.shared.heartRate.map { String(localized: "ELAPSED · ♥ \($0)") } ?? String(localized: "ELAPSED"))
          .forgeOverline()
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Elapsed \(s / 60) minutes \(s % 60) seconds")
    }
  }

  private func headerStat(_ label: String, _ value: String, unit: String? = nil, color: Color = Theme.text) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      MetricValue(value: value, unit: unit, size: 26, color: color)
      Text(label).forgeOverline()
    }
  }

  private var unitLabel: String { usesLb ? "lb" : "kg" }

  private var loggedTonnageText: String {
    let kg = (session?.sets ?? []).reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    return Fmt.grouped(usesLb ? Plates.kgToLb(kg) : kg)
  }

  private func elapsedText(at now: Date) -> String {
    guard let start = session?.date else { return "0:00" }
    let s = max(0, Int(now.timeIntervalSince(start)))
    return String(format: "%d:%02d", s / 60, s % 60)
  }

  private var currentMuscleThumb: some View {
    MuscleMapView(intensity: currentMuscle.map { [$0: 1] } ?? [:])
      .frame(width: 64, height: 50, alignment: .top)
      .clipped()
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Muscles worked today: \(workedMusclesText)")
  }

  private var workedMusclesText: String {
    let muscles = muscleVolumes.isEmpty ? [currentMuscle].compactMap { $0 } : muscleVolumes.map(\.muscle)
    return muscles.map(\.a11yName).joined(separator: ", ")
  }

  private var currentMuscle: Muscle? {
    if let currentExerciseID,
       let planned = exerciseList.first(where: { $0.exercise.id == currentExerciseID }) {
      return planned.exercise.primary
    }
    return exerciseList.first?.exercise.primary
  }

  private var actionNote: String {
    switch action {
    case .reduceOptionalSets: return String(localized: "Fatigue is elevated — optional sets trimmed.")
    case .lightSession: return String(localized: "Light session — volume reduced, RPE capped at 7.")
    case .forceRest: return String(localized: "High fatigue — keep today conservative.")
    default: return ""
    }
  }

  // MARK: setup / resume

  private func setup() {
    UserDefaults(suiteName: WidgetBridge.suite)?.set(true, forKey: "forge.workout.active")
    startHeartbeat()
    WatchSync.shared.startWatchWorkout(dayName: plannedDay.name)
    Task { await Notifications.requestAuthorization() }
    for a in ActivityKit.Activity<RestActivityAttributes>.activities { Task { await a.end(nil, dismissalPolicy: .immediate) } }
    guard session == nil, let profile else { return }
    Analytics.track("workout_started", ["day": plannedDay.name])
    Notifications.cancelReengagement()
    if let resuming {
      session = resuming
      prefill(fromLogged: true)
      loggedCount = resuming.sets.count
      activeSlot = firstPendingSlot()
      sendWatchPlan()
      return
    }
    let newSession = WorkoutSession(date: .now, dayName: plannedDay.name, week: profile.currentWeek(sessions: allSessions), completed: false)
    modelContext.insert(newSession)
    try? modelContext.save()
    session = newSession
    prefill(fromLogged: false)
    activeSlot = firstPendingSlot()
    sendWatchPlan()
  }

  private func prefill(fromLogged: Bool) {
    // ponytail: adjustments(base: nil) — .addReps is the only kind prefill needs; base only gates newVariant
    let addRepIDs = Set(
      adjustments(for: plannedDay, base: nil, sessions: allSessions, profile: profile, usesLb: usesLb)
        .filter { $0.kind == .addReps }
        .map { $0.exercise.id })
    for planned in exerciseList {
      let id = planned.exercise.id
      let exercise = swaps[id] ?? planned.exercise
      let suggestion = suggestedKg(planned)
      let count = max(1, sets(for: id))
      let last = lastSets(exercise.id, in: allSessions)
      var w: [String] = []
      var r: [Int] = []
      var e: [Double] = []
      for index in 0..<count {
        if fromLogged, let logged = loggedSet(exercise.id, index) {
          w.append(formatDisplay(logged.weightKg, lb: isLb(for: id)))
          r.append(logged.reps)
          e.append(logged.rpe)
        } else {
          w.append(formatDisplay(suggestion, lb: isLb(for: id)))
          let ghostReps = index < last.count ? last[index].reps : nil
          r.append(addRepIDs.contains(id) && ghostReps != nil
            ? min(ghostReps! + 1, planned.repRange.upperBound)
            : planned.repRange.lowerBound)
          e.append(8.0)
        }
      }
      weights[id] = w
      reps[id] = r
      rpes[id] = e
      if focusedKg == 0 { focusedKg = suggestion }
    }
  }

  private func sendWatchPlan() {
    var suggestedByID: [String: Double] = [:]
    var restByID: [String: Int] = [:]
    for planned in exerciseList {
      suggestedByID[planned.exercise.id] = suggestedKg(planned)
      restByID[planned.exercise.id] = restSeconds(for: swaps[planned.exercise.id] ?? planned.exercise)
    }
    let day = PlannedDay(name: plannedDay.name, exercises: exerciseList.map {
      PlannedExercise(exercise: $0.exercise, sets: sets(for: $0.exercise.id), repRange: $0.repRange, targetRPE: $0.targetRPE)
    })
    WatchSync.shared.sendPlan(day, suggested: { suggestedByID[$0.id] ?? 0 }, rest: { restByID[$0.id] ?? 0 }, dayName: plannedDay.name)
  }

  // MARK: bindings

  private func weightBinding(_ id: String, _ index: Int) -> Binding<String> {
    Binding(
      get: { weights[id]?[index] ?? "" },
      set: { newValue in
        var array = weights[id] ?? []
        while array.count <= index { array.append("") }
        array[index] = newValue
        weights[id] = array
      })
  }

  private func repsBinding(_ id: String, _ index: Int) -> Binding<Int> {
    Binding(
      get: { reps[id]?[index] ?? 0 },
      set: { newValue in
        var array = reps[id] ?? []
        while array.count <= index { array.append(0) }
        array[index] = newValue
        reps[id] = array
      })
  }

  private func repsText(_ id: String, _ index: Int) -> Binding<String> {
    Binding(
      get: { String(reps[id]?[index] ?? 0) },
      set: { newValue in
        var array = reps[id] ?? []
        while array.count <= index { array.append(0) }
        array[index] = Int(newValue) ?? 0
        reps[id] = array
      })
  }

  private func rpeBinding(_ id: String, _ index: Int) -> Binding<Double> {
    Binding(
      get: { rpes[id]?[index] ?? 8 },
      set: { newValue in
        var array = rpes[id] ?? []
        while array.count <= index { array.append(8) }
        array[index] = newValue
        rpes[id] = array
      })
  }

  private func selectedVariant(_ id: String, _ index: Int) -> SetVariant {
    variants[key(id, index)] ?? .straight
  }

  private func stepWeight(_ id: String, _ index: Int, _ direction: Double) {
    let exercise = swaps[id] ?? plannedDay.exercises.first { $0.exercise.id == id }?.exercise ?? ExerciseDB.find(id)
    let step = isLb(for: id) ? 2.5 : (exercise?.smallestIncrementKg ?? 2.5)
    let current = Double((weights[id]?[index] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
    var array = weights[id] ?? []
    while array.count <= index { array.append("") }
    array[index] = formatDisplay(max(0, current + direction * step))
    weights[id] = array
  }

  private func restSeconds(for exercise: Exercise) -> Int {
    guard let profile else { return exercise.restSeconds }
    return profile.restOverrides[exercise.id] ?? (exercise.isCompound ? profile.restCompoundSeconds : profile.restIsolationSeconds)
  }

  private func log(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int) {
    let id = planned.exercise.id
    let lb = isLb(for: id)
    let text = weights[id]?[index] ?? ""
    let value = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    let kg = lb ? Plates.lbToKg(value) : value
    log(planned, exercise, index, weightKg: kg, reps: reps[id]?[index] ?? 0, rpe: rpes[id]?[index] ?? 8)
  }

  private func log(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int, weightKg: Double, reps: Int, rpe: Double?) {
    let id = planned.exercise.id
    let lb = isLb(for: id)
    focusedKg = weightKg
    platesLbUnit = lb
    let set = LoggedSet(
      exerciseID: exercise.id,
      setIndex: index,
      weightKg: weightKg,
      reps: reps,
      rpe: rpe ?? 8,
      targetRPE: planned.targetRPE,
      variant: selectedVariant(id, index).rawValue,
      loggedAt: .now)
    modelContext.insert(set)
    session?.sets.append(set)
    try? modelContext.save()
    currentExerciseID = exercise.id
    loggedCount += 1
    Analytics.track("set_logged")
    let seconds = restSeconds(for: exercise)
    let firstOfPair = session?.supersets.contains(id) == true
    withAnimation(.snappy) {
      if !firstOfPair {
        restTotal = TimeInterval(seconds)
        restEnd = Date.now.addingTimeInterval(TimeInterval(seconds))
      }
      activeSlot = firstPendingSlot()
      focused = nil
    }
    if !firstOfPair {
      restExercise = exercise
      restNextSet = index + 2
      restTotalSets = sets(for: id)
      scheduleRestNotification(seconds: seconds, exercise: exercise, nextSet: index + 2, totalSets: sets(for: id))
      syncRestActivity(end: restEnd ?? .now, exercise: exercise, nextSet: index + 2, totalSets: sets(for: id))
      startHeartRateLoop()
    }
  }

  private func logActiveSet() {
    guard let slot = activeSlot,
          let planned = exerciseList.first(where: { slot.hasPrefix("\($0.exercise.id)#") }),
          let index = Int(slot.dropFirst(planned.exercise.id.count + 1)) else { return }
    log(planned, swaps[planned.exercise.id] ?? planned.exercise, index)
  }

  // MARK: quick log

  private var quickLogRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        TextField("deadlift 132.5x8 @8", text: $quickLogInput, axis: .vertical)
          .lineLimit(1...2)
          .submitLabel(.done)
          .onSubmit { submitQuickLog() }
          .focused($quickLogFocused)
          .forgeBody()
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .background(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous).fill(Theme.card))
          .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1))
        if Features.voice, speech.isAvailable {
          Button { toggleQuickDictation() } label: {
            if speech.isPreparing || speech.isTranscribing {
              ProgressView()
                .frame(width: 44, height: 44)
            } else {
              Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(speech.isListening ? Theme.onAccent : Theme.accent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(speech.isListening ? Theme.accent : Theme.card))
                .overlay(Circle().strokeBorder(Theme.ring, lineWidth: speech.isListening ? 0 : 1))
            }
          }
          .accessibilityLabel("Dictate")
          .disabled(speech.isPreparing || speech.isTranscribing)
        }
        Button { submitQuickLog() } label: {
          if quickLogParsing {
            ProgressView()
              .frame(width: 44, height: 44)
          } else {
            Image(systemName: "checkmark")
              .font(.system(size: 15, weight: .bold))
              .foregroundColor(Theme.onAccent)
              .frame(width: 44, height: 44)
              .background(Circle().fill(quickLogInput.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.track : Theme.accent))
          }
        }
        .disabled(quickLogInput.trimmingCharacters(in: .whitespaces).isEmpty || quickLogParsing)
        .accessibilityLabel("Quick log")
      }
      #if DEBUG
      if Features.voice, !SpeechLog.shared.text.isEmpty {
        Text(SpeechLog.shared.text).forgeCaption().foregroundStyle(Theme.textTertiary)
      }
      #endif
      if let quickLogError {
        Text(quickLogError).foregroundStyle(Theme.negative).forgeCaption()
      }
    }
    .innerSurface(padding: 10)
  }

  @ViewBuilder
  private var quickLogToastView: some View {
    if let toast = quickLogToast {
      Text(toast)
        .forge(14, .semibold)
        .foregroundStyle(Theme.onAccent)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Theme.accent))
        .padding(.top, 8)
        .transition(reduceMotion ? .forgeFade : .forgeSlideUp)
    }
  }

  private func toggleQuickDictation() {
    if speech.isListening {
      speech.stop()
    } else {
      quickLogPrefix = quickLogInput
      speech.vocabulary = SpeechVocabulary.lifting(extra: exerciseList.map { $0.exercise.name })
      Task { await speech.start() }
    }
  }

  private func quickLogCandidates() -> [QuickLogCandidate] {
    var seen = Set<String>()
    var out: [QuickLogCandidate] = []
    func add(_ exercise: Exercise?) {
      guard let exercise, !seen.contains(exercise.id) else { return }
      seen.insert(exercise.id)
      out.append(QuickLogCandidate(id: exercise.id, name: exercise.name))
    }
    for planned in exerciseList {
      add(swaps[planned.exercise.id] ?? planned.exercise)
    }
    let cutoff = Date.now.addingTimeInterval(-30 * 86400)
    let recentSets = allSessions
      .filter { $0.date > cutoff }
      .sorted { $0.date > $1.date }
      .flatMap { $0.sets.sorted { $0.loggedAt > $1.loggedAt } }
    for set in recentSets { add(ExerciseDB.find(set.exerciseID)) }
    for exercise in ExerciseDB.everything { add(exercise) }
    return out
  }

  private func plannedEntry(for exerciseID: String) -> (slot: PlannedExercise, exercise: Exercise)? {
    for planned in exerciseList {
      let effective = swaps[planned.exercise.id] ?? planned.exercise
      if effective.id == exerciseID {
        return (planned, effective)
      }
    }
    return nil
  }

  private func firstPendingSetIndex(slotID: String, exerciseID: String) -> Int? {
    let count = sets(for: slotID)
    for index in 0..<count where loggedSet(exerciseID, index) == nil {
      return index
    }
    return nil
  }

  private func submitQuickLog() {
    let text = quickLogInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, !quickLogParsing else { return }
    quickLogParsing = true
    quickLogError = nil
    Task { await resolveAndLog(text) }
  }

  private func resolveAndLog(_ text: String) async {
    let candidates = quickLogCandidates()
    var parse = QuickLog.parse(text, candidates: candidates, defaultLb: usesLb)
    if parse == nil, OnDeviceCoach.isAvailable,
       let draft = await OnDeviceCoach.parseQuickLog(text, candidateNames: Array(candidates.prefix(300).map(\.name)), defaultLb: usesLb) {
      parse = QuickLog.parse(QuickLog.canonical(draft), candidates: candidates, defaultLb: usesLb)
    }
    guard let first = parse else {
      quickLogError = "Couldn't read that. Try: deadlift 132.5x8 @8"
      quickLogParsing = false
      return
    }
    var resolved = first
    if isLb(for: first.exerciseID) != usesLb,
       let reparsed = QuickLog.parse(text, candidates: candidates, defaultLb: isLb(for: first.exerciseID)) {
      resolved = reparsed
    }
    guard let exercise = ExerciseDB.find(resolved.exerciseID) else {
      quickLogError = "Couldn't read that. Try: deadlift 132.5x8 @8"
      quickLogParsing = false
      return
    }
    if let (slot, effective) = plannedEntry(for: resolved.exerciseID) {
      if let index = firstPendingSetIndex(slotID: slot.exercise.id, exerciseID: effective.id) {
        log(slot, effective, index, weightKg: resolved.weightKg, reps: resolved.reps, rpe: resolved.rpe)
      } else {
        let newCount = (session?.setCounts[slot.exercise.id] ?? sets(for: slot.exercise.id)) + 1
        session?.setCounts[slot.exercise.id] = newCount
        log(slot, effective, newCount - 1, weightKg: resolved.weightKg, reps: resolved.reps, rpe: resolved.rpe)
      }
    } else {
      addExercise(exercise)
      if let (slot, effective) = plannedEntry(for: exercise.id) {
        log(slot, effective, 0, weightKg: resolved.weightKg, reps: resolved.reps, rpe: resolved.rpe)
      }
    }
    quickLogInput = ""
    quickLogError = nil
    quickLogFocused = false
    quickLogParsing = false
    let lb = isLb(for: resolved.exerciseID)
    let unit = lb ? "lb" : "kg"
    let display = lb ? Plates.kgToLb(resolved.weightKg) : resolved.weightKg
    var toast = "Logged \(exercise.name) · \(Fmt.num(display)) \(unit) × \(resolved.reps)"
    if let rpe = resolved.rpe { toast += " @ \(Fmt.num(rpe))" }
    showQuickLogToast(toast)
  }

  private func showQuickLogToast(_ text: String) {
    withAnimation(.snappy) { quickLogToast = text }
    Task {
      try? await Task.sleep(for: .seconds(2))
      withAnimation(.snappy) { quickLogToast = nil }
    }
  }

  private func loggedSet(_ id: String, _ index: Int) -> LoggedSet? {
    session?.sets.first { $0.exerciseID == id && $0.setIndex == index }
  }

  private func ghostSet(_ id: String, _ index: Int) -> LoggedSet? {
    for s in allSessions.filter(\.completed).sorted(by: { $0.date > $1.date }) {
      if let ghost = s.sets.first(where: { $0.exerciseID == id && $0.setIndex == index }) {
        return ghost
      }
    }
    return nil
  }

  private func suggestedKg(_ planned: PlannedExercise) -> Double {
    suggestedStartKg(for: planned, last: lastSets(planned.exercise.id, in: allSessions), profile: profile)
  }

  private func formatDisplay(_ value: Double, lb: Bool = false) -> String {
    Fmt.num(lb ? Plates.kgToLb(value) : value)
  }

  private func formatDisplay(_ value: Double, fromLb: Bool) -> String {
    Fmt.num(fromLb ? Plates.lbToKg(value) : Plates.kgToLb(value))
  }

  private func displayWeight(_ kg: Double, lb: Bool) -> String {
    formatDisplay(kg, lb: lb)
  }

  /// Spoken weight for VoiceOver labels: "80 kilograms" / "170 pounds".
  private func spokenWeight(kg: Double, lb: Bool) -> String {
    String(localized: "\(displayWeight(kg, lb: lb)) \(lb ? "pounds" : "kilograms")")
  }

  /// Spoken weight from a display-unit text field value.
  private func spokenDisplayWeight(_ text: String, lb: Bool) -> String {
    let value = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    return String(localized: "\(Fmt.num(value)) \(lb ? "pounds" : "kilograms")")
  }

  private func spokenMinutes(_ s: Int) -> String {
    let m = s / 60, r = s % 60
    var parts = [String(localized: "\(m) minutes")]
    if r > 0 { parts.append(String(localized: "\(r) seconds")) }
    return parts.joined(separator: " ")
  }

  private func mmss(_ s: Int) -> String {
    String(format: "%d:%02d", s / 60, s % 60)
  }

  private func key(_ id: String, _ i: Int) -> String { "\(id)#\(i)" }

  private func firstPendingSlot() -> String? {
    let list = exerciseList
    var i = 0
    while i < list.count {
      var group = [list[i]]
      if session?.supersets.contains(list[i].exercise.id) == true, i + 1 < list.count {
        group.append(list[i + 1])
        i += 2
      } else {
        i += 1
      }
      let counts = group.map { sets(for: $0.exercise.id) }
      for index in 0..<(counts.max() ?? 0) {
        for (g, planned) in group.enumerated() where index < counts[g] {
          let exercise = swaps[planned.exercise.id] ?? planned.exercise
          if loggedSet(exercise.id, index) == nil { return key(planned.exercise.id, index) }
        }
      }
    }
    return nil
  }

  // MARK: cards

  private func exerciseCard(_ planned: PlannedExercise, _ exercise: Exercise) -> some View {
    let id = planned.exercise.id
    let count = sets(for: id)
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        EquipmentThumb(equipment: exercise.equipment, size: 40)
          .accessibilityHidden(true)
        Button {
          detailTarget = exercise
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
              Text(exercise.name).forgeSection()
              if inSuperset(id) { supersetChip }
            }
            Text("\(count) × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound) · RPE \(planned.targetRPE, specifier: "%.0f") · rest \(mmss(restSeconds(for: exercise)))")
              .forgeLabel()
              .monospacedDigit()
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(exercise.name), \(count) sets of \(planned.repRange.lowerBound) to \(planned.repRange.upperBound), RPE \(Fmt.num(planned.targetRPE)), rest \(spokenMinutes(restSeconds(for: exercise)))")
        Spacer()
        exerciseMenu(planned, exercise, count)
      }
      VStack(spacing: 8) {
        if !warmUpSteps(planned, exercise).isEmpty {
          warmUpSection(planned, exercise)
        }
        ForEach(0..<count, id: \.self) { index in
          setSlot(planned, exercise, index)
        }
      }
    }
    .card()
  }

  private var supersetChip: some View {
    HStack(spacing: 4) {
      Image(systemName: "link").font(.system(size: 10, weight: .semibold))
      Text("Superset").forge(11, .semibold)
    }
    .foregroundStyle(Theme.accent)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Capsule().fill(Theme.accentTint))
  }

  private func exerciseMenu(_ planned: PlannedExercise, _ exercise: Exercise, _ count: Int) -> some View {
    let id = planned.exercise.id
    return Menu {
      Button("Swap…") { swapTarget = planned }
      Button("Add set") { addSet(planned, count) }
      if count > 1 && loggedSet(exercise.id, count - 1) == nil {
        Button("Remove last set") { removeLastSet(id, count) }
      }
      Button("Move up") { move(id, -1) }
      Button("Move down") { move(id, 1) }
      if inSuperset(id) {
        Button("Break superset") { toggleSuperset(id) }
      } else if hasNext(id) {
        Button("Superset with next") { toggleSuperset(id) }
      }
      Button(isLb(for: id) ? String(localized: "Show in kg") : String(localized: "Show in lb")) { toggleUnit(id) }
      Button("Note…") { noteTarget = planned }
      if !hasLogged(exercise.id) {
        Button("Remove exercise", role: .destructive) { removeExercise(id) }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(Theme.text)
    }
    .buttonStyle(IconButtonStyle())
    .accessibilityLabel("Exercise options")
  }

  private func warmUpSteps(_ planned: PlannedExercise, _ exercise: Exercise) -> [(kg: Double, reps: Int)] {
    guard exercise.isCompound, let profile else { return [] }
    let barKg = isLb(for: planned.exercise.id) ? Plates.lbToKg(profile.barLb) : profile.barKg
    return WarmUp.ramp(workingKg: suggestedKg(planned), barKg: barKg, incrementKg: exercise.smallestIncrementKg)
  }

  private func warmUpSection(_ planned: PlannedExercise, _ exercise: Exercise) -> some View {
    let steps = warmUpSteps(planned, exercise)
    let id = planned.exercise.id
    let expanded = warmUpExpanded.contains(id)
    return VStack(spacing: 8) {
      Button {
        if expanded { warmUpExpanded.remove(id) } else { warmUpExpanded.insert(id) }
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "flame")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
          Text("Warm-up · \(steps.count) sets").forgeLabel()
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .innerSurface(padding: 10)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Warm-up, \(steps.count) sets")
      if expanded {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
          let stepKey = "wu#\(id)#\(index)"
          let done = warmUpDone.contains(stepKey)
          Button {
            if done {
              warmUpDone.remove(stepKey)
            } else {
              warmUpDone.insert(stepKey)
              if steps.indices.allSatisfy({ warmUpDone.contains("wu#\(id)#\($0)") }) {
                warmUpExpanded.remove(id)
              }
            }
          } label: {
            HStack(spacing: 10) {
              ZStack {
                Circle().fill(done ? Theme.positive : Theme.track)
                if done {
                  Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                }
              }
              .frame(width: 22, height: 22)
              Text("\(displayWeight(step.kg, lb: isLb(for: id))) \(displayUnit(for: id)) × \(step.reps)")
                .forgeBody()
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
              Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  @ViewBuilder
  private func setSlot(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int) -> some View {
    let id = planned.exercise.id
    if let logged = loggedSet(exercise.id, index) {
      loggedRow(logged, id)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    } else if activeSlot == key(id, index) {
      setEditor(planned, exercise, index)
    } else {
      pendingRow(planned, exercise, index)
    }
  }

  private func loggedRow(_ logged: LoggedSet, _ id: String) -> some View {
    let variant = SetVariant(rawValue: logged.variant) ?? .straight
    return HStack(spacing: 10) {
      ZStack {
        Circle().fill(Theme.accent)
        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.onAccent)
      }
      .frame(width: 24, height: 24)
      Text("\(displayWeight(logged.weightKg, lb: isLb(for: id))) \(displayUnit(for: id)) × \(logged.reps)")
        .forgeBodyStrong()
        .monospacedDigit()
      if variant != .straight {
        Text(variant.label)
          .forge(11, .semibold)
          .foregroundStyle(Theme.accent)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(Capsule().fill(Theme.accentTint))
      }
      Spacer()
      Text("RPE \(Fmt.num(logged.rpe))")
        .forgeCaption()
        .monospacedDigit()
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.accent.opacity(0.08)))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Set \(logged.setIndex + 1), \(spokenWeight(kg: logged.weightKg, lb: isLb(for: id))) times \(logged.reps), RPE \(Fmt.num(logged.rpe))")
  }

  private func pendingRow(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int) -> some View {
    let id = planned.exercise.id
    return SwipeLogRow(onSwipe: { log(planned, exercise, index) }) {
      Button {
        withAnimation(.snappy) { activeSlot = key(id, index) }
      } label: {
        HStack(spacing: 10) {
          ZStack {
            Circle().fill(Theme.track)
            Text("\(index + 1)").forgeCaption()
          }
          .frame(width: 24, height: 24)
          Text("\(weights[id]?[index] ?? "") \(displayUnit(for: id)) × \(reps[id]?[index] ?? 0)")
            .forgeBody()
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
  }

  private func setEditor(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int) -> some View {
    let id = planned.exercise.id
    let lb = isLb(for: id)
    let unit = displayUnit(for: id)
    let variant = selectedVariant(id, index)
    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Set \(index + 1) of \(sets(for: id))").forgeLabel()
        Spacer()
        if let ghost = ghostSet(exercise.id, index) {
          Text("Last \(displayWeight(ghost.weightKg, lb: lb)) \(unit) × \(ghost.reps) @ \(Fmt.num(ghost.rpe))")
            .forgeCaption()
            .monospacedDigit()
        }
      }
      HStack(spacing: 8) {
        valueChip(
          label: unit,
          text: weightBinding(id, index),
          keyboard: .decimalPad,
          focusKey: "w#\(id)#\(index)",
          a11yName: String(localized: "Weight"),
          a11yValue: spokenDisplayWeight(weights[id]?[index] ?? "", lb: lb),
          minus: { stepWeight(id, index, -1) },
          plus: { stepWeight(id, index, 1) })
          .frame(maxWidth: .infinity)
        valueChip(
          label: String(localized: "reps"),
          text: repsText(id, index),
          keyboard: .numberPad,
          focusKey: "r#\(id)#\(index)",
          a11yName: String(localized: "Reps"),
          a11yValue: String(localized: "\(reps[id]?[index] ?? 0) reps"),
          minus: { repsBinding(id, index).wrappedValue = max(0, (reps[id]?[index] ?? 0) - 1) },
          plus: { repsBinding(id, index).wrappedValue = (reps[id]?[index] ?? 0) + 1 })
          .frame(width: 112)
      }
      HStack(spacing: 8) {
        Text("RPE").forgeCaption()
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(stride(from: 6.0, through: 10.0, by: 0.5).map { $0 }, id: \.self) { rpe in
              let selected = (rpes[id]?[index] ?? 8) == rpe
              Button {
                rpeBinding(id, index).wrappedValue = rpe
              } label: {
                Text(Fmt.num(rpe))
                  .font(.forge(13, .semibold))
                  .monospacedDigit()
                  .foregroundStyle(selected ? Theme.onAccent : Theme.text)
                  .padding(.horizontal, 11)
                  .padding(.vertical, 7)
                  .background(Capsule().fill(selected ? Theme.accent : Theme.card))
                  .overlay(Capsule().strokeBorder(selected ? .clear : Theme.ring, lineWidth: 1))
                  .animation(.easeOut(duration: 0.15), value: selected)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("RPE \(Fmt.num(rpe))")
              .accessibilityAddTraits(selected ? .isSelected : [])
            }
          }
        }
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(SetVariant.allCases, id: \.self) { v in
            let selected = variant == v
            Button {
              variants[key(id, index)] = v
            } label: {
              Text(v.label)
                .font(.forge(13, .semibold))
                .foregroundStyle(selected ? Theme.onAccent : Theme.text)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Theme.accent : Theme.card))
                .overlay(Capsule().strokeBorder(selected ? .clear : Theme.ring, lineWidth: 1))
                .animation(.easeOut(duration: 0.15), value: selected)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(v.label)
            .accessibilityAddTraits(selected ? .isSelected : [])
          }
        }
      }
      if variant != .straight {
        Text(variant.hint).forgeCaption()
      }
      Button { log(planned, exercise, index) } label: {
        Label("Log set", systemImage: "checkmark")
      }
      .buttonStyle(PillButtonStyle(minHeight: 46))
      .accessibilityLabel("Log set \(index + 1) of \(sets(for: id)): \(spokenDisplayWeight(weights[id]?[index] ?? "", lb: lb)), \(reps[id]?[index] ?? 0) reps, RPE \(Fmt.num(rpes[id]?[index] ?? 8))")
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
    .overlay(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1.5))
  }

  private func valueChip(label: String, text: Binding<String>, keyboard: UIKeyboardType, focusKey: String, a11yName: String, a11yValue: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
    HStack(spacing: 4) {
      stepButton("minus", a11yLabel: String(localized: "Decrease \(a11yName)"), action: minus)
      VStack(spacing: 0) {
        TextField("0", text: text)
          .keyboardType(keyboard)
          .multilineTextAlignment(.center)
          .font(.forge(22, .bold))
          .monospacedDigit()
          .foregroundStyle(Theme.text)
          .focused($focused, equals: focusKey)
          .frame(minWidth: 48)
          .accessibilityLabel(a11yName)
        Text(label).forgeCaption()
      }
      stepButton("plus", a11yLabel: String(localized: "Increase \(a11yName)"), action: plus)
    }
    .padding(6)
    .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.card))
    .overlay(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(a11yName)
    .accessibilityValue(a11yValue)
  }

  private func stepButton(_ symbol: String, a11yLabel: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(Theme.text)
        .frame(width: 30, height: 30)
        .background(Circle().fill(Theme.track))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(a11yLabel)
  }

  // MARK: rest

  @ViewBuilder private var restBar: some View {
    if let end = restEnd {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let remaining = max(0, end.timeIntervalSince(context.date))
        VStack(spacing: 14) {
          Capsule().fill(Theme.track).frame(width: 36, height: 4)
          HStack(alignment: .center) {
            ZStack {
              RingView(progress: remaining / max(restTotal, 1), lineWidth: 4, color: Theme.metricTime)
              CoachAvatar(size: 28)
            }
            .frame(width: 44, height: 44)
            .breathing()
            .accessibilityHidden(true)
            Spacer()
            VStack(spacing: 0) {
              Text("REST").forgeOverline()
              MetricValue(value: String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60), size: 48, color: Theme.metricTime)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest")
            .accessibilityValue("\(Int(remaining) / 60) minutes \(Int(remaining) % 60) seconds left")
            Spacer()
            heartRateBadge
          }
          HStack(spacing: 24) {
            restCircle("−30") { adjustRest(-30) }
              .accessibilityLabel("Minus 30 seconds")
            Button { skipRest() } label: {
              Text("Skip").forge(17, .semibold).foregroundColor(Theme.onAccent)
                .frame(width: 88, height: 88)
                .background(Circle().fill(Theme.accent))
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel("Skip rest")
            restCircle("+30") { adjustRest(30) }
              .accessibilityLabel("Plus 30 seconds")
          }
          if let restExercise {
            Text("Next: \(restExercise.name) · set \(restNextSet) of \(restTotalSets)").forgeCaption()
          }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Theme.card).shadow(color: Theme.shadow, radius: 16, y: 6))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .transition(reduceMotion ? .forgeFade : .forgeSlideUp)
      }
    }
  }

  @ViewBuilder private var heartRateBadge: some View {
    if let hr = WatchSync.shared.heartRate {
      HStack(spacing: 4) {
        Image(systemName: "heart.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.metricHeart)
        MetricValue(value: "\(hr)", unit: "bpm", size: 15, color: Theme.metricHeart)
      }
      .frame(width: 64, alignment: .trailing)
      .accessibilityLabel("Heart rate \(hr)")
    } else {
      Color.clear.frame(width: 44, height: 44)
    }
  }

  private func restCircle(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).forge(15, .semibold).monospacedDigit().foregroundColor(Theme.text)
        .frame(width: 56, height: 56)
        .background(Circle().fill(Theme.track))
    }
    .buttonStyle(RowPressStyle())
  }

  private func skipRest() {
    cancelRestNotification()
    endRestActivity()
    hrTask?.cancel()
    withAnimation(.easeOut(duration: 0.15)) { restEnd = nil }
  }

  private func startHeartbeat() {
    heartbeatTask?.cancel()
    heartbeatTask = Task {
      while !Task.isCancelled {
        UserDefaults(suiteName: WidgetBridge.suite)?.set(Date.now.timeIntervalSince1970, forKey: "forge.workout.heartbeat")
        try? await Task.sleep(for: .seconds(30))
      }
    }
  }

  // ponytail: fixed 15 s poll — ≥3 bpm gate keeps Live Activity updates under the frequent-updates budget
  private func startHeartRateLoop() {
    hrTask?.cancel()
    hrTask = Task {
      var lastSent: Int?
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(15))
        guard !Task.isCancelled,
              let hr = WatchSync.shared.heartRate,
              abs(hr - (lastSent ?? hr - 3)) >= 3,
              let end = restEnd,
              let exercise = restExercise else { continue }
        lastSent = hr
        syncRestActivity(end: end, exercise: exercise, nextSet: restNextSet, totalSets: restTotalSets, heartRate: hr)
      }
    }
  }

  private func adjustRest(_ delta: Int) {
    restEnd = restEnd?.addingTimeInterval(TimeInterval(delta))
    restTotal = max(1, restTotal + TimeInterval(delta))
    if let id = currentExerciseID {
      profile?.restOverrides[id] = min(600, max(30, Int(restTotal)))
    }
    if let end = restEnd, let exercise = restExercise {
      scheduleRestNotification(seconds: Int(end.timeIntervalSinceNow), exercise: exercise, nextSet: restNextSet, totalSets: restTotalSets)
      syncRestActivity(end: end, exercise: exercise, nextSet: restNextSet, totalSets: restTotalSets, heartRate: WatchSync.shared.heartRate)
    }
  }

  private func scheduleRestNotification(seconds: Int, exercise: Exercise, nextSet: Int, totalSets: Int) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: ["forge.rest"])
    let content = UNMutableNotificationContent()
    content.title = "Rest over"
    content.body = nextSet <= totalSets ? "\(exercise.name) · set \(nextSet)" : "Next exercise"
    content.sound = .default
    center.add(UNNotificationRequest(
      identifier: "forge.rest",
      content: content,
      trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)))
  }

  private func cancelRestNotification() {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["forge.rest"])
  }

  private func syncRestActivity(end: Date, exercise: Exercise, nextSet: Int, totalSets: Int, heartRate: Int? = nil) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let state = RestActivityAttributes.ContentState(endDate: end, exerciseName: exercise.name, nextSet: nextSet, totalSets: totalSets, heartRate: heartRate, canLogNext: nextSet <= totalSets)
    let content = ActivityContent(state: state, staleDate: end.addingTimeInterval(60))
    if let restActivity {
      Task { await restActivity.update(content) }
    } else {
      restActivity = try? ActivityKit.Activity.request(attributes: RestActivityAttributes(dayName: plannedDay.name), content: content, pushType: nil)
    }
  }

  private func endRestActivity() {
    let activity = restActivity
    restActivity = nil
    Task { await activity?.end(nil, dismissalPolicy: .immediate) }
  }

  // MARK: finish

  private func finishTapped() {
    if loggedCount < totalSets {
      confirmFinish = true
    } else {
      finish()
    }
  }

  private func finish() {
    UserDefaults(suiteName: WidgetBridge.suite)?.set(false, forKey: "forge.workout.active")
    WatchSync.shared.endWatchWorkout()
    hrTask?.cancel()
    session?.completed = true
    session?.updatedAt = .now
    try? modelContext.save()
    if let profile {
      if let start = profile.deloadStartedAt {
        let done = allSessions.filter { $0.completed && $0.date >= start && $0 !== session }.count + 1
        if done >= profile.daysPerWeek {
          profile.mesoStart = .now
          profile.deloadStartedAt = nil
        }
      } else {
        let done = allSessions.filter { $0.completed && $0.date >= profile.mesoStart && $0 !== session }.count + 1
        if done >= Mesocycle.weeks * profile.daysPerWeek { profile.mesoStart = .now }
      }
    }
    profile?.nextDayIndex += 1
    profile?.updatedAt = .now
    finishedCount += 1
    if let start = session?.date { Task { await Health.saveWorkout(start: start, end: .now) } }
    cancelRestNotification()
    endRestActivity()
    withAnimation(.easeOut(duration: 0.15)) { restEnd = nil }
    prs = detectPRs()
    if let session {
      debrief = debriefLines(session: session, sessions: allSessions, prs: prs, profile: profile, usesLb: usesLb)
    }
    Analytics.track("workout_finished", [
      "sets": "\(session?.sets.count ?? 0)",
      "minutes": "\(Int(Date.now.timeIntervalSince(session?.date ?? .now) / 60))"])
    if !prs.isEmpty { Notifications.celebratePR(prs[0].exercise.name) }
    if let profile {
      let weekBefore = profile.currentWeek(sessions: allSessions.filter { $0 !== session })
      let weekAfter = profile.currentWeek(sessions: allSessions)
      if weekBefore != Mesocycle.deloadWeek && weekAfter == Mesocycle.deloadWeek {
        Notifications.notifyDeload(daysPerWeek: profile.daysPerWeek)
      }
      if weekBefore != weekAfter {
        let review = WeeklyReview(week: weekBefore, sessionsDone: profile.daysPerWeek, sessionsPlanned: profile.daysPerWeek, tonnageKg: 0, priorTonnageKg: nil, prs: [], nextWeekNote: "")
        Notifications.notifyWeekReview(week: weekBefore, headline: WeeklyReviewBuilder.headline(review, usesLb: profile.usesLb))
      }
      if let hour = profile.reminderHour {
        Notifications.scheduleDailyReminder(hour: hour, minute: profile.reminderMinute, body: nextReminderBody(profile))
      }
    }
    Notifications.scheduleReengagement(days: 3)
    Task { await SyncEngine.shared.sync() }
    summary = SessionSummary(
      date: session?.date ?? .now,
      dayName: plannedDay.name,
      duration: Date.now.timeIntervalSince(session?.date ?? .now),
      sets: session?.sets.count ?? 0,
      plannedSets: totalSets,
      exercises: Set(session?.sets.map(\.exerciseID) ?? []).count,
      tonnageKg: (session?.sets ?? []).reduce(0) { $0 + $1.weightKg * Double($1.reps) },
      notes: session?.notes ?? "",
      muscles: muscleVolumes)
    showSummary = true
  }

  private var muscleVolumes: [MuscleVolume] {
    var byMuscle: [Muscle: Int] = [:]
    for set in session?.sets ?? [] {
      if let exercise = ExerciseDB.find(set.exerciseID) {
        byMuscle[exercise.primary, default: 0] += 1
      }
    }
    return byMuscle
      .sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
      .map { MuscleVolume(muscle: $0.key, sets: $0.value) }
  }

  private func nextReminderBody(_ profile: UserProfile) -> String {
    let days = Program.week(profile.currentWeek(sessions: allSessions), profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: allSessions)))
    guard !days.isEmpty else { return String(localized: "Open Regulift for today's session.") }
    let day = days[profile.nextDayIndex % days.count]
    guard let compound = day.exercises.first(where: { $0.exercise.isCompound }) ?? day.exercises.first else {
      return String(localized: "Open Regulift for today's session.")
    }
    let kg = suggestedStartKg(for: compound, last: lastSets(compound.exercise.id, in: allSessions), profile: profile)
    let display = profile.usesLb ? Plates.kgToLb(kg) : kg
    return String(localized: "Next: \(day.name) · \(compound.exercise.name) \(Fmt.kg(display, lb: profile.usesLb)) · ≈ \(profile.sessionMinutes) min")
  }

  private func detectPRs() -> [PRRecord] {
    guard let session else { return [] }
    let prior = allSessions.filter { $0.completed && $0 !== session }
    return Set(session.sets.map(\.exerciseID)).compactMap { id -> PRRecord? in
      guard let exercise = ExerciseDB.find(id) else { return nil }
      let best = session.sets.filter { $0.exerciseID == id }
        .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max() ?? 0
      let previous = prior.flatMap(\.sets).filter { $0.exerciseID == id }
        .map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max()
      guard let previous, best > previous else { return nil }
      return PRRecord(exercise: exercise, e1rm: best, previous: previous)
    }
    .sorted { $0.exercise.name < $1.exercise.name }
  }
}

/// Pending set row with a swipe-left-to-log gesture; green checkmark reveals behind it.
private struct SwipeLogRow<Content: View>: View {
  let onSwipe: () -> Void
  @ViewBuilder var content: () -> Content
  @State private var offset: CGFloat = 0

  var body: some View {
    ZStack(alignment: .trailing) {
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
        .fill(Theme.positiveTint)
      Image(systemName: "checkmark")
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(Theme.positive)
        .padding(.trailing, 16)
      content()
        .offset(x: offset)
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
    .gesture(
      DragGesture(minimumDistance: 15)
        .onChanged { value in offset = min(0, value.translation.width) }
        .onEnded { value in
          if value.translation.width <= -80 {
            offset = 0
            onSwipe()
          } else {
            withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
          }
        })
  }
}

/// Shared starting-load suggestion used by the workout prefill and the Today plan card.
func suggestedStartKg(for planned: PlannedExercise, last: [LoggedSet], profile: UserProfile?) -> Double {
  let exercise = planned.exercise
  guard let lastSet = last.last else {
    if let starting = profile?.startingLoads[exercise.id] { return starting }
    return Strength.estimatedStartingLoad(exercise: exercise, bodyweightKg: profile?.bodyweightKg ?? 0)
  }
  let decision = Progression.nextLoad(currentKg: lastSet.weightKg, targetRPE: lastSet.targetRPE, actualRPE: lastSet.rpe)
  var kg: Double
  switch decision {
  case .increase(let k), .addReps(let k), .repeatLoad(let k), .decrease(let k, _): kg = k
  }
  let lastSetLogs = last.map { SetLog(weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe) }
  if Progression.shouldIncreaseLoad(sets: lastSetLogs, repRange: planned.repRange, targetRPE: planned.targetRPE) {
    kg += exercise.smallestIncrementKg
  }
  return Progression.round(kg, toIncrement: exercise.smallestIncrementKg)
}
