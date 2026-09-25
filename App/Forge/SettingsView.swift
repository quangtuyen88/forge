import ForgeCore
import SwiftData
import SwiftUI

struct SettingsView: View {
  /// Extracted so the settings body stays type-checkable, and so the status is one small view
  /// that owns its own probe.
  private var coachServerRow: some View {
    HStack {
      Text("Coach server").forgeBody()
      Spacer()
      Text(coachServerStatus.label)
        .forgeLabel()
        .foregroundStyle(coachServerStatus == .available ? Theme.positive : Theme.textSecondary)
        .accessibilityIdentifier("settings.coachServerStatus")
    }
    .frame(minHeight: 44)
    .task(id: coachServerProbeKey) { coachServerStatus = await CoachAPI.probeServer() }
  }

  @State private var coachServerStatus: CoachAPI.ServerStatus = .checking
  /// Re-probes when the view appears; the status is a measurement, not a constant.
  @State private var coachServerProbeKey = UUID()
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \CoachNote.date, order: .reverse) private var notes: [CoachNote]
  @Query(sort: \DecisionLogEntry.date) private var decisionLog: [DecisionLogEntry]
  @Environment(Store.self) private var store
  @Environment(AuthClient.self) private var auth
  @Environment(SyncEngine.self) private var sync
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @AppStorage("coachServerURL") private var coachServerURL =
    "https://forge-coach.quangtuyen88.workers.dev"
  @State private var secretInput = ""
  @State private var secretPresent = Keychain.get("forge-app-secret") != nil
  @State private var confirmDelete = false
  @State private var confirmRestart = false
  @State private var confirmAccountDelete = false
  @State private var confirmForgetNotes = false
  @State private var planSnapshot: (settings: PlanSettings, offset: Int)?
  @State private var gymSnapshot: (equipment: Set<Equipment>, injuries: Set<InjuryFlag>)?
  @State private var visitPlanEntry: DecisionLogEntry?
  @State private var showAccount = false
  @State private var showFeedback = false
  @State private var showImport = false
  #if DEBUG
    @State private var showPurchaseTest = false
  #endif
  @State private var pendingLanguage: String?
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @AppStorage("coachConsent") private var coachConsent = false
  @AppStorage("coachOnDevice") private var coachOnDevice = true
  // Sharing to the crew is opt-in: a lifter who never touched this setting posts nothing.
  @AppStorage("autoPostWorkouts") private var autoPostWorkouts = false
  @AppStorage("autoPostPRs") private var autoPostPRs = false
  @AppStorage("dictationLanguage") private var dictationLanguage = "auto"
  @AppStorage("dictationEngine") private var dictationEngine = "cloud"
  @AppStorage("voiceActivationRequired") private var voiceActivationRequired = false
  @AppStorage("voiceFastLogging") private var voiceFastLogging = false
  @AppStorage("voiceAllowServerRecognition") private var voiceAllowServerRecognition = false
  @AppStorage("voiceSmartFallback") private var voiceSmartFallback = false
  @AppStorage("appLanguage") private var appLanguage = "en"
  @AppStorage("coachAudioMode") private var coachAudioMode = CoachAudioMode.off.rawValue
  @AppStorage(WhisperModelStore.enabledKey) private var voiceOffline = false
  @State private var whisperModels = WhisperModelStore.shared

  private var coach: Coach { Coach.from(coachID) }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Theme.groupGap) {
          if let p = profiles.first {
            @Bindable var profile = p

            section(String(localized: "Account", bundle: L10n.bundle)) {
              if auth.user == nil {
                Button {
                  showAccount = true
                } label: {
                  HStack {
                    Text("Sign in to sync across devices").forgeBody()
                    Spacer()
                    Image(systemName: "icloud.and.arrow.up").foregroundStyle(Theme.textTertiary)
                  }
                  .frame(minHeight: 44)
                  .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
              } else {
                HStack {
                  Text("Email").forgeBody()
                  Spacer()
                  if let email = auth.user?.email {
                    VStack(alignment: .trailing, spacing: 2) {
                      Text(email).forgeLabel()
                      if email.lowercased().hasSuffix("@privaterelay.appleid.com") {
                        Text("Apple private relay").forgeCaption()
                      }
                    }
                  } else {
                    Text(String(localized: "Signed in", bundle: L10n.bundle)).forgeLabel()
                  }
                }
                .frame(minHeight: 44)
                Divider().overlay(Theme.ring)
                HStack {
                  Text("Plan").forgeBody()
                  Spacer()
                  Text(
                    auth.user?.tier == "pro"
                      ? String(localized: "Pro", bundle: L10n.bundle)
                      : String(localized: "Free", bundle: L10n.bundle)
                  ).forgeLabel()
                }
                .frame(minHeight: 44)
                Divider().overlay(Theme.ring)
                HStack {
                  Text("Last sync · \(relativeSync)").forgeBody()
                  Spacer()
                  if sync.syncing {
                    ProgressView()
                  } else {
                    Button("Sync now") {
                      Task { await SyncEngine.shared.sync() }
                    }
                    .foregroundStyle(Theme.accent)
                    .forgeBodyStrong()
                  }
                }
                .frame(minHeight: 44)
                Divider().overlay(Theme.ring)
                Button("Sign out") {
                  Task { await auth.signOut() }
                }
                .foregroundStyle(Theme.accent)
                .forgeBodyStrong()
                .frame(minHeight: 44)
                Divider().overlay(Theme.ring)
                Button("Delete account") {
                  confirmAccountDelete = true
                }
                .foregroundStyle(Theme.negative)
                .forgeBody()
                .frame(minHeight: 44)
              }
            }

            section(String(localized: "Invite", bundle: L10n.bundle)) {
              ReferralView()
            }

            section(String(localized: "Crew", bundle: L10n.bundle)) {
              Toggle("Post finished workouts to my crew", isOn: $autoPostWorkouts)
                .tint(Theme.accent)
                .forgeBody().padding(.vertical, 6)
              Divider().overlay(Theme.ring)
              Toggle("Post new PRs to my crew", isOn: $autoPostPRs)
                .tint(Theme.accent)
                .forgeBody().padding(.vertical, 6)
            }

            section(String(localized: "Units", bundle: L10n.bundle)) {
              Picker("Weight units", selection: touched($profile.usesLb)) {
                Text("kg").tag(false)
                Text("lb").tag(true)
              }
              .pickerStyle(.segmented)
            }

            section(String(localized: "Rest timer", bundle: L10n.bundle)) {
              Stepper(value: touched($profile.restCompoundSeconds), in: 60...300, step: 15) {
                HStack {
                  Text("Compounds").forgeBody()
                  Spacer()
                  Text(mmss(profile.restCompoundSeconds)).forgeLabel().monospacedDigit()
                }
              }
              Divider().overlay(Theme.ring)
              Stepper(value: touched($profile.restIsolationSeconds), in: 30...180, step: 15) {
                HStack {
                  Text("Isolation").forgeBody()
                  Spacer()
                  Text(mmss(profile.restIsolationSeconds)).forgeLabel().monospacedDigit()
                }
              }
              if !profile.restOverrides.isEmpty {
                Divider().overlay(Theme.ring)
                Button("Reset per-exercise timers") {
                  profile.restOverrides = [:]
                  touch()
                }
                .foregroundStyle(Theme.negative)
                .forgeBodyStrong()
                .frame(minHeight: 44)
              }
            }

            section(String(localized: "Training", bundle: L10n.bundle)) {
              Picker("Goal", selection: touched(goalBinding(profile))) {
                ForEach(Goal.allCases, id: \.self) { Text($0.name).tag($0) }
              }
              .pickerStyle(.segmented)
              Divider().overlay(Theme.ring)
              Picker("Experience", selection: touched(experienceBinding(profile))) {
                ForEach(Experience.allCases, id: \.self) { Text($0.name).tag($0) }
              }
              .pickerStyle(.segmented)
              Divider().overlay(Theme.ring)
              Picker("Split", selection: touched(splitBinding(profile))) {
                ForEach(SplitStyle.allCases, id: \.self) { Text($0.name).tag($0) }
              }
              .pickerStyle(.menu)
              .forgeBody()
              .frame(minHeight: 44)
              Divider().overlay(Theme.ring)
              Stepper(value: daysPerWeekBinding(profile), in: 2...6) {
                HStack {
                  Text("Days per week").forgeBody()
                  Spacer()
                  Text("\(profile.daysPerWeek)").forgeLabel().monospacedDigit()
                }
              }
              Divider().overlay(Theme.ring)
              Picker("Session length", selection: touched(sessionBinding(profile))) {
                ForEach(SessionLength.allCases, id: \.self) { Text("\($0.rawValue) min").tag($0) }
              }
              .pickerStyle(.segmented)
              if planChangedThisVisit(profile) {
                Divider().overlay(Theme.ring)
                VStack(alignment: .leading, spacing: 4) {
                  Text(planConsequenceLine(profile)).forgeCaption()
                  if let advice = planAdvice(profile) {
                    advice.foregroundStyle(Theme.textSecondary).forgeCaption()
                  }
                }
                .padding(.vertical, 6)
              }
              Divider().overlay(Theme.ring)
              HStack {
                Text(String(localized: "Gym", bundle: L10n.bundle)).forgeBody()
                Spacer()
                Menu {
                  ForEach(GymPreset.allCases, id: \.self) { preset in
                    Button(preset.name) { applyGymPreset(preset, to: profile) }
                  }
                  Button(String(localized: "Custom", bundle: L10n.bundle)) {
                    profile.gymPreset = "custom"
                  }
                } label: {
                  Text(gymName(profile)).forgeLabel()
                }
              }
              .frame(minHeight: 44)
              Text(
                String(localized: "Programming only uses equipment you have.", bundle: L10n.bundle)
              )
              .forgeCaption()
              .padding(.vertical, 6)
              ForEach(Equipment.allCases, id: \.self) { item in
                Divider().overlay(Theme.ring)
                Toggle(item.name, isOn: touched(equipmentBinding(profile, item)))
                  .tint(Theme.accent)
                  .forgeBody().padding(.vertical, 6)
              }
              ForEach(InjuryFlag.allCases, id: \.self) { flag in
                Divider().overlay(Theme.ring)
                Toggle(flag.name, isOn: touched(injuryBinding(profile, flag)))
                  .tint(Theme.accent)
                  .forgeBody().padding(.vertical, 6)
              }
              if let line = gymChangeLine(profile) {
                Divider().overlay(Theme.ring)
                Text(line).forgeCaption().padding(.vertical, 6)
              }
              Divider().overlay(Theme.ring)
              Toggle(
                "I sleep under 6 h or life stress is high", isOn: touched($profile.recoveryReduced)
              )
              .accessibilityIdentifier("recovery-reduced-toggle")
              .tint(Theme.accent)
              .forgeBody().padding(.vertical, 6)
              Divider().overlay(Theme.ring)
              Button("Restart training block") {
                confirmRestart = true
              }
              .foregroundStyle(Theme.accent)
              .forgeBodyStrong()
              .frame(minHeight: 44)
              if !profile.exerciseOverrides.isEmpty {
                Divider().overlay(Theme.ring)
                ForEach(profile.exerciseOverrides.sorted { $0.key < $1.key }, id: \.key) {
                  from, to in
                  HStack {
                    Text("\(exerciseName(from)) → \(exerciseName(to))").forgeBody()
                    Spacer()
                    Button {
                      profile.exerciseOverrides.removeValue(forKey: from)
                      touch()
                    } label: {
                      Image(systemName: "minus.circle.fill").foregroundStyle(Theme.negative)
                    }
                  }
                  .frame(minHeight: 44)
                }
              }
              Divider().overlay(Theme.ring)
              NavigationLink {
                CustomExercisesView()
              } label: {
                HStack {
                  Text("Custom exercises").forgeBody()
                  Spacer()
                  Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
              }
              .buttonStyle(RowPressStyle())
              Divider().overlay(Theme.ring)
              NavigationLink {
                TrainingConstraintsView()
              } label: {
                HStack {
                  Text("Training setup & modes").forgeBody()
                  Spacer()
                  Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
              }
              .buttonStyle(RowPressStyle())
            }
            .onChange(
              of: "\(profile.goal)|\(profile.split)|\(profile.daysPerWeek)|\(profile.sessionMinutes)"
            ) { _, _ in
              profile.reviseWeekPlan(sessions: sessions)
              touch()
            }

            section(String(localized: "Coach", bundle: L10n.bundle)) {
              HStack(spacing: 12) {
                ForEach(Coach.allCases) { c in
                  Button {
                    withAnimation(.snappy) { coachID = c.rawValue }
                    touch()
                  } label: {
                    HStack(spacing: 8) {
                      Image(c.avatar).resizable().scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                      Text(c.name).forgeBodyStrong()
                      Spacer()
                    }
                    .padding(10)
                    .background(
                      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(
                        coach == c ? Theme.accentTint : Theme.innerSurface)
                    )
                    .overlay(
                      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
                        .strokeBorder(coach == c ? Theme.accent : .clear, lineWidth: 1.5))
                  }
                  .buttonStyle(RowPressStyle())
                }
              }
              Divider().overlay(Theme.ring)
              Toggle("Share training data with the coach", isOn: $coachConsent)
                .tint(Theme.accent)
                .forgeBody().padding(.vertical, 6)
              Divider().overlay(Theme.ring)
              if OnDeviceCoach.isAvailable {
                Toggle("Answer on-device when possible", isOn: $coachOnDevice)
                  .tint(Theme.accent)
                  .forgeBody().padding(.vertical, 6)
                Text(
                  "Apple Intelligence answers questions on this iPhone. Plan changes still use the Regulift coach service."
                )
                .forgeCaption()
              } else {
                Text(
                  "Apple Intelligence is not available on this device; the coach service answers instead."
                )
                .forgeCaption()
                .padding(.vertical, 6)
              }
              Divider().overlay(Theme.ring)
              Text("Coach memory").forgeLabel()
              let activeNotes = notes.filter { $0.isActive }
              if activeNotes.isEmpty {
                Text(
                  "Nothing yet. Confirmed facts about equipment, injuries, schedule, goals and preferences appear here."
                )
                .forgeCaption()
                .padding(.vertical, 6)
              } else {
                ForEach(activeNotes) { note in
                  HStack {
                    VStack(alignment: .leading, spacing: 2) {
                      Text(note.text).forgeBody()
                      Text("\(note.memoryKind.name) · \(note.source)").forgeCaption()
                    }
                    Spacer()
                    Button {
                      modelContext.delete(note)
                    } label: {
                      Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ControlPressStyle())
                    .accessibilityLabel("Forget this note")
                  }
                  .frame(minHeight: 44)
                }
                Button("Forget all", role: .destructive) { confirmForgetNotes = true }
                  .foregroundStyle(Theme.negative)
                  .forgeBody()
                  .frame(minHeight: 44)
                  .confirmationDialog(
                    "Forget all coach notes?", isPresented: $confirmForgetNotes,
                    titleVisibility: .visible
                  ) {
                    Button("Forget all", role: .destructive) {
                      for note in notes { modelContext.delete(note) }
                    }
                  }
              }
              Divider().overlay(Theme.ring)
              Link("Privacy Policy", destination: Theme.privacyPolicyURL)
                .forgeBody()
                .frame(minHeight: 44)
              Divider().overlay(Theme.ring)
              Link("Terms", destination: Theme.termsURL)
                .forgeBody()
                .frame(minHeight: 44)
              if AppSecret.bundled != nil {
                Divider().overlay(Theme.ring)
                coachServerRow
              } else {
                Divider().overlay(Theme.ring)
                TextField("Server URL", text: $coachServerURL)
                  .keyboardType(.URL)
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .forgeBody()
                  .padding(10)
                  .background(
                    RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(
                      Theme.innerSurface))
                if secretPresent {
                  Divider().overlay(Theme.ring)
                  HStack {
                    Text("App secret · Saved").forgeBody()
                    Spacer()
                    Button("Remove") {
                      Keychain.delete("forge-app-secret")
                      secretPresent = false
                    }
                    .foregroundStyle(Theme.negative)
                    .forgeBodyStrong()
                  }
                  .frame(minHeight: 44)
                } else {
                  Divider().overlay(Theme.ring)
                  HStack {
                    SecureField("App secret", text: $secretInput)
                      .forgeBody()
                      .padding(10)
                      .background(
                        RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(
                          Theme.innerSurface))
                    Button("Save") {
                      Keychain.set(secretInput, for: "forge-app-secret")
                      secretInput = ""
                      secretPresent = true
                    }
                    .disabled(secretInput.isEmpty)
                    .foregroundStyle(Theme.accent)
                    .forgeBodyStrong()
                  }
                }
              }
            }

            if Features.voice {
              section(String(localized: "Voice", bundle: L10n.bundle)) {
                HStack(spacing: 8) {
                  // Settings never records: this line states what the microphone will be set
                  // to, not that it is open. "Listening" belongs on the live workout badge.
                  Image(systemName: "mic.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.metricTime)
                  Text(
                    String(
                      localized: "Recognition language · \(listeningLanguageName)",
                      bundle: L10n.bundle)
                  )
                  .forgeBodyStrong()
                  .foregroundStyle(Theme.metricTime)
                  .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Capsule().fill(Theme.metricTime.opacity(0.12)))
                .padding(.bottom, 10)
                Divider().overlay(Theme.ring)
                Toggle(
                  String(localized: "Require “Coach” before a command", bundle: L10n.bundle),
                  isOn: $voiceActivationRequired
                )
                .tint(Theme.metricSets)
                .forgeBody().padding(.vertical, 6)
                Text(String(localized: "Useful in a noisy gym.", bundle: L10n.bundle))
                  .forgeCaption()
                  .padding(.vertical, 6)
                Divider().overlay(Theme.ring)
                Toggle(
                  String(localized: "Fast logging", bundle: L10n.bundle), isOn: $voiceFastLogging
                )
                .tint(Theme.metricSets)
                .forgeBody().padding(.vertical, 6)
                Text(
                  String(
                    localized: "Logs a set straight away with Undo; off asks first.",
                    bundle: L10n.bundle)
                )
                .forgeCaption()
                .padding(.vertical, 6)
                Divider().overlay(Theme.ring)
                Toggle(
                  String(localized: "Use Apple's speech service", bundle: L10n.bundle),
                  isOn: $voiceAllowServerRecognition
                )
                .tint(Theme.metricSets)
                .forgeBody().padding(.vertical, 6)
                Text(
                  String(
                    localized:
                      "Audio goes to Apple, never to Regulift; off, it never leaves this device.",
                    bundle: L10n.bundle)
                )
                .forgeCaption()
                .padding(.vertical, 6)
                Divider().overlay(Theme.ring)
                Toggle(
                  String(localized: "Understand unusual phrasing", bundle: L10n.bundle),
                  isOn: $voiceSmartFallback
                )
                .tint(Theme.metricSets)
                .forgeBody().padding(.vertical, 6)
                Text(
                  String(
                    localized:
                      "Sends unrecognised words to our server; off by default, the rest stays on your phone.",
                    bundle: L10n.bundle)
                )
                .forgeCaption()
                .padding(.vertical, 6)
                  Divider().overlay(Theme.ring)
                Picker(
                  String(localized: "Coach audio", bundle: L10n.bundle),
                  selection: $coachAudioMode
                ) {
                  ForEach(CoachAudioMode.allCases) { mode in
                    Text(mode.name).tag(mode.rawValue)
                  }
                }
                .pickerStyle(.segmented)
                Text(
                  String(
                    localized:
                      "Speaks only what is already on screen. Audio is generated on device.",
                    bundle: L10n.bundle)
                )
                .forgeCaption()
                .padding(.vertical, 6)
                Divider().overlay(Theme.ring)
                offlineVoiceRows
              }
            }

            section(String(localized: "Plates", bundle: L10n.bundle)) {
              Stepper(
                value: profile.usesLb ? touched($profile.barLb) : touched($profile.barKg),
                in: profile.usesLb ? 25...65 : 10...30,
                step: profile.usesLb ? 5 : 2.5
              ) {
                HStack {
                  Text("Bar weight").forgeBody()
                  Spacer()
                  Text(
                    "\(trim(profile.usesLb ? profile.barLb : profile.barKg)) \(profile.usesLb ? "lb" : "kg")"
                  )
                  .forgeLabel().monospacedDigit()
                }
              }
              ForEach(plateCatalogue(profile.usesLb), id: \.self) { plate in
                Divider().overlay(Theme.ring)
                Toggle(isOn: touched(plateBinding(profile, plate))) {
                  HStack(spacing: 10) {
                    Text(trim(plate))
                      .forgeBodyStrong()
                      .monospacedDigit()
                      .foregroundStyle(Theme.plateLabelColor(plate, usesLb: profile.usesLb))
                      .frame(width: 40, height: 40)
                      .background(
                        RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(
                          Theme.plateColor(plate, usesLb: profile.usesLb)))
                    Text(profile.usesLb ? "lb" : "kg")
                      .forgeLabel()
                  }
                }
                .tint(Theme.metricSets)
                .padding(.vertical, 6)
              }
            }

            section(String(localized: "Appearance", bundle: L10n.bundle)) {
              Picker("Theme", selection: touched(themeBinding(profile))) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
              }
              .pickerStyle(.segmented)
            }

            section(String(localized: "Language", bundle: L10n.bundle)) {
              Picker(
                String(localized: "Language", bundle: L10n.bundle), selection: appLanguageBinding
              ) {
                Text("English").tag("en")
                Text("日本語").tag("ja")
                Text("한국어").tag("ko")
                Text("Tiếng Việt").tag("vi")
              }
              .pickerStyle(.menu)
              .forgeBody()
              .frame(minHeight: 44)
              Divider().overlay(Theme.ring)
              Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                  UIApplication.shared.open(url)
                }
              } label: {
                HStack {
                  Text(String(localized: "Open in iOS Settings", bundle: L10n.bundle)).forgeBody()
                  Spacer()
                  Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
              }
              .buttonStyle(RowPressStyle())
              if Features.voice {
                Divider().overlay(Theme.ring)
                Picker("Dictation engine", selection: $dictationEngine) {
                  Text("Cloud (most accurate)").tag("cloud")
                  Text("On device (private, offline)").tag("device")
                }
                .pickerStyle(.menu)
                .forgeBody()
                .frame(minHeight: 44)
                Text(
                  "Cloud dictation sends the audio clip to Regulift's coach service to turn it into text; it is not stored."
                )
                .forgeCaption()
                .padding(.vertical, 6)
                Divider().overlay(Theme.ring)
                Picker("Dictation language", selection: $dictationLanguage) {
                  Text("Follow app language").tag("auto")
                  Text("English").tag("en")
                  Text("日本語").tag("ja")
                  Text("한국어").tag("ko")
                  Text("Tiếng Việt").tag("vi")
                }
                .pickerStyle(.menu)
                .forgeBody()
                .frame(minHeight: 44)
              }
            }

            section(String(localized: "Notifications", bundle: L10n.bundle)) {
              Toggle("Workout reminder", isOn: touched(reminderBinding(profile)))
                .tint(Theme.accent)
                .forgeBody().padding(.vertical, 6)
              if profile.reminderHour != nil {
                Divider().overlay(Theme.ring)
                DatePicker(
                  "Time", selection: touched(reminderTimeBinding(profile)),
                  displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
              }
              Text("A daily nudge with today's session.")
                .forgeCaption()
                .padding(.top, 6)
            }

            section(String(localized: "Data", bundle: L10n.bundle)) {
              programAndDataLink
              Divider().overlay(Theme.ring)
              Button {
                showImport = true
              } label: {
                Label("Import from Strong or Hevy", systemImage: "square.and.arrow.down")
                  .forgeBody()
              }
              .frame(minHeight: 44)
              Divider().overlay(Theme.ring)
              ShareLink(item: csvURL) {
                Label("Export CSV", systemImage: "square.and.arrow.up").forgeBody()
              }
              .frame(minHeight: 44)
              Divider().overlay(Theme.ring)
              Button("Send feedback") {
                showFeedback = true
              }
              .foregroundStyle(Theme.accent)
              .forgeBody()
              .frame(minHeight: 44)
              Divider().overlay(Theme.ring)
              Button("Delete all training data") {
                confirmDelete = true
              }
              .foregroundStyle(Theme.negative)
              .forgeBody()
              .frame(minHeight: 44)
            }

            if Features.pro {
              section(String(localized: "Subscription", bundle: L10n.bundle)) {
                HStack {
                  Text("Regulift Pro").forgeBody()
                  Spacer()
                  Text(subStatusText).forgeLabel()
                }
                .frame(minHeight: 44)
                #if DEBUG
                  Divider().overlay(Theme.ring)
                  Button("Test purchase flow") {
                    showPurchaseTest = true
                  }
                  .foregroundStyle(Theme.accent)
                  .forgeBodyStrong()
                  .frame(minHeight: 44)
                #endif
                Divider().overlay(Theme.ring)
                Button("Restore purchases") {
                  Task { await store.restore() }
                }
                .foregroundStyle(Theme.accent)
                .forgeBodyStrong()
                .frame(minHeight: 44)
              }
            }

            section(String(localized: "About", bundle: L10n.bundle)) {
              HStack {
                Text("Version").forgeBody()
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1")
                  .forgeLabel()
              }
              .frame(minHeight: 44)
            }
          }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
        .padding(.bottom, 24)
      }
      .background(Theme.page)
      .navigationTitle("Settings")
      .toolbar { Button("Done") { dismiss() }.bold() }
      .onAppear {
        if coachServerURL == Theme.legacyCoachServer { coachServerURL = Theme.coachServer }
        seedOptInSharingDefaults()
        if planSnapshot == nil, let p = profiles.first {
          planSnapshot = (settings: p.planSettings, offset: p.mesoSessionOffset)
        }
        if gymSnapshot == nil, let p = profiles.first {
          let input = p.profileInput
          gymSnapshot = (equipment: input.equipment, injuries: input.injuryFlags)
        }
        Task { await auth.refresh() }
      }
      .onDisappear { recordPlanSettingsChange() }
      .sheet(isPresented: $showFeedback) { FeedbackSheet() }
      .sheet(isPresented: $showImport) { ImportView() }
      .sheet(isPresented: $showAccount) { AccountView() }
      #if DEBUG
        .sheet(isPresented: $showPurchaseTest) { PaywallView() }
      #endif
      .confirmationDialog(
        "Delete all training data?", isPresented: $confirmDelete, titleVisibility: .visible
      ) {
        Button("Delete all training data", role: .destructive) {
          Task { await deleteAllData() }
        }
      } message: {
        if auth.user != nil {
          Text("Deletes your training data on this device and in your account.")
        }
      }
      .confirmationDialog(
        "Start a fresh 6-week block?", isPresented: $confirmRestart, titleVisibility: .visible
      ) {
        Button("Restart training block", role: .destructive) {
          profileReset(profiles.first)
        }
      }
      .confirmationDialog(
        "Delete your account?", isPresented: $confirmAccountDelete, titleVisibility: .visible
      ) {
        Button("Delete account and data", role: .destructive) {
          Analytics.track("account_deleted")
          Task {
            try? await auth.deleteAccount()
            wipeTrainingData()
          }
        }
      }
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
            localized: "The app will switch to \(languageName(code)) right away.",
            bundle: L10n.bundle))
      }
    }
  }

  /// Crew sharing is opt-in. Seed only absent keys so an existing preference is never overwritten.
  private func seedOptInSharingDefaults() {
    for key in ["autoPostWorkouts", "autoPostPRs"]
    where UserDefaults.standard.object(forKey: key) == nil {
      UserDefaults.standard.set(false, forKey: key)
    }
  }

  private func wipeTrainingData() {
    try? modelContext.delete(model: WorkoutSession.self)
    try? modelContext.delete(model: CheckIn.self)
    try? modelContext.delete(model: BodyMeasurement.self)
    try? modelContext.delete(model: ProgressPhoto.self)
    try? modelContext.delete(model: CoachMessage.self)
    try? modelContext.delete(model: FoodEntry.self)
    // JourneyPlans: notes, hide/restore overrides and the local identity card are device-local,
    // so a device or account wipe clears them here. Deleting the override rows never touches a
    // workout, measurement, photo or decision — hiding was never a deletion.
    try? modelContext.delete(model: JourneyReflection.self)
    try? modelContext.delete(model: JourneyVisibilityOverride.self)
    try? modelContext.delete(model: JourneyPrivateProfile.self)
  }

  private func deleteAllData() async {
    if auth.user != nil {
      for m in (try? modelContext.fetch(FetchDescriptor<WorkoutSession>())) ?? [] {
        m.tombstoned = true
        m.updatedAt = .now
      }
      for m in (try? modelContext.fetch(FetchDescriptor<CheckIn>())) ?? [] {
        m.tombstoned = true
        m.updatedAt = .now
      }
      for m in (try? modelContext.fetch(FetchDescriptor<BodyMeasurement>())) ?? [] {
        m.tombstoned = true
        m.updatedAt = .now
      }
      for m in (try? modelContext.fetch(FetchDescriptor<FoodEntry>())) ?? [] {
        m.tombstoned = true
        m.updatedAt = .now
      }
      try? modelContext.save()
      await SyncEngine.shared.sync()
    }
    wipeTrainingData()
  }

  private func touch() {
    profiles.first?.updatedAt = .now
    try? modelContext.save()
  }

  // ponytail: "now" literal matches only en; revisit when translated catalogs ship
  private var relativeSync: String {
    guard let date = sync.lastSync else { return String(localized: "never", bundle: L10n.bundle) }
    let relative = date.formatted(.relative(presentation: .named).locale(L10n.locale))
    return relative == "now" ? String(localized: "just now", bundle: L10n.bundle) : relative
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

  private func languageName(_ code: String) -> String {
    switch code {
    case "ja": return "日本語"
    case "ko": return "한국어"
    case "vi": return "Tiếng Việt"
    default: return "English"
    }
  }

  /// The language the microphone currently listens in: the Dictation-language setting
  /// when it is explicit, otherwise the app language.
  private var listeningLanguageName: String {
    let code = dictationLanguage == "auto" ? L10n.languageCode : dictationLanguage
    return languageName(code)
  }

  /// The canonical route into the program: the block, the week, goals and the imported
  /// program all sit behind this one entry point, kept out of `body` for the type checker.
  private var programAndDataLink: some View {
    NavigationLink {
      ProgramRoadmapView()
    } label: {
      HStack {
        Text(String(localized: "Program & data", bundle: L10n.bundle)).forgeBody()
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.textTertiary)
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(String(localized: "Program & data", bundle: L10n.bundle))
    .accessibilityValue(
      String(
        localized: "Program roadmap, week designer, goals and program import",
        bundle: L10n.bundle))
  }

  private func touched<T>(_ binding: Binding<T>) -> Binding<T> {
    Binding(
      get: { binding.wrappedValue },
      set: {
        binding.wrappedValue = $0
        touch()
      })
  }

  private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title).forgeSection().padding(.bottom, 10)
      rows()
    }
    .card()
  }

  private func mmss(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private var subStatusText: String {
    switch store.status {
    case .trial(let ends):
      return String(
        localized: "Trial · ends \(ends.formatted(.dateTime.day().month().locale(L10n.locale)))",
        bundle: L10n.bundle)
    case .active(let renews):
      if Store.usesTestStore, let renews {
        return
          "Active · Test Store · expires \(renews.formatted(.dateTime.day().month().hour().minute().locale(L10n.locale)))"
      }
      return renews.map {
        String(
          localized: "Active · renews \($0.formatted(.dateTime.day().month().locale(L10n.locale)))",
          bundle: L10n.bundle)
      } ?? String(localized: "Active", bundle: L10n.bundle)
    case .grace: return String(localized: "Grace period · update payment", bundle: L10n.bundle)
    case .expired: return String(localized: "Expired", bundle: L10n.bundle)
    case .none: return String(localized: "Not subscribed", bundle: L10n.bundle)
    }
  }

  private func profileReset(_ profile: UserProfile?) {
    profile?.startNewBlock()
  }

  private func exerciseName(_ id: String) -> String {
    ExerciseDB.find(id)?.name ?? id
  }

  private func trim(_ value: Double) -> String {
    value == value.rounded() ? "\(Int(value))" : "\(value)"
  }

  private func plateCatalogue(_ usesLb: Bool) -> [Double] {
    usesLb ? [45, 35, 25, 10, 5, 2.5, 1.25] : [25, 20, 15, 10, 5, 2.5, 1.25, 0.5]
  }

  private func plateBinding(_ profile: UserProfile, _ plate: Double) -> Binding<Bool> {
    Binding(
      get: { (profile.usesLb ? profile.platesLb : profile.platesKg).contains(plate) },
      set: { on in
        var plates = profile.usesLb ? profile.platesLb : profile.platesKg
        if on {
          if !plates.contains(plate) { plates.append(plate) }
        } else {
          plates.removeAll { $0 == plate }
        }
        let sorted = plates.sorted(by: >)
        if profile.usesLb { profile.platesLb = sorted } else { profile.platesKg = sorted }
      })
  }

  private func goalBinding(_ profile: UserProfile) -> Binding<Goal> {
    Binding(
      get: { Goal(rawValue: profile.goal) ?? .hypertrophy },
      set: { profile.goal = $0.rawValue })
  }

  private func experienceBinding(_ profile: UserProfile) -> Binding<Experience> {
    Binding(
      get: { Experience(rawValue: profile.experience) ?? .intermediate },
      set: { profile.experience = $0.rawValue })
  }

  private func splitBinding(_ profile: UserProfile) -> Binding<SplitStyle> {
    Binding(
      get: { SplitStyle(rawValue: profile.split) ?? .auto },
      set: { profile.split = $0.rawValue })
  }

  private func themeBinding(_ profile: UserProfile) -> Binding<String> {
    Binding(
      get: { profile.theme },
      set: { profile.theme = $0 })
  }

  private func reminderBinding(_ profile: UserProfile) -> Binding<Bool> {
    Binding(
      get: { profile.reminderHour != nil },
      set: { on in
        if on {
          profile.reminderHour = profile.reminderHour ?? 19
          Task {
            await Notifications.requestAuthorization()
            Notifications.scheduleDailyReminder(
              hour: profile.reminderHour ?? 19, minute: profile.reminderMinute)
          }
        } else {
          profile.reminderHour = nil
          Notifications.cancelReminder()
        }
      })
  }

  private func reminderTimeBinding(_ profile: UserProfile) -> Binding<Date> {
    Binding(
      get: {
        var components = DateComponents()
        components.hour = profile.reminderHour ?? 19
        components.minute = profile.reminderMinute
        return Calendar.current.date(from: components) ?? .now
      },
      set: { date in
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        profile.reminderHour = components.hour
        profile.reminderMinute = components.minute ?? 0
        Notifications.scheduleDailyReminder(
          hour: components.hour ?? 19, minute: components.minute ?? 0)
      })
  }

  private func sessionBinding(_ profile: UserProfile) -> Binding<SessionLength> {
    Binding(
      get: { SessionLength(rawValue: profile.sessionMinutes) ?? .m60 },
      set: { profile.sessionMinutes = $0.rawValue })
  }

  /// Days per week goes through the rebase so the program week never moves on an edit; rebase
  /// from the visit's starting values so an overshoot and correction round-trips exactly.
  private func daysPerWeekBinding(_ profile: UserProfile) -> Binding<Int> {
    Binding(
      get: { profile.daysPerWeek },
      set: { days in
        if let snapshot = planSnapshot {
          profile.mesoSessionOffset = snapshot.offset
          profile.daysPerWeek = snapshot.settings.daysPerWeek
        }
        profile.setDaysPerWeek(days, sessions: sessions)
        touch()
      })
  }

  private func planChangedThisVisit(_ profile: UserProfile) -> Bool {
    guard let planSnapshot else { return false }
    return profile.planSettings != planSnapshot.settings
  }

  /// What this visit's gym, equipment or injury change does to the exercises in this week's plan.
  private func gymChangeLine(_ profile: UserProfile) -> String? {
    guard let gymSnapshot else { return nil }
    let after = profile.profileInput
    guard after.equipment != gymSnapshot.equipment || after.injuryFlags != gymSnapshot.injuries else {
      return nil
    }
    var before = after
    before.equipment = gymSnapshot.equipment
    before.injuryFlags = gymSnapshot.injuries
    let swaps = Personalization.exerciseSwaps(before: before, after: after)
    guard !swaps.isEmpty else {
      return String(localized: "This week's plan keeps the same exercises.", bundle: L10n.bundle)
    }
    let shown = swaps.prefix(3).joined(separator: " · ") + (swaps.count > 3 ? " · +\(swaps.count - 3)" : "")
    return String(localized: "This week's plan: \(shown)", bundle: L10n.bundle)
  }

  /// What the plan edit means for the lifter's saved work, week and current week plan.
  private func planConsequenceLine(_ profile: UserProfile) -> String {
    var line = String(
      localized:
        "Applies from today. Workouts you finished stay saved, and you stay in week \(profile.currentWeek(sessions: sessions)) of \(Mesocycle.weeks).",
      bundle: L10n.bundle)
    if let plan = profile.weekPlan,
      let weekEnd = plan.resolvedCalendar(.current).date(
        byAdding: .day, value: 7, to: plan.weekStart),
      Date.now >= plan.weekStart, Date.now < weekEnd
    {
      let counts = plan.evaluation(now: .now).counts
      line += " "
        + String(
          localized: "This week: \(counts.completed) of \(counts.scheduled) done.",
          bundle: L10n.bundle)
    }
    return line
  }

  /// Short advice after a plan edit: judge a plan later, or notice repeated changes.
  private func planAdvice(_ profile: UserProfile) -> Text? {
    let windowStart = Date.now.addingTimeInterval(-Double(PlanChangeAdvice.windowDays) * 86400)
    let logged = decisionLog.filter {
      $0.type == "plan_settings" && $0.date >= windowStart && $0 != visitPlanEntry
    }.count
    guard
      let advice = PlanChangeAdvice.advice(
        blockSessions: profile.mesoSessions(sessions), changesInWindow: 1 + logged)
    else { return nil }
    return Text(advice.text)
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

  private func equipmentBinding(_ profile: UserProfile, _ item: Equipment) -> Binding<Bool> {
    Binding(
      get: { profile.equipment.contains(item.rawValue) },
      set: { on in
        var equipment = currentEquipment(profile)
        if on { equipment.insert(item) } else { equipment.remove(item) }
        var constraints = profile.trainingConstraints
        let custom = GymProfileConfig(id: "custom", name: "Custom", equipment: equipment)
        if let index = constraints.gymProfiles.firstIndex(where: { $0.id == custom.id }) {
          constraints.gymProfiles[index] = custom
        } else {
          constraints.gymProfiles.append(custom)
        }
        constraints.activeGymProfileID = custom.id
        profile.trainingConstraints = constraints
      })
  }

  private func applyGymPreset(_ preset: GymPreset, to profile: UserProfile) {
    var constraints = profile.trainingConstraints
    let gym = GymProfileConfig(id: preset.rawValue, name: preset.name, equipment: preset.equipment)
    if let index = constraints.gymProfiles.firstIndex(where: { $0.id == gym.id }) {
      constraints.gymProfiles[index] = gym
    } else {
      constraints.gymProfiles.append(gym)
    }
    constraints.activeGymProfileID = gym.id
    profile.trainingConstraints = constraints
    Analytics.track("gym_preset", ["preset": preset.rawValue])
  }
  private func currentEquipment(_ profile: UserProfile) -> Set<Equipment> {
    Set(profile.equipment.compactMap { Equipment(rawValue: $0) })
  }

  private func gymName(_ profile: UserProfile) -> String {
    if let matched = GymPreset.matching(currentEquipment(profile)) {
      return matched.name
    }
    return String(localized: "Custom", bundle: L10n.bundle)
  }

  private func injuryBinding(_ profile: UserProfile, _ flag: InjuryFlag) -> Binding<Bool> {
    Binding(
      get: { profile.injuryFlags.contains(flag.rawValue) },
      set: { on in
        var set = Set(profile.injuryFlags)
        if on { set.insert(flag.rawValue) } else { set.remove(flag.rawValue) }
        profile.injuryFlags = set.sorted()
      })
  }

  private var csvURL: URL {
    let rows =
      sessions
      .sorted { $0.date < $1.date }
      .flatMap { session in
        session.sets
          .sorted { $0.setIndex < $1.setIndex }
          .map {
            "\(session.date.description),\($0.exerciseID),\($0.setIndex),\($0.weightKg),\($0.reps),\($0.rpe)"
          }
      }
    let csv = (["date,exercise,set,weight_kg,reps,rpe"] + rows).joined(separator: "\n")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("forge-export.csv")
    try? csv.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  /// Offline speech-to-text. The model is a deliberate, Wi-Fi-only download: the toggle
  /// cannot switch the engine before the files are actually on disk, so voice control never
  /// breaks because a setting promised something the phone does not have.
  @ViewBuilder private var offlineVoiceRows: some View {
    Toggle(String(localized: "Offline voice (Whisper)", bundle: L10n.bundle), isOn: $voiceOffline)
      .tint(Theme.metricSets)
      .forgeBody().padding(.vertical, 6)
      .disabled(!whisperModels.state.isReady)
      .accessibilityIdentifier("settings.voice.offline")
    Text(
      String(
        localized: "Recognises commands on this phone, with no network at all. Needs a one-time model download.",
        bundle: L10n.bundle)
    )
    .forgeCaption()
    .padding(.vertical, 6)
    Picker(String(localized: "Model", bundle: L10n.bundle), selection: whisperVariantBinding) {
      ForEach(WhisperVariant.allCases) { variant in
        Text("\(variant.name) · \(variant.approximateMB) MB").tag(variant)
      }
    }
    .pickerStyle(.segmented)
    .disabled(whisperModels.state.isBusy)
    switch whisperModels.state {
    case .absent:
      Button(String(localized: "Download voice model", bundle: L10n.bundle)) {
        whisperModels.download()
      }
      .buttonStyle(PillSecondaryButtonStyle())
      .accessibilityIdentifier("settings.voice.download")
    case .downloading(let fraction):
      VStack(alignment: .leading, spacing: 6) {
        SwiftUI.ProgressView(value: fraction)
          .tint(Theme.metricTime)
        Button(String(localized: "Cancel", bundle: L10n.bundle)) { whisperModels.cancel() }
          .buttonStyle(PillSecondaryButtonStyle())
      }
      .padding(.vertical, 6)
    case .ready:
      HStack {
        Text(String(localized: "Model ready", bundle: L10n.bundle))
          .forgeCaption()
          .foregroundStyle(Theme.metricSets)
        Spacer()
        Button(String(localized: "Delete", bundle: L10n.bundle), role: .destructive) {
          whisperModels.delete()
        }
        .forgeCaption()
      }
      .padding(.vertical, 6)
      .accessibilityIdentifier("settings.voice.ready")
    case .failed(let message):
      Text(message)
        .forgeCaption()
        .foregroundStyle(Theme.negative)
        .padding(.vertical, 6)
    }
  }

  private var whisperVariantBinding: Binding<WhisperVariant> {
    Binding(get: { whisperModels.variant }, set: { whisperModels.variant = $0 })
  }

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
