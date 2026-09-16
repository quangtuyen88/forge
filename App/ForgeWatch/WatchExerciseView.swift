import SwiftUI
import WatchKit

struct WatchExerciseView: View {
  let exercise: WatchExercise
  @Environment(WatchStore.self) private var store
  @State private var weight: Double = 0
  @State private var reps: Int = 0
  @State private var rpe: Double = 8
  @State private var crownValue: Double = 0
  @State private var restFired: Date?

  private var setIndex: Int {
    store.logged.filter { $0.exerciseID == exercise.id }.count
  }

  private var weightText: String {
    weight == weight.rounded() ? String(format: "%.0f", weight) : String(format: "%.1f", weight)
  }

  var body: some View {
    ScrollView {
      if let end = store.restEnd, end > .now {
        restView(end)
      } else {
        setView
      }
    }
    .navigationTitle(exercise.name)
    .onAppear {
      if weight == 0 { weight = (exercise.suggestedKg / 2.5).rounded() * 2.5 }
      if reps == 0 { reps = exercise.repLow }
    }
  }

  private var setView: some View {
    VStack(spacing: 6) {
      Text("Set \(setIndex + 1) of \(exercise.sets)")
        .font(WatchTheme.font(13, .semibold))
        .monospacedDigit()
        .foregroundStyle(.secondary)

      HStack {
        roundButton("minus") { weight = max(0, weight - 2.5) }
        Spacer()
        VStack(spacing: -2) {
          Text(weightText)
            .font(WatchTheme.font(34, .bold))
            .monospacedDigit()
            .foregroundStyle(WatchTheme.accent)
          Text("KG")
            .font(WatchTheme.font(11, .semibold))
            .foregroundStyle(.secondary)
        }
        Spacer()
        roundButton("plus") { weight = min(500, weight + 2.5) }
      }
      .focusable()
      .digitalCrownRotation($crownValue, from: 0, through: 100, by: 0.5)
      .onChange(of: crownValue) { old, new in
        weight = min(500, max(0, weight + (new - old) * 5))
      }

      HStack {
        roundButton("minus") { reps = max(0, reps - 1) }
        Spacer()
        VStack(spacing: -2) {
          Text("\(reps)")
            .font(WatchTheme.font(34, .bold))
            .monospacedDigit()
            .foregroundStyle(WatchTheme.mint)
          Text("REPS")
            .font(WatchTheme.font(11, .semibold))
            .foregroundStyle(.secondary)
        }
        Spacer()
        roundButton("plus") { reps = min(50, reps + 1) }
      }

      HStack {
        Text("RPE")
          .font(WatchTheme.font(13, .semibold))
          .foregroundStyle(.secondary)
        Spacer()
        roundButton("minus", size: 30) { rpe = max(6, rpe - 0.5) }
        Text(String(format: "%.1f", rpe))
          .font(WatchTheme.font(20, .bold))
          .monospacedDigit()
          .foregroundStyle(WatchTheme.amber)
          .frame(minWidth: 44)
        roundButton("plus", size: 30) { rpe = min(10, rpe + 0.5) }
      }

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
      .padding(.top, 4)
    }
    .padding(.horizontal, 4)
  }

  private func roundButton(_ symbol: String, size: CGFloat = 38, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: size * 0.42, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .background(WatchTheme.fill, in: Circle())
    }
    .buttonStyle(.plain)
  }

  private func restView(_ end: Date) -> some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let remaining = end.timeIntervalSince(context.date)
      if remaining > 0 {
        VStack(spacing: 10) {
          ZStack {
            Circle().stroke(WatchTheme.fill, lineWidth: 6)
            Circle()
              .trim(from: 0, to: remaining / Double(max(exercise.restSeconds, 1)))
              .stroke(WatchTheme.amber, style: StrokeStyle(lineWidth: 6, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Text(String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60))
              .font(WatchTheme.font(34, .bold))
              .monospacedDigit()
              .foregroundStyle(WatchTheme.amber)
          }
          .frame(width: 112, height: 112)
          Text("Set \(setIndex + 1) of \(exercise.sets)")
            .font(WatchTheme.font(13, .semibold))
            .foregroundStyle(.secondary)
          HStack {
            Image(systemName: "heart.fill").foregroundStyle(WatchTheme.danger)
            Text(store.heartRate.map { String(format: "%.0f", $0) } ?? "—")
              .font(WatchTheme.font(15, .semibold))
              .monospacedDigit()
              .foregroundStyle(WatchTheme.danger)
            Spacer()
            Button("Skip") { store.restEnd = nil }
              .font(WatchTheme.font(13, .semibold))
              .buttonStyle(.bordered)
          }
        }
        .padding(.horizontal, 4)
      } else {
        Text("Go")
          .font(WatchTheme.font(34, .bold))
          .foregroundStyle(WatchTheme.mint)
          .onAppear {
            if restFired != end {
              WKInterfaceDevice.current().play(.notification)
              restFired = end
            }
          }
          .task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if store.restEnd == end {
              restFired = nil
              store.restEnd = nil
            }
          }
      }
    }
  }
}
