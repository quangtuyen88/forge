import SwiftUI

struct WatchRootView: View {
  @Environment(WatchStore.self) private var store

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack {
            Text(store.dayName.isEmpty ? "Forge" : store.dayName).font(WatchTheme.font(17, .bold))
            Spacer()
            Image(systemName: "heart.fill").foregroundStyle(.red)
            Text(store.heartRate.map { String(format: "%.0f", $0) } ?? "--")
              .font(WatchTheme.font(15, .semibold))
              .monospacedDigit()
          }
          Button(store.hrOn ? "Stop" : "Start HR") {
            if store.hrOn {
              store.stopHR()
            } else {
              store.startHR()
            }
          }
          .font(WatchTheme.font(15, .semibold))
        }
        if store.plan.isEmpty {
          Section {
            Text("Open Forge on iPhone")
              .font(WatchTheme.font(13))
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
                    .font(WatchTheme.font(15, .semibold))
                  Spacer()
                  Text("\(exercise.sets) × \(exercise.repLow)–\(exercise.repHigh)")
                    .font(WatchTheme.font(12))
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
