import SwiftUI
import SwiftData
import ForgeCore

struct CoachView: View {
  struct Turn: Identifiable {
    let id = UUID()
    let role: String
    let text: String
    var citations: [String] = []
    var onDevice = false
    let time = Date.now
  }

  @Query private var profiles: [UserProfile]
  @Query(sort: \CheckIn.date) private var checkIns: [CheckIn]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \CoachMessage.date) private var history: [CoachMessage]
  @Query(sort: \CoachNote.date, order: .reverse) private var notes: [CoachNote]
  @Environment(\.modelContext) private var modelContext
  @State private var turns: [Turn] = []
  @State private var input = ""
  @State private var thinking = false
  @State private var errorText: String?
  @State private var warmingUp = false
  @State private var revealedID: UUID?
  @State private var pendingAction: CoachAction?
  @State private var historyLoaded = false
  @FocusState private var inputFocused: Bool
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @AppStorage("coachConsent") private var coachConsent = false
  @AppStorage("coachOnDevice") private var coachOnDevice = true
  @State private var speech = SpeechInput()
  @State private var dictationPrefix = ""
  @State private var showConsent = false
  @State private var pendingText: String?
  @State private var showSwap = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var coach: Coach { Coach.from(coachID) }

  private let suggestions: [(title: String, message: String, swap: Bool)] = [
    ("Why did my weight drop?", "Why did my weight drop?", false),
    ("Swap an exercise", "", true),
    ("Explain my deload", "Explain my deload", false),
  ]

  private let prompts: [(symbol: String, title: String, hint: String, message: String, swap: Bool)] = [
    ("arrow.down.right.circle", "Why did my weight drop?", "Compare this week to last", "Why did my weight drop?", false),
    ("arrow.triangle.2.circlepath", "Swap an exercise", "Find a variant for today", "", true),
    ("moon.zzz", "Explain my deload", "What a deload does for you", "Explain my deload", false),
  ]

  var body: some View {
    NavigationStack {
      Group {
        if connected { chat } else { keyForm }
      }
      .background(Theme.page)
      .navigationTitle("Coach")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { CoachAvatar(size: 32) }
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button("Clear conversation", role: .destructive) { clearConversation() }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { inputFocused = false }
        }
      }
      .sheet(isPresented: $showConsent) { consentSheet }
      .sheet(isPresented: $showSwap) { swapSheet }
      .onAppear {
        guard !historyLoaded else { return }
        historyLoaded = true
        if turns.isEmpty {
          turns = history.map { Turn(role: $0.role, text: $0.text, citations: $0.citations) }
        }
      }
      .onChange(of: speech.transcript) { _, value in
        if !value.isEmpty { input = dictationPrefix + value }
      }
    }
  }

  private var consentSheet: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.groupGap) {
        CoachAvatar(size: 56)
        Text("Before you ask \(coach.name)").forgeTitle()
        Text("Your question, your training log and your profile are sent to Regulift's coach service to write the answer. Nothing from Apple Health is sent. You can turn this off any time in Settings.")
          .forgeBody()
        Text("\(coach.name) is an AI coach for training programming, not medical advice.")
          .forgeLabel()
        Link("Privacy Policy", destination: Theme.privacyPolicyURL)
          .forgeLabel()
      }
      .padding(Theme.margin)
    }
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 8) {
        Button("Agree and continue") {
          coachConsent = true
          showConsent = false
          if let t = pendingText {
            pendingText = nil
            send(t)
          }
        }
        .buttonStyle(PillButtonStyle())
        Button("Not now") {
          showConsent = false
          pendingText = nil
        }
        .buttonStyle(PillSecondaryButtonStyle())
      }
      .padding(.horizontal, Theme.margin)
      .padding(.vertical, 10)
      .background(Theme.page.opacity(0.92))
      .background(.ultraThinMaterial)
    }
    .presentationDetents([.medium])
    .presentationBackground(Theme.page)
  }

  private var connected: Bool {
    AppSecret.value != nil
  }

  private var keyForm: some View {
    VStack(spacing: Theme.groupGap) {
      Spacer()
      CoachPhoto(name: coach.wave, height: 240)
      Text("Meet \(coach.name), your coach").forgeTitle()
      Text("The coach server isn't configured in this build.")
        .forgeLabel()
        .multilineTextAlignment(.center)
      Spacer()
      Spacer()
    }
    .padding(.horizontal, Theme.margin)
  }

  private var chat: some View {
    VStack(spacing: 8) {
      GeometryReader { geo in
        ScrollViewReader { proxy in
          ScrollView {
            if turns.isEmpty && !thinking {
              VStack(spacing: Theme.groupGap) {
                Spacer()
                CoachPhoto(name: coach.wave, height: 220)
                Text("Ask \(coach.name)").forgeTitle()
                Text("Swap an exercise, understand a deload, or ask why a lift stalled. AI coach, not medical advice.")
                  .forgeLabel()
                  .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                  ForEach(prompts, id: \.title) { prompt in
                    Button {
                      if prompt.swap { showSwap = true } else { send(prompt.message) }
                    } label: {
                      HStack(spacing: 12) {
                        Image(systemName: prompt.symbol)
                          .font(.system(size: 15, weight: .semibold))
                          .foregroundColor(Theme.accent)
                          .frame(width: 36, height: 36)
                          .background(Circle().fill(Theme.accentTint))
                        VStack(alignment: .leading, spacing: 2) {
                          Text(prompt.title).forgeBodyStrong()
                          Text(prompt.hint).forgeCaption()
                        }
                        Spacer()
                      }
                      .frame(maxWidth: 480)
                      .card()
                      .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                  }
                }
                Spacer()
              }
              .padding(.horizontal, Theme.margin)
              .frame(maxWidth: .infinity)
              .frame(minHeight: geo.size.height)
            } else {
              LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(turns) { turn in
                  bubble(turn, maxWidth: geo.size.width * 0.8)
                    .transition(reduceMotion ? .forgeFade : .forgeSlideUp)
                }
                if let action = pendingAction {
                  actionCard(action)
                    .transition(reduceMotion ? .forgeFade : .forgeSlideUp)
                }
                if thinking {
                  HStack(alignment: .bottom, spacing: 8) {
                    CoachAvatar(size: 28)
                    Image(systemName: "ellipsis")
                      .font(.system(size: 18, weight: .bold))
                      .foregroundStyle(Theme.textSecondary)
                      .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
                      .padding(12)
                      .background(Theme.card)
                      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1))
                  }
                  .transition(reduceMotion ? .forgeFade : .forgeSlideUp)
                }
                Color.clear.frame(height: 0).id("bottom")
              }
              .padding(.horizontal, Theme.margin)
            }
          }
          .onChange(of: turns.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
          .onChange(of: thinking) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
          .scrollDismissesKeyboard(.interactively)
          .onTapGesture { inputFocused = false }
        }
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack {
          ForEach(suggestions, id: \.title) { chip in
            Button(chip.title) {
              if chip.swap { showSwap = true } else { send(chip.message) }
            }
              .forge(13, .medium)
              .foregroundColor(Theme.text)
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .background(
                RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
                  .fill(Theme.card))
              .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
                  .strokeBorder(Theme.ring, lineWidth: 1))
          }
        }
        .padding(.horizontal, Theme.margin)
      }
      if warmingUp {
        HStack(spacing: 10) {
          Image(systemName: "sparkles")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.accent)
          VStack(alignment: .leading, spacing: 2) {
            Text("\(coach.name) is warming up").forgeBodyStrong()
            Text("Coaching goes live once the backend is connected.").forgeCaption()
          }
          Spacer()
        }
        .innerSurface()
        .padding(.horizontal, Theme.margin)
        .transition(reduceMotion ? .forgeFade : .forgeSlideUp)
      }
      if let displayedError = speech.errorText ?? errorText {
        Text(displayedError).foregroundStyle(Theme.negative).forgeCaption()
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Theme.margin)
      }
      #if DEBUG
      if Features.voice, !SpeechLog.shared.text.isEmpty {
        Text(SpeechLog.shared.text).forgeCaption().foregroundStyle(Theme.textTertiary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Theme.margin)
      }
      #endif
      HStack(alignment: .bottom, spacing: 8) {
        TextField("Ask your coach", text: $input, axis: .vertical)
          .lineLimit(1...5)
          .focused($inputFocused)
          .forgeBody()
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
              .fill(Theme.card))
          .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
              .strokeBorder(Theme.ring, lineWidth: 1))
        if Features.voice, speech.isAvailable {
          Button { toggleDictation() } label: {
            if speech.isPreparing || speech.isTranscribing {
              ProgressView()
                .frame(width: 44, height: 44)
            } else {
              Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(speech.isListening ? Theme.onAccent : Theme.accent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(speech.isListening ? Theme.accent : Theme.card))
                .overlay(Circle().strokeBorder(Theme.ring, lineWidth: speech.isListening ? 0 : 1))
            }
          }
          .accessibilityLabel("Dictate")
          .disabled(speech.isPreparing || speech.isTranscribing)
        }
        Button { send(input) } label: {
          Image(systemName: "arrow.up")
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(Theme.onAccent)
            .frame(width: 36, height: 36)
            .background(Circle().fill(canSend ? Theme.accent : Theme.track))
        }
        .disabled(!canSend)
        .scaleEffect(canSend ? 1 : 0.9)
        .animation(.snappy, value: canSend)
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 8)
    }
  }

  private var canSend: Bool {
    !thinking && !input.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private var plannedSwapExercises: [Exercise] {
    guard let profile = profiles.first else { return [] }
    let days = Program.week(
      profile.currentWeek(sessions: sessions),
      profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)))
    guard !days.isEmpty else { return [] }
    let day = days[profile.nextDayIndex % days.count]
    return day.exercises.map(\.exercise)
  }

  private var swapEquipment: Set<Equipment> {
    guard let profile = profiles.first else { return [] }
    return Set(profile.equipment.compactMap { Equipment(rawValue: $0) })
  }

  private var swapInjuries: Set<InjuryFlag> {
    guard let profile = profiles.first else { return [] }
    return Set(profile.injuryFlags.compactMap { InjuryFlag(rawValue: $0) })
  }

  private var swapSheet: some View {
    CoachSwapSheet(planned: plannedSwapExercises, equipment: swapEquipment, injuries: swapInjuries) { from, to in
      applySwap(from: from, to: to)
    }
  }

  private func applySwap(from: Exercise, to: Exercise) {
    profiles.first?.exerciseOverrides[from.id] = to.id
    let reply = "Swapped \(from.name) → \(to.name) from your next session. Undo in Settings → Training."
    withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: reply)) }
    persist("assistant", reply)
  }

  private func toggleDictation() {
    if speech.isListening {
      speech.stop()
    } else {
      dictationPrefix = input
      speech.vocabulary = SpeechVocabulary.lifting(extra: plannedSwapExercises.map(\.name))
      Task { await speech.start() }
    }
  }

  private func bubble(_ turn: Turn, maxWidth: CGFloat) -> some View {
    let isUser = turn.role == "user"
    let bubble = Group {
      if isUser {
        Text(turn.text).foregroundStyle(Theme.onAccent)
      } else {
        Text(turn.text)
      }
    }
    .forgeBody()
    .textSelection(.enabled)
    .padding(12)
    .background(isUser ? Theme.accent : Theme.card)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(Theme.ring, lineWidth: isUser ? 0 : 1))
    .fixedSize(horizontal: false, vertical: true)
    return Group {
      if isUser {
        VStack(alignment: .trailing, spacing: 4) {
          bubble
          if revealedID == turn.id {
            Text(turn.time, style: .time).forgeCaption()
          }
        }
        .frame(maxWidth: maxWidth, alignment: .trailing)
      } else {
        HStack(alignment: .bottom, spacing: 8) {
          CoachAvatar(size: 28)
          VStack(alignment: .leading, spacing: 4) {
            bubble
            if !turn.citations.isEmpty {
              Text(turn.citations.joined(separator: " · "))
                .forgeCaption()
            }
            if turn.onDevice {
              Text("On-device answer").forgeCaption()
            }
            if revealedID == turn.id {
              Text(turn.time, style: .time).forgeCaption()
            }
          }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
      }
    }
    .onLongPressGesture(minimumDuration: 0.3) {
      withAnimation(.snappy) { revealedID = revealedID == turn.id ? nil : turn.id }
    }
  }

  private func send(_ text: String) {
    let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty, !thinking, connected else { return }
    if !coachConsent {
      pendingText = prompt
      showConsent = true
      return
    }
    input = ""
    errorText = nil
    warmingUp = false
    Analytics.track("coach_question")
    withAnimation(.snappy) {
      turns.append(Turn(role: "user", text: prompt))
      thinking = true
    }
    Task { await request() }
  }

  @MainActor
  private func request() async {
    if turns.count > 20 { turns.removeFirst(turns.count - 20) }
    while turns.first?.role != "user" { turns.removeFirst() }
    let question = turns.last?.text ?? ""
    let context = CoachAPI.dataBlock(profile: profiles.first, sessions: sessions, checkIns: checkIns, usesLb: profiles.first?.usesLb ?? false)
    if coachOnDevice, OnDeviceCoach.isAvailable {
      let box = CoachToolBox(exercises: ExerciseDB.everything)
      if let result = await OnDeviceCoach.answer(question, context: context + onDeviceNotes(), coachName: coach.name, tools: box) {
        withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: result.text, onDevice: true)) }
        if !question.isEmpty { persist("user", question) }
        persist("assistant", result.text)
        if let action = result.action { pendingAction = action }
      } else {
        await requestServer()
      }
    } else {
      await requestServer()
    }
    if (errorText != nil || warmingUp), let last = turns.last, last.role == "user" {
      turns.removeLast()
      input = last.text
    }
    withAnimation(.snappy) { thinking = false }
  }

  private func onDeviceNotes() -> String {
    guard !notes.isEmpty else { return "" }
    return "\nLifter notes: " + notes.prefix(20).map(\.text).joined(separator: "; ")
  }

  private func requestServer() async {
    let question = turns.last?.text ?? ""
    let context = CoachAPI.dataBlock(profile: profiles.first, sessions: sessions, checkIns: checkIns, usesLb: profiles.first?.usesLb ?? false)
    do {
      let reply = try await CoachAPI.ask(
        question: question,
        context: context,
        coach: coach.name,
        history: turns.dropLast().map { ["role": $0.role, "content": $0.text] },
        notes: notes.prefix(20).map(\.text))
      withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: reply.answer, citations: reply.citations ?? [])) }
      if !question.isEmpty { persist("user", question) }
      persist("assistant", reply.answer, citations: reply.citations ?? [])
      pendingAction = resolve(reply.action)
      return
    } catch let failure as CoachAPI.Failure {
      switch failure {
      case .notConfigured:
        errorText = "Check server settings"
      case .unauthorized:
        errorText = "Wrong app secret"
      case .warmingUp:
        warmingUp = true
      case .limit(let message), .server(let message):
        errorText = message
      case .offline:
        if OnDeviceCoach.isAvailable,
           let answer = await OnDeviceCoach.answer(question, context: context, coachName: coach.name) {
          withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: answer, onDevice: true)) }
          if !question.isEmpty { persist("user", question) }
          persist("assistant", answer)
        } else {
          errorText = "Coach is offline right now. Try again in a minute."
        }
      }
    } catch {
      errorText = "Coach is offline right now. Try again in a minute."
    }
  }

  private func persist(_ role: String, _ text: String, citations: [String] = []) {
    modelContext.insert(CoachMessage(role: role, text: text, citations: citations))
  }

  private func clearConversation() {
    pendingAction = nil
    withAnimation(.snappy) { turns.removeAll() }
    try? modelContext.delete(model: CoachMessage.self)
  }

  private func resolve(_ payload: CoachAPI.Reply.Action?) -> CoachAction? {
    guard let payload else { return nil }
    switch payload.type {
    case "swap":
      guard let from = payload.from.flatMap(ExerciseDB.find),
            let to = payload.to.flatMap(ExerciseDB.find) else { return nil }
      return .swap(from: from, to: to)
    case "earlyDeload": return .earlyDeload
    case "restartBlock": return .restartBlock
    case "remember":
      guard let note = payload.note, !note.isEmpty else { return nil }
      return .remember(note)
    default: return nil
    }
  }

  private func actionInfo(_ action: CoachAction) -> (title: String, detail: String) {
    switch action {
    case .swap(let from, let to):
      return ("Swap \(from.name) → \(to.name)", "Updates your plan to use the new exercise next session.")
    case .earlyDeload:
      return ("Start an early deload", "Cuts this week's volume so fatigue clears.")
    case .restartBlock:
      return ("Restart the block", "Begins a fresh 6-week block from week 1.")
    case .remember(let note):
      return ("Remember this?", note)
    }
  }

  private func actionCard(_ action: CoachAction) -> some View {
    let info = actionInfo(action)
    return VStack(alignment: .leading, spacing: 10) {
      Text(info.title).forgeBodyStrong()
      Text(info.detail).forgeLabel()
      HStack(spacing: 8) {
        Button("Apply") { apply(action) }
          .buttonStyle(PillButtonStyle(minHeight: 44))
        Button("Not now") { pendingAction = nil }
          .buttonStyle(PillSecondaryButtonStyle())
      }
    }
    .frame(maxWidth: 480, alignment: .leading)
    .card()
  }

  private func apply(_ action: CoachAction) {
    let reply: String
    switch action {
    case .remember(let note):
      if let cleaned = sanitizeNote(note) {
        modelContext.insert(CoachNote(text: cleaned))
        reply = String(localized: "Noted. I'll keep that in mind.")
      } else {
        reply = "That note looks like an instruction, not a fact — skipped."
      }
    case .swap(let from, let to):
      profiles.first?.exerciseOverrides[from.id] = to.id
      reply = String(localized: "Done. \(from.name) → \(to.name) from your next session. You'll see it under \(coach.name)'s adjustments on Today; undo in Settings → Training.")
    case .earlyDeload:
      profiles.first?.deloadStartedAt = .now
      reply = String(localized: "Done. Deload starts now: fewer sets this week, loads stay. Today shows the deload plan.")
    case .restartBlock:
      if let profile = profiles.first {
        profile.mesoStart = .now
        profile.deloadStartedAt = nil
        profile.nextDayIndex = 0
      }
      reply = String(localized: "Done. A fresh 6-week block starts today from week 1.")
    }
    Analytics.track("coach_action_applied")
    pendingAction = nil
    withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: reply)) }
    persist("assistant", reply)
  }
}

enum CoachAction {
  case swap(from: Exercise, to: Exercise)
  case earlyDeload
  case restartBlock
  case remember(String)
}

