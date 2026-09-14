import SwiftUI
import SwiftData
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
  @State private var showPRs = false
  @State private var swaps: [String: Exercise] = [:]
  @State private var swapTarget: PlannedExercise?
  @State private var loggedSlots: Set<String> = []
  @State private var loggedCount = 0
  @State private var finishedCount = 0
  @FocusState private var focused: String?

  private var profile: UserProfile? { profiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }
  private var unit: String { usesLb ? "lb" : "kg" }
  private var equipment: Set<Equipment> {
    Set(profile?.equipment.compactMap { Equipment(rawValue: $0) } ?? [])
  }

  // ponytail: <3-tap logging = tap weight (prefilled), tap RPE, tap ✓; no custom keyboard yet.
  var body: some View {
    NavigationStack {
      List {
        if action != .proceed {
          Section { Text(actionNote).font(.footnote).foregroundStyle(.secondary) }
        }
        ForEach(plannedDay.exercises, id: \.exercise.id) { planned in
          let exercise = swaps[planned.exercise.id] ?? planned.exercise
          Section {
            captionRow
            ForEach(0..<planned.sets, id: \.self) { index in
              if let logged = loggedSet(exercise.id, index) {
                HStack(spacing: 8) {
                  Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                  Text("\(displayWeight(logged.weightKg)) \(unit) × \(logged.reps) @ RPE \(logged.rpe, specifier: "%.1f")")
                    .font(.subheadline)
                    .monospacedDigit()
                }
                .listRowBackground(Theme.accent.opacity(0.06))
              } else if weights[planned.exercise.id] != nil {
                setRow(planned, exercise, index)
              }
            }
          } header: {
            exerciseHeader(planned, exercise)
          }
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle(plannedDay.name)
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom) { restBar }
      .sensoryFeedback(.success, trigger: loggedCount)
      .sensoryFeedback(.success, trigger: finishedCount)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button { showPlates = true } label: { Label("Plates", systemImage: "circle.grid.2x2") }
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
      .sheet(isPresented: $showPRs) {
        PRSheet(prs: prs, usesLb: usesLb) { dismiss() }
      }
      .onAppear(perform: setup)
    }
  }

  @ViewBuilder
  private func exerciseHeader(_ planned: PlannedExercise, _ exercise: Exercise) -> some View {
    if loggedSlots.contains(planned.exercise.id) {
      headerRow(planned, exercise)
    } else {
      headerRow(planned, exercise).contextMenu {
        Button { swapTarget = planned } label: {
          Label("Swap exercise", systemImage: "arrow.2.squarepath")
        }
      }
    }
  }

  private func headerRow(_ planned: PlannedExercise, _ exercise: Exercise) -> some View {
    HStack {
      Text(exercise.name).font(.headline)
      Spacer()
      Text("\(planned.sets) × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound)")
        .font(.caption).monospacedDigit()
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color(.tertiarySystemFill), in: Capsule())
      Text("RPE \(planned.targetRPE, specifier: "%.0f")")
        .font(.caption).monospacedDigit()
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }
    .textCase(nil)
    .contentShape(Rectangle())
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
    let newSession = WorkoutSession(date: .now, dayName: plannedDay.name, week: profile.currentWeek, completed: false)
    modelContext.insert(newSession)
    session = newSession
    for planned in plannedDay.exercises {
      let id = planned.exercise.id
      let suggestion = suggestedKg(planned)
      if focusedKg == 0 { focusedKg = suggestion }
      weights[id] = (0..<planned.sets).map { _ in formatDisplay(suggestion) }
      reps[id] = (0..<planned.sets).map { _ in planned.repRange.lowerBound }
      rpes[id] = (0..<planned.sets).map { _ in 8.0 }
    }
  }

  private var captionRow: some View {
    HStack(spacing: 8) {
      Color.clear.frame(width: 22)
      Text(unit).frame(width: 64)
      Text("reps").frame(width: 48)
      Text("RPE").frame(width: 56)
      Spacer(minLength: 0)
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    .listRowSeparator(.hidden)
  }

  private func setRow(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int) -> some View {
    let id = planned.exercise.id
    return VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 8) {
        Text("\(index + 1)")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .frame(width: 22, height: 22)
          .background(Circle().fill(Color(.tertiarySystemFill)))
        TextField("0", text: weightBinding(id, index))
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.center)
          .monospacedDigit()
          .frame(width: 64)
          .textFieldStyle(.roundedBorder)
          .focused($focused, equals: "w#\(id)#\(index)")
        TextField("reps", value: repsBinding(id, index), format: .number)
          .keyboardType(.numberPad)
          .multilineTextAlignment(.center)
          .monospacedDigit()
          .frame(width: 48)
          .textFieldStyle(.roundedBorder)
          .focused($focused, equals: "r#\(id)#\(index)")
        Menu {
          ForEach(stride(from: 6.0, through: 10.0, by: 0.5).map { $0 }, id: \.self) { rpe in
            Button(String(format: "%.1f", rpe)) { rpeBinding(id, index).wrappedValue = rpe }
          }
        } label: {
          Text(String(format: "%.1f", rpes[id]?[index] ?? 8))
            .monospacedDigit()
            .font(.subheadline)
            .padding(.vertical, 6)
            .frame(width: 56)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
        }
        Spacer(minLength: 0)
        Button { log(planned, exercise, index) } label: {
          Image(systemName: "checkmark").font(.body.bold())
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .frame(width: 36, height: 36)
      }
      if let ghost = ghostSet(exercise.id, index) {
        Text("Last: \(displayWeight(ghost.weightKg)) \(unit) × \(ghost.reps) @ \(ghost.rpe, specifier: "%.1f")")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
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

  private func restSeconds(for exercise: Exercise) -> Int {
    guard let profile else { return exercise.restSeconds }
    return exercise.isCompound ? profile.restCompoundSeconds : profile.restIsolationSeconds
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
    loggedCount += 1
    let seconds = restSeconds(for: exercise)
    withAnimation(.snappy) {
      restTotal = TimeInterval(seconds)
      restEnd = Date.now.addingTimeInterval(TimeInterval(seconds))
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

  private func lastSets(_ exerciseID: String) -> [LoggedSet] {
    for s in allSessions.filter(\.completed).sorted(by: { $0.date > $1.date }) {
      let sets = s.sets.filter { $0.exerciseID == exerciseID }.sorted { $0.setIndex < $1.setIndex }
      if !sets.isEmpty { return sets }
    }
    return []
  }

  private func suggestedKg(_ planned: PlannedExercise) -> Double {
    let exercise = planned.exercise
    let last = lastSets(exercise.id)
    guard let lastSet = last.last else { return profile?.startingLoads[exercise.id] ?? 0 }
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

  private func displayWeight(_ kg: Double) -> String {
    formatDisplay(usesLb ? Plates.kgToLb(kg) : kg)
  }

  private func formatDisplay(_ value: Double) -> String {
    String(format: "%.1f", value)
  }

  @ViewBuilder private var restBar: some View {
    if let end = restEnd {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let remaining = max(0, end.timeIntervalSince(context.date))
        VStack(spacing: 8) {
          ProgressView(value: remaining, total: max(restTotal, 1))
            .tint(Theme.accent)
          HStack {
            Text(String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60))
              .font(.title2).bold().monospacedDigit()
            Spacer()
            Button("−30 s") { adjustRest(-30) }
              .buttonStyle(.bordered).buttonBorderShape(.capsule)
            Button("+30 s") { adjustRest(30) }
              .buttonStyle(.bordered).buttonBorderShape(.capsule)
            Button("Skip") { withAnimation(.snappy) { restEnd = nil } }
              .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
          }
        }
        .padding(16)
        .background(.bar)
      }
    }
  }

  private func adjustRest(_ delta: Int) {
    restEnd = restEnd?.addingTimeInterval(TimeInterval(delta))
    restTotal = max(1, restTotal + TimeInterval(delta))
  }

  private func finish() {
    session?.completed = true
    profile?.nextDayIndex += 1
    finishedCount += 1
    if let start = session?.date { Task { await Health.saveWorkout(start: start, end: .now) } }
    prs = detectPRs()
    if prs.isEmpty { dismiss() } else { showPRs = true }
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
            Text(exercise.name).foregroundStyle(.primary)
            Text(exercise.equipment.rawValue.capitalized)
              .font(.footnote).foregroundStyle(.secondary)
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
    NavigationStack {
      List {
        let target = usesLb ? Plates.kgToLb(kg) : kg
        let bar = usesLb ? 45.0 : 20.0
        let available = usesLb ? Plates.defaultLb : Plates.defaultKg
        Section {
          Text(String(format: "Target: %.1f %@ (bar %.0f)", target, usesLb ? "lb" : "kg", bar))
        } header: {
          Text(usesLb ? "Bar: 45 lb" : "Bar: 20 kg")
        }
        Section("Per side") {
          if let plates = Plates.perSide(target: target, bar: bar, available: available) {
            if plates.isEmpty {
              Text("Bar only")
            } else {
              ForEach(Array(plates.enumerated()), id: \.offset) { _, plate in
                Text(String(format: "%.2f %@", plate, usesLb ? "lb" : "kg"))
              }
            }
          } else {
            Text("Not loadable with these plates")
          }
        }
      }
      .navigationTitle("Plates")
      .toolbar { Button("Done") { dismiss() } }
      .presentationDetents([.medium])
    }
  }
}
