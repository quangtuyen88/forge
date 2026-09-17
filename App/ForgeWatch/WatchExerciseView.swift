import SwiftUI
import WatchKit
import ForgeCore

struct WatchExerciseView: View {
  let exercise: WatchExercise
  @Environment(WatchStore.self) private var store
  @Environment(\.dismiss) private var dismiss
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
    .sheet(isPresented: Binding(
      get: { store.voicePending != nil },
      set: { if !$0 { store.voicePending = nil } }
    )) {
      voiceConfirmation
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
            .foregroundStyle(WatchTheme.sets)
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
          .foregroundStyle(WatchTheme.effort)
          .frame(minWidth: 44)
        roundButton("plus", size: 30) { rpe = min(10, rpe + 0.5) }
      }

      HStack(spacing: 8) {
        Button {
          WKInterfaceDevice.current().play(.success)
          logCurrentSet()
        } label: {
          Text("Log set").font(WatchTheme.font(15, .bold)).foregroundStyle(.black).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchTheme.accent)
        Button {
          beginDictation()
        } label: {
          Image(systemName: "mic.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(WatchTheme.accent)
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Dictate")
      }
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

  // MARK: voice commands

  private func logCurrentSet() {
    store.log(WatchSet(
      exerciseID: exercise.id,
      setIndex: setIndex,
      weightKg: weight,
      reps: reps,
      rpe: rpe,
      targetRPE: exercise.targetRPE,
      date: .now))
  }

  private func beginDictation() {
    WKApplication.shared().rootInterfaceController?.presentTextInputController(
      withSuggestions: nil,
      allowedInputMode: .plain
    ) { results in
      Task { @MainActor in
        guard let text = results?.first as? String, !text.isEmpty else { return }
        let candidates = ExerciseDB.everything.map { QuickLogCandidate(id: $0.id, name: $0.name) }
        let command = VoiceCommandParser.parse(text, candidates: candidates, defaultLb: false)
        store.voiceTranscript = text
        store.voicePending = command
      }
    }
  }

  private var voiceConfirmation: some View {
    VStack(spacing: 10) {
      if let command = store.voicePending {
        Text(store.voiceTranscript)
          .font(WatchTheme.font(12))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        if isSupported(command) {
          Text(summary(command))
            .font(WatchTheme.font(17, .bold))
            .multilineTextAlignment(.center)
          Button { confirm(command) } label: {
            Text("Confirm").font(WatchTheme.font(15, .bold)).frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(WatchTheme.accent)
          Button { store.voicePending = nil } label: {
            Text("Cancel").font(WatchTheme.font(15, .semibold)).frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        } else {
          Text("Do that on iPhone")
            .font(WatchTheme.font(13, .semibold))
            .foregroundStyle(WatchTheme.danger)
          Button { store.voicePending = nil } label: {
            Text("Cancel").font(WatchTheme.font(15, .semibold)).frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .padding(.horizontal, 8)
  }

  private func summary(_ command: VoiceCommand) -> String {
    command.summary { kg in
      let value = kg == kg.rounded() ? String(format: "%.0f", kg) : String(format: "%.1f", kg)
      return "\(value) kg"
    }
  }

  private func isSupported(_ command: VoiceCommand) -> Bool {
    switch command {
    case .logSet, .completeSet, .startRest, .skipRest, .nextExercise: return true
    default: return false
    }
  }

  private func confirm(_ command: VoiceCommand) {
    WKInterfaceDevice.current().play(.success)
    switch command {
    case .logSet(let parse):
      let index = store.logged.filter { $0.exerciseID == parse.exerciseID }.count
      store.log(WatchSet(
        exerciseID: parse.exerciseID,
        setIndex: index,
        weightKg: parse.weightKg,
        reps: parse.reps,
        rpe: parse.rpe ?? 8,
        targetRPE: 8,
        date: .now))
    case .completeSet:
      logCurrentSet()
    case .startRest(let seconds):
      store.restEnd = Date.now.addingTimeInterval(TimeInterval(seconds ?? exercise.restSeconds))
    case .skipRest:
      store.restEnd = nil
    case .nextExercise:
      dismiss()
    default:
      break
    }
    store.voicePending = nil
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
              .stroke(WatchTheme.time, style: StrokeStyle(lineWidth: 6, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Text(String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60))
              .font(WatchTheme.font(34, .bold))
              .monospacedDigit()
              .foregroundStyle(WatchTheme.time)
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
          .foregroundStyle(WatchTheme.sets)
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
