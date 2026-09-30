import ActivityKit
import ForgeCore
import SwiftData
import SwiftUI
import UserNotifications

struct WorkoutView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var allSessions: [WorkoutSession]
  @Query(sort: \CheckIn.date, order: .reverse) private var checkIns: [CheckIn]
  @Query(sort: \CoachNote.date, order: .reverse) private var coachNotes: [CoachNote]
  @AppStorage(Coach.storageKey) private var voiceCoachID = Coach.nova.rawValue
  @AppStorage("voiceActivationRequired") private var voiceActivationRequired = false
  @AppStorage("voiceFastLogging") private var fastVoiceLogging = false
  @AppStorage("voiceSmartFallback") private var voiceSmartFallback = false
  @AppStorage("coachAudioMode") private var coachAudioMode = CoachAudioMode.off.rawValue
  @State private var coachAnswer: String?
  @State private var coachAsking = false

  let plannedDay: PlannedDay
  let action: FatigueAction
  var resuming: WorkoutSession? = nil
  /// The accepted week-plan day this session is for, when Today decided one. Finishing
  /// uses it to record the day instead of guessing from the session's date and name.
  var planDayID: String? = nil

  @State private var session: WorkoutSession?
  @State private var weights: [String: [String]] = [:]
  @State private var reps: [String: [Int]] = [:]
  @State private var rpes: [String: [Double]] = [:]
  @State private var variants: [String: SetVariant] = [:]
  @State private var restEnd: Date?
  @State private var restTotal: TimeInterval = 0
  /// When this rest window began — on-screen rest controls arm 0.6 s later.
  @State private var restStartedAt: Date?
  @State private var showPlates = false
  /// Slots whose RPE the lifter explicitly set — the only ones that count as reported.
  @State private var reportedRPESlots: Set<String> = []
  @State private var prs: [PRRecord] = []
  @State private var showSummary = false
  @State private var summary: SessionSummary?
  /// The logged set whose optional feedback sheet is open, if any. Nothing opens it on its own.
  @State private var feedbackSet: LoggedSet?
  @State private var debrief: [DebriefLine] = []
  @State private var confirmFinish = false
  @State private var confirmDiscard = false
  /// A completion whose save failed: the workout stayed open instead of being announced.
  @State private var completionSaveFailed = false
  @State private var restExercise: Exercise?
  @State private var restNextSet = 0
  @State private var restTotalSets = 0
  @State private var restRPESet: LoggedSet?
  @State private var restActivity: ActivityKit.Activity<RestActivityAttributes>?
  @State private var hrTask: Task<Void, Never>?
  @State private var heartbeatTask: Task<Void, Never>?
  @State private var swaps: [String: Exercise] = [:]
  @State private var swapTarget: PlannedExercise?
  @State private var currentExerciseID: String?
  @State private var pendingJump: LoggedSet?
  @State private var loggedCount = 0
  @State private var finishedCount = 0
  @State private var activeSlot: String?
  /// Why the set on screen refused to log — blank or unusable load text, or zero reps.
  @State private var entryError: String?
  @State private var showNotes = false
  @State private var showAddExercise = false
  @State private var noteTarget: PlannedExercise?
  @State private var detailTarget: Exercise?
  @State private var whyTarget: PlannedExercise?
  @State private var warmUpExpanded: Set<String> = []
  @State private var warmUpDone: Set<String> = []
  @FocusState private var focused: String?
  @State private var quickLogToast: String?
  @State private var quickLogToastUndo: (() -> Void)?
  /// Where a typed or voice set landed, so the receipt can offer "Go to <exercise>".
  @State private var quickLogToastExerciseID: String?
  @State private var quickLogToastExerciseName: String?
  @State private var quickLogToastSlot: String?
  @State private var voice = VoiceControl()
  @State private var stabilizer = VoiceStabilizer()
  @State private var commitLog = VoiceCommitLog()
  /// Turn-based lifecycle for voice commands: decides whether a parsed command must be
  /// clarified, confirmed or run, and remembers what already ran so it can never run twice.
  @State private var voiceCoordinator = VoiceConversationCoordinator()
  /// Spoken guidance narrator: already-committed state only, never a draft.
  @State private var coachAudio = CoachAudioCoordinator()
  /// Monotonic cue revision — a newer event supersedes queued-but-unspoken cues.
  @State private var audioRevision = 0
  @State private var pendingCommand: VoiceCommand?
  @State private var pendingTranscript = ""
  /// Non-nil while the card on screen is a clarification, not a confirmation.
  @State private var voiceClarificationPrompt: String?
  @State private var lastUndo: (() -> Void)?
  @State private var unrecognisedText: String?
  /// Smart-fallback classification in flight: the utterance, its transcript, and the
  /// logged-set count when it started. Any later change drops a late answer.
  @State private var voiceFallbackPending: (id: UUID, transcript: String, loggedAtStart: Int)?
  /// The most recent utterance the mic delivered; a fallback answer older than this is stale.
  @State private var lastVoiceUtteranceID: UUID?
  @State private var liveCandidateResult: VoiceCandidate?
  @State private var toastTask: Task<Void, Never>?
  @State private var expandedExercises: Set<String> = []
  @State private var focusMode = false
  /// Bumped by every stepper tap so one `.sensoryFeedback(.selection,…)` on the screen covers
  /// the weight, reps and RPE steppers — the controls a lifter touches most between sets.
  @State private var stepTick = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  private var profile: UserProfile? { profiles.first }
  private var usesLb: Bool { profile?.usesLb ?? false }
  /// The language the voice parser expects: Vietnamese when the app is in Vietnamese,
  /// English otherwise (until more languages get grammars).
  private var voiceLanguage: VoiceLanguage {
    L10n.languageCode == "vi" ? .vi : .en
  }
  private var equipment: Set<Equipment> {
    Set(profile?.equipment.compactMap { Equipment(rawValue: $0) } ?? [])
  }
  private var goal: Goal { profile.map { Goal(rawValue: $0.goal) ?? .hypertrophy } ?? .hypertrophy }

  // MARK: plate calculator context
  //
  // One identity, read from the slot that is actually open: its exercise, its entered load,
  // its unit, its loading convention. The load used to come from `focusedKg` — the LAST
  // logged weight, whatever exercise it belonged to — so a typed `deadlift 60x8` while
  // Lunge was on screen produced a Lunge card with a 60 kg barbell prescription. A visible
  // exercise name is never combined with a global last-entered load again.

  /// The exercise the plate calculator describes: whatever slot is open in the queue.
  private var platesExercise: Exercise? { activeEditorSlot?.exercise }

  /// The slot's own entered load, in kilograms. Nil when no slot is open or no load is known.
  private var platesTargetKg: Double? {
    guard let slot = activeEditorSlot else { return nil }
    let id = slot.planned.exercise.id
    let entries = weights[id] ?? []
    let text = entries.indices.contains(slot.index) ? entries[slot.index] : ""
    let entered = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    if entered > 0 { return isLb(for: id) ? Plates.lbToKg(entered) : entered }
    return suggestedKg(slot.planned)
  }

  /// The slot's own unit, not the unit of whatever was logged last.
  private var platesUsesLb: Bool {
    guard let slot = activeEditorSlot else { return usesLb }
    return isLb(for: slot.planned.exercise.id)
  }

  /// True only for a bar that plates actually go on. Everything else gets its convention
  /// stated instead of a plate prescription it cannot honour.
  private var platesAreLoadable: Bool {
    platesExercise?.equipment == .barbell
  }

  private var platesConvention: LoadingConvention {
    guard let equipment = platesExercise?.equipment else { return .totalIncludingBar }
    switch equipment {
    case .barbell: return .totalIncludingBar
    case .dumbbell: return .perHand
    case .bodyweight: return .notApplicable
    case .machine, .cable, .bands: return .unknown
    }
  }

  private var platesEquipmentLabel: String? {
    guard let exercise = platesExercise else { return nil }
    let gym =
      profile?.trainingConstraints.activeGymProfile?.name
      ?? String(localized: "Your gym", bundle: L10n.bundle)
    return String(
      localized: "\(exercise.equipment.rawValue.capitalized) · \(gym)", bundle: L10n.bundle)
  }

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 0) {
            band
            if focusMode {
              section { focusModeCard }
            }
            if let active = activeEditorSlot {
              activeSetSection(active.planned, active.exercise, active.index)
                .id(Self.activeCardAnchor)
            }
            if action != .proceed {
              band
              section { fatigueNote }
            }
            if !focusMode {
              if effortShown {
                band
                section { effortSection }
              }
              if !upcomingExercises.isEmpty {
                band
                section { upNextSection }
              }
              band
              section { exerciseQueue }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
          VStack(spacing: 0) {
            headerTabs
            statsRow
          }
          .background(Theme.page)
        }
        .scrollDismissesKeyboard(.interactively)
        // The set being logged is the only thing on this screen with a deadline. When the active
        // slot MOVES — a tapped pending row, a voice jump, or `commit` advancing to the next
        // pending set — the editor and its Log button come back under the thumb instead of being
        // left wherever the lifter had scrolled to.
        //
        // Deliberately keyed on `activeSlot` and not on `loggedCount`: `commit` already reassigns
        // the slot, so keying on the count would only add a second scroll for the same event —
        // and would yank the viewport back even when the slot did not move, overriding a lifter
        // who scrolled ahead to read a later exercise between sets.
        .onChange(of: activeSlot) { _, slot in
          guard slot != nil else { return }
          withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            proxy.scrollTo(Self.activeCardAnchor, anchor: .top)
          }
        }
      }
      .navigationTitle(localizedDayName(plannedDay.name))
      .toolbarTitleDisplayMode(.inlineLarge)
      .overlay {
        if restEnd != nil {
          Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Color.black.opacity(0.3))
            .ignoresSafeArea()
            .transition(.opacity)
            .accessibilityHidden(true)
        }
      }
      .safeAreaInset(edge: .bottom) { restBar }
      .sensoryFeedback(.success, trigger: loggedCount)
      .sensoryFeedback(.success, trigger: finishedCount)
      .sensoryFeedback(.selection, trigger: stepTick)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          coachAudioToggle
        }
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button(focusMode ? "Show full workout" : "Focus mode") {
              withAnimation(reduceMotion ? nil : .snappy) { focusMode.toggle() }
            }
            Button("Notes") { showNotes = true }
            Button("Plate calculator") { showPlates = true }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .accessibilityLabel("More options")
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            finishTapped()
          } label: {
            Text("Finish")
              .forge(16, .semibold)
              .foregroundStyle(Theme.accentText)
          }
          .accessibilityLabel("Finish workout")
        }
        if focused != nil {
          ToolbarItemGroup(placement: .keyboard) {
            if let slot = activeEditorSlot {
              Button("Log set \(slot.index + 1)") {
                focused = nil
                logActiveSet()
              }
              .bold()
              .tint(Theme.accentText)
            }
            Spacer()
            Button("Done") { focused = nil }
          }
        }
      }
      .sheet(isPresented: $showPlates) {
        if let profile, let kg = platesTargetKg {
          PlatesSheet(
            kg: kg,
            usesLb: platesUsesLb,
            bar: platesUsesLb ? profile.barLb : profile.barKg,
            plates: platesUsesLb ? profile.platesLb : profile.platesKg,
            exerciseName: platesExercise?.localizedName,
            convention: platesConvention,
            equipmentLabel: platesEquipmentLabel,
            isLoadable: platesAreLoadable)
        } else {
          // No entered load and no comparable suggestion: no fake 0 kg plate math.
          NavigationStack {
            VStack(spacing: 10) {
              Text("Choose load").forge(15, .semibold)
              Text("Enter a load on a set to see its plates.")
                .forgeCaption()
                .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.page)
            .navigationTitle("Plates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { showPlates = false } }
          }
          .presentationDetents([.medium])
          .presentationBackground(Theme.page)
        }
      }
      .sheet(item: $swapTarget) { planned in
        let current = swaps[planned.exercise.id] ?? planned.exercise
        SwapSheet(current: current, equipment: equipment) { replacement in
          swaps[planned.exercise.id] = replacement
        }
      }
      .sheet(item: $detailTarget) { exercise in
        ExerciseDetailView(
          exercise: exercise,
          sessions: allSessions,
          usesLb: isLb(for: exercise.id),
          note: Binding(
            get: { profile?.exerciseNotes[exercise.id] ?? "" },
            set: { profile?.exerciseNotes[exercise.id] = $0.isEmpty ? nil : $0 }))
      }
      .sheet(item: $noteTarget) { planned in
        NoteSheet(
          title: "Exercise note",
          text: Binding(
            get: { profile?.exerciseNotes[planned.exercise.id] ?? "" },
            set: { profile?.exerciseNotes[planned.exercise.id] = $0.isEmpty ? nil : $0 }))
      }
      .sheet(item: $whyTarget) { planned in
        WhySheet(
          exercise: swaps[planned.exercise.id] ?? planned.exercise, base: baseDecision(for: planned)
        ) { kg in
          let lb = self.isLb(for: planned.exercise.id)
          return Fmt.kg(lb ? Plates.kgToLb(kg) : kg, lb: lb)
        } onOverride: {
          self.reseedSuggestion(for: planned)
        }
      }
      .sheet(isPresented: $showNotes) {
        NoteSheet(
          title: "Workout notes",
          text: Binding(
            get: { session?.notes ?? "" },
            set: { session?.notes = $0 }))
      }
      .sheet(isPresented: $showAddExercise) {
        AddExerciseSheet(equipment: equipment, exclude: Set(exerciseList.map(\.exercise.id))) {
          exercise in
          addExercise(exercise)
        }
      }
      .sheet(isPresented: $showSummary, onDismiss: { dismiss() }) {
        if let summary {
          SessionSummaryView(
            summary: summary, prs: prs, debrief: debrief, usesLb: usesLb, session: session
          ) {
            showSummary = false
          }
          .interactiveDismissDisabled()
        }
      }
      .sheet(item: $feedbackSet) { set in
        SetFeedbackSheet(
          set: set,
          exerciseName: ExerciseDB.find(set.exerciseID)?.localizedName ?? set.exerciseID,
          usesLb: isLb(for: set.exerciseID))
      }
      .sheet(isPresented: voiceSheetBinding) {
        if let command = pendingCommand {
          voiceConfirmation(command)
        }
      }
      .onAppear(perform: setup)
      .onReceive(NotificationCenter.default.publisher(for: .forgeSkipRest)) { _ in skipRest() }
      .onReceive(NotificationCenter.default.publisher(for: .forgeLogSet)) { _ in logActiveSet() }
      .task(id: restEnd) {
        guard let end = restEnd else { return }
        try? await Task.sleep(for: .milliseconds(max(0, Int(end.timeIntervalSinceNow * 1000))))
        guard !Task.isCancelled, restEnd == end else { return }
        coachAudio.announceRestFinished(
          eventID: "rest-\(Int(end.timeIntervalSince1970))",
          revision: nextAudioRevision())
        skipRest()
      }
      .alert("Finish with \(loggedCount) of \(totalSets) sets logged?", isPresented: $confirmFinish) {
        Button("Keep going", role: .cancel) {}
        Button("Finish workout") { finish() }
      }
      .alert(
        String(localized: "Nothing logged yet", bundle: L10n.bundle),
        isPresented: $confirmDiscard
      ) {
        Button(String(localized: "Keep going", bundle: L10n.bundle), role: .cancel) {}
        Button(String(localized: "Discard workout", bundle: L10n.bundle), role: .destructive) {
          discard()
        }
      }
      .alert(
        String(localized: "Couldn't save this workout", bundle: L10n.bundle),
        isPresented: $completionSaveFailed
      ) {
        Button(String(localized: "Try again", bundle: L10n.bundle)) { finish() }
        Button(String(localized: "Keep going", bundle: L10n.bundle), role: .cancel) {}
      } message: {
        Text(
          String(
            localized:
              "Nothing was recorded, so your sets and this workout are still here. Finishing again will try once more — if it keeps failing, free up storage on this device.",
            bundle: L10n.bundle))
      }
      .confirmationDialog(
        pendingJumpTitle,
        isPresented: Binding(
          get: { pendingJump != nil },
          set: { if !$0 { pendingJump = nil } }),
        titleVisibility: .visible
      ) {
        Button("Keep set") { keepPendingJump() }
        Button("Fix it", role: .cancel) { pendingJump = nil }
      }
      .onDisappear {
        UserDefaults(suiteName: WidgetBridge.suite)?.set(false, forKey: "forge.workout.active")
        hrTask?.cancel()
        heartbeatTask?.cancel()
        voice.onPartial = nil
        voice.onUtterance = nil
        voice.stop()
        voiceCoordinator.reduce(.reset)
        coachAudio.tearDown()
        cancelRestNotification()
        endRestActivity()
      }
      .overlay(alignment: .top) { quickLogToastView }
      .onChange(of: scenePhase) { _, phase in
        if phase != .active { coachAudio.clear() }
      }
      .onChange(of: voice.unavailableReason) { _, reason in
        if let reason {
          // A dead engine closes the turn: no pending card may outlive it.
          pendingCommand = nil
          voiceClarificationPrompt = nil
          voiceCoordinator.reduce(.failed(reason))
        }
      }
      .onChange(of: WatchSync.shared.heartRate) { _, value in
        if value != nil { session?.heartRateSeen = true }
      }
    }
    .background(Theme.page)
  }

  // MARK: structure

  /// Scroll anchor for the active set editor. One constant so the card and the two places that
  /// scroll it back into reach can never drift apart.
  private static let activeCardAnchor = "workout.activeSet"

  private var exerciseList: [PlannedExercise] {
    var list = plannedDay.exercises.filter {
      !(session?.removedExerciseIDs.contains($0.exercise.id) ?? false)
    }
    let have = Set(list.map(\.exercise.id))
    list.append(
      contentsOf: (session?.extraExerciseIDs ?? []).compactMap { id -> PlannedExercise? in
        guard !have.contains(id), let ex = ExerciseDB.find(id) else { return nil }
        return PlannedExercise(
          exercise: ex, sets: 3, repRange: Program.repRange(ex, goal: goal), targetRPE: 8)
      })
    guard let order = session?.order, !order.isEmpty else { return list }
    var out: [PlannedExercise] = []
    for id in order {
      if let p = list.first(where: { $0.exercise.id == id }) { out.append(p) }
    }
    out.append(contentsOf: list.filter { !order.contains($0.exercise.id) })
    return out
  }

  private func sets(for id: String) -> Int {
    session?.setCounts[id] ?? plannedDay.exercises.first { $0.exercise.id == id }?.sets ?? 3
  }

  private func isLb(for id: String) -> Bool {
    profile?.unitOverrides[id] ?? usesLb
  }

  private func displayUnit(for id: String) -> String {
    isLb(for: id) ? "lb" : "kg"
  }

  private func hasLogged(_ id: String) -> Bool {
    session?.sets.contains { $0.exerciseID == id } ?? false
  }

  private func hasNext(_ id: String) -> Bool {
    let ids = exerciseList.map(\.exercise.id)
    guard let i = ids.firstIndex(of: id) else { return false }
    return i + 1 < ids.count
  }

  private func isSecondOfSuperset(_ id: String) -> Bool {
    let ids = exerciseList.map(\.exercise.id)
    guard let i = ids.firstIndex(of: id), i > 0 else { return false }
    return session?.supersets.contains(ids[i - 1]) == true
  }

  private func inSuperset(_ id: String) -> Bool {
    session?.supersets.contains(id) == true || isSecondOfSuperset(id)
  }

  private func toggleSuperset(_ id: String) {
    var sup = session?.supersets ?? []
    if sup.contains(id) {
      sup.removeAll { $0 == id }
    } else if isSecondOfSuperset(id) {
      let ids = exerciseList.map(\.exercise.id)
      if let i = ids.firstIndex(of: id), i > 0 { sup.removeAll { $0 == ids[i - 1] } }
    } else if hasNext(id) {
      sup.append(id)
    }
    session?.supersets = sup
  }

  private func move(_ id: String, _ delta: Int) {
    var ids = exerciseList.map(\.exercise.id)
    guard let i = ids.firstIndex(of: id) else { return }
    let j = i + delta
    guard ids.indices.contains(j) else { return }
    ids.swapAt(i, j)
    session?.order = ids
  }

  private func addSet(_ planned: PlannedExercise, _ count: Int) {
    let id = planned.exercise.id
    session?.setCounts[id] = count + 1
    let suggestion = suggestedKg(planned).map { formatDisplay($0, lb: isLb(for: id)) } ?? ""
    var w = weights[id] ?? []
    while w.count < count { w.append(suggestion) }
    w.append(w.last ?? suggestion)
    weights[id] = w
    var r = reps[id] ?? []
    while r.count < count { r.append(planned.repRange.lowerBound) }
    r.append(r.last ?? planned.repRange.lowerBound)
    reps[id] = r
    var e = rpes[id] ?? []
    while e.count < count { e.append(8) }
    e.append(e.last ?? 8)
    rpes[id] = e
  }

  private func removeLastSet(_ id: String, _ count: Int) {
    session?.setCounts[id] = max(1, count - 1)
    if var w = weights[id], w.count >= count {
      w.removeLast()
      weights[id] = w
    }
    if var r = reps[id], r.count >= count {
      r.removeLast()
      reps[id] = r
    }
    if var e = rpes[id], e.count >= count {
      e.removeLast()
      rpes[id] = e
    }
  }

  private func removeExercise(_ id: String) {
    session?.removedExerciseIDs.append(id)
    var sup = session?.supersets ?? []
    sup.removeAll { $0 == id }
    session?.supersets = sup
    session?.order = exerciseList.map(\.exercise.id)
  }

  private func addExercise(_ exercise: Exercise) {
    let id = exercise.id
    session?.extraExerciseIDs.append(id)
    session?.order = exerciseList.map(\.exercise.id)
    let suggestion = suggestedKg(
      PlannedExercise(
        exercise: exercise, sets: 3, repRange: Program.repRange(exercise, goal: goal), targetRPE: 8)
    ).map { formatDisplay($0, lb: isLb(for: id)) } ?? ""
    weights[id] = (0..<3).map { _ in suggestion }
    reps[id] = [Int](repeating: Program.repRange(exercise, goal: goal).lowerBound, count: 3)
    rpes[id] = [Double](repeating: 8, count: 3)
  }

  private func toggleUnit(_ id: String) {
    let toLb = !isLb(for: id)
    profile?.unitOverrides[id] = toLb
    weights[id] = (weights[id] ?? []).map { text in
      let value = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
      return formatDisplay(value, fromLb: !toLb)
    }
  }

  private var plannedSetCoordinates: Set<PlannedSetCoordinate> {
    Set(
      exerciseList.flatMap { planned in
        (0..<sets(for: planned.exercise.id)).map {
          PlannedSetCoordinate(exerciseID: planned.exercise.id, setIndex: $0)
        }
      })
  }

  private var loggedSetCoordinates: Set<PlannedSetCoordinate> {
    Set(
      (session?.sets ?? []).map {
        PlannedSetCoordinate(exerciseID: $0.exerciseID, setIndex: $0.setIndex)
      })
  }

  private var remainingPlannedSetCount: Int {
    WorkoutProgressPolicy.remainingPlannedSets(
      planned: plannedSetCoordinates,
      logged: loggedSetCoordinates)
  }
  private var focusModeCard: some View {
    let remaining = remainingPlannedSetCount
    let remainingText =
      remaining == 1
      ? String(localized: "One set at a time · 1 set left", bundle: L10n.bundle)
      : String(localized: "One set at a time · \(remaining) sets left", bundle: L10n.bundle)
    return HStack(spacing: 10) {
      Image(systemName: "scope")
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Theme.accent)
      VStack(alignment: .leading, spacing: 2) {
        Text("Focus Mode").forgeBodyStrong()
        Text(remainingText).forgeLabel().monospacedDigit()
      }
      Spacer()
      Button {
        withAnimation(reduceMotion ? nil : .snappy) { focusMode = false }
      } label: {
        Text("Exit").forgeLabel().frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
      }
    }
    .innerSurface()
    .accessibilityElement(children: .combine)
  }
  // MARK: header

  /// The full-width white sections and their 8 pt grey separators (Huawei pattern).
  private func section<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .padding(.top, 14)
      .padding(.bottom, 16)
      .padding(.horizontal, 20)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var band: some View {
    Theme.pageGrey.frame(height: 8)
  }

  private var headerTabs: some View {
    ExerciseTabs(
      items: exerciseList.map { planned in
        let id = planned.exercise.id
        let exercise = swaps[id] ?? planned.exercise
        return ExerciseTabs.Item(
          id: id,
          name: exercise.localizedName,
          done: (0..<sets(for: id)).allSatisfy { loggedSet(exercise.id, $0) != nil },
          current: activeEditorSlot?.planned.exercise.id == id)
      },
      onTap: jumpToExercise)
      // Container element so the progress string has its own home: without `.contain`, the
      // label would be pushed onto the tab buttons, whose own exercise-name labels win — and
      // the E2E assertion on "N of M sets logged" would find nothing.
      .accessibilityElement(children: .contain)
      .accessibilityLabel("\(loggedCount) of \(totalSets) sets logged")
  }

  /// Elapsed / load / sets, centered under the tabs (Huawei stat strip).
  private var statsRow: some View {
    HStack(alignment: .top, spacing: 0) {
      statColumn(Theme.gradStand, label: String(localized: "Elapsed", bundle: L10n.bundle)) {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          statValue(elapsedText(at: context.date))
        }
      }
      statColumn(Theme.gradMove, label: String(localized: "Load", bundle: L10n.bundle)) {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          statValue(loadText)
          statSuffix(loadUnit)
        }
      }
      statColumn(Theme.gradExercise, label: String(localized: "Sets", bundle: L10n.bundle)) {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          statValue("\(loggedCount)")
          statSuffix("/\(totalSets)")
        }
      }
    }
    .padding(.top, 10)
    .padding(.bottom, 14)
    .padding(.horizontal, 12)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(statsAccessibilityLabel)
  }

  private func statColumn<Value: View>(
    _ colors: [Color], label: String, @ViewBuilder value: () -> Value
  ) -> some View {
    VStack(spacing: 3) {
      HStack(spacing: 5) {
        GradientDot(colors: colors)
        Text(label).forge(13).foregroundStyle(Theme.textSecondary)
      }
      value()
        .frame(minHeight: 28)
    }
    .frame(maxWidth: .infinity)
  }

  private func statValue(_ text: String) -> some View {
    Text(text)
      .forge(24, .semibold)
      .monospacedDigit()
      .foregroundStyle(Theme.text)
      .contentTransition(reduceMotion ? .identity : .numericText())
  }

  private func statSuffix(_ text: String) -> some View {
    Text(text)
      .forge(13)
      .monospacedDigit()
      .foregroundStyle(Theme.textSecondary)
  }

  /// Live session tonnage in the lifter's unit, grouped ("2,050").
  private var loadKg: Double {
    (session?.sets ?? []).reduce(0) { $0 + $1.weightKg * Double($1.reps) }
  }

  private var loadText: String {
    Fmt.grouped(usesLb ? Plates.kgToLb(loadKg) : loadKg)
  }

  private var loadUnit: String { usesLb ? "lb" : "kg" }

  private var statsAccessibilityLabel: String {
    let s = max(0, Int(Date.now.timeIntervalSince(session?.date ?? .now)))
    return String(
      localized:
        "Elapsed \(s / 60) minutes \(s % 60) seconds, load \(loadText) \(loadUnit), \(loggedCount) of \(totalSets) sets",
      bundle: L10n.bundle)
  }

  /// Rail and Up next taps: open the exercise's first pending set, or its detail when all are logged.
  private func jumpToExercise(_ id: String) {
    guard let planned = exerciseList.first(where: { $0.exercise.id == id }) else { return }
    let exercise = swaps[id] ?? planned.exercise
    for index in 0..<sets(for: id) where loggedSet(exercise.id, index) == nil {
      entryError = nil
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { activeSlot = key(id, index) }
      return
    }
    detailTarget = exercise
  }

  /// Mute/repeat for spoken guidance. Tap toggles mute; long-press repeats the last cue.
  @ViewBuilder private var coachAudioToggle: some View {
    if coachAudioMode != CoachAudioMode.off.rawValue {
      Button {
        coachAudio.toggleMuted()
      } label: {
        Image(systemName: coachAudio.muted ? "speaker.slash" : "speaker.wave.2.fill")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(coachAudio.muted ? Theme.textTertiary : Theme.metricTime)
          .contentTransition(.symbolEffect(.replace))
          .animation(.spring(duration: 0.3, bounce: 0), value: coachAudio.muted)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(ControlPressStyle())
      .accessibilityLabel(
        coachAudio.muted
          ? String(localized: "Coach audio muted", bundle: L10n.bundle)
          : String(localized: "Coach audio on", bundle: L10n.bundle)
      )
      .accessibilityHint(
        String(
          localized: "Double tap to mute or unmute. Touch and hold to repeat.",
          bundle: L10n.bundle)
      )
      .accessibilityIdentifier("workout.audio.toggle")
      .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 44) {
        coachAudio.repeatLast()
      }
    }
  }

  private var fatigueNote: some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.accent)
      Text(actionNote).forgeLabel()
    }
    .innerSurface()
  }

  private var totalSets: Int {
    exerciseList.reduce(0) { $0 + sets(for: $1.exercise.id) }
  }

  private func elapsedText(at now: Date) -> String {
    guard let start = session?.date else { return "0:00" }
    let s = max(0, Int(now.timeIntervalSince(start)))
    return String(format: "%d:%02d", s / 60, s % 60)
  }

  private var actionNote: String {
    switch action {
    case .reduceOptionalSets:
      return String(localized: "Fatigue is elevated — optional sets trimmed.", bundle: L10n.bundle)
    case .lightSession:
      return String(
        localized: "Light session — volume reduced, RPE capped at 7.", bundle: L10n.bundle)
    case .forceRest:
      return String(localized: "High fatigue — keep today conservative.", bundle: L10n.bundle)
    default: return ""
    }
  }

  // MARK: setup / resume

  private func setup() {
    wireVoice()
    UserDefaults(suiteName: WidgetBridge.suite)?.set(true, forKey: "forge.workout.active")
    startHeartbeat()
    WatchSync.shared.startWatchWorkout(dayName: plannedDay.name)
    Task { await Notifications.requestAuthorization() }
    for a in ActivityKit.Activity<RestActivityAttributes>.activities {
      Task { await a.end(nil, dismissalPolicy: .immediate) }
    }
    // A rest left by a killed logger must not fire "Rest over" into this one.
    if restEnd == nil { cancelRestNotification() }
    guard session == nil, let profile else { return }
    // Seed the equipment passport from constraints the first time a workout needs it.
    profile.seedEquipmentPassportIfEmpty()
    focusMode = profile.trainingConstraints.focusModeDefault
    Analytics.track("workout_started", ["day": plannedDay.name])
    Notifications.cancelReengagement()
    if let resuming {
      session = resuming
      prefill(fromLogged: true)
      loggedCount = resuming.sets.count
      activeSlot = firstPendingSlot()
      sendWatchPlan()
      return
    }
    let newSession = WorkoutSession(
      date: .now, dayName: plannedDay.name, week: profile.currentWeek(sessions: allSessions),
      completed: false)
    newSession.rememberPrescription(plannedDay, planDayID: planDayID)
    if planDayID != nil {
      newSession.plannedPlanID = profile.weekPlan?.id
      newSession.plannedAcceptanceID = profile.weekPlan?.acceptanceID
    }
    modelContext.insert(newSession)
    try? modelContext.save()
    session = newSession
    prefill(fromLogged: false)
    activeSlot = firstPendingSlot()
    sendWatchPlan()
  }

  private func prefill(fromLogged: Bool) {
    // ponytail: adjustments(base: nil) — .addReps is the only kind prefill needs; base only gates newVariant
    let addRepIDs = Set(
      adjustments(
        for: plannedDay, base: nil, sessions: allSessions, profile: profile, usesLb: usesLb
      )
      .filter { $0.kind == .addReps }
      .map { $0.exercise.id })
    for planned in exerciseList {
      let id = planned.exercise.id
      let exercise = swaps[id] ?? planned.exercise
      let suggestion = resolvedLoadSuggestion(for: planned, sessions: allSessions, profile: profile)
      let count = max(1, sets(for: id))
      let last = lastSets(exercise.id, in: allSessions, profile: profile)
      var w: [String] = []
      var r: [Int] = []
      var e: [Double] = []
      for index in 0..<count {
        if fromLogged, let logged = loggedSet(exercise.id, index) {
          w.append(formatDisplay(logged.weightKg, lb: isLb(for: id)))
          r.append(logged.reps)
          e.append(logged.rpe)
        } else {
          w.append(suggestion.map { formatDisplay($0, lb: isLb(for: id)) } ?? "")
          let ghostReps = index < last.count ? last[index].reps : nil
          r.append(
            addRepIDs.contains(id) && ghostReps != nil
              ? min(ghostReps! + 1, planned.repRange.upperBound)
              : planned.repRange.lowerBound)
          e.append(8.0)
        }
      }
      weights[id] = w
      reps[id] = r
      rpes[id] = e
    }
  }

  private func sendWatchPlan() {
    var suggestedByID: [String: Double] = [:]
    var restByID: [String: Int] = [:]
    for planned in exerciseList {
      // Omit lifts with no comparable load history so Watch shows no invented load.
      if let kg = suggestedKg(planned) { suggestedByID[planned.exercise.id] = kg }
      restByID[planned.exercise.id] = restSeconds(
        for: swaps[planned.exercise.id] ?? planned.exercise)
    }
    let day = PlannedDay(
      name: plannedDay.name,
      exercises: exerciseList.map {
        PlannedExercise(
          exercise: $0.exercise, sets: sets(for: $0.exercise.id), repRange: $0.repRange,
          targetRPE: $0.targetRPE)
      })
    WatchSync.shared.sendPlan(
      day, suggested: { suggestedByID[$0.id] }, rest: { restByID[$0.id] ?? 0 },
      dayName: plannedDay.name)
  }

  // MARK: bindings

  private func weightBinding(_ id: String, _ index: Int) -> Binding<String> {
    Binding(
      get: { weights[id]?[index] ?? "" },
      set: { newValue in
        var array = weights[id] ?? []
        while array.count <= index { array.append("") }
        array[index] = newValue
        weights[id] = array
        if activeSlot == key(id, index) { entryError = nil }
      })
  }

  private func repsBinding(_ id: String, _ index: Int) -> Binding<Int> {
    Binding(
      get: { reps[id]?[index] ?? 0 },
      set: { newValue in
        var array = reps[id] ?? []
        while array.count <= index { array.append(0) }
        array[index] = newValue
        reps[id] = array
        if activeSlot == key(id, index) { entryError = nil }
      })
  }

  private func repsText(_ id: String, _ index: Int) -> Binding<String> {
    Binding(
      get: { String(reps[id]?[index] ?? 0) },
      set: { newValue in
        var array = reps[id] ?? []
        while array.count <= index { array.append(0) }
        array[index] = Int(newValue) ?? 0
        reps[id] = array
        if activeSlot == key(id, index) { entryError = nil }
      })
  }

  private func rpeBinding(_ id: String, _ index: Int) -> Binding<Double> {
    Binding(
      get: { rpes[id]?[index] ?? 8 },
      set: { newValue in
        var array = rpes[id] ?? []
        while array.count <= index { array.append(8) }
        array[index] = newValue
        rpes[id] = array
        // An explicit change is what turns the plan's default into a reported effort.
        reportedRPESlots.insert(key(id, index))
      })
  }

  private func selectedVariant(_ id: String, _ index: Int) -> SetVariant {
    variants[key(id, index)] ?? .straight
  }

  private func restSeconds(for exercise: Exercise) -> Int {
    guard let profile else { return exercise.restSeconds }
    return profile.restOverrides[exercise.id]
      ?? (exercise.isCompound ? profile.restCompoundSeconds : profile.restIsolationSeconds)
  }

  private func log(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int) {
    let id = planned.exercise.id
    let lb = isLb(for: id)
    let text = weights[id]?[index] ?? ""
    let slotReps = reps[id]?[index] ?? 0
    // A blank or garbled load must refuse to log, not silently save 0 kg.
    guard
      let value = LoadEntry.parse(
        text, allowsZero: exercise.equipment == .bodyweight || exercise.equipment == .bands),
      slotReps >= 1
    else {
      activeSlot = key(id, index)
      entryError = String(localized: "Enter the load and reps you did.", bundle: L10n.bundle)
      return
    }
    let kg = lb ? Plates.lbToKg(value) : value
    // The RPE stepper starts on the plan's default, so only an explicit change is a report.
    let reported = reportedRPESlots.contains(key(id, index)) ? rpes[id]?[index] : nil
    entryError = nil
    log(planned, exercise, index, weightKg: kg, reps: slotReps, rpe: reported)
  }

  /// Same gate as `log(_: _: _:)`, for the button's disabled state.
  private func entryIsValid(_ id: String, _ index: Int, _ exercise: Exercise) -> Bool {
    LoadEntry.parse(
      weights[id]?[index] ?? "",
      allowsZero: exercise.equipment == .bodyweight || exercise.equipment == .bands) != nil
      && (reps[id]?[index] ?? 0) >= 1
  }

  private func log(
    _ planned: PlannedExercise, _ exercise: Exercise, _ index: Int, weightKg: Double, reps: Int,
    rpe: Double?
  ) {
    let id = planned.exercise.id
    let lb = isLb(for: id)
    let loggedAt = Date.now
    let variant = selectedVariant(id, index).rawValue
    let set = LoggedSet(
      exerciseID: exercise.id,
      setIndex: index,
      weightKg: weightKg,
      reps: reps,
      rpe: rpe ?? 8,
      targetRPE: planned.targetRPE,
      variant: variant,
      loggedAt: loggedAt,
      loadDescriptor: resolvedDescriptor(
        slotID: id, exercise: exercise, variant: variant, index: index, weightKg: weightKg),
      effortReported: rpe != nil)
    let e1rm = Strength.epley(weightKg: weightKg, reps: reps)
    if Plausibility.isJump(
      e1rm: e1rm, previousBest: previousBestE1RM(for: exercise.id, reference: set))
    {
      pendingJump = set
      return
    }
    commit(set, planned: planned, exercise: exercise, index: index)
  }

  /// Descriptor for the set about to be logged: the original typed display value/unit plus
  /// the resolved equipment context, or the conservative inference when nothing resolves.
  private func resolvedDescriptor(
    slotID: String, exercise: Exercise, variant: String, index: Int, weightKg: Double
  ) -> LoadDescriptor {
    let display = weights[slotID]?[index] ?? ""
    let kind = EquipmentKind(equipment: exercise.equipment)
    return profile?.equipmentLoadDescriptor(
      exerciseID: exercise.id,
      variant: variant,
      displayValue: display,
      displayUnit: displayUnit(for: slotID),
      weightKg: weightKg,
      side: UserProfile.defaultSide(for: kind))
      ?? LoggedSet.inferredDescriptor(exerciseID: exercise.id, weightKg: weightKg)
  }

  /// Weight (kg) for a displayed slot's typed value, honouring the per-exercise unit.
  private func displayedKg(_ id: String, _ index: Int) -> Double {
    let text = weights[id]?[index] ?? ""
    let value = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    return isLb(for: id) ? Plates.lbToKg(value) : value
  }

  /// Monotonic revision shared by every cue of one committed event, so a newer event
  /// supersedes queued-but-unspoken narration without dropping its siblings.
  private func nextAudioRevision() -> Int {
    audioRevision += 1
    return audioRevision
  }

  /// Narrate only after the set is saved and the next slot is the committed current one.
  private func announceCommittedSet(slotID: String, setIndex: Int) {
    let rev = nextAudioRevision()
    coachAudio.announceSetLogged(
      eventID: "logged-\(slotID)-\(setIndex)",
      revision: rev,
      setIndex: setIndex + 1)
    guard let next = activeEditorSlot else { return }
    let nextID = next.planned.exercise.id
    coachAudio.announceNextSet(
      eventID: "next-\(nextID)-\(next.index)",
      revision: rev,
      exercise: next.exercise.localizedName,
      setIndex: next.index + 1,
      load: spokenWeight(kg: displayedKg(nextID, next.index), lb: isLb(for: nextID)),
      minReps: next.planned.repRange.lowerBound,
      maxReps: next.planned.repRange.upperBound)
  }

  private func commit(_ set: LoggedSet, planned: PlannedExercise, exercise: Exercise, index: Int) {
    // A repeat commit for an already logged slot is a double tap, not a new set.
    guard loggedSet(set.exerciseID, set.setIndex) == nil else { return }
    let id = planned.exercise.id
    set.suspect =
      set.suspect
      || Plausibility.isRapid(loggedAt: set.loggedAt, previous: session?.sets.map(\.loggedAt).max())
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
      modelContext.insert(set)
      session?.sets.append(set)
    }
    do {
      // Test seam for the failed-set-save path; compiled out of Release builds.
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--fail-set-save") {
        throw CocoaError(.fileWriteUnknown)
      }
      #endif
      try modelContext.save()
    } catch {
      session?.sets.removeAll { $0 === set }
      modelContext.delete(set)
      activeSlot = key(planned.exercise.id, index)
      entryError = String(
        localized: "Couldn't save this set. Your numbers are still here — try again.",
        bundle: L10n.bundle)
      return
    }
    currentExerciseID = exercise.id
    loggedCount += 1
    Analytics.track("set_logged")
    let seconds = restSeconds(for: exercise)
    let firstOfPair = session?.supersets.contains(id) == true
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
      if !firstOfPair {
        restTotal = TimeInterval(seconds)
        restEnd = Date.now.addingTimeInterval(TimeInterval(seconds))
        restStartedAt = .now
      }
      activeSlot = firstPendingSlot()
      focused = nil
    }
    if !firstOfPair {
      restRPESet = set
      restExercise = exercise
      restNextSet = index + 2
      restTotalSets = sets(for: id)
      scheduleRestNotification(
        seconds: seconds, exercise: exercise, nextSet: index + 2, totalSets: sets(for: id))
      syncRestActivity(
        end: restEnd ?? .now, exercise: exercise, nextSet: index + 2, totalSets: sets(for: id))
      startHeartRateLoop()
    }
    announceCommittedSet(slotID: id, setIndex: index)
  }

  private func keepPendingJump() {
    guard let set = pendingJump else { return }
    guard
      let planned = exerciseList.first(where: {
        $0.exercise.id == set.exerciseID || swaps[$0.exercise.id]?.id == set.exerciseID
      })
    else {
      pendingJump = nil
      return
    }
    pendingJump = nil
    let exercise = swaps[planned.exercise.id] ?? planned.exercise
    set.suspect = true
    commit(set, planned: planned, exercise: exercise, index: set.setIndex)
  }

  private func previousBestE1RM(for exerciseID: String, reference: LoggedSet) -> Double? {
    let sets =
      allSessions
      .filter { $0.completed && $0 !== session }
      .flatMap(\.sets)
      .filter {
        $0.exerciseID == exerciseID && !$0.suspect && $0.isComparableForBaseline(to: reference)
      }
    return sets.map { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }.max()
  }

  private var pendingJumpTitle: String {
    guard let set = pendingJump else { return "" }
    let lb = isLb(for: set.exerciseID)
    let new = Strength.epley(weightKg: set.weightKg, reps: set.reps)
    let previous = previousBestE1RM(for: set.exerciseID, reference: set) ?? 0
    return String(
      localized:
        "Big jump: \(formatDisplay(previous, lb: lb)) → \(formatDisplay(new, lb: lb)) e1RM. Keep it?",
      bundle: L10n.bundle)
  }

  private func logActiveSet() {
    guard let slot = activeSlot,
      let planned = exerciseList.first(where: { slot.hasPrefix("\($0.exercise.id)#") }),
      let index = Int(slot.dropFirst(planned.exercise.id.count + 1))
    else { return }
    log(planned, swaps[planned.exercise.id] ?? planned.exercise, index)
  }

  // MARK: quick log

  /// Exercises still to come; a tap jumps the editor there.
  private var upcomingExercises: [PlannedExercise] {
    let current = activeEditorSlot?.planned.exercise.id
    return exerciseList.filter { planned in
      let exercise = swaps[planned.exercise.id] ?? planned.exercise
      return planned.exercise.id != current
        && !(0..<sets(for: planned.exercise.id)).allSatisfy { loggedSet(exercise.id, $0) != nil }
    }
  }

  private var upNextSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Up next").forge(16, .semibold)
      ForEach(Array(upcomingExercises.enumerated()), id: \.element.id) { index, planned in
        upNextRow(planned)
          .overlay(alignment: .top) {
            if index > 0 {
              Rectangle().fill(Theme.ring).frame(height: 0.5)
            }
          }
      }
    }
  }

  private func upNextRow(_ planned: PlannedExercise) -> some View {
    let exercise = swaps[planned.exercise.id] ?? planned.exercise
    let id = planned.exercise.id
    return Button {
      jumpToExercise(id)
    } label: {
      HStack(spacing: 12) {
        WorkoutArtTile(exercise: exercise, size: 56)
        VStack(alignment: .leading, spacing: 3) {
          Text(exercise.localizedName)
            .forge(16, .medium)
            .foregroundStyle(Theme.text)
            .lineLimit(1)
          Text(verbatim: prescription(planned, exercise))
            .forge(13)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
  }

  /// "4 × 8–12 · 47.5 kg" — planned sets and rep range, then the suggested load when one
  /// exists (a bodyweight movement with no added-load history says so instead of "0 kg").
  private func prescription(_ planned: PlannedExercise, _ exercise: Exercise) -> String {
    let id = planned.exercise.id
    var text = "\(sets(for: id)) × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound)"
    if let kg = suggestedKg(planned), kg > 0 {
      text += " · \(formatDisplay(kg, lb: isLb(for: id))) \(displayUnit(for: id))"
    } else if exercise.equipment == .bodyweight {
      text += " · \(String(localized: "Bodyweight", bundle: L10n.bundle))"
    }
    return text
  }

  // MARK: effort by set

  private var effortShown: Bool {
    guard let slot = activeEditorSlot else { return false }
    return hasLogged(slot.exercise.id)
  }

  @ViewBuilder private var effortSection: some View {
    if let slot = activeEditorSlot {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
          Text("Effort by set").forge(16, .semibold)
          Text("(RPE)").forge(13).foregroundStyle(Theme.textSecondary)
          Image(systemName: "info.circle")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textTertiary)
            .accessibilityHidden(true)
          Spacer()
          Button {
            detailTarget = slot.exercise
          } label: {
            Text("Last time").forge(14, .medium).foregroundStyle(Theme.accentText)
          }
          .buttonStyle(ControlPressStyle())
        }
        VStack(alignment: .leading, spacing: 8) {
          effortChart(slot)
          effortLegend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(effortAccessibilityLabel(slot))
      }
    }
  }

  /// One bar per planned set: logged sets filled to their RPE with the zone gradient and the
  /// value above, the current set a dashed accent outline to the target, later sets a muted
  /// bar to the target. A dashed target line runs across at the plan's RPE.
  private func effortChart(_ slot: (planned: PlannedExercise, exercise: Exercise, index: Int))
    -> some View
  {
    let count = sets(for: slot.planned.exercise.id)
    let target = slot.planned.targetRPE
    return GeometryReader { geo in
      let width = geo.size.width
      let height = geo.size.height
      let left: CGFloat = 26
      let bottom: CGFloat = 22
      let top: CGFloat = 8
      let plotHeight = height - bottom - top
      let y: (Double) -> CGFloat = { v in top + plotHeight * (10 - v) / 5 }
      let step = count > 0 ? (width - left - 12) / CGFloat(count) : 0
      ZStack(alignment: .topLeading) {
        ForEach(6...10, id: \.self) { v in
          Rectangle()
            .fill(Theme.track)
            .frame(width: width - left, height: 1)
            .position(x: left + (width - left) / 2, y: y(Double(v)))
          Text(verbatim: "\(v)")
            .forge(11)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
            .frame(width: left - 8, alignment: .trailing)
            .position(x: (left - 8) / 2, y: y(Double(v)))
        }
        Path { p in
          p.move(to: CGPoint(x: left, y: y(target)))
          p.addLine(to: CGPoint(x: width, y: y(target)))
        }
        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
        HStack {
          Spacer()
          Text("Target \(Fmt.num(target))")
            .forge(11, .semibold)
            .foregroundStyle(Theme.accentText)
            .monospacedDigit()
        }
        .frame(width: width - left)
        .position(x: left + (width - left) / 2, y: y(target) - 11)
        ForEach(0..<max(count, 1), id: \.self) { i in
          let x = left + 6 + step * CGFloat(i) + step / 2
          Text("Set \(i + 1)")
            .forge(11, i == slot.index ? .semibold : .regular)
            .foregroundStyle(i == slot.index ? Theme.accentText : Theme.textSecondary)
            .position(x: x, y: height - 8)
          if let logged = loggedSet(slot.exercise.id, i) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(.mark(Theme.zone(rpe: logged.rpe), startPoint: .bottom, endPoint: .top))
              .frame(width: 34, height: max(0, y(5) - y(logged.rpe)))
              .position(x: x, y: (y(logged.rpe) + y(5)) / 2)
            Text(Fmt.num(logged.rpe))
              .forge(12, .semibold)
              .monospacedDigit()
              .foregroundStyle(Theme.text)
              .position(x: x, y: y(logged.rpe) - 9)
          } else if i == slot.index {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
              .frame(width: 34, height: max(0, y(5) - y(target)))
              .position(x: x, y: (y(target) + y(5)) / 2)
          } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(Theme.innerSurface)
              .frame(width: 34, height: max(0, y(5) - y(target)))
              .position(x: x, y: (y(target) + y(5)) / 2)
          }
        }
      }
    }
    .frame(height: 150)
  }

  private var effortLegend: some View {
    let labels = [
      String(localized: "Easy", bundle: L10n.bundle),
      String(localized: "Moderate", bundle: L10n.bundle),
      String(localized: "Hard", bundle: L10n.bundle),
      String(localized: "Very hard", bundle: L10n.bundle),
      String(localized: "Max", bundle: L10n.bundle),
    ]
    return HStack(spacing: 12) {
      ForEach(Array(zip(Theme.zones.indices, labels)), id: \.0) { zone, label in
        HStack(spacing: 5) {
          GradientDot(colors: Theme.zones[zone])
          Text(label).forge(12).foregroundStyle(Theme.textSecondary)
        }
      }
    }
  }

  private func effortAccessibilityLabel(
    _ slot: (planned: PlannedExercise, exercise: Exercise, index: Int)
  ) -> String {
    let parts = (0..<sets(for: slot.planned.exercise.id)).compactMap { i -> String? in
      guard let logged = loggedSet(slot.exercise.id, i) else { return nil }
      return String(
        localized: "set \(i + 1) RPE \(Fmt.num(logged.rpe))", bundle: L10n.bundle)
    }
    return String(
      localized:
        "Effort by set: \(parts.joined(separator: ", ")), target \(Fmt.num(slot.planned.targetRPE))",
      bundle: L10n.bundle)
  }

  /// 48pt mic: quiet outlined/tinted when idle; cyan + white icon + breathing ring while hearing.
  private var voiceButton: some View {
    Button {
      toggleVoiceControl()
    } label: {
      ZStack {
        Circle().fill(voiceArmed ? Theme.metricTime : Theme.innerSurface)
        if voice.state == .arming {
          ProgressView()
        } else {
          Image(systemName: voiceIcon)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(
              voiceArmed ? Theme.onAccent : (voiceFailed ? Theme.negative : Theme.textSecondary))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, isActive: voice.state == .hearing)
            .offset(y: voiceIcon == "waveform" ? 0 : 1)
        }
      }
      .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0), value: voice.state)
      .frame(width: 48, height: 48)
      .overlay(Circle().strokeBorder(voiceArmed ? .clear : Theme.ring, lineWidth: 1))
    }
    .buttonStyle(ControlPressStyle())
    .accessibilityLabel(voiceAccessibilityLabel)
    .disabled(voice.state == .arming)
  }

  @ViewBuilder
  private var quickLogToastView: some View {
    if let toast = quickLogToast {
      let goToName = quickLogToastExerciseName
      VStack(alignment: .leading, spacing: 8) {
        Text(toast)
          .forge(14, .semibold)
          .foregroundStyle(Theme.onAccent)
          .lineLimit(2)
        if goToName != nil || quickLogToastUndo != nil {
          HStack(spacing: 10) {
            if let goToName {
              Button {
                goToLoggedExercise()
              } label: {
                HStack(spacing: 6) {
                  Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 12, weight: .bold))
                  Text(String(localized: "Go to \(goToName)", bundle: L10n.bundle))
                    .forge(14, .bold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous).fill(Theme.onAccent.opacity(0.18)))
              }
              .buttonStyle(RowPressStyle())
              .accessibilityLabel(String(localized: "Go to \(goToName)", bundle: L10n.bundle))
              .accessibilityHint("Shows this exercise in the queue without changing it")
            }
            Spacer(minLength: 0)
            if quickLogToastUndo != nil {
              Button {
                performUndo()
                toastTask?.cancel()
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { clearToast() }
              } label: {
                Text(String(localized: "Undo", bundle: L10n.bundle))
                  .forge(14, .bold)
                  .foregroundStyle(Theme.onAccent)
                  .padding(.horizontal, 12)
                  .frame(minHeight: 44)
                  .background(RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous).fill(Theme.onAccent.opacity(0.18)))
              }
              .buttonStyle(RowPressStyle())
              .accessibilityLabel("Undo")
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Theme.inner)
      .background(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.accentStrong)
      )
      .padding(.horizontal, Theme.margin)
      .padding(.top, 8)
      .transition(reduceMotion ? .opacity : .offset(y: -8).combined(with: .opacity))
    }
  }

  private func wireVoice() {
    // Partials are display-only: show a live candidate hint, never act on it.
    voice.onPartial = { _ in
      unrecognisedText = nil
      liveCandidateResult = liveCandidate()
    }
    voice.onUtterance = { transcript, utteranceID in
      liveCandidateResult = nil
      stabilizer.reset()
      handleUtterance(transcript, utteranceID: utteranceID)
    }
  }

  private func toggleVoiceControl() {
    switch voice.state {
    case .off:
      startVoice()
    case .failed:
      startVoice()
    default:
      voice.stop()
    }
  }

  private func startVoice() {
    voiceCoordinator.reduce(.beginListening)
    let vocab = SpeechVocabulary.lifting(extra: exerciseList.map { $0.exercise.localizedName })
    Task { await voice.start(vocabulary: vocab) }
  }

  private func quickLogCandidates() -> [QuickLogCandidate] {
    var seen = Set<String>()
    var out: [QuickLogCandidate] = []
    func add(_ exercise: Exercise?) {
      guard let exercise, !seen.contains(exercise.id) else { return }
      seen.insert(exercise.id)
      out.append(QuickLogCandidate(id: exercise.id, name: exercise.name))
    }
    for planned in exerciseList {
      add(swaps[planned.exercise.id] ?? planned.exercise)
    }
    let cutoff = Date.now.addingTimeInterval(-30 * 86400)
    let recentSets =
      allSessions
      .filter { $0.date > cutoff }
      .sorted { $0.date > $1.date }
      .flatMap { $0.sets.sorted { $0.loggedAt > $1.loggedAt } }
    for set in recentSets { add(ExerciseDB.find(set.exerciseID)) }
    for exercise in ExerciseDB.everything { add(exercise) }
    return out
  }

  private func plannedEntry(for exerciseID: String) -> (slot: PlannedExercise, exercise: Exercise)?
  {
    for planned in exerciseList {
      let effective = swaps[planned.exercise.id] ?? planned.exercise
      if effective.id == exerciseID {
        return (planned, effective)
      }
    }
    return nil
  }

  private func firstPendingSetIndex(slotID: String, exerciseID: String) -> Int? {
    let count = sets(for: slotID)
    for index in 0..<count where loggedSet(exerciseID, index) == nil {
      return index
    }
    return nil
  }

  /// Log a parsed quick-log set (the voice `.logSet` command).
  private func logParsed(_ parse: QuickLogParse, undo: (() -> Void)? = nil) {
    guard let exercise = ExerciseDB.find(parse.exerciseID) else {
      return
    }
    var landingSlot: String?
    if let (slot, effective) = plannedEntry(for: parse.exerciseID) {
      if let index = firstPendingSetIndex(slotID: slot.exercise.id, exerciseID: effective.id) {
        log(slot, effective, index, weightKg: parse.weightKg, reps: parse.reps, rpe: parse.rpe)
        landingSlot = key(slot.exercise.id, index)
      } else {
        let newCount = (session?.setCounts[slot.exercise.id] ?? sets(for: slot.exercise.id)) + 1
        session?.setCounts[slot.exercise.id] = newCount
        log(
          slot, effective, newCount - 1, weightKg: parse.weightKg, reps: parse.reps, rpe: parse.rpe)
        landingSlot = key(slot.exercise.id, newCount - 1)
      }
    } else {
      addExercise(exercise)
      if let (slot, effective) = plannedEntry(for: exercise.id) {
        log(slot, effective, 0, weightKg: parse.weightKg, reps: parse.reps, rpe: parse.rpe)
        landingSlot = key(slot.exercise.id, 0)
      }
    }
    let lb = isLb(for: parse.exerciseID)
    let unit = lb ? "lb" : "kg"
    let display = lb ? Plates.kgToLb(parse.weightKg) : parse.weightKg
    var toast = "Logged \(exercise.localizedName) · \(Fmt.num(display)) \(unit) × \(parse.reps)"
    if let rpe = parse.rpe { toast += " @ \(Fmt.num(rpe))" }
    if let undo { lastUndo = undo }
    showToast(
      toast, undo: undo,
      exerciseID: exercise.id, exerciseName: exercise.localizedName, slot: landingSlot)
  }

  private func showToast(
    _ text: String,
    undo: (() -> Void)? = nil,
    exerciseID: String? = nil,
    exerciseName: String? = nil,
    slot: String? = nil
  ) {
    toastTask?.cancel()
    quickLogToastUndo = undo
    quickLogToastExerciseID = exerciseID
    quickLogToastExerciseName = exerciseName
    quickLogToastSlot = slot
    withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0)) { quickLogToast = text }
    let seconds = undo == nil ? 2 : 5
    toastTask = Task {
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled else { return }
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { clearToast() }
    }
  }

  private func clearToast() {
    quickLogToast = nil
    quickLogToastUndo = nil
    quickLogToastExerciseID = nil
    quickLogToastExerciseName = nil
    quickLogToastSlot = nil
  }

  /// Reveal and select the exercise a typed or voice set landed in. Selection only — it never
  /// touches weight, reps or RPE, so no prescription changes behind the lifter's back.
  private func goToLoggedExercise() {
    guard let exerciseID = quickLogToastExerciseID else { return }
    toastTask?.cancel()
    guard
      let planned = exerciseList.first(where: {
        $0.exercise.id == exerciseID || swaps[$0.exercise.id]?.id == exerciseID
      })
    else {
      withAnimation(reduceMotion ? nil : .snappy) { clearToast() }
      return
    }
    let slotID = planned.exercise.id
    let pending = firstPendingSetIndex(slotID: slotID, exerciseID: exerciseID).map {
      key(slotID, $0)
    }
    currentExerciseID = exerciseID
    withAnimation(reduceMotion ? nil : .snappy) {
      expandedExercises.insert(slotID)
      if let target = pending ?? quickLogToastSlot { activeSlot = target }
      clearToast()
    }
  }

  // MARK: voice commands

  private var voiceSheetBinding: Binding<Bool> {
    Binding(
      get: { pendingCommand != nil },
      set: { if !$0 { dismissVoiceCard() } })
  }

  private func handleUtterance(_ transcript: String, utteranceID: UUID) {
    lastVoiceUtteranceID = utteranceID
    // A cancelled or failed turn is closed; the next utterance opens a fresh one.
    if voiceCoordinator.state == .cancelled || voiceCoordinator.state == .failed {
      voiceCoordinator.reduce(.reset)
    }
    let required = voiceActivationRequired
    guard
      let stripped = VoiceCommandParser.stripActivation(
        transcript, required: required, language: voiceLanguage),
      !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    let command = VoiceCommandParser.parse(
      stripped, candidates: quickLogCandidates(), defaultLb: usesLb, language: voiceLanguage)
    routeVoiceCommand(command, transcript: stripped, utteranceID: utteranceID)
  }

  private func routeVoiceCommand(
    _ raw: VoiceCommand, transcript: String, utteranceID: UUID,
    classified: (intent: VoiceIntent, confidence: Double)? = nil
  ) {
    var command = raw
    if case .logSet(let parse) = command, parse.exerciseID.isEmpty {
      if let (planned, _, _) = activeEditorSlot {
        var resolved = parse
        resolved.exerciseID = planned.exercise.id
        command = .logSet(resolved)
      } else {
        command = .unrecognised(transcript)
      }
    }

    // Idempotency: a partial and its final transcript share one utterance id, so the
    // same command only commits once.
    guard commitLog.shouldCommit(command, utteranceID: utteranceID) else { return }

    Analytics.track("voice_command", ["kind": voiceKind(command)])

    // A classifier's answer is a guess with a number attached: a guessed log always
    // confirms (a wrong load is the one mistake that hurts someone), and anything else
    // — including undo/confirm/cancel/ask-coach — needs ≥ 0.9 confidence before it may
    // act. `.unrecognised` never acts, so it falls through to its own branch below.
    // An uncertain guess is never run behind the lifter's back: the coordinator holds it
    // as a clarification until an explicit yes.
    if let classified, classifierMustConfirm(command, classified) {
      dispatchVoice(.heardIncomplete(command), transcript: transcript)
      return
    }

    switch command {
    case .confirm:
      approveVoiceCard()
    case .cancel:
      cancelVoiceCard()
    case .undo:
      applyUndo()
    case .askCoach(let question):
      // A question changes nothing in the workout: it gets its own card and never enters
      // the command lifecycle.
      pendingTranscript = transcript
      voiceClarificationPrompt = nil
      pendingCommand = .askCoach(question)
      Task { await askCoachFromVoice(question) }
    case .unrecognised:
      if voiceSmartFallback, classified == nil {
        startFallback(transcript: transcript, utteranceID: utteranceID)
      } else {
        dispatchVoice(.heard(command), transcript: transcript)
      }
    default:
      dispatchVoice(.heard(command), transcript: transcript)
    }
  }

  /// Whether a classifier's guess is certain enough to act on its own.
  private func classifierMustConfirm(
    _ command: VoiceCommand, _ classified: (intent: VoiceIntent, confidence: Double)
  ) -> Bool {
    if case .unrecognised = command { return false }
    if case .askCoach = command { return false }
    if case .logSet = command { return true }
    return classified.confidence < 0.9
  }

  /// Reduce one turn and run the single effect the coordinator answered with. This is the
  /// only road a voice command has to `runVoiceCommand`, so an ambiguous command is always
  /// clarified, a consequential one always confirmed, and an already-applied fingerprint
  /// never runs a second time.
  private func dispatchVoice(_ event: VoiceTurnEvent, transcript: String) {
    let effect = voiceCoordinator.reduce(event)
    let explicitApproval: Bool
    switch event {
    case .heard, .heardIncomplete, .propose: explicitApproval = false
    default: explicitApproval = true
    }
    switch effect {
    case .none:
      break
    case .apply(let command):
      // A voice-confirmed command keeps the receipt it always had: the card was the
      // acknowledgement, so only self-running commands raise their own toast.
      if explicitApproval { runVoiceCommand(command) } else { presentApplied(command) }
    case .requestConfirmation(let command):
      presentVoiceCard(command, prompt: nil, transcript: transcript)
    case .requestClarification(let command, let prompt):
      if case .unrecognised = command {
        // A miss is not a question: keep the existing banner and its analytics, no card.
        voiceCoordinator.reduce(.reset)
        showUnrecognised(transcript)
      } else {
        presentVoiceCard(command, prompt: prompt, transcript: transcript)
      }
    case .ignoreDuplicate:
      presentDuplicate()
    case .reject:
      break
    }
  }

  private func presentVoiceCard(_ command: VoiceCommand, prompt: String?, transcript: String) {
    pendingTranscript = transcript
    voiceClarificationPrompt = prompt
    pendingCommand = command
  }

  /// Close the card. `.reset` rather than `.cancel`: the coordinator refuses new input after
  /// a cancelled turn, and the mic is still listening.
  private func dismissVoiceCard() {
    pendingCommand = nil
    voiceClarificationPrompt = nil
    voiceCoordinator.reduce(.reset)
  }

  /// The lifter said or tapped yes. A consequential command resumes its pending turn; a
  /// clarification is the answer that lets the held command run.
  private func approveVoiceCard() {
    guard let command = pendingCommand else { return }
    let transcript = pendingTranscript
    let wasClarification = voiceClarificationPrompt != nil
    pendingCommand = nil
    voiceClarificationPrompt = nil
    dispatchVoice(wasClarification ? .clarify(command) : .confirm, transcript: transcript)
  }

  private func cancelVoiceCard() {
    if pendingCommand != nil {
      pendingCommand = nil
      voiceClarificationPrompt = nil
      voiceCoordinator.reduce(.reset)
    } else {
      unrecognisedText = nil
    }
  }

  /// The same command already ran this session; nothing ran again.
  private func presentDuplicate() {
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
    showToast(String(localized: "Already done — nothing changed", bundle: L10n.bundle))
  }

  /// The coordinator let it through on its own: keep the consequence-shaped receipt.
  private func presentApplied(_ command: VoiceCommand) {
    switch command.consequence(fastLogging: fastVoiceLogging) {
    case .immediate:
      applyImmediate(command)
    case .undoable, .confirm:
      applyUndoable(command)
    }
  }

  private func applyImmediate(_ command: VoiceCommand) {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    runVoiceCommand(command)
    showToast(voiceToastText(command))
  }

  private func applyUndoable(_ command: VoiceCommand) {
    let undo = makeUndo(for: command)
    let feedback = UINotificationFeedbackGenerator()
    feedback.notificationOccurred(.success)
    if case .logSet(let parse) = command {
      logParsed(parse, undo: undo)
    } else {
      runVoiceCommand(command)
      lastUndo = undo
      showToast(voiceToastText(command), undo: undo)
    }
  }

  /// Let the card finish dismissing before the swap sheet takes over.
  private func openSwapCard(_ id: String) {
    dismissVoiceCard()
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(0.35))
      swapExercise(id)
    }
  }

  private func applyUndo() {
    guard lastUndo != nil else { return }
    performUndo()
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    showToast(String(localized: "Undone", bundle: L10n.bundle))
  }

  private func performUndo() {
    guard let undo = lastUndo else { return }
    lastUndo = nil
    undo()
    Analytics.track("voice_undo")
  }

  /// Single last-action undo (no stack). Matches the just-created set by identity rather
  /// than array position, since SwiftData to-many relationships don't guarantee ordering.
  private func makeUndo(for command: VoiceCommand) -> (() -> Void)? {
    switch command {
    case .logSet, .completeSet:
      guard let session else { return nil }
      let before = Set(session.sets.map(\.persistentModelID))
      return {
        guard let session = self.session else { return }
        guard let set = session.sets.first(where: { !before.contains($0.persistentModelID) }) else {
          return
        }
        session.sets.removeAll { $0.persistentModelID == set.persistentModelID }
        self.modelContext.delete(set)
        if self.restRPESet === set { self.restRPESet = nil }
        try? self.modelContext.save()
        self.loggedCount = max(0, self.loggedCount - 1)
        withAnimation(self.reduceMotion ? nil : .easeOut(duration: 0.15)) { self.activeSlot = self.firstPendingSlot() }
      }
    case .changeWeight:
      guard let (planned, _, index) = activeEditorSlot else { return nil }
      let id = planned.exercise.id
      let previous = weights[id]?[index] ?? ""
      return {
        var array = self.weights[id] ?? []
        while array.count <= index { array.append("") }
        array[index] = previous
        self.weights[id] = array
        withAnimation(self.reduceMotion ? nil : .easeOut(duration: 0.15)) { self.activeSlot = self.key(id, index) }
      }
    case .changeReps:
      guard let (planned, _, index) = activeEditorSlot else { return nil }
      let id = planned.exercise.id
      let previous = reps[id]?[index] ?? 0
      return {
        var array = self.reps[id] ?? []
        while array.count <= index { array.append(0) }
        array[index] = previous
        self.reps[id] = array
        withAnimation(self.reduceMotion ? nil : .easeOut(duration: 0.15)) { self.activeSlot = self.key(id, index) }
      }
    case .changeRPE:
      guard let (planned, _, index) = activeEditorSlot else { return nil }
      let id = planned.exercise.id
      let previous = rpes[id]?[index] ?? 8
      return {
        var array = self.rpes[id] ?? []
        while array.count <= index { array.append(8) }
        array[index] = previous
        self.rpes[id] = array
        withAnimation(self.reduceMotion ? nil : .easeOut(duration: 0.15)) { self.activeSlot = self.key(id, index) }
      }
    default:
      return nil
    }
  }

  private func showUnrecognised(_ transcript: String) {
    let shown = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !shown.isEmpty else { return }
    Analytics.track("voice_miss")
    withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0)) { unrecognisedText = shown }
    Task {
      try? await Task.sleep(for: .seconds(2))
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
        if unrecognisedText == shown { unrecognisedText = nil }
      }
    }
  }

  /// The local parser gave up, so ask the classifier — but never ambush the lifter with
  /// a late answer: the result only counts while this is still the in-flight request,
  /// nothing newer was said, no set was logged, and voice stayed armed.
  private func startFallback(transcript: String, utteranceID: UUID) {
    voiceFallbackPending = (id: utteranceID, transcript: transcript, loggedAtStart: loggedCount)
    let language = voiceLanguage
    Task {
      let result = await VoiceIntentClient.classify(transcript, language: language)
      guard let pending = voiceFallbackPending, pending.id == utteranceID else { return }
      voiceFallbackPending = nil
      guard lastVoiceUtteranceID == utteranceID,
        loggedCount == pending.loggedAtStart,
        voiceArmed
      else { return }
      guard let result else {
        showUnrecognised(transcript)
        return
      }
      Analytics.track(
        "voice_fallback",
        ["intent": result.intent.rawValue, "confident": result.confidence >= 0.9 ? "1" : "0"])
      let rebuilt = VoiceCommandParser.command(
        for: result.intent, transcript: transcript,
        candidates: quickLogCandidates(), defaultLb: usesLb, language: language)
      routeVoiceCommand(
        rebuilt, transcript: transcript, utteranceID: utteranceID,
        classified: (result.intent, result.confidence))
    }
  }

  private func voiceToastText(_ command: VoiceCommand) -> String {
    command.summary { "\(formatDisplay($0, lb: usesLb)) \(usesLb ? "lb" : "kg")" }
  }

  private func liveCandidate() -> VoiceCandidate? {
    let partial = voice.partial.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !partial.isEmpty else { return nil }
    return VoiceCommandParser.candidate(
      partial, candidates: quickLogCandidates(), defaultLb: usesLb, language: voiceLanguage)
  }

  @ViewBuilder
  private var voiceLiveBar: some View {
    if voiceLiveVisible {
      HStack(spacing: 8) {
        Image(systemName: voiceFailed ? "mic.slash.fill" : "waveform")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(voiceBadgeNegative ? Theme.negative : Theme.metricTime)
        Text(voiceStatusText)
          .forge(13, .semibold)
          .foregroundStyle(voiceBadgeNegative ? Theme.negative : Theme.metricTime)
          .lineLimit(voiceFailed ? 3 : 1)
          .truncationMode(.tail)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity, minHeight: 44)
      .background(
        Capsule().fill(
          voiceBadgeNegative ? Theme.negative.opacity(0.12) : Theme.metricTime.opacity(0.12))
      )
      .overlay(
        Capsule().strokeBorder(
          voiceBadgeNegative ? Theme.negative.opacity(0.3) : Theme.metricTime.opacity(0.25),
          lineWidth: 1)
      )
      .accessibilityElement(children: .combine)
      .accessibilityLabel(voiceStatusText)
      .transition(.forgeFade)
    }
  }

  /// The one line the live voice badge shows, most specific first.
  private var voiceStatusText: String {
    if voiceFailed {
      return voice.unavailableReason ?? String(localized: "Voice unavailable", bundle: L10n.bundle)
    }
    if let unrecognised = unrecognisedText {
      return String(localized: "Didn't catch that — \(unrecognised)", bundle: L10n.bundle)
    }
    if let candidate = liveCandidateResult, candidate.isComplete {
      return voiceToastText(candidate.command)
    }
    if voiceFallbackPending != nil {
      return String(localized: "Thinking…", bundle: L10n.bundle)
    }
    let partial = voice.partial.trimmingCharacters(in: .whitespacesAndNewlines)
    if !partial.isEmpty {
      return partial
    }
    return String(localized: "Listening…", bundle: L10n.bundle)
  }

  /// Show the badge whenever voice is armed, failing, or reacting to an utterance.
  private var voiceLiveVisible: Bool {
    if voiceFailed || unrecognisedText != nil || voiceFallbackPending != nil { return true }
    switch voice.state {
    case .listening, .hearing, .thinking: return true
    case .off, .arming, .failed: return false
    }
  }

  /// Failure and unrecognised utterances read as negative; everything active is cyan.
  private var voiceBadgeNegative: Bool { voiceFailed || unrecognisedText != nil }

  private var voiceArmed: Bool {
    switch voice.state {
    case .off, .failed: return false
    default: return true
    }
  }

  private var voiceFailed: Bool {
    if case .failed = voice.state { return true }
    return false
  }

  private var voiceIcon: String {
    if voiceFailed { return "mic.slash.fill" }
    if voice.state == .hearing { return "waveform" }
    return voiceArmed ? "mic.fill" : "mic"
  }

  private var voiceAccessibilityLabel: String {
    if voiceFailed {
      return String(localized: "Voice control unavailable", bundle: L10n.bundle)
    }
    return voiceArmed
      ? String(localized: "Stop voice control", bundle: L10n.bundle)
      : String(localized: "Start voice control", bundle: L10n.bundle)
  }

  /// Voice "ask coach" answers in place, the same call the Siri intent makes.
  @MainActor
  private func askCoachFromVoice(_ question: String) async {
    guard UserDefaults.standard.bool(forKey: "coachConsent") else {
      coachAnswer = String(localized: "Turn the coach on in Settings first.", bundle: L10n.bundle)
      return
    }
    coachAsking = true
    defer { coachAsking = false }
    let coachName = Coach.from(voiceCoachID).name
    let context = CoachAPI.dataBlock(
      profile: profile, sessions: allSessions, checkIns: checkIns, usesLb: usesLb)
    if let reply = try? await CoachAPI.ask(
      question: question,
      context: context,
      coach: coachName,
      history: [],
      notes: coachNotes.prefix(20).map(\.text))
    {
      coachAnswer = reply.answer
      modelContext.insert(CoachMessage(role: "user", text: question))
      modelContext.insert(
        CoachMessage(role: "assistant", text: reply.answer, citations: reply.citations ?? []))
    } else if let onDevice = await OnDeviceCoach.answer(
      question, context: context, coachName: coachName)
    {
      coachAnswer = onDevice
    } else {
      coachAnswer = String(localized: "Coach is offline right now.", bundle: L10n.bundle)
    }
  }

  /// The one card voice uses: a confirmation for a consequential command, and an explanation
  /// plus an explicit next step for the ones the coordinator could not resolve alone.
  @ViewBuilder
  private func voiceConfirmation(_ command: VoiceCommand) -> some View {
    let headline = voiceHeadline(command)
    VStack(spacing: 14) {
      Text(pendingTranscript)
        .forgeCaption()
        .multilineTextAlignment(.center)
      if !headline.isEmpty {
        Text(headline)
          .forge(20, .bold)
          .tracking(-0.6)
          .foregroundStyle(Theme.text)
          .multilineTextAlignment(.center)
      }
      // Only a genuinely ambiguous command gets the question line; an unclear edit just shows
      // what was understood and asks for a yes.
      if let prompt = voiceClarificationPrompt, command.isAmbiguous, prompt != headline {
        Text(prompt)
          .forgeLabel()
          .foregroundStyle(Theme.textSecondary)
          .multilineTextAlignment(.center)
      }
      switch command {
      case .askCoach:
        if coachAsking {
          HStack(spacing: 10) {
            ProgressView()
            Text(String(localized: "Thinking…", bundle: L10n.bundle)).forgeLabel()
          }
        } else if let coachAnswer {
          ScrollView {
            Text(coachAnswer).forgeBody().frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 160)
        }
        Button {
          dismissVoiceCard()
          coachAnswer = nil
        } label: {
          Text(String(localized: "Done", bundle: L10n.bundle))
        }
        .buttonStyle(PillSecondaryButtonStyle())
      case .swapExercise(let id):
        // A swap is the most ambiguous command there is: the app may never choose for the
        // lifter, so the card only opens the options.
        Button {
          openSwapCard(id)
        } label: {
          Text(String(localized: "Choose exercise", bundle: L10n.bundle))
        }
        .buttonStyle(PillButtonStyle())
        Button {
          cancelVoiceCard()
        } label: {
          Text(String(localized: "Cancel", bundle: L10n.bundle))
        }
        .buttonStyle(PillSecondaryButtonStyle())
      default:
        if command.isAmbiguous {
          // Nothing may run yet: the next utterance is the answer.
          Button {
            dismissVoiceCard()
          } label: {
            Text(String(localized: "Got it", bundle: L10n.bundle))
          }
          .buttonStyle(PillSecondaryButtonStyle())
        } else {
          Button {
            approveVoiceCard()
          } label: {
            Text(String(localized: "Confirm", bundle: L10n.bundle))
          }
          .buttonStyle(PillButtonStyle())
          Button {
            cancelVoiceCard()
          } label: {
            Text(String(localized: "Cancel", bundle: L10n.bundle))
          }
          .buttonStyle(PillSecondaryButtonStyle())
        }
      }
    }
    .padding(20)
    .presentationDetents([.height(voiceClarificationPrompt == nil ? 220 : 260)])
    .presentationBackground(Theme.card)
    .presentationDragIndicator(.visible)
  }

  private func voiceHeadline(_ command: VoiceCommand) -> String {
    if case .changeWeight(let delta) = command, let preview = weightDeltaPreview(delta) {
      return preview
    }
    return command.summary { "\(formatDisplay($0, lb: usesLb)) \(usesLb ? "lb" : "kg")" }
  }

  private func weightDeltaPreview(_ deltaKg: Double) -> String? {
    guard let (planned, exercise, index) = activeEditorSlot else { return nil }
    let id = planned.exercise.id
    let lb = isLb(for: id)
    let inc = WeightRuler.step(for: exercise, lb: lb)
    let current = Double((weights[id]?[index] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
    let newDisplay =
      max(0, (current + (lb ? Plates.kgToLb(deltaKg) : deltaKg)) / inc).rounded() * inc
    return "\(Fmt.num(newDisplay)) \(lb ? "lb" : "kg")"
  }

  private func runVoiceCommand(_ command: VoiceCommand) {
    switch command {
    case .logSet(let parse): logParsed(parse)
    case .completeSet: completeSet()
    case .startRest(let seconds): startRest(seconds: seconds)
    case .skipRest: skipRest()
    case .changeWeight(let delta): applyWeightDelta(delta)
    case .changeReps(let to, let delta): applyReps(to: to, delta: delta)
    case .changeRPE(let rpe): applyRPE(rpe)
    case .nextExercise: nextExercise()
    case .askCoach: break
    case .swapExercise(let id): swapExercise(id)
    case .confirm, .cancel, .undo: break
    case .unrecognised: break
    }
  }

  private func voiceKind(_ command: VoiceCommand) -> String {
    switch command {
    case .logSet: return "logSet"
    case .completeSet: return "completeSet"
    case .startRest: return "startRest"
    case .skipRest: return "skipRest"
    case .changeWeight: return "changeWeight"
    case .changeReps: return "changeReps"
    case .changeRPE: return "changeRPE"
    case .nextExercise: return "nextExercise"
    case .askCoach: return "askCoach"
    case .swapExercise: return "swapExercise"
    case .confirm: return "confirm"
    case .cancel: return "cancel"
    case .undo: return "undo"
    case .unrecognised: return "unrecognised"
    }
  }

  private var activeEditorSlot: (planned: PlannedExercise, exercise: Exercise, index: Int)? {
    let slot = activeSlot ?? firstPendingSlot()
    guard let slot,
      let planned = exerciseList.first(where: { slot.hasPrefix("\($0.exercise.id)#") }),
      let index = Int(slot.dropFirst(planned.exercise.id.count + 1))
    else { return nil }
    return (planned, swaps[planned.exercise.id] ?? planned.exercise, index)
  }

  private func completeSet() {
    guard let (planned, exercise, index) = activeEditorSlot else { return }
    log(planned, exercise, index)
  }

  private func startRest(seconds: Int?) {
    restRPESet = nil
    guard let (planned, exercise, index) = activeEditorSlot else { return }
    let s = seconds ?? restSeconds(for: exercise)
    restTotal = TimeInterval(s)
    restNextSet = index + 2
    restTotalSets = sets(for: planned.exercise.id)
    restExercise = exercise
    restStartedAt = .now
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { restEnd = Date.now.addingTimeInterval(TimeInterval(s)) }
    scheduleRestNotification(
      seconds: s, exercise: exercise, nextSet: restNextSet, totalSets: restTotalSets)
    syncRestActivity(
      end: restEnd ?? .now, exercise: exercise, nextSet: restNextSet, totalSets: restTotalSets)
    startHeartRateLoop()
  }

  private func applyWeightDelta(_ deltaKg: Double) {
    guard let (planned, exercise, index) = activeEditorSlot else { return }
    let id = planned.exercise.id
    let lb = isLb(for: id)
    let inc = WeightRuler.step(for: exercise, lb: lb)
    let current = Double((weights[id]?[index] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
    let newDisplay =
      max(0, (current + (lb ? Plates.kgToLb(deltaKg) : deltaKg)) / inc).rounded() * inc
    var array = weights[id] ?? []
    while array.count <= index { array.append("") }
    array[index] = Fmt.num(newDisplay)
    weights[id] = array
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { activeSlot = key(id, index) }
  }

  private func applyReps(to: Int?, delta: Int?) {
    guard let (planned, _, index) = activeEditorSlot else { return }
    let id = planned.exercise.id
    let current = reps[id]?[index] ?? 0
    let newReps: Int
    if let to {
      newReps = to
    } else if let delta {
      newReps = max(0, current + delta)
    } else {
      return
    }
    repsBinding(id, index).wrappedValue = newReps
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { activeSlot = key(id, index) }
  }

  private func applyRPE(_ value: Double) {
    if restEnd != nil, restRPESet != nil {
      reportRestEffort(min(10, max(5, value)))
      return
    }
    guard let (planned, _, index) = activeEditorSlot else { return }
    let id = planned.exercise.id
    rpeBinding(id, index).wrappedValue = min(10, max(5, value))
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { activeSlot = key(id, index) }
  }

  private func nextExercise() {
    let list = exerciseList
    let ids = list.map(\.exercise.id)
    let currentSlot = activeSlot ?? firstPendingSlot()
    guard let currentSlot,
      let currentID = currentSlot.split(separator: "#").first.map(String.init),
      let i = ids.firstIndex(of: currentID),
      i + 1 < ids.count
    else { return }
    let nextPlanned = list[i + 1]
    let nextExercise = swaps[nextPlanned.exercise.id] ?? nextPlanned.exercise
    let nextID = nextPlanned.exercise.id
    for index in 0..<sets(for: nextID) where loggedSet(nextExercise.id, index) == nil {
      withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { activeSlot = key(nextID, index) }
      coachAudio.announceExerciseChange(
        eventID: "exercise-\(nextID)",
        revision: nextAudioRevision(),
        exercise: nextExercise.localizedName,
        sets: sets(for: nextID),
        minReps: nextPlanned.repRange.lowerBound,
        maxReps: nextPlanned.repRange.upperBound)
      return
    }
  }

  private func swapExercise(_ id: String) {
    guard
      let planned = exerciseList.first(where: {
        $0.exercise.id == id || swaps[$0.exercise.id]?.id == id
      })
    else { return }
    swapTarget = planned
  }

  private func loggedSet(_ id: String, _ index: Int) -> LoggedSet? {
    session?.sets.first { $0.exerciseID == id && $0.setIndex == index }
  }

  /// Nil when no comparable equipment history can suggest a load — callers must not invent one.
  private func suggestedKg(_ planned: PlannedExercise) -> Double? {
    resolvedLoadSuggestion(for: planned, sessions: allSessions, profile: profile)
  }

  private func baseDecision(for planned: PlannedExercise) -> Decision {
    buildDecision(for: planned, sessions: allSessions, profile: profile)
  }

  private func reseedSuggestion(for planned: PlannedExercise) {
    let id = planned.exercise.id
    let display = suggestedKg(planned).map { formatDisplay($0, lb: isLb(for: id)) } ?? ""
    var w = weights[id] ?? []
    let count = sets(for: id)
    while w.count < count { w.append(display) }
    for index in 0..<count where loggedSet(id, index) == nil {
      w[index] = display
    }
    weights[id] = w
  }

  private func decisionTargetKg(_ decision: Decision) -> Double? {
    switch decision.action {
    case .increaseLoad(_, let kg), .decreaseLoad(_, let kg), .holdLoad(let kg), .addReps(let kg),
      .firstTime(let kg):
      return kg
    default:
      return nil
    }
  }

  private func formatDisplay(_ value: Double, lb: Bool = false) -> String {
    Fmt.num(lb ? Plates.kgToLb(value) : value)
  }

  private func formatDisplay(_ value: Double, fromLb: Bool) -> String {
    Fmt.num(fromLb ? Plates.lbToKg(value) : Plates.kgToLb(value))
  }

  private func displayWeight(_ kg: Double, lb: Bool) -> String {
    formatDisplay(kg, lb: lb)
  }

  /// Spoken weight for VoiceOver labels: "80 kilograms" / "170 pounds".
  private func spokenWeight(kg: Double, lb: Bool) -> String {
    String(
      localized: "\(displayWeight(kg, lb: lb)) \(lb ? "pounds" : "kilograms")", bundle: L10n.bundle)
  }

  /// Spoken weight from a display-unit text field value.
  private func spokenDisplayWeight(_ text: String, lb: Bool) -> String {
    let value = Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0
    return String(
      localized: "\(Fmt.num(value)) \(lb ? "pounds" : "kilograms")", bundle: L10n.bundle)
  }

  private func spokenMinutes(_ s: Int) -> String {
    let m = s / 60
    let r = s % 60
    var parts = [String(localized: "\(m) minutes", bundle: L10n.bundle)]
    if r > 0 { parts.append(String(localized: "\(r) seconds", bundle: L10n.bundle)) }
    return parts.joined(separator: " ")
  }

  private func mmss(_ s: Int) -> String {
    String(format: "%d:%02d", s / 60, s % 60)
  }

  private func key(_ id: String, _ i: Int) -> String { "\(id)#\(i)" }

  private func firstPendingSlot() -> String? {
    let list = exerciseList
    var i = 0
    while i < list.count {
      var group = [list[i]]
      if session?.supersets.contains(list[i].exercise.id) == true, i + 1 < list.count {
        group.append(list[i + 1])
        i += 2
      } else {
        i += 1
      }
      let counts = group.map { sets(for: $0.exercise.id) }
      for index in 0..<(counts.max() ?? 0) {
        for (g, planned) in group.enumerated() where index < counts[g] {
          let exercise = swaps[planned.exercise.id] ?? planned.exercise
          if loggedSet(exercise.id, index) == nil { return key(planned.exercise.id, index) }
        }
      }
    }
    return nil
  }

  // MARK: cards

  private func activeSetSection(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int)
    -> some View
  {
    let id = planned.exercise.id
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 16) {
        Button {
          detailTarget = exercise
        } label: {
          WorkoutArtTile(exercise: exercise, size: 128)
        }
        .buttonStyle(ControlPressStyle())
        .accessibilityLabel(String(localized: "Details", bundle: L10n.bundle))
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .top, spacing: 4) {
            Button {
              detailTarget = exercise
            } label: {
              Text(exercise.localizedName)
                .forge(24, .bold)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
            }
            .buttonStyle(RowPressStyle())
            .layoutPriority(1)
            .accessibilityLabel(
              "\(exercise.localizedName), set \(index + 1) of \(sets(for: id)), target RPE \(Fmt.num(planned.targetRPE)), rest \(spokenMinutes(restSeconds(for: exercise)))"
            )
            Spacer(minLength: 4)
            exerciseMenu(planned, exercise, sets(for: id), variantIndex: index)
          }
          equipmentContextMenu(planned, exercise, index)
          setProgress(exercise.id, index: index, count: sets(for: id))
        }
      }
      HStack(alignment: .center, spacing: 8) {
        WordFlow(spacing: 8, lineSpacing: 4) {
          Text(
            verbatim:
              "\(String(localized: "Target RPE \(Fmt.num(planned.targetRPE))", bundle: L10n.bundle)) · \(String(localized: "Rest \(mmss(restSeconds(for: exercise)))", bundle: L10n.bundle))"
          )
          .forge(14)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
          if inSuperset(id) {
            Text(String(localized: "Superset", bundle: L10n.bundle))
              .forge(14)
              .foregroundStyle(Theme.textSecondary)
          }
          decisionTag(planned)
        }
        Spacer(minLength: 4)
        Button {
          detailTarget = exercise
        } label: {
          HStack(spacing: 2) {
            Text("Details").forge(14, .medium)
            Image(systemName: "chevron.right")
              .font(.system(size: 12, weight: .semibold))
          }
          .foregroundStyle(Theme.accentText)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(ControlPressStyle())
      }
      setEditor(planned, exercise, index)
    }
    .padding(.top, 14)
    .padding(.horizontal, 20)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// "Set 2 of 3" with one pip per set: logged sets green, the current set accent, the rest track.
  private func setProgress(_ exerciseID: String, index: Int, count: Int) -> some View {
    HStack(spacing: 8) {
      Text("Set \(index + 1) of \(count)")
        .forge(14, .semibold)
        .monospacedDigit()
        .foregroundStyle(Theme.text)
      HStack(spacing: 4) {
        ForEach(0..<count, id: \.self) { i in
          Capsule()
            .fill(
              loggedSet(exerciseID, i) != nil ? Theme.positive : i == index ? Theme.accent : Theme
                .track)
            .frame(width: 16, height: 6)
        }
      }
      .accessibilityHidden(true)
    }
  }

  /// The load decision's headline ("First time", …) as an accent link; a tap opens Why.
  @ViewBuilder private func decisionTag(_ planned: PlannedExercise) -> some View {
    let base = baseDecision(for: planned)
    let override = DecisionOverrides.get(planned.exercise.id)
    let decision = override.map { base.applying($0) } ?? base
    if let signal = (override == nil ? decision.causes.first : decision.causes.last)?.signal.label,
      !signal.isEmpty
    {
      Button {
        whyTarget = planned
      } label: {
        HStack(spacing: 3) {
          Image(systemName: decisionSymbol(decision.action)).font(.system(size: 10, weight: .bold))
          Text(signal).forge(13, .medium).lineLimit(1)
        }
        .foregroundStyle(Theme.accentText)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(ControlPressStyle())
    }
  }

  /// One section per exercise, stacked inside the white queue section.
  private var exerciseQueue: some View {
    VStack(spacing: Theme.groupGap) {
      ForEach(exerciseList) { planned in
        let exercise = swaps[planned.exercise.id] ?? planned.exercise
        exerciseCard(planned, exercise)
      }
      Button("Add exercise") { showAddExercise = true }
        .buttonStyle(PillSecondaryButtonStyle())
        .padding(.top, 4)
    }
  }

  private func exerciseCard(_ planned: PlannedExercise, _ exercise: Exercise) -> some View {
    let id = planned.exercise.id
    let count = sets(for: id)
    let expanded = expandedExercises.contains(id)
    let done = session?.sets.filter { $0.exerciseID == exercise.id }.count ?? 0
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        WorkoutArtTile(exercise: exercise, size: 44)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Button {
            detailTarget = exercise
          } label: {
            HStack(spacing: 8) {
              Text(exercise.localizedName).forge(16, .semibold)
              if inSuperset(id) { supersetChip }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
          }
          .buttonStyle(RowPressStyle())
          .accessibilityLabel(
            "\(exercise.localizedName), \(count) sets of \(planned.repRange.lowerBound) to \(planned.repRange.upperBound), RPE \(Fmt.num(planned.targetRPE)), rest \(spokenMinutes(restSeconds(for: exercise)))"
          )
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
              Text(
                verbatim:
                  "\(count) × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound) · RPE \(Fmt.num(planned.targetRPE))"
              )
              Label {
                Text(verbatim: mmss(restSeconds(for: exercise)))
              } icon: {
                Image(systemName: "timer")
              }
              .foregroundStyle(Theme.metricTime)
            }
            HStack(spacing: 6) {
              Text(
                verbatim:
                  "\(count) × \(planned.repRange.lowerBound)–\(planned.repRange.upperBound)"
              )
              Label {
                Text(verbatim: mmss(restSeconds(for: exercise)))
              } icon: {
                Image(systemName: "timer")
              }
              .foregroundStyle(Theme.metricTime)
            }
          }
          .forgeLabel()
          .monospacedDigit()
          .lineLimit(1)
        }
        Spacer()
        Button {
          withAnimation(reduceMotion ? nil : .snappy) {
            if expanded { expandedExercises.remove(id) } else { expandedExercises.insert(id) }
          }
        } label: {
          ZStack {
            Circle().stroke(Theme.track, lineWidth: 3)
            Circle()
              .trim(from: 0, to: count > 0 ? CGFloat(done) / CGFloat(count) : 0)
              .stroke(Theme.metricSets, style: StrokeStyle(lineWidth: 3, lineCap: .round))
              .rotationEffect(.degrees(-90))
            Text(verbatim: "\(done)/\(count)")
              .forge(11, .semibold)
              .monospacedDigit()
              .foregroundStyle(Theme.text)
          }
          .frame(width: 36, height: 36)
          .background(Circle().fill(expanded ? Theme.innerSurface : Color.clear))
          .frame(minWidth: 44, minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("\(exercise.localizedName), \(done) of \(count) sets done")
        .accessibilityHint(expanded ? "Collapse sets" : "Expand to edit sets")
        exerciseMenu(planned, exercise, count)
      }
      if expanded {
        VStack(spacing: 8) {
          if !warmUpSteps(planned, exercise).isEmpty { warmUpSection(planned, exercise) }
          ForEach(0..<count, id: \.self) { index in setSlot(planned, exercise, index) }
        }
      }
    }
  }

  private var supersetChip: some View {
    HStack(spacing: 4) {
      Image(systemName: "link").font(.system(size: 10, weight: .semibold))
      Text("Superset").forge(11, .semibold)
    }
    .foregroundStyle(Theme.accentText)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Capsule().fill(Theme.accentTint))
  }

  private func exerciseMenu(
    _ planned: PlannedExercise, _ exercise: Exercise, _ count: Int, variantIndex: Int? = nil
  ) -> some View {
    let id = planned.exercise.id
    return Menu {
      if let index = variantIndex {
        Menu("Set variant") {
          ForEach(SetVariant.allCases, id: \.self) { v in
            Button {
              variants[key(id, index)] = v
            } label: {
              if v == selectedVariant(id, index) {
                Label(v.label, systemImage: "checkmark")
              } else {
                Text(v.label)
              }
            }
          }
        }
      }
      Button("Why?") { whyTarget = planned }
      Button("Swap…") { swapTarget = planned }
      Button("Add set") { addSet(planned, count) }
      if count > 1 && loggedSet(exercise.id, count - 1) == nil {
        Button("Remove last set") { removeLastSet(id, count) }
      }
      Button("Move up") { move(id, -1) }
      Button("Move down") { move(id, 1) }
      if inSuperset(id) {
        Button("Break superset") { toggleSuperset(id) }
      } else if hasNext(id) {
        Button("Superset with next") { toggleSuperset(id) }
      }
      Button(
        isLb(for: id)
          ? String(localized: "Show in kg", bundle: L10n.bundle)
          : String(localized: "Show in lb", bundle: L10n.bundle)
      ) { toggleUnit(id) }
      Button("Note…") { noteTarget = planned }
      if !hasLogged(exercise.id) {
        Button("Remove exercise", role: .destructive) { removeExercise(id) }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Theme.text)
    }
    .buttonStyle(IconButtonStyle())
    .padding(2)
    .accessibilityLabel("Exercise options")
  }

  private func warmUpSteps(_ planned: PlannedExercise, _ exercise: Exercise) -> [(
    kg: Double, reps: Int
  )] {
    guard exercise.isCompound, let profile, let workingKg = suggestedKg(planned) else { return [] }
    let barKg = isLb(for: planned.exercise.id) ? Plates.lbToKg(profile.barLb) : profile.barKg
    return WarmUp.ramp(
      workingKg: workingKg, barKg: barKg, incrementKg: exercise.smallestIncrementKg)
  }

  private func warmUpSection(_ planned: PlannedExercise, _ exercise: Exercise) -> some View {
    let steps = warmUpSteps(planned, exercise)
    let id = planned.exercise.id
    let expanded = warmUpExpanded.contains(id)
    return VStack(spacing: 8) {
      Button {
        if expanded { warmUpExpanded.remove(id) } else { warmUpExpanded.insert(id) }
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "flame")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.accent)
          Text("Warm-up · \(steps.count) sets").forgeLabel()
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .frame(minHeight: 24)
        .innerSurface(padding: 10)
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel("Warm-up, \(steps.count) sets")
      if expanded {
        // Positional by design: two warm-up steps can share the same weight and reps, and the
        // done-state key is the index itself ("wu#id#index").
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
          let stepKey = "wu#\(id)#\(index)"
          let done = warmUpDone.contains(stepKey)
          Button {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0)) {
              if done {
                warmUpDone.remove(stepKey)
              } else {
                warmUpDone.insert(stepKey)
                if steps.indices.allSatisfy({ warmUpDone.contains("wu#\(id)#\($0)") }) {
                  warmUpExpanded.remove(id)
                }
              }
            }
          } label: {
            HStack(spacing: 10) {
              ZStack {
                Circle().fill(done ? Theme.positive : Theme.track)
                if done {
                  Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .transition(.symbolEffect(.appear))
                }
              }
              .frame(width: 22, height: 22)
              Text(
                "\(displayWeight(step.kg, lb: isLb(for: id))) \(displayUnit(for: id)) × \(step.reps)"
              )
              .forgeBody()
              .foregroundStyle(Theme.textSecondary)
              .monospacedDigit()
              Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
          }
          .buttonStyle(RowPressStyle())
        }
      }
    }
  }

  @ViewBuilder
  private func setSlot(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int) -> some View
  {
    let id = planned.exercise.id
    if let logged = loggedSet(exercise.id, index) {
      loggedRow(logged, id)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    } else {
      pendingRow(planned, exercise, index)
    }
  }

  private func loggedRow(_ logged: LoggedSet, _ id: String) -> some View {
    let variant = SetVariant(rawValue: logged.variant) ?? .straight
    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 8) {
        loggedRowBody(logged, id, variant)
        feedbackButton(logged)
      }
      if let note = SetFeedbackAnalysisPolicy.historyNote(for: logged.setFeedback) {
        Text(note)
          .forgeCaption()
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  /// The recorded set itself, unchanged. The feedback action sits beside it rather than inside it,
  /// so the row keeps one combined accessibility element.
  private func loggedRowBody(_ logged: LoggedSet, _ id: String, _ variant: SetVariant) -> some View
  {
    HStack(spacing: 10) {
      ZStack {
        Circle().fill(Theme.positive)
        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(
          Theme.onAccent)
      }
      .frame(width: 24, height: 24)
      Text(
        "\(displayWeight(logged.weightKg, lb: isLb(for: id))) \(displayUnit(for: id)) × \(logged.reps)"
      )
      .forgeBodyStrong()
      .monospacedDigit()
      if variant != .straight {
        Text(variant.label)
          .forge(11, .semibold)
          .foregroundStyle(Theme.positive)
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
          .background(Capsule().fill(Theme.positive.opacity(0.14)))
      }
      Spacer()
      Text(
        logged.effortReported
          ? String(localized: "Reported effort \(Fmt.num(logged.rpe))", bundle: L10n.bundle)
          : String(localized: "Reported effort: Not entered", bundle: L10n.bundle)
      )
      .forgeCaption()
      .monospacedDigit()
      .foregroundStyle(logged.effortReported ? Theme.textSecondary : Theme.textTertiary)
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(
        Theme.positiveTint)
    )
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      String(
        localized:
          "Set \(logged.setIndex + 1), \(spokenWeight(kg: logged.weightKg, lb: isLb(for: id))) times \(logged.reps), reported effort \(logged.effortText)",
        bundle: L10n.bundle))
  }

  /// Optional feedback entry point for one logged set. Secondary, 44pt, and never a prompt: it
  /// opens only on a tap and skipping it changes nothing about the set or the workout.
  @ViewBuilder
  private func feedbackButton(_ logged: LoggedSet) -> some View {
    let stored = logged.setFeedback
    Button {
      feedbackSet = logged
    } label: {
      Image(systemName: stored == nil ? "text.bubble" : "text.bubble.fill")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(stored == nil ? Theme.textTertiary : Theme.accent)
        .contentTransition(.symbolEffect(.replace))
        .animation(.spring(duration: 0.3, bounce: 0), value: stored == nil)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(ControlPressStyle())
    .accessibilityLabel(
      stored == nil
        ? String(localized: "Set feedback for set \(logged.setIndex + 1)", bundle: L10n.bundle)
        : String(
          localized: "Set feedback for set \(logged.setIndex + 1), \(stored?.kind.label ?? "")",
          bundle: L10n.bundle)
    )
    .accessibilityHint("Optional. Opens a sheet and changes nothing by itself")
  }

  private func pendingRow(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int)
    -> some View
  {
    let id = planned.exercise.id
    let isActive = activeSlot == key(id, index)
    // A pending set is the next thing to do, not a disabled row. The numbers stay at full
    // text weight, the set index carries the sets hue, and the trailing word says what the
    // tap does — the old tertiary-grey numeral plus a bare chevron read as unavailable.
    return SwipeLogRow(onSwipe: { log(planned, exercise, index) }) {
      Button {
        entryError = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { activeSlot = key(id, index) }
      } label: {
        HStack(spacing: 10) {
          ZStack {
            Circle().fill(Theme.card).overlay(
              Circle().strokeBorder(Theme.ring, lineWidth: 1))
            Text("\(index + 1)")
              .forge(12, .bold)
              .monospacedDigit()
              .foregroundStyle(Theme.textSecondary)
          }
          .frame(width: 24, height: 24)
          Text("\(weights[id]?[index] ?? "") \(displayUnit(for: id)) × \(reps[id]?[index] ?? 0)")
            .forgeBodyStrong()
            .monospacedDigit()
          Spacer()
          Text("Log")
            .forge(13, .semibold)
            .foregroundStyle(Theme.accentText)
          Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.accentText.opacity(0.7))
        }
        .padding(10)
        .frame(minHeight: 44)
        .background(
          RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(
            Theme.innerSurface)
        )
        .overlay(
          RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
            .strokeBorder(isActive ? Theme.accent : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityHint("Opens this set in the editor. Swipe right on the row to log it as shown")
    }
  }

  private func setEditor(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int)
    -> some View
  {
    let id = planned.exercise.id
    let lb = isLb(for: id)
    let variant = selectedVariant(id, index)
    let step = WeightRuler.step(for: exercise, lb: lb)
    return VStack(alignment: .leading, spacing: 12) {
      bigSetLine(id, index)
      WeightRuler(value: weightValueBinding(id, index), step: step, unit: displayUnit(for: id)) { stepTick &+= 1 }
        .id(key(id, index))
      HStack(spacing: 12) {
        Text("Reps").forgeCaption()
        RepPills(reps: repsBinding(id, index), count: max(12, planned.repRange.upperBound)) {
          stepTick &+= 1
        }
      }
      if let entryError, activeSlot == key(id, index) {
        Text(entryError)
          .forgeCaption()
          .foregroundStyle(Theme.negative)
          .accessibilityIdentifier("logger.entryError")
      }
      if variant != .straight { Text(variant.hint).forgeCaption() }
      voiceLiveBar
      HStack(spacing: 12) {
        if Features.voice { voiceButton }
        Button {
          log(planned, exercise, index)
        } label: {
          Label("Log set \(index + 1)", systemImage: "checkmark.circle.fill")
        }
        .buttonStyle(PillButtonStyle(minHeight: 52))
        .disabled(!entryIsValid(id, index, exercise))
        .accessibilityLabel(
          reportedRPESlots.contains(key(id, index))
            ? "Log set \(index + 1) of \(sets(for: id)): \(spokenDisplayWeight(weights[id]?[index] ?? "", lb: lb)), \(reps[id]?[index] ?? 0) reps, RPE \(Fmt.num(rpes[id]?[index] ?? 8))"
            : "Log set \(index + 1) of \(sets(for: id)): \(spokenDisplayWeight(weights[id]?[index] ?? "", lb: lb)), \(reps[id]?[index] ?? 0) reps, effort not entered"
        )
      }
    }
  }

  /// "120 kg × 8": the load (tap to type) and the reps, 58 pt bold in the text color.
  private func bigSetLine(_ id: String, _ index: Int) -> some View {
    let weightText = weights[id]?[index] ?? ""
    let repCount = reps[id]?[index] ?? 0
    return HStack(alignment: .firstTextBaseline, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        bigField(
          String(localized: "Weight", bundle: L10n.bundle),
          weightBinding(id, index), keyboard: .decimalPad, focusKey: "w#\(id)#\(index)",
          color: Theme.text, shown: weightText,
          alignment: .trailing)
        Text(displayUnit(for: id)).forge(20).foregroundStyle(Theme.textSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
      Text(verbatim: "×").forge(26).foregroundStyle(Theme.textTertiary)
      bigField(
        String(localized: "Reps", bundle: L10n.bundle),
        repsText(id, index), keyboard: .numberPad, focusKey: "r#\(id)#\(index)",
        color: Theme.text, shown: "\(repCount)",
        alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// A 58 pt number that becomes a text field on tap.
  private func bigField(
    _ label: String, _ text: Binding<String>, keyboard: UIKeyboardType, focusKey: String, color: Color,
    shown: String, alignment: TextAlignment
  ) -> some View {
    let editing = focused == focusKey
    return TextField("0", text: text)
      .keyboardType(keyboard)
      .multilineTextAlignment(alignment)
      .font(.forge(58, .bold))
      .monospacedDigit()
      .foregroundStyle(editing ? color : Color.clear)
      .focused($focused, equals: focusKey)
      .accessibilityLabel(label)
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .dynamicTypeSize(...DynamicTypeSize.large)
      .overlay(alignment: alignment == .trailing ? .trailing : .leading) {
        if !editing {
          Text(shown.isEmpty ? "0" : shown)
            .font(.forge(58, .bold))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
  }

  /// The load as a number for the ruler; writes the same display text the old stepper wrote.
  private func weightValueBinding(_ id: String, _ index: Int) -> Binding<Double> {
    Binding(
      get: { Double((weights[id]?[index] ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0 },
      set: { weightBinding(id, index).wrappedValue = Fmt.num(max(0, $0)) })
  }

  /// Compact equipment-context control. When exactly one instance resolves it reads as a
  /// label — the lifter never has to tap to record the right equipment — and tapping swaps
  /// to another instance or back to Auto.
  @ViewBuilder
  private func equipmentContextMenu(_ planned: PlannedExercise, _ exercise: Exercise, _ index: Int)
    -> some View
  {
    if let profile {
      let id = planned.exercise.id
      let kind = EquipmentKind(equipment: exercise.equipment)
      let variant = selectedVariant(id, index).rawValue
      let choice = profile.equipmentInstanceChoice(
        exerciseID: exercise.id, variant: variant, kind: kind)
      let candidates = profile.equipmentCandidates(kind: kind)
      if !candidates.isEmpty {
        Menu {
          Button {
            profile.bindEquipment(exerciseID: exercise.id, variant: variant, instanceID: nil)
          } label: {
            Label(
              String(localized: "Auto", bundle: L10n.bundle),
              systemImage: choice.isBound ? "circle" : "checkmark")
          }
          ForEach(candidates, id: \.id) { instance in
            Button {
              profile.bindEquipment(
                exerciseID: exercise.id, variant: variant, instanceID: instance.id)
            } label: {
              if choice.instance?.id == instance.id {
                Label(instance.name, systemImage: "checkmark")
              } else {
                Text(instance.name)
              }
            }
          }
        } label: {
          HStack(spacing: 2) {
            Text(equipmentContextText(choice)).forge(14).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
          }
          .foregroundStyle(Theme.textSecondary)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(ControlPressStyle())
        .accessibilityLabel(
          String(localized: "Equipment: \(equipmentContextText(choice))", bundle: L10n.bundle)
        )
        .accessibilityHint(
          String(
            localized: "Choose the machine or implement this set is logged on", bundle: L10n.bundle)
        )
      }
    }
  }

  private func equipmentContextText(_ choice: UserProfile.EquipmentInstanceChoice) -> String {
    switch choice {
    case .bound(let instance), .uniqueActiveGym(let instance): return instance.name
    case .unresolved: return String(localized: "Auto", bundle: L10n.bundle)
    }
  }

  private func decisionSymbol(_ action: DecisionAction) -> String {
    switch action {
    case .increaseLoad, .addReps, .addSets: "arrow.up.right"
    case .decreaseLoad, .removeSets, .lightSession, .deload: "arrow.down.right"
    case .holdLoad: "arrow.right"
    case .firstTime: "flag"
    case .swapExercise, .changeRepRange: "arrow.triangle.2.circlepath"
    }
  }

  // MARK: rest

  @ViewBuilder private var restBar: some View {
    if let end = restEnd {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let remaining = max(0, end.timeIntervalSince(context.date))
        VStack(alignment: .leading, spacing: 16) {
          // The coach resting, with the countdown ring on the scene's calm left side.
          ZStack(alignment: .leading) {
            Theme.sceneBlue
            Image(Coach.from(voiceCoachID).scene(.rest)).resizable().scaledToFill()
              .frame(width: 150, height: 150)
              .sceneFade()
              .frame(maxWidth: .infinity, alignment: .trailing)
              .clipped()
              .allowsHitTesting(false)
              .accessibilityHidden(true)
            ZStack {
              RestArcRing(
                progress: remaining / max(restTotal, 1),
                lineWidth: 14,
                colors: Theme.gradStand,
                glyph: "clock.fill")
              VStack(spacing: 0) {
                Text(String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60))
                  .forge(36, .bold, tracking: -1)
                  .monospacedDigit()
                  .foregroundStyle(Theme.sceneTimeInk)
                  .contentTransition(.numericText(countsDown: true))
                Text("Rest").forge(13).foregroundStyle(Theme.sceneInkSecondary)
              }
            }
            .frame(width: 128, height: 128)
            .padding(.leading, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest")
            .accessibilityValue(
              "\(Int(remaining) / 60) minutes \(Int(remaining) % 60) seconds left")
          }
          .frame(height: 150)
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          HStack(spacing: 12) {
            restNextColumn
            Spacer(minLength: 0)
            if WatchSync.shared.heartRate != nil { heartRateBadge }
          }
          if let set = restRPESet {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Text("How hard was set \(set.setIndex + 1)?")
                  .forge(18, .semibold)
                  .foregroundStyle(Theme.text)
                Spacer()
                Text(
                  String(localized: "Target RPE \(Fmt.num(set.targetRPE))", bundle: L10n.bundle)
                )
                .forge(14)
                .foregroundStyle(Theme.textSecondary)
              }
              RPEPicker(
                selected: set.effortReported ? set.rpe : nil, target: set.targetRPE,
                onPick: reportRestEffort)
            }
          }
          HStack(spacing: 10) {
            restCapsule("−30 s") {
              if Date.now.timeIntervalSince(restStartedAt ?? .distantPast) < 0.6 { return }
              adjustRest(-30)
            }
            .accessibilityLabel("Minus 30 seconds")
            Button {
              if Date.now.timeIntervalSince(restStartedAt ?? .distantPast) < 0.6 { return }
              skipRest()
            } label: {
              Text("Skip rest")
                .forge(16, .semibold)
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Capsule().fill(Theme.innerSurface))
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel("Skip rest")
            restCapsule("+30 s") {
              if Date.now.timeIntervalSince(restStartedAt ?? .distantPast) < 0.6 { return }
              adjustRest(30)
            }
            .accessibilityLabel("Plus 30 seconds")
          }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Theme.card))
        .overlay(
          RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
      }
      .transition(reduceMotion ? .forgeFade : .forgeSlideUp)
    }
  }

  @ViewBuilder private var restNextColumn: some View {
    if let next = activeEditorSlot {
      let nextID = next.planned.exercise.id
      let weight = weights[nextID]?[next.index] ?? ""
      HStack(spacing: 12) {
        WorkoutArtTile(exercise: next.exercise, size: 48)
        VStack(alignment: .leading, spacing: 2) {
          Text("Next · set \(next.index + 1) of \(sets(for: nextID))")
            .forge(13)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
            .lineLimit(1)
          HStack(spacing: 6) {
            Text(next.exercise.localizedName)
              .forge(16, .semibold)
              .foregroundStyle(Theme.text)
              .lineLimit(1)
            Text(
              weight.isEmpty
                ? String(localized: "Choose load", bundle: L10n.bundle)
                : "\(weight) \(displayUnit(for: nextID)) × \(reps[nextID]?[next.index] ?? next.planned.repRange.lowerBound)"
            )
            .forge(17, .semibold)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
            .lineLimit(1)
          }
        }
      }
    } else {
      Text("Rest").forgeLabel()
    }
  }

  @ViewBuilder private var heartRateBadge: some View {
    if let hr = WatchSync.shared.heartRate {
      HStack(spacing: 4) {
        Image(systemName: "heart.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(
          Theme.metricHeart)
        MetricValue(value: "\(hr)", unit: "bpm", size: 15, color: Theme.metricHeart)
      }
      .frame(width: 64, alignment: .trailing)
      .accessibilityLabel("Heart rate \(hr)")
    } else {
      Image(systemName: "timer")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Theme.textSecondary)
        .frame(width: 64, alignment: .trailing)
        .accessibilityHidden(true)
    }
  }

  private func restCapsule(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(LocalizedStringKey(title)).forge(16, .semibold).monospacedDigit().foregroundStyle(
        Theme.text)
        .frame(width: 80, height: 52)
        .background(Capsule().fill(Theme.innerSurface))
    }
    .buttonStyle(RowPressStyle())
  }

  private func skipRest() {
    cancelRestNotification()
    endRestActivity()
    hrTask?.cancel()
    withAnimation(.easeOut(duration: 0.15)) { restEnd = nil }
  }

  /// The rest panel's effort question. Only a tap reports effort; an untouched set keeps
  /// `effortReported == false`.
  private func reportRestEffort(_ value: Double) {
    guard Date.now.timeIntervalSince(restStartedAt ?? .distantPast) >= 0.6 else { return }
    guard let set = restRPESet else { return }
    set.rpe = value
    set.effortReported = true
    try? modelContext.save()
    stepTick &+= 1
  }

  private func startHeartbeat() {
    heartbeatTask?.cancel()
    heartbeatTask = Task {
      while !Task.isCancelled {
        UserDefaults(suiteName: WidgetBridge.suite)?.set(
          Date.now.timeIntervalSince1970, forKey: "forge.workout.heartbeat")
        try? await Task.sleep(for: .seconds(30))
      }
    }
  }

  // ponytail: fixed 15 s poll — ≥3 bpm gate keeps Live Activity updates under the frequent-updates budget
  private func startHeartRateLoop() {
    hrTask?.cancel()
    hrTask = Task {
      var lastSent: Int?
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(15))
        guard !Task.isCancelled,
          let hr = WatchSync.shared.heartRate,
          abs(hr - (lastSent ?? hr - 3)) >= 3,
          let end = restEnd,
          let exercise = restExercise
        else { continue }
        lastSent = hr
        syncRestActivity(
          end: end, exercise: exercise, nextSet: restNextSet, totalSets: restTotalSets,
          heartRate: hr)
      }
    }
  }

  private func adjustRest(_ delta: Int) {
    restEnd = restEnd?.addingTimeInterval(TimeInterval(delta))
    restTotal = max(1, restTotal + TimeInterval(delta))
    if let id = currentExerciseID {
      profile?.restOverrides[id] = min(600, max(30, Int(restTotal)))
    }
    if let end = restEnd, let exercise = restExercise {
      scheduleRestNotification(
        seconds: Int(end.timeIntervalSinceNow), exercise: exercise, nextSet: restNextSet,
        totalSets: restTotalSets)
      syncRestActivity(
        end: end, exercise: exercise, nextSet: restNextSet, totalSets: restTotalSets,
        heartRate: WatchSync.shared.heartRate)
    }
  }

  private func scheduleRestNotification(
    seconds: Int, exercise: Exercise, nextSet: Int, totalSets: Int
  ) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: ["forge.rest"])
    let content = UNMutableNotificationContent()
    content.title = "Rest over"
    content.body =
      nextSet <= totalSets ? "\(exercise.localizedName) · set \(nextSet)" : "Next exercise"
    content.sound = .default
    center.add(
      UNNotificationRequest(
        identifier: "forge.rest",
        content: content,
        trigger: UNTimeIntervalNotificationTrigger(
          timeInterval: TimeInterval(max(1, seconds)), repeats: false)))
  }

  private func cancelRestNotification() {
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
      "forge.rest"
    ])
  }

  private func syncRestActivity(
    end: Date, exercise: Exercise, nextSet: Int, totalSets: Int, heartRate: Int? = nil
  ) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let state = RestActivityAttributes.ContentState(
      endDate: end, exerciseName: exercise.localizedName, nextSet: nextSet, totalSets: totalSets,
      heartRate: heartRate, canLogNext: nextSet <= totalSets)
    let content = ActivityContent(state: state, staleDate: end.addingTimeInterval(60))
    if let restActivity {
      Task { await restActivity.update(content) }
    } else {
      restActivity = try? ActivityKit.Activity.request(
        attributes: RestActivityAttributes(dayName: plannedDay.name), content: content,
        pushType: nil)
    }
  }

  private func endRestActivity() {
    let activity = restActivity
    restActivity = nil
    Task { await activity?.end(nil, dismissalPolicy: .immediate) }
  }

  // MARK: finish

  private func finishTapped() {
    if loggedCount == 0 {
      confirmDiscard = true
    } else if loggedCount < totalSets {
      confirmFinish = true
    } else {
      finish()
    }
  }

  private func discard() {
    UserDefaults(suiteName: WidgetBridge.suite)?.set(false, forKey: "forge.workout.active")
    WatchSync.shared.endWatchWorkout()
    hrTask?.cancel()
    heartbeatTask?.cancel()
    voice.stop()
    coachAudio.clear()
    cancelRestNotification()
    endRestActivity()
    withAnimation(.easeOut(duration: 0.15)) { restEnd = nil }
    if let session { modelContext.delete(session) }
    try? modelContext.save()
    dismiss()
  }

  private func finish() {
    // A second tap before the summary appears must not advance the plan or save Health twice.
    guard session?.completed != true else { return }
    // Flush what the lifter changed on the way here — a note, set feedback — before the
    // completion is staged, so the rollback below can only ever discard the completion itself.
    // Nothing above this line has marked the session complete, so this save cannot strand a
    // finished session on a stale plan.
    try? modelContext.save()

    // One transaction for every write a finish implies: the session's completion and its
    // timestamp, the plan day it satisfied, and the block calendar it moved. A session marked
    // done next to a stale `WeekPlan` or `nextDayIndex` is worse than no record at all.
    let recorded = WorkoutCompletionCommit.commit(in: modelContext) {
      session?.completed = true
      session?.updatedAt = .now
      session?.plannedSetCount = totalSets
      recordPlanCompletion()
      advanceBlockCalendar()
    }
    guard recorded else {
      // Rolled back, and the workout is still on screen with every set intact. Announce
      // nothing — a summary, a counter, a Health sample, a notification or an analytics event
      // would all claim a finished workout the store does not have.
      completionSaveFailed = true
      return
    }

    DecisionOverrides.clearAll()
    UserDefaults(suiteName: WidgetBridge.suite)?.set(false, forKey: "forge.workout.active")
    WatchSync.shared.endWatchWorkout()
    hrTask?.cancel()
    voice.stop()
    coachAudio.clear()
    finishedCount += 1
    if let start = session?.date { Task { await Health.saveWorkout(start: start, end: .now) } }
    cancelRestNotification()
    endRestActivity()
    withAnimation(.easeOut(duration: 0.15)) { restEnd = nil }
    prs = detectPRs()
    if let session {
      debrief = debriefLines(
        session: session, sessions: allSessions, prs: prs, profile: profile, usesLb: usesLb)
    }
    Analytics.track(
      "workout_finished",
      [
        "sets": "\(session?.sets.count ?? 0)",
        "minutes": "\(Int(Date.now.timeIntervalSince(session?.date ?? .now) / 60))",
      ])
    if !prs.isEmpty { Notifications.celebratePR(prs[0].exercise.localizedName) }
    if let profile {
      let weekBefore = profile.currentWeek(sessions: allSessions.filter { $0 !== session })
      let weekAfter = profile.currentWeek(sessions: allSessions)
      if weekBefore != Mesocycle.deloadWeek && weekAfter == Mesocycle.deloadWeek {
        Notifications.notifyDeload(daysPerWeek: profile.daysPerWeek)
      }
      if weekBefore != weekAfter {
        let review = WeeklyReview(
          week: weekBefore, sessionsDone: profile.daysPerWeek, sessionsPlanned: profile.daysPerWeek,
          tonnageKg: 0, priorTonnageKg: nil, prs: [], nextWeekNote: "")
        Notifications.notifyWeekReview(
          week: weekBefore, headline: WeeklyReviewBuilder.headline(review, usesLb: profile.usesLb))
      }
      if profile.reminderHour != nil {
        ReminderScheduler.reschedule(profile: profile, body: nextReminderBody(profile))
      }
    }
    Notifications.scheduleReengagement(days: 3)
    Task { await SyncEngine.shared.sync() }
    summary = SessionSummary(
      date: session?.date ?? .now,
      dayName: plannedDay.name,
      duration: Date.now.timeIntervalSince(session?.date ?? .now),
      sets: session?.sets.count ?? 0,
      plannedSets: totalSets,
      exercises: Set(session?.sets.map(\.exerciseID) ?? []).count,
      tonnageKg: (session?.sets ?? []).reduce(0) { $0 + $1.weightKg * Double($1.reps) },
      notes: session?.notes ?? "",
      muscles: muscleVolumes,
      verified: session?.verified ?? false,
      topSets: SessionTopSet.best(in: session?.sets ?? []))
    showSummary = true
  }

  /// Moves the block calendar on for the session just finished: a new block once the block's
  /// session budget is met — `daysPerWeek` in a deload block, `Mesocycle.weeks * daysPerWeek`
  /// plus any `mesoSessionOffset` a plan edit rebased, in a normal mesocycle — otherwise the
  /// next day in the current one. This only stages the change; the completion transaction
  /// saves it with everything else.
  private func advanceBlockCalendar() {
    guard let profile else { return }
    let deloadStartedAt = profile.deloadStartedAt
    let done =
      allSessions.filter {
        $0.completed && $0.date >= (deloadStartedAt ?? profile.mesoStart) && $0 !== session
      }.count + 1
    if WorkoutCompletionCommit.restartsBlock(
      sessionsDone: done + (deloadStartedAt == nil ? profile.mesoSessionOffset : 0),
      daysPerWeek: profile.daysPerWeek,
      inDeloadBlock: deloadStartedAt != nil
    ) {
      profile.startNewBlock()
    } else {
      profile.nextDayIndex += 1
    }
    profile.updatedAt = .now
  }

  /// Marks the accepted plan day done — but only for the work the lifter actually did.
  ///
  /// An early partial finish is still recorded as a session; it never rewrites a plan day
  /// into a state the lifter did not earn, and days the plan has already settled — completed,
  /// moved or skipped — are left exactly as they are.
  private func recordPlanCompletion() {
    guard let planDayID, let session, let profile, var plan = profile.weekPlan,
      RoutineAdaptationService.canComplete(session, dayID: planDayID, in: plan),
      let index = plan.days.firstIndex(where: { $0.id == planDayID })
    else { return }
    let day = plan.days[index]
    guard day.state == .planned || day.state == .remaining else { return }
    guard
      WeekPlanCompletionPolicy.satisfies(
        plannedSetCount: day.plannedSetCount,
        scheduledSets: totalSets,
        loggedSetCount: loggedCount,
        mode: day.mode,
        timeBudgetMinutes: day.timeBudgetMinutes)
    else { return }
    guard
      plan.complete(dayID: planDayID, sessionID: WeekPlanCompletionPolicy.sessionReference(session))
    else { return }
    // The plan day now points at the session that satisfied it. Only a successful encode
    // touches the stored payload, so a decode-only read can never blank the plan.
    profile.weekPlan = plan
  }

  private var muscleVolumes: [MuscleVolume] {
    var byMuscle: [Muscle: Int] = [:]
    for set in session?.sets ?? [] {
      if let exercise = ExerciseDB.find(set.exerciseID) {
        byMuscle[exercise.primary, default: 0] += 1
      }
    }
    return
      byMuscle
      .sorted { $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value }
      .map { MuscleVolume(muscle: $0.key, sets: $0.value) }
  }

  private func nextReminderBody(_ profile: UserProfile) -> String {
    let days = Program.week(
      profile.currentWeek(sessions: allSessions),
      profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: allSessions)))
    guard !days.isEmpty else {
      return String(localized: "Open Regulift for today's session.", bundle: L10n.bundle)
    }
    let day = days[profile.nextDayIndex % days.count]
    guard
      let compound = day.exercises.first(where: { $0.exercise.isCompound }) ?? day.exercises.first
    else {
      return String(localized: "Open Regulift for today's session.", bundle: L10n.bundle)
    }
    let kg = suggestedStartKg(
      for: compound, last: lastSets(compound.exercise.id, in: allSessions), profile: profile)
    let display = profile.usesLb ? Plates.kgToLb(kg) : kg
    return String(
      localized:
        "Next: \(localizedDayName(day.name)) · \(compound.exercise.localizedName) \(Fmt.kg(display, lb: profile.usesLb)) · ≈ \(profile.sessionMinutes) min",
      bundle: L10n.bundle)
  }

  private func detectPRs() -> [PRRecord] {
    guard let session, session.verified else { return [] }
    let prior = allSessions.filter { $0.completed && $0 !== session }
    let e1rm: (LoggedSet) -> Double = { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
    return Set(session.analysisSets(.achievements).map(\.exerciseID)).compactMap {
      id -> PRRecord? in
      guard let exercise = ExerciseDB.find(id) else { return nil }
      let mine = session.sets.filter {
        $0.exerciseID == id && !$0.suspect && $0.isEligibleForAnalysis(.achievements)
      }
      guard let reference = mine.max(by: { e1rm($0) < e1rm($1) }) else { return nil }
      let best = e1rm(reference)
      // Only records compatible with this session's verified equipment context may stand as the
      // predecessor; a different machine can never be a PR baseline. A set the lifter left out of
      // records — or reported discomfort on — is not a record on either side of the comparison.
      let previous = prior.flatMap(\.sets)
        .filter {
          $0.exerciseID == id && !$0.suspect && $0.isEligibleForAnalysis(.achievements)
            && $0.isComparableForBaseline(to: reference)
        }
        .map(e1rm).max()
      guard let previous, best > previous else { return nil }
      return PRRecord(exercise: exercise, e1rm: best, previous: previous, weightKg: reference.weightKg, reps: reference.reps)
    }
    .sorted { $0.exercise.localizedName < $1.exercise.localizedName }
  }
}

/// The single write a finished workout is allowed to make.
///
/// A completion touches four things at once — the session's `completed` flag, its `updatedAt`,
/// the plan day it satisfied, and the profile's block calendar. Staging them together and
/// saving once is what keeps a finished session from sitting next to a stale `WeekPlan` and
/// `nextDayIndex`. When that save fails the context is rolled back, and the caller must run no
/// side effect at all: no summary, no counters, no Health sample, no notification — the workout
/// stays open and resumable.
@MainActor
enum WorkoutCompletionCommit {
  /// Stages `changes` and saves exactly once. `true` means the store took the whole
  /// transaction; `false` means nothing was written and the context is back where it started.
  @discardableResult
  static func commit(in context: ModelContext, _ changes: () -> Void) -> Bool {
    changes()
    do {
      try context.save()
      return true
    } catch {
      context.rollback()
      return false
    }
  }

  /// Whether the session just finished closes out the block. A deload block rolls over after
  /// `daysPerWeek` sessions, a normal mesocycle after `Mesocycle.weeks * daysPerWeek`.
  nonisolated static func restartsBlock(sessionsDone: Int, daysPerWeek: Int, inDeloadBlock: Bool)
    -> Bool
  {
    let budget = inDeloadBlock ? daysPerWeek : Mesocycle.weeks * daysPerWeek
    return sessionsDone >= budget
  }
}

/// Pending set row with a swipe-left-to-log gesture; the green checkmark reveals behind it **as
/// it is dragged**, not permanently — an always-on affordance prints through a transparent row.
private struct SwipeLogRow<Content: View>: View {
  let onSwipe: () -> Void
  @ViewBuilder var content: () -> Content
  @State private var offset: CGFloat = 0

  private var reveal: Double { min(1, Double(-offset) / 80) }

  var body: some View {
    ZStack(alignment: .trailing) {
      if offset < 0 {
        RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
          .fill(Theme.positive.opacity(0.14 * reveal))
        Image(systemName: "checkmark")
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(Theme.positive)
          .padding(.trailing, 16)
          .opacity(reveal)
          .scaleEffect(0.85 + 0.15 * reveal)
          .accessibilityHidden(true)
      }
      content()
        .offset(x: offset)
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
    .gesture(
      DragGesture(minimumDistance: 15)
        .onChanged { value in offset = min(0, value.translation.width) }
        .onEnded { value in
          if value.translation.width <= -80 {
            offset = 0
            onSwipe()
          } else {
            withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
          }
        })
  }
}

/// Shared starting-load suggestion used by the workout prefill and the Today plan card.
func suggestedStartKg(for planned: PlannedExercise, last: [LoggedSet], profile: UserProfile?)
  -> Double
{
  let exercise = planned.exercise
  guard let lastSet = last.last else {
    if let starting = profile?.startingLoads[exercise.id] { return starting }
    return Strength.estimatedStartingLoad(
      exercise: exercise, bodyweightKg: profile?.bodyweightKg ?? 0)
  }
  guard let reported = lastSet.reportedRPE else {
    // Effort was never reported, so nothing may claim the lifter hit or missed target.
    // Hold the last load instead of reading the default as a report.
    return Progression.round(lastSet.weightKg, toIncrement: exercise.smallestIncrementKg)
  }
  let decision = Progression.nextLoad(
    currentKg: lastSet.weightKg, targetRPE: lastSet.targetRPE, actualRPE: reported)
  var kg: Double
  switch decision {
  case .increase(let k), .addReps(let k), .repeatLoad(let k), .decrease(let k, _): kg = k
  }
  if let logs = reportedSetLogs(last),
    Progression.shouldIncreaseLoad(
      sets: logs, repRange: planned.repRange, targetRPE: planned.targetRPE)
  {
    kg += exercise.smallestIncrementKg
  }
  return Progression.round(kg, toIncrement: exercise.smallestIncrementKg)
}

private struct WhySheet: View {
  let exercise: Exercise
  let base: Decision
  let weight: (Double) -> String
  let onOverride: () -> Void
  @State private var override: DecisionOverride?

  init(
    exercise: Exercise, base: Decision, weight: @escaping (Double) -> String,
    onOverride: @escaping () -> Void
  ) {
    self.exercise = exercise
    self.base = base
    self.weight = weight
    self.onOverride = onOverride
    _override = State(initialValue: DecisionOverrides.get(exercise.id))
  }

  private var decision: Decision {
    override.map { base.applying($0) } ?? base
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.groupGap) {
        Text(exercise.localizedName).forgeTitle()
        Text(decision.headline(name: exercise.localizedName, weight: weight)).forgeBodyStrong()
        Text(decision.reason).forgeLabel().monospacedDigit()
        if decision.overridable {
          HStack(spacing: 8) {
            ForEach(DecisionOverride.allCases, id: \.self) { o in
              let selected = override == o
              Button {
                let next: DecisionOverride? = selected ? nil : o
                DecisionOverrides.set(next, for: exercise.id)
                override = next
                Analytics.track("decision_override", ["override": next?.rawValue ?? "clear"])
                onOverride()
              } label: {
                Text(o.title)
                  .forge(11, .semibold)
                  .foregroundStyle(selected ? Theme.onAccent : Theme.text)
                  .padding(.horizontal, 10)
                  .padding(.vertical, 6)
                  .background(Capsule().fill(selected ? Theme.accentStrong : Theme.innerSurface))
              }
              .buttonStyle(RowPressStyle())
            }
          }
        }
      }
      .padding(Theme.margin)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Theme.page)
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.page)
  }
}
