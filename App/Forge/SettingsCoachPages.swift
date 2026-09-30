import ForgeCore
import SwiftData
import SwiftUI

/// Coach: the two coaches side by side, what the coach sees, and its confirmed memory.
struct CoachPage: View {
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @AppStorage("coachConsent") private var coachConsent = false
  @AppStorage("coachOnDevice") private var coachOnDevice = true
  @AppStorage("coachServerURL") private var coachServerURL =
    "https://forge-coach.quangtuyen88.workers.dev"
  @Query(sort: \CoachNote.date, order: .reverse) private var notes: [CoachNote]
  @Query private var profiles: [UserProfile]
  @Environment(\.modelContext) private var modelContext
  @State private var confirmForgetNotes = false
  @State private var secretInput = ""
  @State private var secretPresent = Keychain.get("forge-app-secret") != nil
  @State private var serverStatus: CoachAPI.ServerStatus = .checking
  @State private var probeKey = UUID()

  private var coach: Coach { Coach.from(coachID) }
  private var activeNotes: [CoachNote] { notes.filter { $0.isActive } }

  var body: some View {
    SettingsFieldPage(title: String(localized: "Coach", bundle: L10n.bundle)) {
      HStack(alignment: .top, spacing: 14) {
        ForEach(Coach.allCases) { c in
          CoachChoiceCard(coach: c, selected: coach == c) {
            withAnimation(.snappy) { coachID = c.rawValue }
            profiles.first?.updatedAt = .now
            try? modelContext.save()
          }
          .accessibilityIdentifier("settings.coach.\(c.rawValue)")
        }
      }
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, 6)
      Text(String(localized: "Switching keeps your plan, loads and history.", bundle: L10n.bundle))
        .forge(15).foregroundStyle(Theme.textSecondary)
    } content: {
      SettingsSectionLabel(String(localized: "What \(coach.name) sees", bundle: L10n.bundle))
      SettingsToggleRow(
        title: String(localized: "Share training data", bundle: L10n.bundle),
        subtitle: String(localized: "Sets, check-ins and your plan", bundle: L10n.bundle),
        isOn: $coachConsent)
      SettingsHairline(inset: false)
      if OnDeviceCoach.isAvailable {
        SettingsToggleRow(
          title: String(localized: "Answer on this iPhone", bundle: L10n.bundle),
          subtitle: String(localized: "Plan changes still use the coach service", bundle: L10n.bundle),
          isOn: $coachOnDevice)
      } else {
        Text(
          String(
            localized: "Apple Intelligence is not available on this device; the coach service answers instead.",
            bundle: L10n.bundle)
        )
        .forge(15).foregroundStyle(Theme.textSecondary)
        .padding(.vertical, 8)
      }

      SettingsSectionLabel(String(localized: "Memory", bundle: L10n.bundle))
      if activeNotes.isEmpty {
        Text(
          String(
            localized: "Nothing yet. Confirmed facts about equipment, injuries, schedule, goals and preferences appear here.",
            bundle: L10n.bundle)
        )
        .forge(15).foregroundStyle(Theme.textSecondary)
        .padding(.vertical, 8)
      } else {
        ForEach(activeNotes) { note in
          if activeNotes.first !== note { SettingsHairline(inset: false) }
          SettingsRow(
            title: note.text,
            subtitle: "\(note.memoryKind.name) · \(note.source)",
            accessory: .none
          ) {
            forgetButton(note)
          }
        }
        SettingsHairline(inset: false)
        Button {
          confirmForgetNotes = true
        } label: {
          SettingsRow(
            title: String(localized: "Forget all", bundle: L10n.bundle),
            titleColor: Theme.negative,
            accessory: .none)
        }
        .buttonStyle(RowPressStyle())
        .confirmationDialog(
          String(localized: "Forget all coach notes?", bundle: L10n.bundle),
          isPresented: $confirmForgetNotes,
          titleVisibility: .visible
        ) {
          Button(String(localized: "Forget all", bundle: L10n.bundle), role: .destructive) {
            for note in notes { modelContext.delete(note) }
          }
        }
      }

      if AppSecret.bundled != nil {
        Spacer().frame(height: 16)
        SettingsRow(
          title: String(localized: "\(coach.name)’s connection", bundle: L10n.bundle),
          accessory: .none
        ) {
          statusText
        }
      } else {
        SettingsSectionLabel(String(localized: "Developer", bundle: L10n.bundle))
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
            .foregroundStyle(Theme.accentText)
            .forgeBodyStrong()
          }
        }
      }
    }
  }

  private var statusText: some View {
    Text(statusLabel)
      .forge(15)
      .foregroundStyle(serverStatus == .available ? Theme.positiveText : Theme.textSecondary)
      .accessibilityIdentifier("settings.coachServerStatus")
      .task(id: probeKey) { serverStatus = await CoachAPI.probeServer() }
  }

  private var statusLabel: String {
    switch serverStatus {
    case .available: return String(localized: "Online", bundle: L10n.bundle)
    case .unavailable: return String(localized: "Offline", bundle: L10n.bundle)
    default: return serverStatus.label
    }
  }

  private func forgetButton(_ note: CoachNote) -> some View {
    Button {
      modelContext.delete(note)
    } label: {
      Image(systemName: "xmark.circle.fill")
        .font(.system(size: 22))
        .foregroundStyle(Theme.textSecondary.opacity(0.7))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(ControlPressStyle())
    .accessibilityLabel(String(localized: "Forget this note", bundle: L10n.bundle))
  }
}

/// Voice: how the microphone listens, what the coach reads aloud, and where audio may go.
struct VoicePage: View {
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @AppStorage("dictationLanguage") private var dictationLanguage = "auto"
  @AppStorage("dictationEngine") private var dictationEngine = "cloud"
  @AppStorage("voiceActivationRequired") private var voiceActivationRequired = false
  @AppStorage("voiceFastLogging") private var voiceFastLogging = false
  @AppStorage("voiceAllowServerRecognition") private var voiceAllowServerRecognition = false
  @AppStorage("voiceSmartFallback") private var voiceSmartFallback = false
  @AppStorage("coachAudioMode") private var coachAudioMode = CoachAudioMode.off.rawValue
  @AppStorage(WhisperModelStore.enabledKey) private var voiceOffline = false
  @State private var whisperModels = WhisperModelStore.shared
  @Query private var profiles: [UserProfile]
  @ScaledMetric(relativeTo: .title) private var quoteHang: CGFloat = 11.8

  private var coach: Coach { Coach.from(coachID) }
  private var usesLb: Bool { profiles.first?.usesLb ?? false }
  private var listeningName: String {
    SettingsFormat.languageName(dictationLanguage == "auto" ? L10n.languageCode : dictationLanguage)
  }

  var body: some View {
    SettingsFieldPage(title: String(localized: "Voice", bundle: L10n.bundle)) {
      VStack(alignment: .leading, spacing: 0) {
        ZStack(alignment: .topTrailing) {
          VStack(alignment: .leading, spacing: 8) {
            Text(
              usesLb
                ? String(localized: "“225 pounds for 8”", bundle: L10n.bundle)
                : String(localized: "“100 kilos for 8”", bundle: L10n.bundle)
            )
            .font(.forge(28, .bold, relativeTo: .title))
            .tracking(-0.5)
            .foregroundStyle(Theme.text)
            .padding(.leading, -quoteHang)
            .accessibilityAddTraits(.isHeader)
            Text(String(localized: "Heard on this iPhone and logged as your next set.", bundle: L10n.bundle))
              .forge(15).foregroundStyle(Theme.textSecondary)
          }
          .padding(.trailing, 76)
          .frame(maxWidth: .infinity, alignment: .leading)
          Image("art-voice")
            .resizable()
            .scaledToFit()
            .frame(width: 64, height: 64)
            .offset(y: -2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(.top, 2)
        HStack(spacing: 8) {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 18))
            .foregroundStyle(Theme.positiveText)
            .accessibilityHidden(true)
          Text(usesLb ? "225 lb × 8" : "100 kg × 8")
            .forge(17, .bold)
            .foregroundStyle(Theme.text)
            .monospacedDigit()
          Text(String(localized: "logged", bundle: L10n.bundle))
            .forge(17, .medium)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.fieldChip))
        .accessibilityElement(children: .combine)
        .padding(.top, 4)
      }
    } content: {
      SettingsSectionLabel(String(localized: "Listening", bundle: L10n.bundle))
      Menu {
        Picker(selection: $dictationLanguage) {
          Text(String(localized: "Follow app language", bundle: L10n.bundle)).tag("auto")
          Text(verbatim: "English").tag("en")
          Text(verbatim: "日本語").tag("ja")
          Text(verbatim: "한국어").tag("ko")
          Text(verbatim: "Tiếng Việt").tag("vi")
        } label: { EmptyView() }
        .pickerStyle(.inline)
      } label: {
        SettingsRow(
          title: String(localized: "Speech language", bundle: L10n.bundle),
          value: listeningName,
          accessory: .menu)
      }
      .accessibilityIdentifier("settings.voice.language")
      SettingsHairline(inset: false)
      SettingsToggleRow(
        title: String(localized: "Fast logging", bundle: L10n.bundle),
        subtitle: String(localized: "Logs at once, with Undo", bundle: L10n.bundle),
        isOn: $voiceFastLogging)
      SettingsHairline(inset: false)
      SettingsToggleRow(
        title: String(localized: "Say “Coach” first", bundle: L10n.bundle),
        subtitle: String(localized: "Helps in a noisy gym", bundle: L10n.bundle),
        isOn: $voiceActivationRequired)

      SettingsSectionLabel(String(localized: "\(coach.name)’s voice", bundle: L10n.bundle))
      Picker(String(localized: "Voice", bundle: L10n.bundle), selection: $coachAudioMode) {
        ForEach(CoachAudioMode.allCases) { mode in
          Text(mode.name).tag(mode.rawValue)
        }
      }
      .pickerStyle(.segmented)
      .padding(.top, 8)
      Text(
        String(
          localized: "When on, \(coach.name) reads out only what is on screen. The audio is made on this iPhone.",
          bundle: L10n.bundle)
      )
      .forge(15).foregroundStyle(Theme.textSecondary)
      .padding(.top, 12)

      SettingsSectionLabel(String(localized: "Privacy", bundle: L10n.bundle))
      SettingsToggleRow(
        title: String(localized: "Cloud dictation", bundle: L10n.bundle),
        subtitle: String(localized: "Most accurate. The clip goes to Regulift and is not stored.", bundle: L10n.bundle),
        isOn: Binding(
          get: { dictationEngine == "cloud" },
          set: { dictationEngine = $0 ? "cloud" : "device" }))
      SettingsHairline(inset: false)
      SettingsToggleRow(
        title: String(localized: "Apple speech service", bundle: L10n.bundle),
        subtitle: String(localized: "Audio goes to Apple, never to Regulift", bundle: L10n.bundle),
        isOn: $voiceAllowServerRecognition)
      SettingsHairline(inset: false)
      SettingsToggleRow(
        title: String(localized: "Unusual phrasing", bundle: L10n.bundle),
        subtitle: String(localized: "Unmatched words go to our server", bundle: L10n.bundle),
        isOn: $voiceSmartFallback)
      SettingsHairline(inset: false)
      offlineVoiceRows
      SettingsHairline(inset: false)
      Menu {
        Picker(selection: whisperVariantBinding) {
          ForEach(WhisperVariant.allCases) { variant in
            Text(verbatim: "\(variant.name) · \(variant.approximateMB) MB").tag(variant)
          }
        } label: { EmptyView() }
        .pickerStyle(.inline)
      } label: {
        SettingsRow(
          title: String(localized: "Model size", bundle: L10n.bundle),
          value: whisperModels.variant.name,
          accessory: .menu)
      }
      .disabled(whisperModels.state.isBusy)
      .accessibilityIdentifier("settings.voice.model")
    }
  }

  /// Offline speech-to-text, by model state. The toggle cannot switch the engine before the
  /// model files are actually on disk, so voice never breaks over a promised download.
  @ViewBuilder private var offlineVoiceRows: some View {
    switch whisperModels.state {
    case .absent:
      offlineGetRow
    case .downloading(let fraction):
      SettingsRow(
        title: String(localized: "Offline voice", bundle: L10n.bundle),
        subtitle: String(localized: "Downloading \(Int(fraction * 100)) %", bundle: L10n.bundle),
        accessory: .none
      ) {
        offlineButton(String(localized: "Cancel", bundle: L10n.bundle)) { whisperModels.cancel() }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("settings.voice.offline")
      ProgressView(value: fraction).tint(Theme.accent)
    case .ready:
      SettingsToggleRow(
        title: String(localized: "Offline voice", bundle: L10n.bundle),
        subtitle: String(localized: "Works with no network", bundle: L10n.bundle),
        isOn: $voiceOffline)
      .accessibilityIdentifier("settings.voice.offline")
      SettingsHairline(inset: false)
      SettingsRow(
        title: String(localized: "Model ready", bundle: L10n.bundle),
        subtitle: "\(whisperModels.variant.name) · \(whisperModels.variant.approximateMB) MB",
        accessory: .none
      ) {
        Button(String(localized: "Delete", bundle: L10n.bundle), role: .destructive) {
          whisperModels.delete()
        }
        .forge(15, .semibold)
        .foregroundStyle(Theme.negative)
        .frame(minHeight: 44)
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("settings.voice.ready")
    case .failed(let message):
      offlineGetRow
      Text(message).forge(15).foregroundStyle(Theme.negative)
    }
  }

  private var offlineGetRow: some View {
    SettingsRow(
      title: String(localized: "Offline voice", bundle: L10n.bundle),
      subtitle: String(
        localized: "Works with no network · \(whisperModels.variant.approximateMB) MB", bundle: L10n.bundle),
      accessory: .none
    ) {
      offlineButton(String(localized: "Get", bundle: L10n.bundle)) { whisperModels.download() }
        .accessibilityIdentifier("settings.voice.download")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("settings.voice.offline")
  }

  private func offlineButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
      .forge(15, .semibold)
      .foregroundStyle(Theme.text)
      .padding(.horizontal, 14)
      .frame(height: 32)
      .background(Capsule().fill(Theme.innerSurface))
      .frame(minHeight: 44)
      .buttonStyle(ControlPressStyle())
  }

  private var whisperVariantBinding: Binding<WhisperVariant> {
    Binding(get: { whisperModels.variant }, set: { whisperModels.variant = $0 })
  }
}
