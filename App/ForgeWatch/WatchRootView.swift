import SwiftUI

struct WatchRootView: View {
  @Environment(WatchStore.self) private var store

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack {
            Text(store.dayName.isEmpty ? "Forge" : store.dayName).font(.headline)
            Spacer()
            Image(systemName: "heart.fill").foregroundStyle(.red)
            Text(store.heartRate.map { String(format: "%.0f", $0) } ?? "--")
              .monospacedDigit()
          }
          Button(store.hrOn ? "Stop" : "Start HR") {
            if store.hrOn {
              store.stopHR()
            } else {
              store.startHR()
            }
          }
        }
        if store.plan.isEmpty {
          Section {
            Text("Open Forge on iPhone")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        } else {
          Section {
            ForEach(store.plan) { exercise in
              NavigationLink {
                WatchExerciseView(exercise: exercise)
              } label: {
                HStack {
                  Text(exercise.name)
                  Spacer()
                  Text("\(exercise.sets) × \(exercise.repLow)–\(exercise.repHigh)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
    }
  }
}
