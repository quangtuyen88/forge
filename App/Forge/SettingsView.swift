import ForgeCore
import SwiftData
import SwiftUI

struct SettingsView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \DecisionLogEntry.date) private var decisionLog: [DecisionLogEntry]
  @Query private var customExercises: [CustomExercise]
  @Environment(Store.self) private var store
  @Environment(AuthClient.self) private var auth
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("coachServerURL") private var coachServerURL =
    "https://forge-coach.quangtuyen88.workers.dev"
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @AppStorage("autoPostWorkouts") private var autoPostWorkouts = false
  @AppStorage("autoPostPRs") private var autoPostPRs = false
  @AppStorage("dictationLanguage") private var dictationLanguage = "auto"
  @AppStorage("appLanguage") private var appLanguage = "en"
  @AppStorage(ReminderScheduler.trainingDaysKey) private var reminderTrainingDaysOnly = false
  @State private var planSnapshot: (settings: PlanSettings, offset: Int)?
  @State private var visitPlanEntry: DecisionLogEntry?
  @State private var activeChoice: PlanChoice?
  @State private var pendingOption: String?
  @State private var planUndo: PlanUndo?
  @State private var undoTask: Task<Void, Never>?
  @State private var showAccount = false
  @State private var showFeedback = false
  @State private var pendingLanguage: String?

  private var coach: Coach { Coach.from(coachID) }

  var body: some View {
    NavigationStack {
      ScrollView {
        if let p = profiles.first {
          VStack(alignment: .leading, spacing: 0) {
            FieldSection {
              planSentence(p)
              planNote
            }
            VStack(alignment: .leading, spacing: 0) {
              trainingRows(p)
              coachRows
              appRows(p)
              accountRows
              footer
            }
            .padding(.horizontal, Theme.margin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.page)
          }
          .onChange(
            of: "\(p.goal)|\(p.split)|\(p.daysPerWeek)|\(p.sessionMinutes)"
          ) { _, _ in
            p.reviseWeekPlan(sessions: sessions)
            touch()
          }
        }
      }
      .progressFieldPage(String(localized: "Settings", bundle: L10n.bundle))
      .toolbar { Button("Done") { dismiss() }.bold() }
      .onAppear {
        if coachServerURL == Theme.legacyCoachServer { coachServerURL = Theme.coachServer }
        seedOptInSharingDefaults()
        if planSnapshot == nil, let p = profiles.first {
          planSnapshot = (settings: p.planSettings, offset: p.mesoSessionOffset)
        }
        Task { await auth.refresh() }
      }
      .onDisappear { recordPlanSettingsChange() }
      .sheet(item: $activeChoice, onDismiss: { pendingOption = nil }) { choice in
        if let p = profiles.first {
          PlanChoiceSheet(
            choice: choice, profile: p, sessions: sessions, advice: planAdviceText(p),
            pending: $pendingOption
          ) { id in
            apply(choice, id, to: p)
          }
        }
      }
      .sheet(isPresented: $showFeedback) { FeedbackSheet() }
      .sheet(isPresented: $showAccount) { AccountView() }
      .alert(
        String(localized: "Change language?", bundle: L10n.bundle),
        isPresented: Binding(
          get: { pendingLanguage != nil }, set: { if !$0 { pendingLanguage = nil } }),
        presenting: pendingLanguage
      ) { code in
        Button(String(localized: "Cancel", bundle: L10n.bundle), role: .cancel) {
          pendingLanguage = nil
        }
        Button(String(localized: "OK", bundle: L10n.bundle)) {
          applyLanguage(code)
          pendingLanguage = nil
          dismiss()
        }
      } message: { code in
        Text(
          String(
            localized: "The app will switch to \(SettingsFormat.languageName(code)) right away.",
            bundle: L10n.bundle))
      }
    }
  }

  // MARK: Plan sentence

  private func planSentence(_ p: UserProfile) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 9) {
        CoachAvatar(size: 30)
        Text(String(localized: "\(coach.name) plans", bundle: L10n.bundle))
          .font(.forge(23, .medium)).tracking(-0.35).foregroundStyle(Theme.text)
      }
      .frame(minHeight: 44, alignment: .leading)
      PlanSentenceLine(template: String(localized: "\(PlanSentence.slot) a week,", bundle: L10n.bundle)) {
        PlanChip(value: daysValue(p), label: String(localized: "Days a week", bundle: L10n.bundle)) {
          activeChoice = .days
        }
        .accessibilityIdentifier("settings.chip.days")
      }
      PlanSentenceLine(template: String(localized: "\(PlanSentence.slot) each,", bundle: L10n.bundle)) {
        PlanChip(value: minutesValue(p), label: String(localized: "Session length", bundle: L10n.bundle)) {
          activeChoice = .minutes
        }
        .accessibilityIdentifier("settings.chip.minutes")
      }
      PlanSentenceLine(template: String(localized: "to \(PlanSentence.slot)", bundle: L10n.bundle)) {
        PlanChip(value: goalValue(p), label: String(localized: "Goal", bundle: L10n.bundle)) {
          activeChoice = .goal
        }
        .accessibilityIdentifier("settings.chip.goal")
      }
    }
    .animation(
      reduceMotion ? .easeOut(duration: 0.2) : .snappy(duration: 0.3),
      value: "\(p.daysPerWeek)|\(p.sessionMinutes)|\(p.goal)|\(pendingOption ?? "")")
  }

  /// While a sheet is open the chip mirrors the option picked so far, before it is saved.
  private func daysValue(_ p: UserProfile) -> String {
    let d = (activeChoice == .days ? pendingOption.flatMap(Int.init) : nil) ?? p.daysPerWeek
    return String(localized: "\(d) days", bundle: L10n.bundle)
  }

  private func minutesValue(_ p: UserProfile) -> String {
    let m = (activeChoice == .minutes ? pendingOption.flatMap(Int.init) : nil) ?? p.sessionMinutes
    return String(localized: "\(m) min", bundle: L10n.bundle)
  }

  private func goalValue(_ p: UserProfile) -> String {
    let raw = (activeChoice == .goal ? pendingOption : nil) ?? p.goal
    return PlanPreview.goalPhrase(Goal(rawValue: raw) ?? .hypertrophy)
  }

  private var planNote: some View {
    ZStack(alignment: .leading) {
      Text(String(localized: "Change one and \(coach.name) replans from today.", bundle: L10n.bundle))
        .forge(15).foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(planUndo == nil ? 1 : 0)
        .accessibilityHidden(planUndo != nil)
      if planUndo != nil {
        ApprovalPill(kind: .updated, onTap: {}, onUndo: undoPlanChange)
      }
    }
    .frame(minHeight: 44, alignment: .leading)
  }

  // MARK: Applying a sheet pick, Undo

  private func apply(_ choice: PlanChoice, _ id: String, to profile: UserProfile) {
    let before = PlanUndo(
      goal: profile.goal, split: profile.split, days: profile.daysPerWeek,
      minutes: profile.sessionMinutes, offset: profile.mesoSessionOffset)
    switch choice {
    case .days:
      guard let days = Int(id), days != profile.daysPerWeek else { return }
      // Same rebase as the old daysPerWeekBinding: from the visit's starting values,
      // so a change and its reversal round-trip.
      if let snapshot = planSnapshot {
        profile.mesoSessionOffset = snapshot.offset
        profile.daysPerWeek = snapshot.settings.daysPerWeek
      }
      profile.setDaysPerWeek(days, sessions: sessions)
    case .minutes:
      guard let minutes = Int(id), minutes != profile.sessionMinutes else { return }
      profile.sessionMinutes = minutes
    case .goal:
      guard id != profile.goal else { return }
      profile.goal = id
    }
    touch()
    showUpdated(before)
  }

  private func showUpdated(_ before: PlanUndo) {
    undoTask?.cancel()
    withAnimation(.easeOut(duration: 0.25)) { planUndo = before }
    AccessibilityNotification.Announcement(String(localized: "Plan updated", bundle: L10n.bundle)).post()
    let seconds: Double = UIAccessibility.isVoiceOverRunning ? 12 : 4
    undoTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.25)) { planUndo = nil }
    }
  }

  private func undoPlanChange() {
    guard let undo = planUndo, let profile = profiles.first else { return }
    undoTask?.cancel()
    profile.goal = undo.goal
    profile.split = undo.split
    profile.daysPerWeek = undo.days
    profile.sessionMinutes = undo.minutes
    profile.mesoSessionOffset = undo.offset
    touch()
    withAnimation(.easeOut(duration: 0.25)) { planUndo = nil }
  }

  private func planAdviceText(_ profile: UserProfile) -> String? {
    let windowStart = Date.now.addingTimeInterval(-Double(PlanChangeAdvice.windowDays) * 86400)
    let logged = decisionLog.filter {
      $0.type == "plan_settings" && $0.date >= windowStart && $0 != visitPlanEntry
    }.count
    return PlanChangeAdvice.advice(
      blockSessions: profile.mesoSessions(sessions), changesInWindow: 1 + logged
    )?.text
  }

  // MARK: Row lists

  private func pushRow<Destination: View, Label: View>(
    _ id: String, @ViewBuilder to destination: () -> Destination, @ViewBuilder label: () -> Label
  ) -> some View {
    NavigationLink { destination() } label: { label() }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier(id)
  }

  private func trainingRows(_ p: UserProfile) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsSectionLabel(String(localized: "Training", bundle: L10n.bundle))
      pushRow("settings.row.plan", to: { PlanDetailsPage(profile: p) }) {
        SettingsRow(
          glyph: "list.bullet.clipboard.fill", title: String(localized: "Plan details", bundle: L10n.bundle),
          value: PlanPreview.planDetailsValue(
            experience: Experience(rawValue: p.experience) ?? .intermediate,
            split: SplitStyle(rawValue: p.split) ?? .auto, days: p.daysPerWeek))
      }
      SettingsHairline()
      pushRow("settings.row.gym", to: { GymPage(profile: p) }) {
        SettingsRow(
          glyph: "dumbbell.fill", title: String(localized: "Gym & equipment", bundle: L10n.bundle),
          value: SettingsFormat.gymName(equipment: p.equipment))
      }
      SettingsHairline()
      pushRow("settings.row.plates", to: { PlatesPage(profile: p) }) {
        SettingsRow(
          glyph: "opticaldisc.fill", title: String(localized: "Plates & bar", bundle: L10n.bundle),
          value: platesValue(p))
      }
      SettingsHairline()
      pushRow("settings.row.rest", to: { RestTimerPage(profile: p) }) {
        SettingsRow(
          glyph: "stopwatch.fill", title: String(localized: "Rest timer", bundle: L10n.bundle),
          subtitle: String(
            localized: "Big lifts \(SettingsFormat.mmss(p.restCompoundSeconds)) · others \(SettingsFormat.mmss(p.restIsolationSeconds))",
            bundle: L10n.bundle))
      }
      SettingsHairline()
      pushRow("settings.row.injuries", to: { InjuriesPage(profile: p) }) {
        SettingsRow(
          glyph: "bandage.fill", title: String(localized: "Injuries & recovery", bundle: L10n.bundle),
          value: injuryValue(p))
      }
      SettingsHairline()
      pushRow("settings.row.custom", to: { CustomExercisesView() }) {
        SettingsRow(
          glyph: "list.bullet.circle.fill",
          title: String(localized: "Custom exercises", bundle: L10n.bundle),
          value: customExercises.isEmpty
            ? String(localized: "None yet", bundle: L10n.bundle) : "\(customExercises.count)")
      }
    }
  }

  private func platesValue(_ p: UserProfile) -> String {
    let barText = Fmt.kg(p.usesLb ? p.barLb : p.barKg, lb: p.usesLb)
    let count = (p.usesLb ? p.platesLb : p.platesKg).count
    return String(localized: "\(barText) bar · \(count) sizes", bundle: L10n.bundle)
  }

  private func injuryValue(_ p: UserProfile) -> String {
    let names = InjuryFlag.allCases.filter { p.injuryFlags.contains($0.rawValue) }.map(\.name)
    return names.isEmpty
      ? String(localized: "None", bundle: L10n.bundle) : names.joined(separator: ", ")
  }

  private var coachRows: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsSectionLabel(String(localized: "Coach", bundle: L10n.bundle))
      pushRow("settings.row.coach", to: { CoachPage() }) {
        SettingsRow(avatar: true, title: coach.name, subtitle: coach.tagline)
      }
      if Features.voice {
        SettingsHairline()
        pushRow("settings.row.voice", to: { VoicePage() }) {
          SettingsRow(
            glyph: "mic.fill", title: String(localized: "Voice", bundle: L10n.bundle),
            value: SettingsFormat.languageName(
              dictationLanguage == "auto" ? L10n.languageCode : dictationLanguage))
        }
      }
    }
  }

  private func appRows(_ p: UserProfile) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsSectionLabel(String(localized: "App", bundle: L10n.bundle))
      Menu {
        Picker(selection: touched(Binding(get: { p.usesLb }, set: { p.usesLb = $0 }))) {
          Text(verbatim: "kg").tag(false)
          Text(verbatim: "lb").tag(true)
        } label: { EmptyView() }
        .pickerStyle(.inline)
      } label: {
        SettingsRow(
          glyph: "scalemass.fill", title: String(localized: "Units", bundle: L10n.bundle),
          value: p.usesLb ? "lb" : "kg", accessory: .menu)
      }
      .accessibilityIdentifier("settings.row.units")
      SettingsHairline()
      pushRow("settings.row.reminder", to: { ReminderPage(profile: p) }) {
        SettingsRow(
          glyph: "bell.fill", title: String(localized: "Reminder", bundle: L10n.bundle),
          value: reminderValue(p))
      }
      SettingsHairline()
      Menu {
        Picker(selection: touched(Binding(get: { p.theme }, set: { p.theme = $0 }))) {
          Text(String(localized: "System", bundle: L10n.bundle)).tag("system")
          Text(String(localized: "Light", bundle: L10n.bundle)).tag("light")
          Text(String(localized: "Dark", bundle: L10n.bundle)).tag("dark")
        } label: { EmptyView() }
        .pickerStyle(.inline)
      } label: {
        SettingsRow(
          glyph: "circle.lefthalf.filled", title: String(localized: "Appearance", bundle: L10n.bundle),
          value: themeLabel(p.theme), accessory: .menu)
      }
      .accessibilityIdentifier("settings.row.appearance")
      SettingsHairline()
      Menu {
        Picker(selection: appLanguageBinding) {
          Text(verbatim: "English").tag("en")
          Text(verbatim: "日本語").tag("ja")
          Text(verbatim: "한국어").tag("ko")
          Text(verbatim: "Tiếng Việt").tag("vi")
        } label: { EmptyView() }
        .pickerStyle(.inline)
        Divider()
        Button(String(localized: "Open in iOS Settings", bundle: L10n.bundle)) {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
        }
      } label: {
        SettingsRow(
          glyph: "character.bubble.fill", title: String(localized: "Language", bundle: L10n.bundle),
          value: SettingsFormat.languageName(appLanguage), accessory: .menu)
      }
      .accessibilityIdentifier("settings.row.language")
    }
  }

  private func reminderValue(_ p: UserProfile) -> String {
    guard p.reminderHour != nil else { return String(localized: "Off", bundle: L10n.bundle) }
    return reminderTrainingDaysOnly
      ? String(localized: "Training days", bundle: L10n.bundle)
      : String(localized: "Every day", bundle: L10n.bundle)
  }

  private func themeLabel(_ theme: String) -> String {
    switch theme {
    case "light": return String(localized: "Light", bundle: L10n.bundle)
    case "dark": return String(localized: "Dark", bundle: L10n.bundle)
    default: return String(localized: "System", bundle: L10n.bundle)
    }
  }

  private var accountRows: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsSectionLabel(String(localized: "Account", bundle: L10n.bundle))
      if auth.user == nil {
        Button {
          showAccount = true
        } label: {
          SettingsRow(
            glyph: "person.crop.circle.fill",
            title: String(localized: "Sign in to sync", bundle: L10n.bundle),
            subtitle: String(localized: "Keep your training on every device", bundle: L10n.bundle))
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("settings.row.account")
      } else {
        pushRow("settings.row.account", to: { AccountPage() }) {
          SettingsRow(
            glyph: "person.crop.circle.fill", title: String(localized: "Account", bundle: L10n.bundle),
            subtitle: auth.user?.email ?? String(localized: "Signed in", bundle: L10n.bundle))
        }
      }
      if Features.pro {
        SettingsHairline()
        pushRow("settings.row.pro", to: { ProPage() }) {
          SettingsRow(
            glyph: "star.fill", title: String(localized: "Regulift Pro", bundle: L10n.bundle),
            value: SettingsFormat.subscriptionShort(store.status))
        }
      }
      SettingsHairline()
      pushRow("settings.row.crew", to: { CrewSharingPage() }) {
        SettingsRow(
          glyph: "person.2.fill", title: String(localized: "Crew sharing", bundle: L10n.bundle),
          value: (autoPostWorkouts || autoPostPRs)
            ? String(localized: "On", bundle: L10n.bundle)
            : String(localized: "Off", bundle: L10n.bundle))
      }
      SettingsHairline()
      pushRow("settings.row.invite", to: { InvitePage() }) {
        SettingsRow(
          glyph: "gift.fill", title: String(localized: "Invite friends", bundle: L10n.bundle),
          subtitle: String(localized: "Give a month, get a month", bundle: L10n.bundle))
      }
      SettingsHairline()
      pushRow("settings.row.data", to: { DataPage() }) {
        SettingsRow(
          glyph: "tray.full.fill", title: String(localized: "Your data", bundle: L10n.bundle),
          value: dataValue)
      }
    }
  }

  private var dataValue: String {
    let n = sessions.filter { $0.completed && !$0.tombstoned }.count
    return String(localized: "\(n) workout\(L10n.pluralSuffix(n))", bundle: L10n.bundle)
  }

  // MARK: Footer

  private var footer: some View {
    VStack(spacing: 14) {
      Button { showFeedback = true } label: {
        HStack(spacing: 8) {
          Image(systemName: "bubble.left.fill").font(.system(size: 17))
          Text(String(localized: "Send feedback", bundle: L10n.bundle)).forge(17, .semibold)
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(Capsule().fill(Theme.innerSurface))
      }
      .buttonStyle(ControlPressStyle())
      .accessibilityIdentifier("settings.feedback")
      HStack(spacing: 18) {
        Link(String(localized: "Privacy Policy", bundle: L10n.bundle), destination: Theme.privacyPolicyURL)
        Link(String(localized: "Terms", bundle: L10n.bundle), destination: Theme.termsURL)
      }
      .forge(15, .medium)
      .foregroundStyle(Theme.accentText)
      .frame(minHeight: 44)
      Text(verbatim: "Regulift \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1")")
        .forge(13).foregroundStyle(Theme.textSecondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 30)
    .padding(.bottom, 40)
  }

  // MARK: Persistence, language

  /// Crew sharing is opt-in. Seed only absent keys so an existing preference is never overwritten.
  private func seedOptInSharingDefaults() {
    for key in ["autoPostWorkouts", "autoPostPRs"]
    where UserDefaults.standard.object(forKey: key) == nil {
      UserDefaults.standard.set(false, forKey: key)
    }
  }

  private func touch() {
    profiles.first?.updatedAt = .now
    try? modelContext.save()
  }

  private func touched<T>(_ binding: Binding<T>) -> Binding<T> {
    Binding(
      get: { binding.wrappedValue },
      set: {
        binding.wrappedValue = $0
        touch()
      })
  }

  private var appLanguageBinding: Binding<String> {
    Binding(
      get: { appLanguage },
      set: { code in
        if code != appLanguage { pendingLanguage = code }
      })
  }

  private func applyLanguage(_ code: String) {
    appLanguage = code
    L10n.apply(code)
    UserDefaults.standard.set([code], forKey: "AppleLanguages")
  }

  /// Keeps one decision row per visit holding the visit's net plan change.
  private func recordPlanSettingsChange() {
    guard let profile = profiles.first, let snapshot = planSnapshot else { return }
    let changes = PlanSettings.changes(from: snapshot.settings, to: profile.planSettings)
    if changes.isEmpty {
      if let entry = visitPlanEntry {
        modelContext.delete(entry)
        visitPlanEntry = nil
      }
      try? modelContext.save()
      return
    }
    let summary = "Plan settings changed: " + changes.joined(separator: ", ") + "."
    if let entry = visitPlanEntry {
      entry.evidence = changes
      entry.humanSummary = summary
      entry.fromValue = Double(snapshot.settings.daysPerWeek)
      entry.toValue = Double(profile.daysPerWeek)
      entry.date = .now
    } else {
      let entry = DecisionLogEntry(
        DecisionRecord(
          id: "plan-settings-\(Int(Date.now.timeIntervalSince1970))",
          date: .now,
          type: "plan_settings",
          exerciseID: nil,
          muscle: nil,
          fromValue: Double(snapshot.settings.daysPerWeek),
          toValue: Double(profile.daysPerWeek),
          reasonCodes: [DecisionSignal.userOverride.code],
          evidence: changes,
          humanSummary: summary))
      modelContext.insert(entry)
      visitPlanEntry = entry
    }
    try? modelContext.save()
  }
}

/// The plan inputs before the last confirmed change, for Undo.
private struct PlanUndo: Equatable {
  let goal: String
  let split: String
  let days: Int
  let minutes: Int
  let offset: Int
}

extension PlanChangeAdvice {
  /// The one advice sentence Settings and the Coach card both show.
  var text: String {
    switch self {
    case .early(let n):
      return String(
        localized:
          "Only \(n) workout\(L10n.pluralSuffix(n)) on this plan so far — too early to judge it. If one thing isn't fitting, change just that: time, exercises or days.",
        bundle: L10n.bundle)
    case .repeated(let n):
      return String(
        localized:
          "\(n) plan changes in 2 weeks. What isn't fitting: time, exercises, difficulty or days? A plan you can repeat shows progress more clearly.",
        bundle: L10n.bundle)
    }
  }
}
