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
    var record: DecisionRecord? = nil
    let time = Date.now
    var receipt: CoachReceipt? = nil
  }

  @Query private var profiles: [UserProfile]
  @Query(sort: \CheckIn.date) private var checkIns: [CheckIn]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \CoachMessage.date) private var history: [CoachMessage]
  @Query(sort: \CoachNote.date, order: .reverse) private var notes: [CoachNote]
  @Query(sort: \DecisionLogEntry.date) private var decisionLog: [DecisionLogEntry]
  @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
  @Environment(\.modelContext) private var modelContext
  @State private var turns: [Turn] = []
  @State private var input = ""
  @State private var thinking = false
  @State private var errorText: String?
  @State private var warmingUp = false
  @State private var revealedID: UUID?
  @State private var pendingAction: CoachAction?
  /// The ledger identity of the pending proposal. Set by `propose` only after the
  /// snapshot and its exposure are persisted; cleared whenever the card goes away.
  @State private var pendingActionID: RecommendationID?
  /// The exact preview the card is showing, bound to the plan state it describes. Apply is
  /// checked against this, so a change that arrives later — a different diff, a plan that
  /// moved, a replay with other content — cannot ride an approval given for something else.
  @State private var pendingPreview: CommitPreview?
  @State private var historyLoaded = false
  @FocusState private var inputFocused: Bool
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @AppStorage("coachConsent") private var coachConsent = false
  @AppStorage("coachOnDevice") private var coachOnDevice = true
  @State private var speech = SpeechInput()
  @State private var voiceOpen = false
  @State private var voiceStarting = false
  @State private var voiceSince: Date?
  @State private var voiceQuestion: String?
  @State private var voiceCancelled = false
  @State private var voiceSendWhenReady = false
  @State private var voiceToInput = false
  @State private var voiceMissed = false
  @Namespace private var voiceNamespace
  @State private var showConsent = false
  @State private var pendingText: String?
  /// The clarification lifecycle. The branching lives in ForgeCore's `CoachConversation`,
  /// where it is testable; the view only holds it.
  @State private var conversation = CoachConversation()
  @State private var showSwap = false
  @State private var expandedRecords: Set<String> = []
  @State private var overrideTick = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var coach: Coach { Coach.from(coachID) }
  private var profile: UserProfile? { profiles.first }

  /// One question the empty state and the chip row can offer.
  private struct Prompt: Identifiable {
    let symbol: String
    let title: String
    let hint: String
    let message: String
    let swap: Bool
    /// A stable selector, independent of the localized title.
    var key: String = ""
    var id: String { key.isEmpty ? title : key }
  }

  /// The chips are the same prompts, so a chip can never ask something the cards do not.
  private var suggestions: [Prompt] { prompts }

  /// While a clarification is open the chips are its options: one tap answers it, and the
  /// answer is routed through `send` like any other reply, so it resolves the same way.
  private var chipRow: [Prompt] {
    guard conversation.isAwaitingChoice else {
      guard !(turns.isEmpty && !thinking) else { return [] }
      return suggestions
    }
    return conversation.options.enumerated().map { index, option in
      Prompt(
        symbol: "questionmark.circle", title: option, hint: "", message: option, swap: false,
        key: "clarify.\(index)")
    }
  }

  /// Prompts are built from what the log actually holds — a real engine decision, a real
  /// stalled lift, a real weight move, a real recovery signal — never from a fixed list. A
  /// lifter who has never logged a body weight is never asked why it dropped. The swap
  /// action is always offered because it acts on the plan rather than claiming a fact.
  private var prompts: [Prompt] {
    var items: [Prompt] = []
    var seen = Set<String>()
    for candidate in dataPrompts + [profilePrompt] where items.count < 2 {
      if seen.insert(candidate.title).inserted { items.append(candidate) }
    }
    items.append(swapPrompt)
    return items
  }

  private var swapPrompt: Prompt {
    Prompt(
      symbol: "arrow.triangle.2.circlepath",
      title: String(localized: "Swap an exercise", bundle: L10n.bundle),
      hint: String(localized: "Pick a variant for today", bundle: L10n.bundle),
      message: "",
      swap: true)
  }

  private var dataPrompts: [Prompt] {
    [explainableDecision, stalledLift, weightMove, recoverySignal].compactMap { $0 }
  }

  /// The newest engine decision the coach can actually explain: the reason already exists,
  /// so the prompt points at it instead of asking the lifter to describe a change.
  private var explainableDecision: Prompt? {
    let cutoff = Date.now.addingTimeInterval(-21 * 86400)
    guard let entry = decisionLog.last(where: {
      $0.date >= cutoff && !$0.humanSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) else { return nil }
    let name = entry.exerciseID.flatMap { ExerciseDB.find($0)?.localizedName }
    let symbol: String
    let title: String
    switch entry.type {
    case "plateau":
      symbol = "chart.line.downtrend.xyaxis"
      title = name.map { String(localized: "Why did \($0) stall?", bundle: L10n.bundle) }
        ?? String(localized: "Why did my lifts stall?", bundle: L10n.bundle)
    case "swap":
      symbol = "arrow.triangle.2.circlepath"
      title = name.map { String(localized: "Why swap \($0)?", bundle: L10n.bundle) }
        ?? String(localized: "Why was that swapped?", bundle: L10n.bundle)
    case "volume_change":
      symbol = "chart.bar.doc.horizontal"
      title = String(localized: "Why did my sets change?", bundle: L10n.bundle)
    case "deload", "session":
      symbol = "moon.zzz"
      title = String(localized: "Why this session?", bundle: L10n.bundle)
    default:
      symbol = "arrow.up.right.circle"
      title = name.map { String(localized: "Why did \($0) change?", bundle: L10n.bundle) }
        ?? String(localized: "Why did my plan change?", bundle: L10n.bundle)
    }
    return Prompt(
      symbol: symbol,
      title: title,
      hint: String(localized: "\(relative(entry.date)) · from your log", bundle: L10n.bundle),
      message: String(localized: "Explain this change to my program: \(entry.humanSummary)", bundle: L10n.bundle),
      swap: false)
  }

  /// A lift the log itself reports as plateaued.
  private var stalledLift: Prompt? {
    let stalled = plateauedExerciseIDs(sessions: sessions, now: .now)
    guard !stalled.isEmpty else { return nil }
    var sets: [String: Int] = [:]
    for session in sessions where session.completed {
      for set in session.sets where stalled.contains(set.exerciseID) {
        sets[set.exerciseID, default: 0] += 1
      }
    }
    let ranked = sets.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
    guard let top = ranked.first, let name = ExerciseDB.find(top.key)?.name else { return nil }
    let displayName = ExerciseDB.find(top.key)?.localizedName ?? name
    return Prompt(
      symbol: "chart.line.downtrend.xyaxis",
      title: String(localized: "Why has \(displayName) stalled?", bundle: L10n.bundle),
      hint: String(localized: "\(top.value) logged sets, no new best", bundle: L10n.bundle),
      message: String(localized: "My \(name) has stopped progressing. What should I change?", bundle: L10n.bundle),
      swap: false)
  }

  /// A body-weight move the measurements actually show, in the profile's unit.
  private var weightMove: Prompt? {
    let cutoff = Date.now.addingTimeInterval(-28 * 86400)
    let points = measurements
      .filter { ($0.weightKg ?? 0) > 0 && $0.date >= cutoff }
      .sorted { $0.date < $1.date }
    guard let profile, let first = points.first?.weightKg, let last = points.last?.weightKg else {
      return nil
    }
    let deltaKg = last - first
    guard abs(deltaKg) >= 0.5 else { return nil }
    let rising = deltaKg > 0
    let unit = profile.usesLb ? "lb" : "kg"
    let amount = "\(Fmt.num(abs(profile.usesLb ? Plates.kgToLb(deltaKg) : deltaKg))) \(unit)"
    return Prompt(
      symbol: rising ? "arrow.up.right.circle" : "arrow.down.right.circle",
      title: rising
        ? String(localized: "Why is my weight up?", bundle: L10n.bundle)
        : String(localized: "Why did my weight drop?", bundle: L10n.bundle),
      hint: String(localized: "\(rising ? "+" : "−")\(amount) in 28 days", bundle: L10n.bundle),
      message: rising
        ? String(localized: "My body weight is up \(amount) over four weeks. Is that on track for my goal?", bundle: L10n.bundle)
        : String(localized: "My body weight is down \(amount) over four weeks. Why, and should I change anything?", bundle: L10n.bundle),
      swap: false)
  }

  /// The last three check-ins, averaged. The recovery prompt and the ledger share this
  /// read, so what the prompt offers and what a proposal records cannot disagree.
  private var recoveryAverages: (sleepHours: Double, soreness: Int)? {
    let recent = checkIns.sorted { $0.date > $1.date }.prefix(3)
    guard recent.count == 3 else { return nil }
    let hours = recent.map(\.sleepHours)
    return (hours.reduce(0, +) / Double(hours.count),
            recent.map(\.soreness).reduce(0, +) / recent.count)
  }

  /// A recovery signal from the last three check-ins, when one is actually there.
  private var recoverySignal: Prompt? {
    guard let recovery = recoveryAverages else { return nil }
    let average = recovery.sleepHours
    let soreness = recovery.soreness
    guard average < 6 || soreness >= 4 else { return nil }
    return Prompt(
      symbol: "bed.double",
      title: average < 6
        ? String(localized: "Ask about my sleep", bundle: L10n.bundle)
        : String(localized: "Why am I so sore?", bundle: L10n.bundle),
      hint: String(localized: "Last 3 check-ins · \(Fmt.num(average)) h sleep", bundle: L10n.bundle),
      message: String(localized: "My last three check-ins average \(Fmt.num(average)) hours of sleep. Should I change my training this week?", bundle: L10n.bundle),
      swap: false)
  }

  /// What the profile and the log can answer even on the first day.
  private var profilePrompt: Prompt {
    let goal = Goal(rawValue: profile?.goal ?? "")?.name
      ?? String(localized: "training", bundle: L10n.bundle)
    let days = profile?.daysPerWeek ?? 3
    let logged = sessions.filter(\.completed).count
    return Prompt(
      symbol: "calendar",
      title: String(localized: "Is my \(days)-day split right?", bundle: L10n.bundle),
      hint: String(
        localized: "\(goal) goal · \(logged) session\(L10n.pluralSuffix(logged)) logged",
        bundle: L10n.bundle),
      message: String(localized: "My goal is \(goal) and I train \(days) days a week. Is that split right for me?", bundle: L10n.bundle),
      swap: false)
  }

  private func relative(_ date: Date) -> String {
    date.formatted(.relative(presentation: .named).locale(L10n.locale))
  }

  var body: some View {
    NavigationStack {
      // Voice mode is a sibling of the chat; the covered chat leaves the accessibility tree.
      ZStack {
        Group {
          if connected { chat } else { keyForm }
        }
        .safeAreaInset(edge: .top, spacing: 0) { coachHeader }
        .accessibilityHidden(voiceOpen)
        if voiceOpen { voiceMode.transition(.opacity).zIndex(1) }
      }
      .sensoryFeedback(.selection, trigger: overrideTick)
      .background(Theme.page)
      .toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { inputFocused = false }
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .toolbar(voiceOpen ? .hidden : .visible, for: .tabBar)
      .sheet(isPresented: $showConsent) { consentSheet }
      .sheet(isPresented: $showSwap) { swapSheet }
      .onAppear {
        guard !historyLoaded else { return }
        historyLoaded = true
        if turns.isEmpty {
          turns = history.suffix(40).map { t in
            Turn(role: t.role, text: t.text, citations: t.citations,
                 record: t.role == "assistant" ? matchingRecord(for: t.text) : nil)
          }
        }
      }
      .onChange(of: speech.isListening) { was, now in if was && !now { listeningEnded() } }
      .onChange(of: speech.isTranscribing) { was, now in
        guard was, !now else { return }
        if voiceToInput {
          voiceToInput = false
          let heard = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
          if !heard.isEmpty { input = heard }
        } else if voiceSendWhenReady {
          sendVoiceTranscript()
        }
      }
      .onDisappear { if voiceOpen { closeVoice() } }
    }
  }

  private var coachHeader: some View {
    ZStack {
      VStack(spacing: 4) {
        CoachAvatar(size: 36)
        Text(coach.name)
          .forge(13, .semibold)
          .foregroundStyle(Theme.text)
      }
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isHeader)
      HStack {
        Spacer()
        Menu {
          Button("Clear conversation", role: .destructive) { clearConversation() }
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Theme.innerSurface))
        }
        .accessibilityLabel("More options")
      }
      .padding(.horizontal, Theme.margin)
    }
    .padding(.top, 4)
    .padding(.bottom, 8)
    .frame(maxWidth: .infinity)
    .background(Theme.page)
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
      .padding(.horizontal, Theme.barMargin)
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
                        iconBadge(prompt.symbol)
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
                    .buttonStyle(RowPressStyle())
                  }
                }
                Spacer()
              }
              .padding(.horizontal, Theme.margin)
              .frame(maxWidth: .infinity)
              .frame(minHeight: geo.size.height)
            } else {
              VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                  bubble(
                    turn,
                    maxWidth: geo.size.width * 0.8,
                    showsName: index == 0 || turns[index - 1].role != "assistant"
                  )
                  .transition(reduceMotion ? .forgeFade : .forgeSlideUp)
                }
                if let action = pendingAction {
                  if case .adjustPlan(let adjustment) = action {
                    adjustPlanCard(adjustment)
                      .transition(reduceMotion ? .forgeFade : .forgeSlideUp)
                  } else {
                    actionCard(action)
                      .transition(reduceMotion ? .forgeFade : .forgeSlideUp)
                  }
                }
                if thinking {
                  VStack(alignment: .leading, spacing: 8) {
                    nameLine
                    Image(systemName: "ellipsis")
                      .font(.system(size: 18, weight: .bold))
                      .foregroundStyle(Theme.textSecondary)
                      .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
                      .padding(.leading, 32)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .transition(reduceMotion ? .forgeFade : .forgeSlideUp)
                }
                Color.clear.frame(height: 0).id("bottom")
              }
              .padding(.horizontal, Theme.margin)
            }
          }
          .onChange(of: turns.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
          .onChange(of: thinking) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
          .onChange(of: pendingAction != nil) { _, showing in
            if showing { DispatchQueue.main.async { withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) } } }
          }
          .scrollDismissesKeyboard(.interactively)
          .defaultScrollAnchor(.bottom)
          .onTapGesture { inputFocused = false }
        }
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack {
          ForEach(chipRow) { chip in
            Button(chip.title) {
              if chip.swap { showSwap = true } else { send(chip.message) }
            }
              .accessibilityIdentifier("coach.chip.\(chip.id)")
              .forge(13, .medium)
              .foregroundStyle(Theme.text)
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
          Image(systemName: "ellipsis.message")
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
      if let displayedError = errorText {
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
      TextField(text: $input, prompt: Text("Ask \(coach.name)", bundle: L10n.bundle).foregroundStyle(Theme.textSecondary), axis: .vertical) {
        Text("Ask \(coach.name)", bundle: L10n.bundle)
      }
      .lineLimit(1...5)
      .focused($inputFocused)
      .forgeBody()
      .accessibilityIdentifier("coach.input")
      .padding(.leading, 14)
      .padding(.trailing, 50)
      .padding(.vertical, 14)
      .frame(minHeight: 50)
      .background(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous).fill(Theme.innerSurface))
      .overlay(alignment: .bottomTrailing) { composerTrailing.padding(3) }
      .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.2), value: input.isEmpty)
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 8)
    }
  }

  @ViewBuilder
  private var composerTrailing: some View {
    if !input.trimmingCharacters(in: .whitespaces).isEmpty {
      Button { send(input) } label: {
        Image(systemName: "arrow.up")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(Theme.onAccent)
          .frame(width: 32, height: 32)
          .background(Circle().fill(canSend ? Theme.accent : Theme.track))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(ControlPressStyle())
      .accessibilityLabel("Send message")
      .disabled(!canSend)
      .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.25)))
    } else if Features.voice, speech.isAvailable {
      Button { openVoice() } label: {
        Image(systemName: "mic")
          .font(.system(size: 19, weight: .medium))
          .foregroundStyle(Theme.textSecondary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(ControlPressStyle())
      .matchedGeometryEffect(id: reduceMotion ? "coach.voice.mic" : "coach.voice.disc", in: voiceNamespace, isSource: !voiceOpen)
      .opacity(voiceOpen ? 0 : 1)
      .accessibilityLabel(String(localized: "Talk to \(coach.name)", bundle: L10n.bundle))
      .accessibilityIdentifier("coach.voice.open")
      .disabled(thinking || speech.isTranscribing)
      .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.25)))
    }
  }

  private var voiceMode: some View {
    VStack(spacing: 0) {
      VoiceHeader(name: coach.name)
      voiceContent.frame(maxWidth: .infinity, maxHeight: .infinity)
      if let status = voiceStatus {
        VoiceStatusLine(title: status, since: voicePhase == .listening ? voiceSince : nil)
          .padding(.bottom, 12)
      }
      VoiceControlRow(
        closeLabel: String(localized: "Close voice mode", bundle: L10n.bundle),
        keyboardLabel: String(localized: "Type instead", bundle: L10n.bundle),
        onClose: { closeVoice() },
        onKeyboard: typeInstead
      ) {
        LiveVoiceDisc(speech: speech, phase: voicePhase, label: voiceDiscLabel, action: voiceDiscTapped)
          .matchedGeometryEffect(id: "coach.voice.disc", in: voiceNamespace, isSource: voiceOpen)
      }
      Text(voiceHint ?? " ")          // keeps its height so the row never moves
        .forge(13, .medium)
        .foregroundStyle(Theme.textSecondary)
        .opacity(voiceHint == nil ? 0 : 1)
        .accessibilityHidden(voiceHint == nil)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }
    .background(Theme.page.ignoresSafeArea())
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .sensoryFeedback(trigger: speech.isListening) { _, listening in listening ? .start : .stop }
  }

  private var voiceStatus: String? {
    switch voicePhase {
    case .preparing, .listening: String(localized: "Listening", bundle: L10n.bundle)
    case .transcribing: String(localized: "Transcribing", bundle: L10n.bundle)
    default: nil
    }
  }

  private var voiceHint: String? {
    switch voicePhase {
    case .listening: String(localized: "Tap to send", bundle: L10n.bundle)
    case .answered: String(localized: "Tap to talk", bundle: L10n.bundle)
    default: nil
    }
  }

  private var voiceDiscLabel: String {
    switch voicePhase {
    case .listening: String(localized: "Send message", bundle: L10n.bundle)
    case .thinking, .transcribing: String(localized: "\(coach.name) is thinking", bundle: L10n.bundle)
    case .preparing: String(localized: "Listening", bundle: L10n.bundle)
    case .answered, .failed: String(localized: "Talk to \(coach.name)", bundle: L10n.bundle)
    }
  }

  @ViewBuilder
  private var voiceContent: some View {
    switch voicePhase {
    case .failed(let message, let permission):
      VoiceFailureNotice(
        title: permission
          ? String(localized: "Microphone is off", bundle: L10n.bundle)
          : speech.errorText != nil
            ? String(localized: "Voice didn't start", bundle: L10n.bundle)
            : String(localized: "Couldn't reach \(coach.name)", bundle: L10n.bundle),
        message: permission ? String(localized: "Enable it in Settings.", bundle: L10n.bundle) : message,
        actionTitle: permission ? String(localized: "Open Settings", bundle: L10n.bundle) : nil,
        action: permission ? { openAppSettings() } : nil)
      .padding(.horizontal, 28)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .thinking, .answered:
      if voiceQuestion != nil, !voiceMissed {
        GeometryReader { geo in
          ScrollView {
            VStack(alignment: .leading, spacing: 16) {
              ForEach(Array(voiceTurns.enumerated()), id: \.element.id) { index, turn in
                bubble(
                  turn,
                  maxWidth: geo.size.width * 0.8,
                  showsName: index == 0 || voiceTurns[index - 1].role != "assistant"
                )
                .transition(reduceMotion ? .forgeFade : .forgeSlideUp)
              }
              if let action = pendingAction, voiceTurns.contains(where: { $0.role == "assistant" }) {
                if case .adjustPlan(let adjustment) = action {
                  adjustPlanCard(adjustment)
                    .transition(reduceMotion ? .forgeFade : .forgeSlideUp)
                } else {
                  actionCard(action)
                    .transition(reduceMotion ? .forgeFade : .forgeSlideUp)
                }
              }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 8)
          }
          .defaultScrollAnchor(.top)
        }
      } else {
        voiceTranscript
      }
    default:
      voiceTranscript
    }
  }

  private var voiceTranscript: some View {
    GeometryReader { geo in
      ScrollView {
        LiveVoiceTranscript(
          speech: speech,
          placeholder: voiceMissed
            ? String(localized: "Didn't catch that.", bundle: L10n.bundle)
            : String(localized: "Go ahead, I'm listening.", bundle: L10n.bundle),
          showsCursor: voicePhase == .listening)
          .padding(.horizontal, 28)
          .frame(maxWidth: .infinity, minHeight: geo.size.height)
      }
      .defaultScrollAnchor(.bottom)
      .scrollBounceBehavior(.basedOnSize)
      .scrollIndicators(.hidden)
    }
  }

  private var canSend: Bool {
    !thinking && !input.trimmingCharacters(in: .whitespaces).isEmpty
  }

  /// The session the coach reads from: the next planned day, built the same way the swap
  /// sheet builds it, so a read and a swap can never describe different sessions.
  private var plannedCoachDay: PlannedDay? {
    guard let profile = profiles.first else { return nil }
    return RoutineAdaptationService.currentDay(profile: profile, sessions: sessions)
  }

  private var plannedSwapExercises: [Exercise] {
    plannedCoachDay?.exercises.map(\.exercise) ?? []
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
    let previous = profiles.first?.exerciseOverrides[from.id]
    profiles.first?.exerciseOverrides[from.id] = to.id
    let reply = "Swapped \(from.localizedName) → \(to.localizedName) from your next session. Undo in Settings → Training."
    let receipt = CoachReceipt(
      title: String(localized: "Exercise swapped", bundle: L10n.bundle),
      undo: .swap(fromID: from.id, previousTarget: previous),
      appliedEntry: nil,
      recommendationID: nil,
      revision: planRevision)
    withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: reply, receipt: receipt)) }
    persist("assistant", reply)
  }

  private var voicePhase: CoachVoicePhase {
    if let message = speech.errorText { return .failed(message: message, permission: message == SpeechInput.permissionMessage) }
    if let message = errorText, voiceQuestion != nil { return .failed(message: message, permission: false) }
    if warmingUp, voiceQuestion != nil { return .failed(message: String(localized: "Coaching goes live once the backend is connected.", bundle: L10n.bundle), permission: false) }
    if voiceStarting || speech.isPreparing { return .preparing }
    if speech.isListening { return .listening }
    if speech.isTranscribing || voiceSendWhenReady { return .transcribing }
    if thinking { return .thinking }
    return .answered
  }

  private func openVoice() {
    inputFocused = false
    voiceQuestion = nil
    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 1)) { voiceOpen = true }
    startListening()
  }

  private func startListening() {
    speech.errorText = nil
    errorText = nil
    voiceCancelled = false
    voiceSendWhenReady = false
    voiceMissed = false
    speech.vocabulary = SpeechVocabulary.coach(extra: plannedSwapExercises.map(\.localizedName))
    voiceStarting = true
    Task {
      await speech.start()
      voiceStarting = false
      guard voiceOpen, !voiceCancelled else { speech.cancel(); return }
      if speech.isListening { voiceSince = .now }
    }
  }

  private func voiceDiscTapped() {
    switch voicePhase {
    case .listening: speech.stop()          // onChange(of: speech.isListening) sends what was heard
    case .answered: startListening()
    case .failed(_, let permission) where !permission: startListening()
    default: break
    }
  }

  /// Listening stopped (tap, 60 s auto-stop): send what was heard unless the lifter closed or switched to typing.
  private func listeningEnded() {
    voiceSince = nil
    guard voiceOpen, !voiceCancelled, speech.errorText == nil else { return }
    if speech.isTranscribing { voiceSendWhenReady = true } else { sendVoiceTranscript() }
  }

  private func sendVoiceTranscript() {
    voiceSendWhenReady = false
    let text = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      guard speech.errorText == nil else { return }
      voiceMissed = true
      AccessibilityNotification.Announcement(String(localized: "Didn't catch that.", bundle: L10n.bundle)).post()
      return
    }
    voiceQuestion = text
    send(text)
  }

  private func closeVoice(dropRecording: Bool = true) {
    voiceCancelled = true
    if speech.isListening || speech.isPreparing || voiceStarting {
      if dropRecording { speech.cancel() } else { speech.stop() }
    }
    voiceSendWhenReady = false
    voiceSince = nil
    speech.errorText = nil
    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 1)) { voiceOpen = false }
  }

  private func typeInstead() {
    let heard = speech.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let wasListening = speech.isListening
    if wasListening && heard.isEmpty {
      // Cloud engine: the words arrive after the upload and land in the field.
      closeVoice(dropRecording: false)
      voiceToInput = speech.isTranscribing
    } else {
      closeVoice()
      if wasListening, !heard.isEmpty { input = heard }
    }
    inputFocused = true
  }

  private func openAppSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
  }

  /// The spoken exchange: from the voice question's bubble to the latest turn.
  private var voiceTurns: [Turn] {
    guard let question = voiceQuestion,
          let start = turns.lastIndex(where: { $0.role == "user" && $0.text == question }) else { return [] }
    return Array(turns[start...])
  }

  private var knownProfileFields: Set<String> {
    ["goal", "days per week", "bodyweight", "units", "injuries", "equipment", "language"]
  }

  private var medicalDeflection: String {
    String(localized: "\(coach.name) coaches training, not medicine. For pain or injury, see a physio or doctor.", bundle: L10n.bundle)
  }

  private var fallbackAnswer: String {
    String(localized: "I couldn't verify that answer against your log, so I'm holding it back. Ask again and I'll stick to your real numbers.", bundle: L10n.bundle)
  }

  private func finishLocal(_ text: String, question: String) {
    withAnimation(.snappy) {
      turns.append(Turn(role: "assistant", text: text))
      thinking = false
    }
    if !question.isEmpty { persist("user", question) }
    persist("assistant", text)
  }

  private func needsWithheldHealth(_ question: String, _ withheld: [String]) -> Bool {
    guard !withheld.isEmpty else { return false }
    let q = question.lowercased()
    let keywords: Set<String> = ["sleep", "slept", "sleeping", "hrv", "heart rate", "resting hr", "resting heart"]
    return keywords.contains { q.contains($0) }
  }

  private func onDeviceHealthContext(_ packet: CoachContextPacket) -> String {
    var lines = [packet.rendered()]
    if let sleepHours = checkIns.last?.sleepHours {
      lines.append("sleep_hours: \(Fmt.num(sleepHours))")
    }
    return lines.joined(separator: "\n")
  }

  private var decisionRecords: [DecisionRecord] { decisionLog.map(\.record) }

  private func matchingRecord(for text: String) -> DecisionRecord? {
    for ex in ExerciseDB.everything {
      if text.localizedCaseInsensitiveContains(ex.localizedName) || text.localizedCaseInsensitiveContains(ex.name) {
        if let record = DecisionLedger.latest(for: ex.id, in: decisionRecords) {
          return record
        }
      }
    }
    return nil
  }

  private func reasonText(_ code: String) -> String {
    DecisionSignal.allCases.first { $0.code == code }?.label ?? code
  }

  private func keepLabel(_ record: DecisionRecord) -> String {
    let kg = record.toValue ?? record.fromValue
    guard let kg else { return String(localized: "Keep original", bundle: L10n.bundle) }
    let lb = profiles.first?.usesLb ?? false
    let v = lb ? Plates.kgToLb(kg) : kg
    return String(localized: "Keep \(Fmt.kg(v, lb: lb))", bundle: L10n.bundle)
  }

  private func textBubble(_ turn: Turn) -> some View {
    Text(turn.text)
      .foregroundStyle(Theme.text)
      .forgeBody()
      .textSelection(.enabled)
      .padding(12)
      .background(Theme.track)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .fixedSize(horizontal: false, vertical: true)
  }

  private var nameLine: some View {
    HStack(spacing: 8) {
      CoachAvatar(size: 24)
      Text(coach.name).forgeBodyStrong()
    }
    .accessibilityElement(children: .combine)
  }

  private func bubble(_ turn: Turn, maxWidth: CGFloat, showsName: Bool) -> some View {
    Group {
      if turn.role == "user" {
        VStack(alignment: .trailing, spacing: 4) {
          textBubble(turn)
          if revealedID == turn.id {
            Text(turn.time, style: .time).forgeCaption()
          }
        }
        .frame(maxWidth: maxWidth, alignment: .trailing)
      } else {
        coachTurn(turn, showsName: showsName)
      }
    }
    .onLongPressGesture(minimumDuration: 0.3) {
      withAnimation(.snappy) { revealedID = revealedID == turn.id ? nil : turn.id }
    }
  }

  /// A coach turn is plain text on the page: optional name line, then text indented under it.
  private func coachTurn(_ turn: Turn, showsName: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let receipt = turn.receipt { receiptRow(receipt, turnID: turn.id) }
      if showsName { nameLine }
      VStack(alignment: .leading, spacing: 4) {
        Text(turn.text)
          .foregroundStyle(Theme.text)
          .forgeBody()
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        if let record = turn.record {
          HStack(spacing: 8) {
            decisionChip(String(localized: "Show calculation", bundle: L10n.bundle)) {
              withAnimation(.snappy) {
                if expandedRecords.contains(record.id) { expandedRecords.remove(record.id) }
                else { expandedRecords.insert(record.id) }
              }
            }
            if let id = record.exerciseID {
              let current = DecisionOverrides.get(id)
              decisionChip(keepLabel(record), selected: current == .keepOriginal) {
                applyOverride(current == .keepOriginal ? nil : .keepOriginal, for: id, record: record)
              }
              decisionChip(DecisionOverride.easier.title, selected: current == .easier) {
                applyOverride(current == .easier ? nil : .easier, for: id, record: record)
              }
            }
          }
          if expandedRecords.contains(record.id) {
            VStack(alignment: .leading, spacing: 4) {
              ForEach(record.evidence, id: \.self) { line in
                Text(line).forgeCaption().monospacedDigit()
              }
              ForEach(record.reasonCodes, id: \.self) { code in
                Text(reasonText(code)).forgeCaption()
              }
            }
          }
        }
        if turn.onDevice {
          HStack(spacing: 4) {
            Image(systemName: "iphone")
            Text("On-device answer")
          }
          .forgeCaption()
        }
        if revealedID == turn.id {
          Text(turn.time, style: .time).forgeCaption()
        }
      }
      .padding(.leading, 32)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The one-line receipt that replaces an applied card.
  private func receiptRow(_ receipt: CoachReceipt, turnID: UUID) -> some View {
    HStack(spacing: 12) {
      Image(systemName: receipt.undone ? "arrow.uturn.backward" : "checkmark")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(Theme.onAccent)
        .frame(width: 28, height: 28)
        .background(Circle().fill(receipt.undone ? Theme.textSecondary : Theme.positive))
        .accessibilityHidden(true)
      Text(receipt.undone ? String(localized: "Undone", bundle: L10n.bundle) : receipt.title)
        .forgeBody()
      Spacer(minLength: 8)
      if canUndo(receipt) {
        Button {
          undo(turnID)
        } label: {
          Text(String(localized: "Undo", bundle: L10n.bundle))
            .font(.forge(15, .semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("coach.receipt.undo")
      }
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 52)
    .frame(maxWidth: 480, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("coach.receipt")
  }

  /// Undo is offered only while the plan is still exactly the one the change produced.
  private func canUndo(_ receipt: CoachReceipt) -> Bool {
    !receipt.undone && receipt.undo != nil && undoIsCurrent(receipt)
  }

  /// Whether the world is still exactly the one the applied change left behind.
  private func undoIsCurrent(_ receipt: CoachReceipt) -> Bool {
    switch receipt.undo {
    case .plan(let s):
      return planRevision == receipt.revision
        && profile?.weekPlanJSON == s.afterWeekPlanJSON
        && profile?.mesoSessionOffset == s.afterMesoSessionOffset
    case .swap, .deload:
      return planRevision == receipt.revision
    case .note(let note, _):
      guard let live = stored(note) else { return false }
      return live.isActive
    case nil:
      return false
    }
  }

  /// The model again, or nil when it was deleted elsewhere in the app.
  private func stored<T: PersistentModel>(_ model: T) -> T? {
    let id = model.persistentModelID
    var fetch = FetchDescriptor<T>(predicate: #Predicate { $0.persistentModelID == id })
    fetch.fetchLimit = 1
    return (try? modelContext.fetch(fetch))?.first
  }

  /// Puts back exactly what one applied change replaced, then says so in one line.
  private func undo(_ turnID: UUID) {
    guard let index = turns.firstIndex(where: { $0.id == turnID }),
      let receipt = turns[index].receipt,
      !receipt.undone,
      let undoCase = receipt.undo,
      let profile
    else { return }
    let now = Date.now
    if !undoIsCurrent(receipt) {
      turns[index].receipt?.undo = nil
      let stale = String(
        localized:
          "Your plan changed after that, so I can't undo it here. Change it in Settings → Training.",
        bundle: L10n.bundle)
      withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: stale)) }
      persist("assistant", stale)
      return
    }
    let line: String
    switch undoCase {
    case .plan(let s):
      let after = profile.planSettings
      profile.daysPerWeek = s.daysPerWeek
      profile.sessionMinutes = s.sessionMinutes
      profile.goal = s.goal
      profile.split = s.split
      profile.mesoSessionOffset = s.mesoSessionOffset
      profile.weekPlanJSON = s.weekPlanJSON
      profile.updatedAt = now
      // A snapshot always holds values the live profile accepted; nil only guards a corrupted store.
      if let restored = PlanAdjustment(daysPerWeek: s.daysPerWeek, sessionMinutes: s.sessionMinutes, goal: s.goal, split: s.split) {
        line = String(
          localized: "Undone. Your plan is back to \(planChangeSummary(restored.changing(after) ?? restored)).",
          bundle: L10n.bundle)
      } else {
        line = String(localized: "Undone", bundle: L10n.bundle)
      }
    case .swap(let fromID, let previousTarget):
      if let previousTarget {
        profile.exerciseOverrides[fromID] = previousTarget
      } else {
        profile.exerciseOverrides.removeValue(forKey: fromID)
      }
      profile.updatedAt = now
      let name = ExerciseDB.find(fromID)?.localizedName ?? fromID
      line = String(localized: "Undone. \(name) is back in your plan.", bundle: L10n.bundle)
    case .deload(let previousStart):
      profile.deloadStartedAt = previousStart
      profile.updatedAt = now
      line = String(localized: "Undone. The deload is off, and your planned sets are back.", bundle: L10n.bundle)
    case .note(let note, let superseded):
      modelContext.delete(note)
      for existing in superseded where stored(existing) != nil {
        existing.supersededAt = nil
      }
      line = String(localized: "Undone. I won't keep that note.", bundle: L10n.bundle)
    }
    if let entry = receipt.appliedEntry, stored(entry) != nil {
      modelContext.delete(entry)
    }
    if let id = receipt.recommendationID {
      var ledger = profile.recommendationLedger
      ledger.revert(id, at: now)
      profile.recommendationLedger = ledger
    }
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      let failure = String(
        localized: "I couldn't save that change, so nothing was changed. Try again.",
        bundle: L10n.bundle)
      withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: failure)) }
      persist("assistant", failure)
      return
    }
    withAnimation(.snappy) {
      turns[index].receipt?.undone = true
      turns.append(Turn(role: "assistant", text: line))
    }
    persist("assistant", line)
    Analytics.track("coach_action_undone")
    overrideTick += 1
  }

  private func decisionChip(_ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .forge(11, .semibold)
        .foregroundStyle(selected ? Theme.onAccent : Theme.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(selected ? Theme.accent : Theme.innerSurface))
    }
    .buttonStyle(RowPressStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  /// Same toggle as the Today card, plus a line in the chat so the tap visibly did something.
  private func applyOverride(_ override: DecisionOverride?, for id: String, record: DecisionRecord) {
    DecisionOverrides.set(override, for: id)
    Analytics.track("decision_override", ["override": override?.rawValue ?? "clear", "source": "coach"])
    overrideTick += 1
    let name = ExerciseDB.find(id)?.localizedName ?? id
    let line: String
    switch override {
    case .keepOriginal:
      if let kg = record.toValue ?? record.fromValue {
        let lb = profiles.first?.usesLb ?? false
        line = String(localized: "\(name) stays at \(Fmt.kg(lb ? Plates.kgToLb(kg) : kg, lb: lb)) today.", bundle: L10n.bundle)
      } else {
        line = String(localized: "\(name) keeps the original plan today.", bundle: L10n.bundle)
      }
    case .easier:
      line = String(localized: "\(name) is one step easier today. Change it any time on Today or in the logger.", bundle: L10n.bundle)
    case .harder:
      line = String(localized: "\(name) is one step harder today. Change it any time on Today or in the logger.", bundle: L10n.bundle)
    case nil:
      line = String(localized: "\(name) is back on the planned load.", bundle: L10n.bundle)
    }
    withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: line)) }
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
    inputFocused = false
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
    while let first = turns.first, first.role != "user" { turns.removeFirst() }
    guard let asked = turns.last?.text, !asked.isEmpty else {
      thinking = false
      return
    }
    if PromptSecurity.isAttack(asked) {
      finishLocal(PromptSecurity.refusal, question: asked)
      return
    }
    // A reply to a clarification is not a new question. Resolve it first, so "Yes" or
    // "body weight" goes back to what the lifter actually asked instead of reaching the
    // model on its own.
    let question: String
    let skipClassification: Bool
    switch conversation.step(
      reply: asked,
      resolvedQuestion: { original, choice in
        String(localized: "\(original) (I mean: \(choice).)", bundle: L10n.bundle)
      })
    {
    case .ask(let text, let skip):
      question = text
      skipClassification = skip
    case .reAsk(let options):
      finishLocal(
        String(localized: "Which one — \(options.joined(separator: " or "))?", bundle: L10n.bundle),
        question: asked)
      return
    }

    let intent = skipClassification
      ? CoachIntent.trainingQuestion
      : CoachIntentClassifier.classify(question, known: knownProfileFields)
    switch intent {
    case .profileFactMissing(let field):
      finishLocal(String(localized: "I don't have your \(field) saved.", bundle: L10n.bundle), question: question)
      return
    case .ambiguous(let options):
      conversation.clarify(question: question, options: options)
      finishLocal(String(localized: "Do you mean \(options.joined(separator: " or "))?", bundle: L10n.bundle), question: question)
      return
    case .unsafeOrMedical:
      finishLocal(medicalDeflection, question: question)
      return
    case .trainingQuestion, .outOfScope:
      break
    }

    let packet = CoachAPI.contextPacket(
      profile: profiles.first,
      sessions: sessions,
      checkIns: checkIns,
      decisions: decisionLog.map(\.record),
      bodyweightKg: profiles.first?.bodyweightKg,
      usesLb: profiles.first?.usesLb ?? false,
      notes: activeNotes.prefix(20).map(\.text))

    if needsWithheldHealth(question, packet.withheld) {
      if coachOnDevice, OnDeviceCoach.isAvailable {
        let box = CoachToolBox(exercises: ExerciseDB.everything, reads: readSource)
        if let result = await OnDeviceCoach.answer(question, context: onDeviceHealthContext(packet) + onDeviceNotes(), coachName: coach.name, tools: box) {
          withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: result.text, onDevice: true, record: matchingRecord(for: result.text))) }
          if !question.isEmpty { persist("user", question) }
          persist("assistant", result.text)
          if let action = result.action { propose(action) }
          withAnimation(.snappy) { thinking = false }
          return
        }
      }
      finishLocal(String(localized: "That comes from Apple Health, and I keep it on this phone.", bundle: L10n.bundle), question: question)
      return
    }

    if coachOnDevice, OnDeviceCoach.isAvailable {
      let box = CoachToolBox(exercises: ExerciseDB.everything, reads: readSource)
      var result = await OnDeviceCoach.answer(question, context: packet.rendered() + onDeviceNotes(), coachName: coach.name, tools: box)
      if let r = result, r.action == nil, CoachOutputValidator.claimsUnbackedChange(r.text) {
        Analytics.track("coach_answer_replaced", ["kind": "unbacked_change"])
        result = nil
      }
      if let result {
        withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: result.text, onDevice: true, record: matchingRecord(for: result.text))) }
        if !question.isEmpty { persist("user", question) }
        persist("assistant", result.text)
        if let action = result.action { propose(action) }
      } else {
        await requestServer(question: question, intent: intent, packet: packet)
      }
    } else {
      await requestServer(question: question, intent: intent, packet: packet)
    }
    if (errorText != nil || warmingUp), let last = turns.last, last.role == "user" {
      turns.removeLast()
      input = last.text
    }
    withAnimation(.snappy) { thinking = false }
  }


  private var activeNotes: [CoachNote] { notes.filter { $0.isActive } }
  private func onDeviceNotes() -> String {
    guard !activeNotes.isEmpty else { return "" }
    return "\nLifter notes: " + activeNotes.prefix(20).map(\.text).joined(separator: "; ")
  }

  private func requestServer(question: String, intent: CoachIntent, packet: CoachContextPacket) async {
    do {
      let reply = try await CoachAPI.ask(
        question: question,
        packet: packet,
        coach: coach.name,
        history: turns.dropLast().map { ["role": $0.role, "content": $0.text] },
        notes: activeNotes.prefix(20).map(\.text))
      let issues = CoachOutputValidator.validate(
        answer: reply.answer,
        intent: intent,
        context: packet.rendered(),
        language: L10n.languageCode,
        usesLb: profiles.first?.usesLb ?? false)
      let resolved = resolve(reply.action)
      let answerText: String
      if CoachOutputValidator.mustReplace(issues) {
        answerText = fallbackAnswer
        if let first = issues.first {
          Analytics.track("coach_answer_replaced", ["kind": first.kind.rawValue])
        }
      } else if let unchanged = unchangedPlanChange(reply.action) {
        answerText = String(
          localized: "That's already your plan: \(planChangeSummary(unchanged)).",
          bundle: L10n.bundle)
      } else if resolved == nil, CoachOutputValidator.claimsUnbackedChange(reply.answer) {
        answerText = String(
          localized:
            "I couldn't prepare that change from your message. Tell me exactly what to change, for example “2 days a week” or “45-minute sessions”, or change it in Settings → Training.",
          bundle: L10n.bundle)
        Analytics.track("coach_answer_replaced", ["kind": "unbacked_change"])
      } else {
        answerText = reply.answer
      }
      withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: answerText, citations: reply.citations ?? [], record: matchingRecord(for: answerText))) }
      if !question.isEmpty { persist("user", question) }
      persist("assistant", answerText, citations: reply.citations ?? [])
      propose(resolved)
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
           let answer = await OnDeviceCoach.answer(question, context: packet.rendered(), coachName: coach.name) {
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

  /// A parseable adjustPlan that asks for what the profile already has, so nothing changes.
  private func unchangedPlanChange(_ payload: CoachAPI.Reply.Action?) -> PlanAdjustment? {
    guard let payload, payload.type == "adjustPlan",
      let adjustment = PlanAdjustment(
        daysPerWeek: payload.daysPerWeek,
        sessionMinutes: payload.sessionMinutes,
        goal: payload.goal,
        split: payload.split),
      let profile,
      adjustment.changing(profile.planSettings) == nil
    else { return nil }
    return adjustment
  }

  private func persist(_ role: String, _ text: String, citations: [String] = []) {
    modelContext.insert(CoachMessage(role: role, text: text, citations: citations))
  }

  private func clearConversation() {
    dismissProposal()
    conversation.reset()
    withAnimation(.snappy) { turns.removeAll() }
    try? modelContext.delete(model: CoachMessage.self)
  }

  private func resolve(_ payload: CoachAPI.Reply.Action?) -> CoachAction? {
    guard let payload else { return nil }
    let action: CoachAction
    switch payload.type {
    case "swap":
      guard let from = payload.from.flatMap(ExerciseDB.find),
            let to = payload.to.flatMap(ExerciseDB.find) else { return nil }
      action = .swap(from: from, to: to)
    case "earlyDeload": action = .earlyDeload
    case "restartBlock": action = .restartBlock
    case "remember":
      guard let note = payload.note, let cleaned = sanitizeNote(note) else { return nil }
      action = .remember(cleaned)
    case "adjustPlan":
      guard let adjustment = PlanAdjustment(
        daysPerWeek: payload.daysPerWeek,
        sessionMinutes: payload.sessionMinutes,
        goal: payload.goal,
        split: payload.split) else { return nil }
      action = .adjustPlan(adjustment)
    default: return nil
    }
    return validatedAction(action)
  }


  private func validatedAction(_ action: CoachAction?) -> CoachAction? {
    guard let action else { return nil }
    switch action {
    case .swap(let from, let to):
      guard from.id != to.id,
            plannedSwapExercises.contains(where: { $0.id == from.id }),
            ExerciseDB.replacements(for: from, equipment: swapEquipment, injuries: swapInjuries)
              .contains(where: { $0.id == to.id }) else { return nil }
      return action
    case .remember(let note):
      guard let cleaned = sanitizeNote(note), !PromptSecurity.isAttack(cleaned) else { return nil }
      return .remember(cleaned)
    case .adjustPlan(let adjustment):
      guard let profile else { return nil }
      return adjustment.changing(profile.planSettings).map { .adjustPlan($0) }
    case .earlyDeload, .restartBlock:
      return action
    }
  }
  // MARK: - Recommendation ledger
  //
  // A coach action is a recommendation: proposed, shown, then applied, declined or
  // refused. The ledger keeps those four facts separately and immutably, so "we never
  // showed it", "you waved it away" and "the engine refused it" stay distinguishable
  // afterwards, and so the effectiveness screen never has to infer them. All of it is
  // written *before* the confirmation card appears: a card can never be answered with a
  // change the ledger has no record of, and a completion alone claims no effectiveness.

  /// Where a recommendation was shown. Exposures are stored per surface, so a coach card
  /// and a Today card about the same recommendation stay countable separately.
  private static let coachSurface = "coach"

  /// One proposal window. The same action about the same program version inside one window
  /// is the *same* recommendation — which is what makes Apply idempotent — while a later
  /// ask, or a different target, is a new one. A plain 24-hour bucket of the epoch, so no
  /// locale, time zone or formatter is involved.
  private static let proposalWindow: TimeInterval = 86_400

  /// How long a proposal may still be applied. Past this it is *expired* rather than
  /// applied to a program it no longer describes.
  private static let proposalLifetime: TimeInterval = 7 * 86_400

  /// The single funnel for every coach action. Model and tool output is untrusted, so the
  /// payload is validated first; only a validated action becomes the pending action, and
  /// only a validated program change is recorded, exposed and persisted.
  private func propose(_ action: CoachAction?) {
    guard let validated = validatedAction(action) else {
      dismissProposal()
      return
    }
    if case .remember = validated {
      // A remembered fact is not a program recommendation: it changes nothing about the
      // plan, and `RecommendationValidationPolicy.knownActionTypes` has no honest type for
      // it. Recording it as a load, volume or session change would put a false label on the
      // effectiveness screen, so it is written to the coach's memory only.
      pendingAction = validated
      pendingActionID = nil
      return
    }
    guard let id = recordRecommendation(for: validated) else {
      dismissProposal()
      return
    }
    pendingAction = validated
    pendingActionID = id
    pendingPreview = preview(for: validated, id: id)
  }

  /// The identity of everything a commit must still be true about: the lines on the card,
  /// the plan they describe, and the window they are valid in.
  private func preview(for action: CoachAction, id: RecommendationID, at now: Date = .now) -> CommitPreview? {
    guard let profile else { return nil }
    let info = actionInfo(action)
    return CommitPreview(
      recommendationID: id,
      programVersion: profile.currentProgramVersionID,
      planRevision: planRevision,
      // Ids and enum cases, never the rendered card: the app switches language in place and
      // formats numbers by region, and neither of those is a change to the plan.
      previewDigest: CommitPreview.digest(
        ownerKey: profile.persistentModelID.storeIdentifier ?? "local",
        recommendationID: id,
        components: Self.digestComponents(action)),
      displayedLines: [info.title, info.detail],
      expiresAt: now.addingTimeInterval(Self.proposalLifetime))
  }

  /// The meaning of a coach action, in values no locale can rewrite.
  private static func digestComponents(_ action: CoachAction) -> [String] {
    switch action {
    case .swap(let from, let to): return ["swap", from.id, to.id]
    case .earlyDeload: return ["earlyDeload"]
    case .restartBlock: return ["restartBlock"]
    case .remember(let note): return ["remember", note]
    case .adjustPlan(let adjustment): return adjustment.digestComponents
    }
  }

  /// Compact signature of one plan state, e.g. "4-60-hypertrophy-auto".
  private static func planSignature(_ settings: PlanSettings) -> String {
    "\(settings.daysPerWeek)-\(settings.sessionMinutes)-\(settings.goal.rawValue)-\(settings.split.rawValue)"
  }

  /// The read side handed to the on-device tools: snapshots only, stamped with the plan
  /// revision they describe.
  private var readSource: CoachReadSource {
    let day = plannedCoachDay
    return CoachLocalReads(
      planRevision: planRevision,
      asOf: .now,
      dayName: day?.name,
      prescriptions: (day?.exercises ?? []).map { (planned: PlannedExercise) -> SetPrescription in
        SetPrescription(
          exerciseID: planned.exercise.id,
          load: nil,
          workingSets: planned.sets,
          minimumReps: planned.repRange.lowerBound,
          maximumReps: planned.repRange.upperBound,
          targetRPETenths: Int((planned.targetRPE * 10).rounded()))
      },
      sessionID: day.map { "\(profile?.currentProgramVersionID.rawValue ?? "v0")#\($0.name)" },
      decisions: decisionLog.map(\.record),
      sets: sessions.flatMap { session in
        session.sets.map {
          (exerciseID: $0.exerciseID, at: $0.loggedAt, weightKg: $0.weightKg, reps: $0.reps,
           rpe: $0.rpe, effortReported: $0.effortReported)
        }
      },
      equipmentIDs: profile?.equipment.sorted() ?? [],
      excludedExerciseIDs: (profile?.exerciseOverrides.keys).map { Array($0).sorted() } ?? [],
      minutesPerSession: profile?.sessionMinutes,
      daysPerWeek: profile?.daysPerWeek,
      usesLb: profile?.usesLb ?? false)
  }

  /// One definition of "which plan is this", used by the commit check and by every coach
  /// read. A content digest, not a counter: the store has no version column, and equality
  /// is all a compare-and-swap needs.
  private var planRevision: String {
    guard let profile else { return PlanRevision.none }
    var parts = [profile.currentProgramVersionID.rawValue, "week:\(profile.currentWeek(sessions: sessions))"]
    parts.append("settings:\(profile.daysPerWeek)|\(profile.sessionMinutes)|\(profile.goal)|\(profile.split)")
    for (from, to) in profile.exerciseOverrides.sorted(by: { $0.key < $1.key }) {
      parts.append("override:\(from)>\(to)")
    }
    parts.append("deload:\(profile.deloadStartedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "-")")
    parts.append("sessions:\(sessions.count)")
    return PlanRevision.digest(parts)
  }

  /// Clears the pending proposal without touching the ledger: a declined recommendation
  /// stays `.proposed`, which is exactly what "you never applied it" should look like.
  private func dismissProposal() {
    pendingAction = nil
    pendingActionID = nil
    pendingPreview = nil
  }

  /// The observations a proposal actually rests on, and the evidence lines that state them.
  /// Required and present are deliberately the same set: a signal is only required when the
  /// log really shows it, so a proposal can never be recorded as under-supported for a
  /// reason the app never had.
  private struct ProposalEvidence {
    let signals: [DecisionSignal]
    let lines: [String]
  }

  /// Freezes one validated action as a snapshot, records it once, records the exposure and
  /// persists the ledger. Returns the id the card will be answered with.
  @discardableResult
  private func recordRecommendation(for action: CoachAction, at now: Date = .now) -> RecommendationID? {
    guard let profile else { return nil }
    let programVersion = profile.currentProgramVersionID
    let evidence = proposalEvidence(for: action, profile: profile, at: now)
    let id = recommendationID(for: action, programVersion: programVersion, at: now)
    let snapshot = RecommendationSnapshot(
      id: id,
      programVersion: programVersion,
      createdAt: now,
      expiresAt: now.addingTimeInterval(Self.proposalLifetime),
      record: recommendationRecord(for: action, id: id, at: now, evidence: evidence),
      coverage: EvidenceCoverage(required: evidence.signals, present: evidence.signals),
      policy: .consequential,
      authorization: .notRequested)
    var ledger = profile.recommendationLedger
    // The ledger's idea of "current" is put in step with the profile before the snapshot is
    // stamped, or a freshly recorded proposal would read as stale on the first apply.
    ledger.advanceProgramVersion(to: programVersion)
    ledger.record(snapshot)   // write-once: re-recording an id never rewrites a snapshot
    ledger.expose(RecommendationExposure(
      recommendationID: id,
      programVersion: programVersion,
      exposedAt: now,
      surface: Self.coachSurface,
      wasConsequential: snapshot.policy.requiresConfirmation))
    profile.recommendationLedger = ledger
    try? modelContext.save()
    return id
  }

  /// Deterministic identity for one proposal: the action's own target, the program version
  /// it was generated against, and the window it belongs to.
  private func recommendationID(
    for action: CoachAction,
    programVersion: ProgramVersionID,
    at now: Date
  ) -> RecommendationID {
    let window = Int(now.timeIntervalSince1970 / Self.proposalWindow)
    let subject: String
    switch action {
    case .swap(let from, let to): subject = "swap.\(from.id).\(to.id)"
    case .earlyDeload: subject = "deload"
    case .restartBlock: subject = "restart"
    case .remember(let note): subject = "note.\(note)"
    case .adjustPlan(let adjustment):
      let current = profile?.planSettings
      let from = current.map { Self.planSignature($0) } ?? "none"
      let to = current.map { Self.planSignature(adjustment.applied(to: $0)) } ?? "none"
      subject = "plan.\(from)>\(to)"
    }
    return RecommendationID("coach.\(subject).\(programVersion.rawValue).w\(window)")
  }

  /// What the app can honestly say it observed. The lifter asking is always one of them;
  /// log-derived signals are added only when the log shows them, with the concrete number
  /// the line states.
  private func proposalEvidence(
    for action: CoachAction,
    profile: UserProfile,
    at now: Date
  ) -> ProposalEvidence {
    var signals: [DecisionSignal] = [.userOverride]
    var lines = [String(localized: "You asked for this in Coach.", bundle: L10n.bundle)]
    let plateaued = plateauedExerciseIDs(sessions: sessions, now: now)
    switch action {
    case .swap(let from, let to):
      lines.append(String(localized: "\(from.localizedName) is in your next planned session.", bundle: L10n.bundle))
      lines.append(String(localized: "\(to.localizedName) fits your equipment and injury settings.", bundle: L10n.bundle))
      if plateaued.contains(from.id) {
        signals.append(.plateau)
        lines.append(String(localized: "\(from.localizedName) has no new best in 3 weeks", bundle: L10n.bundle))
      }
    case .earlyDeload:
      if let recovery = recoveryAverages {
        if recovery.sleepHours < 6 {
          signals.append(.sleepShort)
          lines.append(String(localized: "Last 3 check-ins: \(Fmt.num(recovery.sleepHours)) h sleep", bundle: L10n.bundle))
        }
        if recovery.soreness >= 4 {
          signals.append(.sorenessHigh)
          lines.append(String(localized: "Last 3 check-ins: soreness \(recovery.soreness)/5", bundle: L10n.bundle))
        }
      }
      lines.append(blockWeekLine(profile, at: now))
    case .restartBlock:
      if !plateaued.isEmpty {
        signals.append(.plateau)
        lines.append(String(localized: "\(plateaued.count) lift\(L10n.pluralSuffix(plateaued.count)) with no new best in 3 weeks", bundle: L10n.bundle))
      }
      lines.append(blockWeekLine(profile, at: now))
    case .remember:
      break
    case .adjustPlan(let adjustment):
      let current = profile.planSettings
      return ProposalEvidence(
        signals: [.userOverride],
        lines: PlanSettings.changes(from: current, to: adjustment.applied(to: current)))
    }
    return ProposalEvidence(signals: signals, lines: lines)
  }

  private func blockWeekLine(_ profile: UserProfile, at now: Date) -> String {
    let week = profile.currentWeek(sessions: sessions)
    return String(localized: "Block is in week \(week) of \(Mesocycle.weeks)", bundle: L10n.bundle)
  }

  /// The frozen record. Its type comes from the vocabulary the ledger validates against, and
  /// its reason codes are exactly the signals the coverage requires.
  private func recommendationRecord(
    for action: CoachAction,
    id: RecommendationID,
    at now: Date,
    evidence: ProposalEvidence
  ) -> DecisionRecord {
    let info = actionInfo(action)
    let subject = ledgerSubject(for: action)
    return DecisionRecord(
      id: id.rawValue,
      date: now,
      type: ledgerType(for: action, signals: evidence.signals),
      exerciseID: subject.exerciseID,
      muscle: subject.muscle,
      fromValue: nil,
      toValue: nil,
      reasonCodes: evidence.signals.map(\.code),
      evidence: evidence.lines,
      humanSummary: "\(info.title). \(info.detail)")
  }

  /// `plateau` is derived the way `DecisionRecord.from` derives it: a decision caused by a
  /// plateau is recorded as a plateau response whatever action it takes. A block restart
  /// clears the applied set deltas and rep-range overrides, so without a plateau in the log
  /// its recorded effect is a volume change.
  private func ledgerType(for action: CoachAction, signals: [DecisionSignal]) -> String {
    switch action {
    case .swap: return "swap"
    case .earlyDeload: return "session"
    case .restartBlock: return signals.contains(.plateau) ? "plateau" : "volume_change"
    case .remember: return "session"
    case .adjustPlan: return "plan_settings"
    }
  }

  /// What the record is about: the exercise a swap replaces, or the whole session for the
  /// plan-wide actions. The ledger's conflict check keys off this.
  private func ledgerSubject(for action: CoachAction) -> (exerciseID: String?, muscle: String?) {
    switch action {
    case .swap(let from, _): return (from.id, nil)
    case .earlyDeload, .restartBlock, .remember, .adjustPlan: return (nil, nil)
    }
  }

  private func actionInfo(_ action: CoachAction) -> (title: String, detail: String) {
    switch action {
    case .swap(let from, let to):
      return ("Swap \(from.localizedName) → \(to.localizedName)", "Updates your plan to use the new exercise next session.")
    case .earlyDeload:
      return ("Start an early deload", "Cuts this week's volume so fatigue clears.")
    case .restartBlock:
      return ("Restart the block", "Begins a fresh 6-week block from week 1.")
    case .remember(let note):
      return ("Remember this?", note)
    case .adjustPlan(let adjustment):
      return (
        String(localized: "Adjust your training plan", bundle: L10n.bundle),
        planChangeSummary(adjustment))
    }
  }

  private func actionCard(_ action: CoachAction) -> some View {
    let info = actionInfo(action)
    let isRemember: Bool
    if case .remember = action { isRemember = true } else { isRemember = false }
    return VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        iconBadge(symbol(for: action))
        VStack(alignment: .leading, spacing: 2) {
          if case .swap = action {
            Text(String(localized: "Swap exercise", bundle: L10n.bundle)).forgeBodyStrong()
          } else {
            Text(info.title).forgeBodyStrong()
          }
          Text(info.detail).forgeLabel()
        }
      }
      if case .swap(let from, let to) = action { swapTiles(from, to) }
      HStack(spacing: 8) {
        Button(isRemember ? "Save note" : "Apply") { apply(action) }
          .buttonStyle(PillButtonStyle(minHeight: 44))
        Button("Not now") { dismissProposal() }
          .buttonStyle(PillSecondaryButtonStyle())
      }
    }
    .frame(maxWidth: 480, alignment: .leading)
    .card()
  }

  private func symbol(for action: CoachAction) -> String {
    switch action {
    case .swap: return "arrow.left.arrow.right"
    case .earlyDeload: return "arrow.down.right"
    case .restartBlock: return "arrow.counterclockwise"
    case .remember: return "bookmark"
    case .adjustPlan: return "calendar"
    }
  }

  /// Both exercise illustrations with the swap arrow centred on the artwork.
  private func swapTiles(_ from: Exercise, _ to: Exercise) -> some View {
    HStack(alignment: .artworkCenter, spacing: 8) {
      swapTile(from, isTo: false)
      Image(systemName: "arrow.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.accent)
        .frame(width: 32, height: 32)
        .background(Circle().fill(Theme.accentTint))
        .alignmentGuide(.artworkCenter) { $0[.top] + $0.height / 2 }
      swapTile(to, isTo: true)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(actionInfo(.swap(from: from, to: to)).title)
  }

  private func swapTile(_ ex: Exercise, isTo: Bool) -> some View {
    VStack(spacing: 6) {
      Color.clear.aspectRatio(1, contentMode: .fit)
        .overlay {
          if UIImage(named: "ex-\(ex.id)") != nil {
            Image("ex-\(ex.id)").resizable().scaledToFit().padding(6)
          } else {
            Image(systemName: "dumbbell.fill").foregroundStyle(Theme.textSecondary)
          }
        }
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).strokeBorder(Theme.imageOutline, lineWidth: 1))
      if isTo {
        Text(ex.localizedName).multilineTextAlignment(.center).lineLimit(2).forgeBodyStrong()
      } else {
        Text(ex.localizedName).multilineTextAlignment(.center).lineLimit(2).forgeLabel()
      }
    }
    .alignmentGuide(.artworkCenter) { $0[.top] + $0.width / 2 }
  }

  /// The plan-adjustment card: the real change, its consequences, the real revised sessions.
  private func adjustPlanCard(_ adjustment: PlanAdjustment) -> some View {
    let previewWeek = profile?.previewWeekPlan(adjustment, sessions: sessions)
    let counts = previewWeek?.evaluation(now: .now).counts
    let rows = planChangeRows(adjustment)
    return VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        iconBadge("calendar")
        VStack(alignment: .leading, spacing: 2) {
          Text(String(localized: "Plan change", bundle: L10n.bundle)).forgeBodyStrong()
          Text(startLine(previewWeek)).forgeLabel()
        }
      }
      VStack(spacing: 0) {
        hairline
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          changeRow(label: row.label, old: row.old, new: row.new)
          hairline
        }
      }
      if let advice = planAdjustAdvice {
        Text(advice.text).foregroundStyle(Theme.textSecondary).forgeCaption()
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(
          String(
            localized:
              "Completed workouts stay as they are. You stay in week \(profile?.currentWeek(sessions: sessions) ?? 1) of \(Mesocycle.weeks).",
            bundle: L10n.bundle))
        if adjustment.goal == nil {
          let goalName = (Goal(rawValue: profile?.goal ?? "") ?? .hypertrophy).name
          Text(String(localized: "Your goal stays \(goalName).", bundle: L10n.bundle))
        }
        if let counts {
          Text(
            String(
              localized: "This week: \(counts.completed) done · \(counts.remaining) left.",
              bundle: L10n.bundle))
        }
      }
      .forgeCaption()
      DisclosureGroup(String(localized: "View revised workouts", bundle: L10n.bundle)) {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(
            Array(revisedSessionRows(adjustment, previewWeek: previewWeek).enumerated()),
            id: \.offset
          ) { _, row in
            VStack(alignment: .leading, spacing: 2) {
              Text(row.line).forgeLabel()
              Text(row.names).forgeCaption()
            }
          }
        }
      }
      .tint(Theme.accent)
      HStack(spacing: 8) {
        Button("Apply plan changes") { apply(.adjustPlan(adjustment)) }
          .buttonStyle(PillButtonStyle(minHeight: 44))
        Button("Keep current plan") { dismissProposal() }
          .buttonStyle(PillSecondaryButtonStyle())
      }
    }
    .frame(maxWidth: 480, alignment: .leading)
    .card()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("coach.planChange")
  }

  private var hairline: some View { Divider().overlay(Theme.ring) }

  private func iconBadge(_ symbol: String) -> some View {
    Image(systemName: symbol)
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(Theme.accent)
      .frame(width: 36, height: 36)
      .background(Circle().fill(Theme.accentTint))
      .accessibilityHidden(true)
  }

  /// The first day the revision would actually rebuild, not just the first open day.
  private func startLine(_ previewWeek: WeekPlan?) -> String {
    if let previewWeek, let current = profile?.weekPlan {
      let formatter = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated).locale(
        L10n.locale)
      let byID = Dictionary(current.days.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      if let day = previewWeek.days
        .sorted(by: { $0.date < $1.date })
        .first(where: { byID[$0.id] != $0 && $0.state == .planned })
      {
        return String(
          localized: "Starts with \(day.sessionName) · \(day.date.formatted(formatter))",
          bundle: L10n.bundle)
      }
    }
    return String(localized: "Starts with your next unstarted session.", bundle: L10n.bundle)
  }

  /// One row per changed field, old value to new.
  private func planChangeRows(_ adjustment: PlanAdjustment) -> [(label: String, old: String, new: String)] {
    guard let profile else { return [] }
    let current = profile.planSettings
    var rows: [(label: String, old: String, new: String)] = []
    if let days = adjustment.daysPerWeek {
      rows.append((
        String(localized: "Days per week", bundle: L10n.bundle),
        "\(current.daysPerWeek)", "\(days)"))
    }
    if let minutes = adjustment.sessionMinutes {
      rows.append((
        String(localized: "Session length", bundle: L10n.bundle),
        String(localized: "\(current.sessionMinutes) min", bundle: L10n.bundle),
        String(localized: "\(minutes) min", bundle: L10n.bundle)))
    }
    if let goal = adjustment.goal {
      rows.append((
        String(localized: "Goal", bundle: L10n.bundle),
        current.goal.name, goal.name))
    }
    if let split = adjustment.split {
      rows.append((
        String(localized: "Split", bundle: L10n.bundle),
        current.split.name, split.name))
    }
    return rows
  }

  private func changeRow(label: String, old: String, new: String) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 8) {
        Text(label).forgeBody()
        Spacer(minLength: 8)
        Text(old).foregroundStyle(Theme.textSecondary).forgeBody()
        Image(systemName: "arrow.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Theme.textSecondary)
        Text(new)
          .foregroundStyle(Theme.accent)
          .font(.forge(15, .semibold))
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(label).forgeBody()
        HStack(spacing: 8) {
          Text(old).foregroundStyle(Theme.textSecondary).forgeBody()
          Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
          Text(new)
            .foregroundStyle(Theme.accent)
            .font(.forge(15, .semibold))
        }
      }
    }
    .monospacedDigit()
    .frame(minHeight: 44)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(String(localized: "\(label): \(old) to \(new)", bundle: L10n.bundle))
  }

  /// The same early/repeated advice Settings shows, from the real log counts.
  private var planAdjustAdvice: PlanChangeAdvice? {
    guard let profile else { return nil }
    let windowStart = Date.now.addingTimeInterval(-Double(PlanChangeAdvice.windowDays) * 86400)
    let logged = decisionLog.filter {
      $0.type == "plan_settings" && $0.date >= windowStart
    }.count
    return PlanChangeAdvice.advice(
      blockSessions: profile.mesoSessions(sessions), changesInWindow: 1 + logged)
  }

  /// The new values in words, for the card detail and the applied reply.
  private func planChangeSummary(_ adjustment: PlanAdjustment) -> String {
    var parts: [String] = []
    if let days = adjustment.daysPerWeek {
      parts.append(String(localized: "\(days) days a week", bundle: L10n.bundle))
    }
    if let minutes = adjustment.sessionMinutes {
      parts.append(
        String(localized: "about \(minutes)-minute sessions", bundle: L10n.bundle))
    }
    if let goal = adjustment.goal {
      parts.append(String(localized: "goal \(goal.name)", bundle: L10n.bundle))
    }
    if let split = adjustment.split {
      parts.append(String(localized: "split \(split.name)", bundle: L10n.bundle))
    }
    return parts.joined(separator: ", ")
  }

  /// The proposed sessions the card lists: the revised week's open days when a plan exists, else the rotation.
  private func revisedSessionRows(
    _ adjustment: PlanAdjustment, previewWeek: WeekPlan?
  ) -> [(line: String, names: String)] {
    let formatter = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated).locale(
      L10n.locale)
    if let previewWeek {
      let calendar = previewWeek.resolvedCalendar(.current)
      let today = calendar.startOfDay(for: .now)
      return previewWeek.days
        .filter { $0.state != .completed && calendar.startOfDay(for: $0.date) >= today }
        .sorted { $0.date < $1.date }
        .map { day in
          (
            String(
              localized:
                "\(day.date.formatted(formatter)) · \(day.sessionName) · \(day.exerciseIDs.count) exercises · \(day.timeBudgetMinutes) min",
              bundle: L10n.bundle),
            day.exerciseIDs.compactMap { ExerciseDB.find($0)?.localizedName }
              .joined(separator: ", ")
          )
        }
    }
    guard let profile else { return [] }
    let program = profile.previewProgram(adjustment, sessions: sessions)
    guard !program.isEmpty else { return [] }
    let applied = adjustment.applied(to: profile.planSettings)
    let count = min(applied.daysPerWeek, program.count)
    return (0..<count).map { i in
      let day = program[((profile.nextDayIndex + i) % program.count + program.count) % program.count]
      return (
        String(
          localized: "\(day.name) · \(day.exercises.count) exercises · \(applied.sessionMinutes) min",
          bundle: L10n.bundle),
        day.exercises.map(\.exercise.localizedName).joined(separator: ", ")
      )
    }
  }

  /// "Next: …" after an applied change: the accepted plan's owed day, else the rotation's next day.
  private func nextSessionLine() -> String? {
    let formatter = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated).locale(
      L10n.locale)
    if let plan = profile?.weekPlan,
      let owed = WeekPlanTodayStatus(plan: plan, now: .now).owed
    {
      return String(
        localized: "Next: \(owed.sessionName) · \(owed.date.formatted(formatter)).",
        bundle: L10n.bundle)
    }
    if let day = plannedCoachDay {
      return String(localized: "Next: \(day.name).", bundle: L10n.bundle)
    }
    return nil
  }

  /// Applies a pending coach action, ledger first. The ledger decides whether the
  /// recommendation may still be applied — idempotency, validation, staleness, eligibility
  /// and conflicts are all checked there — and only an `.applied` outcome is allowed to
  /// touch profile state. Every other outcome changes nothing and is said out loud in the
  /// conversation instead of silently disappearing.
  private func apply(_ action: CoachAction) {
    if case .remember(let note) = action {
      applyRememberedNote(note)
      return
    }
    guard let profile else { return }
    guard let id = pendingActionID,
          let snapshot = profile.recommendationLedger.snapshot(for: id) else {
      Analytics.track("coach_action_blocked", ["outcome": "unknown_recommendation"])
      finishBlocked(blockedMessage(for: .unknownRecommendation))
      return
    }

    // Consent is bound to the preview on screen. Apply mints the approval for *that*
    // preview and the policy re-checks it against the stored proposal and the current plan;
    // only then does the ledger — still the one write gate — get to decide.
    let now = Date.now
    if let stored = pendingPreview {
      let approval = CommitApproval(preview: stored, approvedAt: now)
      let rejection = CoachCommitPolicy.check(
        approval: approval,
        storedProposal: stored,
        ownerKey: profile.persistentModelID.storeIdentifier ?? "local",
        expectedOwnerKey: profile.persistentModelID.storeIdentifier ?? "local",
        currentPlanRevision: planRevision,
        currentProgramVersion: profile.currentProgramVersionID,
        existingReceiptDigest: nil,
        now: now)
      if let rejection {
        Analytics.track("coach_action_blocked", ["outcome": rejection.rawValue])
        var ledger = profile.recommendationLedger
        ledger.markFailed(id, reason: rejection.rawValue, at: now)
        profile.recommendationLedger = ledger
        try? modelContext.save()
        finishBlocked(blockedMessage(for: rejection))
        return
      }
    }

    var ledger = profile.recommendationLedger
    let outcome = ledger.apply(id, authorization: .granted, at: now)
    profile.recommendationLedger = ledger

    if case .applied = outcome, case .adjustPlan(let adjustment) = action {
      // One transaction: applyPlanChange's single save covers the ledger apply, the settings,
      // the revised week and the decision row; a failed save rolls them all back together, so
      // the ledger reads `.proposed` again and the card's "Try again" can actually work.
      applyPlanChange(adjustment, snapshot: snapshot, id: id)
      return
    }

    // Every other outcome, and every other action, is persisted here, refusals included: a
    // stale, conflicting or failed recommendation has to stay visible instead of vanishing
    // with the card.
    try? modelContext.save()

    guard case .applied = outcome else {
      Analytics.track("coach_action_blocked", ["outcome": outcomeName(outcome)])
      finishBlocked(blockedMessage(for: outcome))
      return
    }

    if case .adjustPlan(let adjustment) = action {
      applyPlanChange(adjustment, snapshot: snapshot, id: id)
      return
    }

    let reply: String
    var undo: CoachUndo?
    var title: String
    switch action {
    case .swap(let from, let to):
      let previous = profile.exerciseOverrides[from.id]
      profile.exerciseOverrides[from.id] = to.id
      reply = String(localized: "Done. \(from.localizedName) → \(to.localizedName) from your next session. You'll see it under \(coach.name)'s adjustments on Today; undo in Settings → Training.", bundle: L10n.bundle)
      undo = .swap(fromID: from.id, previousTarget: previous)
      title = String(localized: "Exercise swapped", bundle: L10n.bundle)
    case .earlyDeload:
      let previous = profile.deloadStartedAt
      profile.deloadStartedAt = .now
      reply = String(localized: "Done. Deload starts now: fewer sets this week, loads stay. Today shows the deload plan.", bundle: L10n.bundle)
      undo = .deload(previousStart: previous)
      title = String(localized: "Deload started", bundle: L10n.bundle)
    case .restartBlock:
      profile.startNewBlock()
      reply = String(localized: "Done. A fresh 6-week block starts today from week 1.", bundle: L10n.bundle)
      title = String(localized: "New block started", bundle: L10n.bundle)
    case .remember:
      // Routed to `applyRememberedNote` above; a note never reaches the ledger.
      return
    case .adjustPlan:
      // Routed to `applyPlanChange` above; the save is transactional there.
      return
    }

    // The change is written, so the ledger and the decision log are updated together, and
    // with the same reasons and the same evidence the snapshot recorded.
    profile.recommendationLedger = ledger
    let appliedEntry = DecisionLogEntry(appliedRecord(snapshot.record, at: .now, id: id))
    modelContext.insert(appliedEntry)
    try? modelContext.save()
    let receipt = CoachReceipt(
      title: title,
      undo: undo,
      appliedEntry: appliedEntry,
      recommendationID: id,
      revision: planRevision)
    Analytics.track("coach_action_applied")
    dismissProposal()
    withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: reply, receipt: receipt)) }
    persist("assistant", reply)
  }

  /// Applies an approved plan adjustment: settings, revised unstarted workouts, one decision row, one save.
  private func applyPlanChange(
    _ adjustment: PlanAdjustment, snapshot: RecommendationSnapshot, id: RecommendationID
  ) {
    guard let profile else { return }
    let beforeDays = profile.daysPerWeek
    let beforeMinutes = profile.sessionMinutes
    let beforeGoal = profile.goal
    let beforeSplit = profile.split
    let beforeOffset = profile.mesoSessionOffset
    let beforeWeekPlanJSON = profile.weekPlanJSON
    profile.applyPlanAdjustment(adjustment, sessions: sessions)
    let appliedEntry = DecisionLogEntry(appliedRecord(snapshot.record, at: .now, id: id))
    modelContext.insert(appliedEntry)
    do {
      try modelContext.save()
    } catch {
      modelContext.rollback()
      let line = String(
        localized: "I couldn't save that change, so nothing was changed. Try again.",
        bundle: L10n.bundle)
      withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: line)) }
      persist("assistant", line)
      return
    }
    var reply = String(
      localized:
        "Your upcoming plan is updated: \(planChangeSummary(adjustment)). Your completed workouts are unchanged.",
      bundle: L10n.bundle)
    if let next = nextSessionLine() {
      reply += " " + next
    }
    let receipt = CoachReceipt(
      title: String(localized: "Plan updated", bundle: L10n.bundle),
      undo: .plan(PlanUndoSnapshot(
        daysPerWeek: beforeDays,
        sessionMinutes: beforeMinutes,
        goal: beforeGoal,
        split: beforeSplit,
        mesoSessionOffset: beforeOffset,
        weekPlanJSON: beforeWeekPlanJSON,
        afterWeekPlanJSON: profile.weekPlanJSON,
        afterMesoSessionOffset: profile.mesoSessionOffset)),
      appliedEntry: appliedEntry,
      recommendationID: id,
      revision: planRevision)
    Analytics.track("coach_action_applied")
    dismissProposal()
    withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: reply, receipt: receipt)) }
    persist("assistant", reply)
  }

  /// A remembered fact only ever touches the coach's memory: it changes nothing about the
  /// plan, so it is not recorded in the ledger (see `propose`).
  private func applyRememberedNote(_ note: String) {
    let reply: String
    var receipt: CoachReceipt?
    if let cleaned = sanitizeNote(note) {
      let kind = CoachMemoryKind.infer(from: cleaned)
      var superseded: [CoachNote] = []
      if [.equipment, .schedule, .goal].contains(kind) {
        for existing in activeNotes where existing.memoryKind == kind && existing.text != cleaned {
          existing.supersededAt = .now
          superseded.append(existing)
        }
      }
      let inserted = CoachNote(text: cleaned, kind: kind, source: "coach")
      modelContext.insert(inserted)
      reply = String(localized: "Noted. I'll keep that in mind.", bundle: L10n.bundle)
      receipt = CoachReceipt(
        title: String(localized: "Note saved", bundle: L10n.bundle),
        undo: .note(inserted, superseded: superseded),
        appliedEntry: nil,
        recommendationID: nil,
        revision: planRevision)
    } else {
      reply = "That note looks like an instruction, not a fact — skipped."
    }
    Analytics.track("coach_action_applied")
    dismissProposal()
    withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: reply, receipt: receipt)) }
    persist("assistant", reply)
  }

  /// Nothing was changed, and the lifter is told why in the conversation.
  private func finishBlocked(_ text: String) {
    dismissProposal()
    withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: text)) }
    persist("assistant", text)
  }

  /// One sentence per bound-consent rejection. The lifter is told what stopped it, never
  /// that "something went wrong".
  private func blockedMessage(for rejection: CommitRejection) -> String {
    switch rejection {
    case .expired:
      return String(localized: "That suggestion is too old to apply now. Ask again and I'll rebuild it against your current plan.", bundle: L10n.bundle)
    case .staleRevision:
      return String(localized: "Your plan changed after I showed you that, so nothing was changed. Ask again for a fresh version.", bundle: L10n.bundle)
    case .digestMismatch, .replayedWithDifferentContent:
      return String(localized: "That doesn't match what I showed you, so I didn't apply it.", bundle: L10n.bundle)
    case .unknownProposal, .wrongOwner:
      return blockedMessage(for: .unknownRecommendation)
    }
  }

  /// One sentence per ledger outcome, naming the limit that stopped the change. A conflict
  /// names no recommendation id: the id is internal, the target is what the lifter can see.
  private func blockedMessage(for outcome: RecommendationApplyOutcome) -> String {
    switch outcome {
    case .alreadyApplied:
      return String(localized: "You already applied this one and your program hasn't changed since, so nothing was changed.", bundle: L10n.bundle)
    case .stale:
      return String(localized: "Your plan has moved on since \(coach.name) suggested this, so I haven't changed anything. Ask again and I'll propose it against your current plan.", bundle: L10n.bundle)
    case .conflict:
      return String(localized: "Another suggestion already changed this same part of your plan, so I haven't changed anything. Undo that change in Settings → Training if you'd rather have this one.", bundle: L10n.bundle)
    case .ineligible(let reasons):
      return String(localized: "I can't apply this one: \(reasons.map(ineligibilityReason).joined(separator: " ")) Nothing was changed.", bundle: L10n.bundle)
    case .failed:
      return String(localized: "This suggestion didn't pass my own checks, so I haven't changed anything.", bundle: L10n.bundle)
    case .unknownRecommendation:
      return String(localized: "I don't have a record of this suggestion, so I haven't changed anything.", bundle: L10n.bundle)
    case .applied:
      return String(localized: "Nothing was changed.", bundle: L10n.bundle)
    }
  }

  private func ineligibilityReason(_ reason: RecommendationIneligibility) -> String {
    switch reason {
    case .insufficientEvidence:
      return String(localized: "I haven't recorded enough of the evidence it needs.", bundle: L10n.bundle)
    case .authorizationMissing, .authorizationDenied, .authorizationRevoked:
      return String(localized: "this kind of change isn't allowed for you.", bundle: L10n.bundle)
    }
  }

  private func outcomeName(_ outcome: RecommendationApplyOutcome) -> String {
    switch outcome {
    case .applied: return "applied"
    case .alreadyApplied: return "already_applied"
    case .stale: return "stale"
    case .conflict: return "conflict"
    case .ineligible: return "ineligible"
    case .failed: return "failed"
    case .unknownRecommendation: return "unknown_recommendation"
    }
  }

  /// The decision log entry for an applied recommendation: the same type, subject, reasons
  /// and evidence the snapshot froze, dated when the change was actually written.
  private func appliedRecord(_ record: DecisionRecord, at now: Date, id: RecommendationID) -> DecisionRecord {
    DecisionRecord(
      id: id.rawValue,
      date: now,
      type: record.type,
      exerciseID: record.exerciseID,
      muscle: record.muscle,
      fromValue: record.fromValue,
      toValue: record.toValue,
      reasonCodes: record.reasonCodes,
      evidence: record.evidence,
      humanSummary: record.humanSummary)
  }
}

/// Reads the per-frame mic level in its own body so the chat behind voice mode is not re-evaluated.
private struct LiveVoiceDisc: View {
  let speech: SpeechInput
  let phase: CoachVoicePhase
  let label: String
  let action: () -> Void

  var body: some View {
    VoiceDisc(phase: phase, level: speech.level, label: label, action: action)
  }
}

/// Reads the live transcript in its own body so word updates do not re-evaluate the chat.
private struct LiveVoiceTranscript: View {
  let speech: SpeechInput
  let placeholder: String
  let showsCursor: Bool

  var body: some View {
    VoiceTranscript(
      text: speech.transcript,
      pending: speech.pending,
      placeholder: placeholder,
      showsCursor: showsCursor)
  }
}

enum CoachAction {
  case swap(from: Exercise, to: Exercise)
  case earlyDeload
  case restartBlock
  case remember(String)
  case adjustPlan(PlanAdjustment)
}

/// Centres the swap arrow on the exercise artwork, not on the label under it.
private extension VerticalAlignment {
  enum ArtworkCenter: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.top] }
  }
  static let artworkCenter = VerticalAlignment(ArtworkCenter.self)
}

/// What one applied change replaced, so the receipt's Undo can put exactly that back.
enum CoachUndo {
  case plan(PlanUndoSnapshot)
  case swap(fromID: String, previousTarget: String?)
  case deload(previousStart: Date?)
  case note(CoachNote, superseded: [CoachNote])
}

/// The plan fields `applyPlanAdjustment` rewrites, as they were before it ran, plus the
/// week state it produced, so Undo never wipes a plan that moved on afterwards.
struct PlanUndoSnapshot {
  let daysPerWeek: Int
  let sessionMinutes: Int
  let goal: String
  let split: String
  let mesoSessionOffset: Int
  let weekPlanJSON: String
  let afterWeekPlanJSON: String
  let afterMesoSessionOffset: Int
}

/// The one-line receipt that replaces an applied card. Undo is offered only while the plan is
/// still exactly the one the change produced.
struct CoachReceipt {
  let title: String
  var undo: CoachUndo?
  let appliedEntry: DecisionLogEntry?
  let recommendationID: RecommendationID?
  let revision: String
  var undone = false
}
