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
  @State private var showPlates = false
  @State private var focusedKg = 0.0

  private var profile: UserProfile? { profiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }
  private var unit: String { usesLb ? "lb" : "kg" }

  // ponytail: <3-tap logging = tap weight (prefilled), tap RPE, tap ✓; no custom keyboard yet.
  var body: some View {
    NavigationStack {
      List {
        if action != .proceed {
          Section { Text(actionNote).font(.footnote).foregroundStyle(.secondary) }
        }
        ForEach(plannedDay.exercises, id: \.exercise.id) { planned in
          Section("\(planned.exercise.name) · \(planned.sets) × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound) @ RPE \(planned.targetRPE, specifier: "%.0f") · rest \(planned.exercise.restSeconds)s") {
            ForEach(0..<planned.sets, id: \.self) { index in
              if let logged = loggedSet(planned.exercise.id, index) {
                Label("\(displayWeight(logged.weightKg)) \(unit) × \(logged.reps) @ RPE \(logged.rpe, specifier: "%.1f")", systemImage: "checkmark.circle.fill")
                  .foregroundStyle(.secondary)
              } else if weights[planned.exercise.id] != nil {
                setRow(planned, index)
              }
            }
          }
        }
      }
      .navigationTitle(plannedDay.name)
      .safeAreaInset(edge: .bottom) { restBar }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Plates") { showPlates = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Finish") { finish() }.bold()
        }
      }
      .sheet(isPresented: $showPlates) {
        PlatesSheet(kg: focusedKg, usesLb: usesLb)
      }
      .onAppear(perform: setup)
    }
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

  private func setRow(_ planned: PlannedExercise, _ index: Int) -> some View {
    let id = planned.exercise.id
    return VStack(alignment: .leading, spacing: 6) {
      if let ghost = ghostSet(id, index) {
        Text("Prev: \(displayWeight(ghost.weightKg)) \(unit) × \(ghost.reps) @ RPE \(ghost.rpe, specifier: "%.1f")")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      HStack {
        TextField("0", text: weightBinding(id, index))
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
          .frame(width: 70)
          .textFieldStyle(.roundedBorder)
        Text(unit).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Picker("RPE", selection: rpeBinding(id, index)) {
          ForEach(stride(from: 6.0, through: 10.0, by: 0.5).map { $0 }, id: \.self) { rpe in
            Text(rpe, format: .number.precision(.fractionLength(1))).tag(rpe)
          }
        }
        .pickerStyle(.menu)
        Button("✓") { log(planned, index) }
          .buttonStyle(.borderedProminent)
      }
      Stepper("Reps: \(reps[id]?[index] ?? 0)", value: repsBinding(id, index), in: 0...60)
    }
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

  private func log(_ planned: PlannedExercise, _ index: Int) {
    let id = planned.exercise.id
    let text = weights[id]?[index] ?? ""
    let value = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    let kg = usesLb ? Plates.lbToKg(value) : value
    focusedKg = kg
    let set = LoggedSet(
      exerciseID: id,
      setIndex: index,
      weightKg: kg,
      reps: reps[id]?[index] ?? 0,
      rpe: rpes[id]?[index] ?? 8,
      targetRPE: planned.targetRPE,
      loggedAt: .now)
    modelContext.insert(set)
    session?.sets.append(set)
    restEnd = Date.now.addingTimeInterval(TimeInterval(planned.exercise.restSeconds))
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
        let remaining = max(0, Int(end.timeIntervalSince(context.date)))
        HStack {
          Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
            .font(.title3.monospacedDigit().bold())
          Spacer()
          Button("−30s") { restEnd = end.addingTimeInterval(-30) }
          Button("+30s") { restEnd = end.addingTimeInterval(30) }
          Button("Skip") { restEnd = nil }.bold()
        }
        .padding()
        .background(.bar)
      }
    }
  }

  private func finish() {
    session?.completed = true
    profile?.nextDayIndex += 1
    dismiss()
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
