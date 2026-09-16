import SwiftUI
import WatchConnectivity

struct WatchRootView: View {
  @Environment(WatchStore.self) private var store

  private var planStale: Bool {
    guard let date = store.planDate else { return false }
    return Date.now.timeIntervalSince(date) > 20 * 3600
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(store.dayName.isEmpty ? "Regulift" : store.dayName).font(WatchTheme.font(17, .bold))
              if planStale, let date = store.planDate {
                Text("Plan from \(date.formatted(.relative(presentation: .named)))")
                  .font(WatchTheme.font(11))
                  .foregroundStyle(.secondary)
              }
            }
            Spacer()
            Image(systemName: "heart.fill").foregroundStyle(.red)
            Text(store.heartRate.map { String(format: "%.0f", $0) } ?? "--")
              .font(WatchTheme.font(15, .semibold))
              .monospacedDigit()
          }
          Button(store.hrOn ? String(localized: "End workout") : String(localized: "Start HR")) {
            if store.hrOn {
              store.endWorkout()
            } else {
              store.startHR()
            }
          }
          .font(WatchTheme.font(15, .semibold))
          if store.pending > 0 {
            Text("\(store.pending) sets waiting for iPhone")
              .font(WatchTheme.font(11))
              .foregroundStyle(.secondary)
          }
        }
        if store.plan.isEmpty {
          Section {
            Text("Open Regulift on iPhone")
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
      .task {
        if planStale, WCSession.default.isReachable {
          WCSession.default.sendMessage(["wantPlan": true], replyHandler: nil)
        }
      }
    }
  }
}
