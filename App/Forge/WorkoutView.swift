import SwiftUI
import SwiftData
import UserNotifications
import ForgeCore

struct WorkoutView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var allSessions: [WorkoutSession]

  let plannedDay: PlannedDay
  let action: FatigueAction

  @State private var session: WorkoutSession?
  @State private var weights: [String: [String]] = [:]
  @State private var reps: [String: [Int]] = [:]
  @State private var rpes: [String: [Double]] = [:]
  @State private var restEnd: Date?
  @State private var restTotal: TimeInterval = 0
  @State private var showPlates = false
  @State private var focusedKg = 0.0
  @State private var prs: [PRRecord] = []
  @State private var showSummary = false
  @State private var summary: SessionSummary?
  @State private var restExercise: Exercise?
  @State private var restNextSet = 0
  @State private var restTotalSets = 0
  @State private var swaps: [String: Exercise] = [:]
  @State private var swapTarget: PlannedExercise?
  @State private var loggedSlots: Set<String> = []
  @State private var currentExerciseID: String?
  @State private var loggedCount = 0
  @State private var finishedCount = 0
  @State private var activeSlot: String?
  @FocusState private var focused: String?

  private var profile: UserProfile? { profiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }
  private var unit: String { usesLb ? "lb" : "kg" }
  private var equipment: Set<Equipment> {
    Set(profile?.equipment.compactMap { Equipment(rawValue: $0) } ?? [])
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Theme.groupGap) {
          header
          if action != .proceed {
            fatigueNote
          }
          ForEach(plannedDay.exercises, id: \.exercise.id) { planned in
            let exercise = swaps[planned.exercise.id] ?? planned.exercise
            exerciseCard(planned, exercise)
          }
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
          Button { showPlates = true } label: { Image(systemName: "circle.grid.2x2") }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Finish workout") { finish() }.bold()
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { focused = nil }
        }
      }
      .sheet(isPresented: $showPlates) {
        PlatesSheet(kg: focusedKg, usesLb: usesLb)
      }
      .sheet(item: $swapTarget) { planned in
        let current = swaps[planned.exercise.id] ?? planned.exercise
        SwapSheet(current: current, equipment: equipment) { replacement in
          swaps[planned.exercise.id] = replacement
        }
      }
      .sheet(isPresented: $showSummary, onDismiss: { dismiss() }) {
        if let summary {
          SessionSummaryView(summary: summary, prs: prs, usesLb: usesLb) { showSummary = false }
            .interactiveDismissDisabled()
        }
      }
      .onAppear(perform: setup)
      .onDisappear { cancelRestNotification() }
    }
    .background(Theme.page)
  }

  private var header: some View {
    VStack(spacing: 12) {
      progressBar
      HStack(spacing: 10) {
        elapsedTile
        StatTile(symbol: "square.stack.3d.up.fill", value: "\(loggedCount)/\(totalSets)", label: "sets")
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
    plannedDay.exercises.reduce(0) { $0 + $1.sets }
  }

  private var elapsedTile: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      StatTile(symbol: "stopwatch", value: elapsedText(at: context.date), label: "elapsed")
    }
  }

  private func elapsedText(at now: Date) -> String {
    guard let start = session?.date else { return "0:00" }
    let s = max(0, Int(now.timeIntervalSince(start)))
    return String(format: "%d:%02d", s / 60, s % 60)
  }

  private var currentMuscleThumb: some View {
    MuscleMapView(intensity: currentMuscle.map { [$0: 1] } ?? [:])
      .frame(width: 72, height: 56, alignment: .top)
      .clipped()
      .allowsHitTesting(false)
      .frame(maxWidth: .infinity, minHeight: 88)
      .card(padding: 10)
  }

  private var currentMuscle: Muscle? {
    if let currentExerciseID,
       let planned = plannedDay.exercises.first(where: { $0.exercise.id == currentExerciseID }) {
      return planned.exercise.primary
    }
    return plannedDay.exercises.first?.exercise.primary
  }

  private var actionNote: String {
    switch action {
    case .reduceOptionalSets: return "Fatigue is elevated — optional sets trimmed."
    case .lightSession: return "Light session — volume reduced, RPE capped at 7."
    case .forceRest: return "High fatigue — keep today conservative."
    default: return ""
    }
  }

  private func setup() {
    guard session == nil, let profile else { return }
    let newSession = WorkoutSession(date: .now, dayName: plannedDay.name, week: profile.currentWeek(sessions: allSessions), completed: false)
    modelContext.insert(newSession)
    session = newSession
    var suggestedKgByID: [String: Double] = [:]
    var restByID: [String: Int] = [:]
    for planned in plannedDay.exercises {
      let id = planned.exercise.id
      let suggestion = suggestedKg(planned)
      if focusedKg == 0 { focusedKg = suggestion }
      weights[id] = (0..<planned.sets).map { _ in formatDisplay(suggestion) }
      reps[id] = (0..<planned.sets).map { _ in planned.repRange.lowerBound }
      rpes[id] = (0..<planned.sets).map { _ in 8.0 }
      suggestedKgByID[id] = suggestion
      restByID[id] = restSeconds(for: planned.exercise)
    }
    WatchSync.shared.sendPlan(plannedDay, suggested: { suggestedKgByID[$0.id] ?? 0 }, rest: { restByID[$0.id] ?? 0 }, dayName: plannedDay.name)
    activeSlot = firstPendingSlot()
  }

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

  private func stepWeight(_ id: String, _ index: Int, _ direction: Double) {
    let planned = plannedDay.exercises.first { $0.exercise.id == id }
    let exercise = swaps[id] ?? planned?.exercise
    let step = usesLb ? 2.5 : (exercise?.smallestIncrementKg ?? 2.5)
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
    let text = weights[id]?[index] ?? ""
    let value = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    let kg = usesLb ? Plates.lbToKg(value) : value
    focusedKg = kg
    let set = LoggedSet(
      exerciseID: exercise.id,
      setIndex: index,
      weightKg: kg,
      reps: reps[id]?[index] ?? 0,
      rpe: rpes[id]?[index] ?? 8,
      targetRPE: planned.targetRPE,
      loggedAt: .now)
    modelContext.insert(set)
    session?.sets.append(set)
    loggedSlots.insert(planned.exercise.id)
    currentExerciseID = exercise.id
    loggedCount += 1
    let seconds = restSeconds(for: exercise)
    withAnimation(.snappy) {
      restTotal = TimeInterval(seconds)
      restEnd = Date.now.addingTimeInterval(TimeInterval(seconds))
      activeSlot = firstPendingSlot()
      focused = nil
    }
    restExercise = exercise
    restNextSet = index + 2
    restTotalSets = planned.sets
    scheduleRestNotification(seconds: seconds, exercise: exercise, nextSet: index + 2, totalSets: planned.sets)
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

  private func displayWeight(_ kg: Double) -> String {
    formatDisplay(usesLb ? Plates.kgToLb(kg) : kg)
  }

  private func formatDisplay(_ value: Double) -> String {
    String(format: "%.1f", value)
  }

  private func mmss(_ s: Int) -> String {
    String(format: "%d:%02d", s / 60, s % 60)
  }

  private func key(_ id: String, _ i: Int) -> String { "\(id)#\(i)" }

  private func firstPendingSlot() -> String? {
    for planned in plannedDay.exercises {
      let exercise = swaps[planned.exercise.id] ?? planned.exercise
      for index in 0..<planned.sets where loggedSet(exercise.id, index) == nil {
        return key(planned.exercise.id, index)
      }
    }
    return nil
  }

  private func exerciseCard(_ planned: PlannedExercise, _ exercise: Exercise) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        EquipmentThumb(equipment: exercise.equipment, size: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(exercise.name).forgeSection()
          Text("\(planned.sets) × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound) · RPE \(planned.targetRPE, specifier: "%.0f") · rest \(mmss(restSeconds(for: exercise)))")
            .forgeLabel()
            .monospacedDigit()
        }
        Spacer()
        if !loggedSlots.contains(planned.exercise.id) {
          IconCircleButton(symbol: "arrow.2.squarepath") { swapTarget = planned }
        }
      }
      VStack(spacing: 8) {
        ForEach(0..<planned.sets, id: \.self) { index in
          setSlot(planned, exercise, index)
        }
      }
    }
    .card(padding: 14)
  }

  @ViewBuilder
  private func setSlot(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int) -> some View {
    let id = planned.exercise.id
    if let logged = loggedSet(exercise.id, index) {
      loggedRow(logged)
    } else if activeSlot == key(id, index) {
      setEditor(planned, exercise, index)
    } else {
      pendingRow(planned, exercise, index)
    }
  }

  private func loggedRow(_ logged: LoggedSet) -> some View {
    HStack(spacing: 10) {
      ZStack {
        Circle().fill(Theme.accent)
        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
      }
      .frame(width: 24, height: 24)
      Text("\(displayWeight(logged.weightKg)) \(unit) × \(logged.reps)")
        .forgeBodyStrong()
        .monospacedDigit()
      Spacer()
      Text("RPE \(logged.rpe, specifier: "%.1f")")
        .forgeCaption()
        .monospacedDigit()
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.accent.opacity(0.08)))
  }

  private func pendingRow(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int) -> some View {
    let id = planned.exercise.id
    return Button {
      withAnimation(.snappy) { activeSlot = key(id, index) }
    } label: {
      HStack(spacing: 10) {
        ZStack {
          Circle().fill(Theme.track)
          Text("\(index + 1)").forgeCaption()
        }
        .frame(width: 24, height: 24)
        Text("\(weights[id]?[index] ?? "") \(unit) × \(reps[id]?[index] ?? 0)")
          .forgeBody()
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Theme.textTertiary)
      }
      .innerSurface(padding: 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func setEditor(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int) -> some View {
    let id = planned.exercise.id
    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Set \(index + 1) of \(planned.sets)").forgeLabel()
        Spacer()
        if let ghost = ghostSet(exercise.id, index) {
          Text("Last \(displayWeight(ghost.weightKg)) × \(ghost.reps) @ \(ghost.rpe, specifier: "%.1f")")
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
          minus: { stepWeight(id, index, -1) },
          plus: { stepWeight(id, index, 1) })
          .frame(maxWidth: .infinity)
        valueChip(
          label: "reps",
          text: repsText(id, index),
          keyboard: .numberPad,
          focusKey: "r#\(id)#\(index)",
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
                Text(String(format: "%g", rpe))
                  .font(.forge(13, .semibold))
                  .monospacedDigit()
                  .foregroundStyle(selected ? .white : Theme.text)
                  .padding(.horizontal, 11)
                  .padding(.vertical, 7)
                  .background(Capsule().fill(selected ? Theme.accent : Theme.card))
                  .overlay(Capsule().strokeBorder(selected ? .clear : Theme.ring, lineWidth: 1))
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      Button { log(planned, exercise, index) } label: {
        Label("Log set", systemImage: "checkmark")
      }
      .buttonStyle(PillButtonStyle(minHeight: 46))
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
    .overlay(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1.5))
  }

  private func valueChip(label: String, text: Binding<String>, keyboard: UIKeyboardType, focusKey: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
    HStack(spacing: 4) {
      stepButton("minus", action: minus)
      VStack(spacing: 0) {
        TextField("0", text: text)
          .keyboardType(keyboard)
          .multilineTextAlignment(.center)
          .font(.forge(22, .bold))
          .monospacedDigit()
          .foregroundStyle(Theme.text)
          .focused($focused, equals: focusKey)
          .frame(minWidth: 48)
        Text(label).forgeCaption()
      }
      stepButton("plus", action: plus)
    }
    .padding(6)
    .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.card))
    .overlay(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1))
  }

  private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(Theme.text)
        .frame(width: 30, height: 30)
        .background(Circle().fill(Theme.track))
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder private var restBar: some View {
    if let end = restEnd {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let remaining = max(0, end.timeIntervalSince(context.date))
        HStack(spacing: 12) {
          ZStack {
            Circle().stroke(Theme.track, lineWidth: 4)
            Circle().trim(from: 0, to: remaining / max(restTotal, 1))
              .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
              .rotationEffect(.degrees(-90))
            CoachAvatar(size: 36)
          }
          .frame(width: 48, height: 48)
          VStack(alignment: .leading, spacing: 0) {
            Text("Rest").forgeCaption()
            Text(String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60)).forgeNumber()
          }
          Spacer()
          smallChip("−30 s") { adjustRest(-30) }
          smallChip("+30 s") { adjustRest(30) }
          Button {
            cancelRestNotification()
            withAnimation(.snappy) { restEnd = nil }
          } label: {
            Text("Skip")
              .font(.forge(13, .semibold))
              .foregroundStyle(.white)
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .background(Capsule().fill(Theme.accent))
          }
          .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.card).shadow(color: Theme.shadow, radius: 16, y: 6))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1))
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
  }

  private func smallChip(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.forge(13, .medium))
        .monospacedDigit()
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(Theme.track))
    }
    .buttonStyle(.plain)
  }

  private func adjustRest(_ delta: Int) {
    restEnd = restEnd?.addingTimeInterval(TimeInterval(delta))
    restTotal = max(1, restTotal + TimeInterval(delta))
    if let id = currentExerciseID {
      profile?.restOverrides[id] = min(600, max(30, Int(restTotal)))
    }
    if let end = restEnd, let exercise = restExercise {
      scheduleRestNotification(seconds: Int(end.timeIntervalSinceNow), exercise: exercise, nextSet: restNextSet, totalSets: restTotalSets)
    }
  }

  private func scheduleRestNotification(seconds: Int, exercise: Exercise, nextSet: Int, totalSets: Int) {
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
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

  private func finish() {
    session?.completed = true
    if let profile {
      let done = allSessions.filter { $0.completed && $0.date >= profile.mesoStart && $0 !== session }.count + 1
      if done >= Mesocycle.weeks * profile.daysPerWeek { profile.mesoStart = .now }
    }
    profile?.nextDayIndex += 1
    finishedCount += 1
    if let start = session?.date { Task { await Health.saveWorkout(start: start, end: .now) } }
    cancelRestNotification()
    withAnimation(.snappy) { restEnd = nil }
    prs = detectPRs()
    summary = SessionSummary(
      dayName: plannedDay.name,
      duration: Date.now.timeIntervalSince(session?.date ?? .now),
      sets: session?.sets.count ?? 0,
      exercises: Set(session?.sets.map(\.exerciseID) ?? []).count,
      tonnageKg: (session?.sets ?? []).reduce(0) { $0 + $1.weightKg * Double($1.reps) })
    showSummary = true
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

extension PlannedExercise: Identifiable {
  public var id: String { exercise.id }
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

private struct SwapSheet: View {
  @Environment(\.dismiss) private var dismiss
  let current: Exercise
  let equipment: Set<Equipment>
  let pick: (Exercise) -> Void
  @State private var query = ""

  private var pool: [Exercise] {
    ExerciseDB.all.filter { $0.primary == current.primary && equipment.contains($0.equipment) && $0.id != current.id }
  }

  private var filtered: [Exercise] {
    query.isEmpty ? pool : pool.filter { $0.name.localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    NavigationStack {
      List(filtered) { exercise in
        Button {
          pick(exercise)
          dismiss()
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name).foregroundStyle(.primary).forgeBodyStrong()
            Text(exercise.equipment.rawValue.capitalized)
              .foregroundStyle(Theme.textSecondary).forgeCaption()
          }
        }
      }
      .searchable(text: $query)
      .navigationTitle("Swap exercise")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Cancel") { dismiss() } }
    }
  }
}

private struct PlatesSheet: View {
  @Environment(\.dismiss) private var dismiss
  let kg: Double
  let usesLb: Bool

  var body: some View {
    let target = usesLb ? Plates.kgToLb(kg) : kg
    let bar = usesLb ? 45.0 : 20.0
    let available = usesLb ? Plates.defaultLb : Plates.defaultKg
    let plates = Plates.perSide(target: target, bar: bar, available: available)
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.groupGap) {
          VStack(alignment: .leading, spacing: 12) {
            Text("Per side").forgeSection()
            Text(String(format: "Target %.1f %@ · bar %.0f", target, usesLb ? "lb" : "kg", bar))
              .forgeLabel()
              .monospacedDigit()
            if let plates {
              if plates.isEmpty {
                Text("Bar only").forgeLabel()
              } else {
                barDrawing(plates, available: available)
              }
            } else {
              Text("Not loadable with these plates").forgeLabel()
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
          VStack(alignment: .leading, spacing: 12) {
            Text("Plates").forgeSection()
            // ponytail: LazyVGrid instead of a flow Layout — chips equalize width per row
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], alignment: .leading, spacing: 8) {
              ForEach(available, id: \.self) { plate in
                Text(plateLabel(plate))
                  .forge(13, .medium)
                  .monospacedDigit()
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 8)
                  .background(Capsule().fill(Theme.track))
              }
            }
          }
          .card()
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
      }
      .background(Theme.page)
      .navigationTitle("Plates")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Done") { dismiss() } }
    }
    .presentationDetents([.medium])
    .presentationBackground(Theme.page)
  }

  private func plateLabel(_ plate: Double) -> String {
    plate.formatted()
  }

  private func barDrawing(_ plates: [Double], available: [Double]) -> some View {
    let maxPlate = available.first ?? 1
    return HStack(alignment: .center, spacing: 3) {
      Capsule().fill(Theme.textSecondary).frame(width: 44, height: 8)
      ForEach(Array(plates.enumerated()), id: \.offset) { _, plate in
        let fraction = plate / maxPlate
        VStack(spacing: 4) {
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Theme.ramp[min(4, max(1, Int(fraction * 3.99) + 1))])
            .frame(width: 12 + 12 * fraction, height: 36 + 64 * fraction)
          Text(plateLabel(plate))
            .forgeCaption()
            .monospacedDigit()
        }
      }
      Capsule().fill(Theme.textSecondary).frame(width: 18, height: 8)
    }
    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
  }
}
