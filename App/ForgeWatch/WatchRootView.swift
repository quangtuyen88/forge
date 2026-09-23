import SwiftUI
import WatchConnectivity

struct WatchRootView: View {
  @Environment(WatchStore.self) private var store

  private var planStale: Bool {
    guard let date = store.planDate else { return false }
    return Date.now.timeIntervalSince(date) > 20 * 3600
  }

  private func kgText(_ kg: Double) -> String {
    kg == kg.rounded() ? String(format: "%.0f", kg) : String(format: "%.1f", kg)
  }

  private func planLine(_ exercise: WatchExercise) -> String {
    let base = "\(exercise.sets) × \(exercise.repLow)–\(exercise.repHigh)"
    return exercise.suggestedKg.map { "\(base) · \(kgText($0)) kg" } ?? "\(base) · Choose load"
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
            Image(systemName: "heart.fill").foregroundStyle(WatchTheme.danger)
            if let hr = store.heartRate {
              Text(String(format: "%.0f", hr))
                .font(WatchTheme.font(20, .semibold))
                .monospacedDigit()
                .foregroundStyle(WatchTheme.danger)
            } else {
              Text("—")
                .font(WatchTheme.font(20, .semibold))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            }
          }
        }
        Section {
          NavigationLink {
            WatchCoachView()
          } label: {
            Label("Ask coach", systemImage: "bubble.left.fill")
              .font(WatchTheme.font(15, .semibold))
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
                  VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                      .font(WatchTheme.font(15, .semibold))
                    Text(planLine(exercise))
                      .font(WatchTheme.font(12))
                      .monospacedDigit()
                      .foregroundStyle(.secondary)
                  }
                  Spacer()
                  let loggedSets = store.logged.filter { $0.exerciseID == exercise.id }.count
                  HStack(spacing: 3) {
                    ForEach(0..<max(exercise.sets, 1), id: \.self) { i in
                      Circle()
                        .frame(width: 6, height: 6)
                        .foregroundStyle(i < loggedSets ? WatchTheme.sets : WatchTheme.fill)
                    }
                  }
                }
              }
            }
          }
        }
        Section {
          Button {
            if store.hrOn {
              store.endWorkout()
            } else {
              store.startHR()
            }
          } label: {
            Label(
              store.hrOn ? String(localized: "End workout") : String(localized: "Start HR"),
              systemImage: store.hrOn ? "xmark.circle.fill" : "heart.fill"
            )
            .font(WatchTheme.font(15, .semibold))
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .tint(WatchTheme.danger)
          if store.pending > 0 {
            Text("\(store.pending) sets waiting for iPhone")
              .font(WatchTheme.font(11))
              .foregroundStyle(.secondary)
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
