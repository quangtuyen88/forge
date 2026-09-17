import SwiftUI
import SwiftData
import ForgeCore

struct LiftBest: Identifiable {
  let exercise: Exercise
  let e1rm: Double
  let weightKg: Double
  let reps: Int
  let date: Date
  var id: String { exercise.id }
}

struct PRBoardView: View {
  let usesLb: Bool
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

  private enum Mode: Hashable { case all, muscle, equipment }
  @State private var mode: Mode = .all
  @State private var muscle: Muscle = .chest
  @State private var equipment: Equipment = .barbell

  private var lifts: [LiftBest] {
    var bests: [String: (e1rm: Double, date: Date, w: Double, r: Int)] = [:]
    for s in sessions where s.completed {
      for set in s.sets {
        let e = Strength.epley(weightKg: set.weightKg, reps: set.reps)
        var v = bests[set.exerciseID] ?? (e1rm: 0, date: s.date, w: 0, r: 0)
        if e > v.e1rm { v.e1rm = e; v.date = s.date }
        if set.weightKg > v.w || (set.weightKg == v.w && set.reps > v.r) {
          v.w = set.weightKg
          v.r = set.reps
        }
        bests[set.exerciseID] = v
      }
    }
    return bests.compactMap { id, v -> LiftBest? in
      guard let exercise = ExerciseDB.find(id) else { return nil }
      switch mode {
      case .all: break
      case .muscle: guard exercise.primary == muscle else { return nil }
      case .equipment: guard exercise.equipment == equipment else { return nil }
      }
      return LiftBest(exercise: exercise, e1rm: v.e1rm, weightKg: v.w, reps: v.r, date: v.date)
    }
    .sorted { $0.e1rm > $1.e1rm }
  }

  var body: some View {
    List {
      Section {
        Picker("Filter", selection: $mode) {
          Text("All").tag(Mode.all)
          Text("Muscle").tag(Mode.muscle)
          Text("Equipment").tag(Mode.equipment)
        }
        .pickerStyle(.segmented)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        switch mode {
        case .muscle:
          Picker("Muscle", selection: $muscle) {
            ForEach(Muscle.allCases, id: \.self) { m in
              Text(m.a11yName).tag(m)
            }
          }
        case .equipment:
          Picker("Equipment", selection: $equipment) {
            ForEach(Equipment.allCases, id: \.self) { e in
              Text(e.name).tag(e)
            }
          }
        case .all:
          EmptyView()
        }
      }
      Section {
        ForEach(lifts) { lift in
          HStack(spacing: 12) {
            EquipmentThumb(equipment: lift.exercise.equipment, size: 36)
            VStack(alignment: .leading, spacing: 2) {
              Text(lift.exercise.localizedName).forgeBodyStrong()
              Text("e1RM \(UnitFormat.weight(lift.e1rm, usesLb: usesLb)) · \(Int(UnitFormat.plain(lift.weightKg, usesLb: usesLb).rounded())) × \(lift.reps)")
                .forgeLabel()
                .monospacedDigit()
            }
            Spacer()
            Text(lift.date, format: .dateTime.month().day().year().locale(L10n.locale))
              .forgeCaption()
          }
        }
      }
    }
    .navigationTitle("PR board")
  }
}
