import SwiftUI
import SwiftData
import ForgeCore

struct OnboardingView: View {
  @Environment(\.modelContext) private var modelContext

  @State private var goal: Goal = .hypertrophy
  @State private var experience: Experience = .intermediate
  @State private var daysPerWeek = 3
  @State private var sessionLength: SessionLength = .m60
  @State private var equipment: Set<Equipment> = [.barbell, .dumbbell, .machine, .cable]
  @State private var usesLb = false
  @State private var bodyweightText = ""
  @State private var lifts: [String: String] = [:]
  @State private var injuries: Set<InjuryFlag> = []
  @State private var recoveryReduced = false

  private let liftIDs = ["barbell_bench", "back_squat", "deadlift", "overhead_press", "bent_row"]

  private var bodyweightKg: Double {
    guard let v = number(bodyweightText) else { return 0 }
    return usesLb ? Plates.lbToKg(v) : v
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Goal") {
          Picker("Goal", selection: $goal) {
            ForEach(Goal.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
          }
          .pickerStyle(.segmented)
        }
        Section("Experience") {
          Picker("Experience", selection: $experience) {
            ForEach(Experience.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
          }
          .pickerStyle(.segmented)
        }
        Section("Schedule") {
          Stepper("Days per week: \(daysPerWeek)", value: $daysPerWeek, in: 3...6)
          Picker("Session length", selection: $sessionLength) {
            ForEach(SessionLength.allCases, id: \.self) { Text("\($0.rawValue) min").tag($0) }
          }
          .pickerStyle(.segmented)
        }
        Section("Equipment") {
          ForEach(Equipment.allCases, id: \.self) { item in
            Toggle(item.rawValue.capitalized, isOn: equipmentBinding(item))
          }
        }
        Section("Units & bodyweight") {
          Toggle("Use pounds", isOn: $usesLb)
          TextField(usesLb ? "Bodyweight (lb)" : "Bodyweight (kg)", text: $bodyweightText)
            .keyboardType(.decimalPad)
        }
        Section("Current lifts (optional)") {
          ForEach(liftIDs, id: \.self) { id in
            TextField(liftName(id), text: liftBinding(id))
              .keyboardType(.decimalPad)
          }
        }
        Section("Injuries") {
          ForEach(InjuryFlag.allCases, id: \.self) { flag in
            Toggle(flag.rawValue.capitalized, isOn: injuryBinding(flag))
          }
        }
        Section("Recovery") {
          Toggle("I sleep < 6 h or life stress is high", isOn: $recoveryReduced)
        }
        Section {
          Button("Continue") { save() }
            .frame(maxWidth: .infinity)
            .disabled(bodyweightKg <= 0)
        }
      }
      .navigationTitle("Onboarding")
    }
  }

  private func equipmentBinding(_ item: Equipment) -> Binding<Bool> {
    Binding(
      get: { equipment.contains(item) },
      set: { on in
        if on { equipment.insert(item) } else { equipment.remove(item) }
      })
  }

  private func injuryBinding(_ flag: InjuryFlag) -> Binding<Bool> {
    Binding(
      get: { injuries.contains(flag) },
      set: { on in
        if on { injuries.insert(flag) } else { injuries.remove(flag) }
      })
  }

  private func liftBinding(_ id: String) -> Binding<String> {
    Binding(
      get: { lifts[id] ?? "" },
      set: { lifts[id] = $0 })
  }

  private func liftName(_ id: String) -> String {
    let name = ExerciseDB.find(id)?.name ?? id
    return "\(name) (\(usesLb ? "lb" : "kg"))"
  }

  private func number(_ text: String) -> Double? {
    Double(text.replacingOccurrences(of: ",", with: "."))
  }

  private func save() {
    var starting: [String: Double] = [:]
    for id in liftIDs {
      if let entered = number(lifts[id] ?? "") {
        starting[id] = usesLb ? Plates.lbToKg(entered) : entered
      } else if let estimate = Strength.estimatedStartingLoad(exerciseID: id, bodyweightKg: bodyweightKg) {
        starting[id] = estimate
      }
    }
    modelContext.insert(UserProfile(
      goal: goal,
      experience: experience,
      daysPerWeek: daysPerWeek,
      sessionMinutes: sessionLength.rawValue,
      equipment: equipment,
      injuryFlags: injuries,
      recoveryReduced: recoveryReduced,
      bodyweightKg: bodyweightKg,
      usesLb: usesLb,
      startingLoads: starting))
  }
}
