import SwiftUI
import WatchKit

struct WatchExerciseView: View {
  let exercise: WatchExercise
  @Environment(WatchStore.self) private var store
  @State private var weight: Double = 0
  @State private var reps: Int = 0
  @State private var rpe: Double = 8
  @State private var crownValue: Double = 0

  private var setIndex: Int {
    store.logged.filter { $0.exerciseID == exercise.id }.count
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 8) {
        Text("Set \(setIndex + 1) of \(exercise.sets)")
          .font(WatchTheme.font(17, .bold))
          .monospacedDigit()
        Stepper(value: $weight, in: 0...500, step: 2.5) {
          Text(String(format: "%.1f kg", weight)).font(WatchTheme.font(15, .semibold)).monospacedDigit()
        }
        .focusable()
        .digitalCrownRotation($crownValue, from: 0, through: 100, by: 0.5)
        .onChange(of: crownValue) { old, new in
          weight = min(500, max(0, weight + (new - old) * 5))
        }
        Stepper(value: $reps, in: 0...50) {
          Text("Reps \(reps)").font(WatchTheme.font(15, .semibold)).monospacedDigit()
        }
        Picker("RPE", selection: $rpe) {
          ForEach(stride(from: 6.0, through: 10.0, by: 0.5).map { $0 }, id: \.self) { value in
            Text(String(format: "%.1f", value)).font(WatchTheme.font(14)).tag(value)
          }
        }
        .pickerStyle(.wheel)
        Button {
          WKInterfaceDevice.current().play(.success)
          store.log(WatchSet(
            exerciseID: exercise.id,
            setIndex: setIndex,
            weightKg: weight,
            reps: reps,
            rpe: rpe,
            targetRPE: exercise.targetRPE,
            date: .now))
        } label: {
          Text("Log set").font(WatchTheme.font(15, .bold)).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchTheme.accent)
        if let end = store.restEnd {
          TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = end.timeIntervalSince(context.date)
            if remaining > 0 {
              VStack(spacing: 4) {
                Text(String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60))
                  .font(WatchTheme.font(28, .bold))
                  .monospacedDigit()
                Button("Skip") { store.restEnd = nil }
                  .font(WatchTheme.font(13, .semibold))
              }
            }
          }
        }
      }
      .padding(.horizontal, 4)
    }
    .navigationTitle(exercise.name)
    .onAppear {
      if weight == 0 { weight = (exercise.suggestedKg / 2.5).rounded() * 2.5 }
      if reps == 0 { reps = exercise.repLow }
    }
  }
}
