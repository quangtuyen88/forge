import ForgeCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Preview-first import of a structured program file, explicit activation, and
/// redacted sharing.
///
/// The order of operations is the contract:
///
///   1. `ProgramImportDecoder` reads the file. A payload that carries user history,
///      coach memory or identity keys is refused outright and nothing is written.
///   2. `ProgramImportPreview` shows warnings and the version diff. Still nothing has
///      been written.
///   3. Only an explicit tap — routed through `ProgramActivationPolicy` — writes the
///      imported program and the active version. A version is never activated because
///      a file declared it.
///   4. Sharing goes through `ProgramRedactor`, which emits a `ShareableProgram` with
///      days and nothing else, guarded by a sensitive-key check before it is offered.
///   5. An unlisted link is published only after that redaction, a second sensitive-key
///      scan of the wire payload, an explicit rights confirmation and a visible expiry.
///      The returned token metadata is stored; the session bearer stays in a header and
///      never enters the payload.
///   6. Opening someone else's code fetches the allowlisted program and turns it into a
///      private, unactivated draft that reuses this same preview. A code never activates.
struct ProgramImportAnalysisView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Query private var profiles: [UserProfile]

  @State private var jsonText = ""
  @State private var candidate: ImportedProgram?
  @State private var preview: ProgramImportPreview?
  @State private var failure: ImportFailure?
  @State private var status: StatusMessage?
  @State private var selectedVersion: Int?
  @State private var shareNote = ""
  @State private var redacted: SharedProgram?
  @State private var rightsConfirmed = false
  @State private var expiryDays = ProgramShareClient.Limits.defaultExpiryDays
  @State private var isPublishing = false
  @State private var published: ProgramShareClient.PublishedShare?
  @State private var publishError: String?
  @State private var sharedCodeInput = ""
  @State private var isFetching = false
  @State private var fetchError: String?
  @State private var isRevoking: String?
  @State private var isImportingFile = false
  @State private var now = Date.now
  @State private var confirmingActivation = false
  @State private var revokingToken: ShareTokenMetadata?
  @State private var removingToken: ShareTokenMetadata?
  /// A training day of the previewed candidate the user chose to adapt. Opening a
  /// link or analysing a file never sets this — only an explicit per-day tap does.
  @State private var adaptDay: CandidateDay?
  private enum Field: Hashable { case programText, shareCode, shareNote }
  @FocusState private var focusedField: Field?

  private static let expiryChoices = [7, 30, 90]
  private static let columns = [
    GridItem(.flexible(), spacing: 8),
    GridItem(.flexible(), spacing: 8),
  ]

  private struct ImportFailure: Equatable {
    let headline: String
    let detail: String
  }

  private struct StatusMessage: Equatable {
    let text: String
    let isError: Bool
  }

  private struct SharedProgram: Equatable {
    /// The redacted program itself, so the review screen and the wire payload are the
    /// same object rather than two renderings that can drift apart.
    let program: ShareableProgram
    let json: String
    let title: String
    /// Should always be empty: sharing is refused when it is not.
    let sensitiveKeys: [String]
  }

  /// Wraps a candidate day because two days of an imported program may share a name.
  private struct CandidateDay: Identifiable {
    let offset: Int
    let day: ProgramDay
    var id: Int { offset }
  }

  private var profile: UserProfile? { profiles.first }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        inputCard
        openCodeCard
        if let failure { errorCard(failure) }
        if let preview {
          previewCard(preview)
          activationCard(preview)
        }
        onDeviceCard
        shareCard
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle(Text(String(localized: "Program import", bundle: L10n.bundle)))
    .scrollDismissesKeyboard(.interactively)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button(String(localized: "Done", bundle: L10n.bundle)) { dismiss() }
      }
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button(String(localized: "Done", bundle: L10n.bundle)) { focusedField = nil }
      }
    }
    .fileImporter(
      isPresented: $isImportingFile,
      allowedContentTypes: [.json, .plainText],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        guard let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
          // Bounded read: pull at most one byte past the decoder's limit, so an oversized
          // file is rejected with a specific error before any UTF-8 conversion happens.
          let handle = try FileHandle(forReadingFrom: url)
          defer { try? handle.close() }
          let data = try handle.read(upToCount: ProgramImportDecoder.maximumBytes + 1) ?? Data()
          if data.count > ProgramImportDecoder.maximumBytes {
            failure = ImportFailure(
              headline: String(localized: "That file is too large", bundle: L10n.bundle),
              detail: String(
                localized: "Program files are capped at \(ProgramImportDecoder.maximumBytes / 1024) KB. Nothing was changed.",
                bundle: L10n.bundle))
            return
          }
          guard let text = String(data: data, encoding: .utf8) else {
            failure = ImportFailure(
              headline: String(localized: "That file is not readable text", bundle: L10n.bundle),
              detail: String(localized: "It is not valid UTF-8. Nothing was changed.", bundle: L10n.bundle))
            return
          }
          jsonText = text
          analyze()
        } catch {
          failure = ImportFailure(
            headline: String(localized: "Could not read that file", bundle: L10n.bundle),
            detail: String(
              localized: "\(error.localizedDescription) Nothing was changed.", bundle: L10n.bundle))
        }
      case .failure(let error):
        failure = ImportFailure(
          headline: String(localized: "Could not open the file", bundle: L10n.bundle),
          detail: error.localizedDescription)
      }
    }
    .onAppear { now = .now }
    .onChange(of: failure) { _, newValue in
      if let newValue {
        AccessibilityNotification.Announcement("\(newValue.headline). \(newValue.detail)").post()
      }
    }
    .onChange(of: status) { _, newValue in
      if let newValue { AccessibilityNotification.Announcement(newValue.text).post() }
    }
    .onChange(of: fetchError) { _, newValue in
      if let newValue { AccessibilityNotification.Announcement(newValue).post() }
    }
    .onChange(of: publishError) { _, newValue in
      if let newValue { AccessibilityNotification.Announcement(newValue).post() }
    }
    .confirmationDialog(
      String(
        localized: "Activate version \(selectedVersion.map { "\($0)" } ?? "—")?",
        bundle: L10n.bundle),
      isPresented: $confirmingActivation,
      titleVisibility: .visible
    ) {
      Button(
        String(
          localized: "Activate version \(selectedVersion.map { "\($0)" } ?? "—")",
          bundle: L10n.bundle),
        role: .destructive
      ) { activateSelectedVersion() }
      Button(String(localized: "Cancel", bundle: L10n.bundle), role: .cancel) {}
    } message: {
      Text(
        String(
          localized:
            "This replaces your active program. Recommendations recorded against the older version are marked stale.",
          bundle: L10n.bundle))
    }
    .confirmationDialog(
      String(localized: "Revoke this link?", bundle: L10n.bundle),
      isPresented: Binding(
        get: { revokingToken != nil },
        set: { if !$0 { revokingToken = nil } }),
      titleVisibility: .visible
    ) {
      Button(String(localized: "Revoke link", bundle: L10n.bundle), role: .destructive) {
        if let token = revokingToken { Task { await revoke(token) } }
        revokingToken = nil
      }
      Button(String(localized: "Cancel", bundle: L10n.bundle), role: .cancel) {}
    } message: {
      Text(
        String(
          localized:
            "Anyone holding the link or import code loses access. A copy already saved by someone else cannot be recalled.",
          bundle: L10n.bundle))
    }
    .confirmationDialog(
      String(localized: "Remove this link?", bundle: L10n.bundle),
      isPresented: Binding(
        get: { removingToken != nil },
        set: { if !$0 { removingToken = nil } }),
      titleVisibility: .visible
    ) {
      Button(String(localized: "Remove link", bundle: L10n.bundle), role: .destructive) {
        if let token = removingToken { remove(token) }
        removingToken = nil
      }
      Button(String(localized: "Cancel", bundle: L10n.bundle), role: .cancel) {}
    } message: {
      Text(
        String(
          localized: "The link disappears from this list. It is already expired or revoked, so it stops working either way.",
          bundle: L10n.bundle))
    }
    .sheet(item: $adaptDay) { item in
      RoutineAdaptationSheet(
        source: .importedDay(item.day, programTitle: candidate?.title ?? ""))
    }
  }

  // MARK: - Input

  private var inputCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Program file", bundle: L10n.bundle).forgeTitle()
        .accessibilityAddTraits(.isHeader)
      Text(
        "A structured program file: format version, versions and training days. Paste it below, or open one from Files.",
        bundle: L10n.bundle
      )
      .forgeCaption()
      TextEditor(text: $jsonText)
        .font(.forge(12, .regular, relativeTo: .footnote))
        .scrollContentBackground(.hidden)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .frame(minHeight: 120)
        .innerSurface(padding: 10)
        .overlay(alignment: .topLeading) {
          if jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("{\n  \"formatVersion\": 1,\n  \"title\": \"…\"\n}")
              .font(.forge(12, .regular, relativeTo: .footnote))
              .foregroundStyle(Theme.textTertiary)
              .padding(16)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .accessibilityLabel(Text(String(localized: "Program file contents", bundle: L10n.bundle)))
        .focused($focusedField, equals: .programText)
      HStack(spacing: 10) {
        Button {
          isImportingFile = true
        } label: {
          Text(String(localized: "Choose file…", bundle: L10n.bundle))
        }
        .buttonStyle(PillSecondaryButtonStyle())
        Button { analyze() } label: {
          Text(String(localized: "Analyse", bundle: L10n.bundle))
        }
        .buttonStyle(PillButtonStyle())
        .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      Text("Analysing only reads the file. Nothing is saved, and nothing is activated, until you tap it below.", bundle: L10n.bundle)
        .forgeCaption()
    }
    .card()
  }

  private func errorCard(_ failure: ImportFailure) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .scaledSystemFont(16, weight: .semibold)
          .foregroundStyle(Theme.negative)
          .frame(width: 26)
          .accessibilityHidden(true)
        Text(failure.headline).forgeSection()
      }
      Text(failure.detail).forgeBody()
      Text("Nothing was saved and nothing was activated.", bundle: L10n.bundle).forgeCaption()
    }
    .card()
    .accessibilityElement(children: .combine)
  }

  // MARK: - Preview

  private func previewCard(_ preview: ProgramImportPreview) -> some View {
    let diff = preview.diff
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 3) {
          Text(
            preview.title.isEmpty
              ? String(localized: "Untitled program", bundle: L10n.bundle) : preview.title)
            .forgeSection()
          Text("Format v\(preview.formatVersion) · \(preview.versionsLabel)", bundle: L10n.bundle)
            .forgeCaption()
        }
        Spacer(minLength: 8)
        if preview.hasBlockingErrors {
          Text("Blocked", bundle: L10n.bundle)
            .forge(11, .bold, tracking: 0)
            .foregroundStyle(Theme.negative)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.negative.opacity(0.14)))
        }
      }
      LazyVGrid(columns: Self.columns, spacing: 8) {
        metricTile(String(localized: "Training days", bundle: L10n.bundle), "\(preview.dayCount)")
        metricTile(String(localized: "Exercises", bundle: L10n.bundle), "\(preview.exerciseCount)")
        metricTile(String(localized: "Errors", bundle: L10n.bundle), "\(preview.errorCount)")
        metricTile(String(localized: "Warnings", bundle: L10n.bundle), "\(preview.warningCount)")
      }
      Text("Nothing has been saved yet. This is a preview.", bundle: L10n.bundle)
        .forgeCaption()

      if !preview.warnings.isEmpty {
        Divider().overlay(Theme.ring)
        Text("Check before you continue", bundle: L10n.bundle).forgeBodyStrong()
        ForEach(preview.warnings) { warning in
          HStack(alignment: .top, spacing: 10) {
            Image(
              systemName: warning.severity == .error
                ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill"
            )
            .scaledSystemFont(13)
            .foregroundStyle(warning.severity == .error ? Theme.negative : Theme.metricTime)
            .frame(width: 22)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
              Text(warning.message).forgeBody()
              if let context = warning.context {
                Text(contextLine(context)).forgeCaption()
              }
            }
          }
        }
      }

      Divider().overlay(Theme.ring)
      Text("What changes", bundle: L10n.bundle).forgeBodyStrong()
      Text(diffHeadline(diff)).forgeLabel()
      if diff.isEmpty {
        Text("Identical days, exercises and set counts.", bundle: L10n.bundle).forgeCaption()
      }
      if !diff.addedExerciseIDs.isEmpty {
        diffRow("plus", String(localized: "Added", bundle: L10n.bundle), diff.addedExerciseIDs.map(displayName), Theme.metricSets)
      }
      if !diff.removedExerciseIDs.isEmpty {
        diffRow("minus", String(localized: "Removed", bundle: L10n.bundle), diff.removedExerciseIDs.map(displayName), Theme.negative)
      }
      if !diff.setCountChanges.isEmpty {
        setChangeRow(diff.setCountChanges)
      }
      if !diff.changedDays.isEmpty {
        diffRow("calendar", String(localized: "Days changed", bundle: L10n.bundle), diff.changedDays, Theme.metricTime)
      }
    }
    .card()
  }

  private func metricTile(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(value)
        .font(.forge(20, .bold).monospacedDigit())
        .foregroundStyle(Theme.text)
      Text(label).forgeCaption()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .innerSurface(padding: 12)
    .accessibilityElement(children: .combine)
  }

  private func diffRow(_ symbol: String, _ label: String, _ values: [String], _ tint: Color) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol)
        .foregroundStyle(tint)
        .frame(width: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("\(label) · \(values.count)", bundle: L10n.bundle).forgeBodyStrong()
        Text(values.prefix(8).joined(separator: ", ")).forgeCaption()
        if values.count > 8 {
          Text("+\(values.count - 8) more", bundle: L10n.bundle).forgeCaption()
        }
      }
    }
  }

  private func setChangeRow(_ changes: [ProgramSetChange]) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "number")
        .foregroundStyle(Theme.metricLoad)
        .frame(width: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("Set changes · \(changes.count)", bundle: L10n.bundle).forgeBodyStrong()
        ForEach(changes.prefix(6), id: \.self) { change in
          Text("\(change.day) · \(displayName(change.exerciseID)): \(change.fromSets) → \(change.toSets) sets", bundle: L10n.bundle)
            .forgeCaption()
            .monospacedDigit()
        }
        if changes.count > 6 {
          Text("+\(changes.count - 6) more", bundle: L10n.bundle).forgeCaption()
        }
      }
    }
  }

  private func diffHeadline(_ diff: ProgramVersionDiff) -> String {
    guard let toVersion = diff.toVersion else {
      return String(
        localized: "This file has no versions, so there is nothing to compare.",
        bundle: L10n.bundle)
    }
    let from =
      diff.fromVersion.map { String(localized: "imported v\($0)", bundle: L10n.bundle) }
      ?? String(localized: "no previously imported version", bundle: L10n.bundle)
    if diff.isEmpty {
      return String(
        localized: "Against \(from): no exercise or set change (v\(toVersion)).", bundle: L10n.bundle)
    }
    return "\(from) → v\(toVersion)"
  }

  private func contextLine(_ context: ImportWarningContext) -> String {
    var parts: [String] = []
    if let day = context.day {
      parts.append(String(localized: "Day: \(day)", bundle: L10n.bundle))
    }
    if let exerciseID = context.exerciseID {
      parts.append(String(localized: "Exercise: \(displayName(exerciseID))", bundle: L10n.bundle))
    }
    if let index = context.index {
      parts.append(String(localized: "Version \(index)", bundle: L10n.bundle))
    }
    return parts.joined(separator: " · ")
  }

  // MARK: - Activation

  private func activationCard(_ preview: ProgramImportPreview) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Activation", bundle: L10n.bundle).forgeSection()
        .accessibilityAddTraits(.isHeader)
      Text(
        "Importing never changes your plan. An imported version becomes your program only when you activate it here.",
        bundle: L10n.bundle
      )
      .forgeCaption()

      if let candidate {
        if candidate.versions.count > 1 {
          Picker("Version", selection: $selectedVersion) {
            ForEach(candidate.versions, id: \.number) { version in
              Text("Version \(version.number) · \(version.days.count) days", bundle: L10n.bundle)
                .tag(Optional(version.number))
            }
          }
          .pickerStyle(.menu)
          .tint(Theme.accentText)
          .accessibilityLabel(Text(String(localized: "Version to activate", bundle: L10n.bundle)))
        } else if let only = candidate.activeVersion {
          Text("Version \(only.number) · \(only.days.count) days", bundle: L10n.bundle)
            .forgeBodyStrong()
        }

        if let selectedVersion, let version = candidate.versions.first(where: { $0.number == selectedVersion }) {
          VStack(alignment: .leading, spacing: 4) {
            // Positional: an imported program may name two days the same.
      ForEach(Array(version.days.enumerated()), id: \.offset) { offset, day in
              HStack(alignment: .center) {
                Text("\(day.name) · \(day.exercises.count) exercises · \(day.totalSets) sets", bundle: L10n.bundle)
                  .forgeCaption()
                  .monospacedDigit()
                Spacer(minLength: 8)
                Button {
                  adaptDay = CandidateDay(offset: offset, day: day)
                } label: {
                  Text(String(localized: "Adapt to me", bundle: L10n.bundle))
                    .font(.forge(13, .semibold))
                    .foregroundStyle(
                      preview.hasBlockingErrors || day.exercises.isEmpty
                        ? Theme.textTertiary : Theme.accentText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .disabled(preview.hasBlockingErrors || day.exercises.isEmpty)
                .accessibilityIdentifier("routineadapt.day.\(offset)")
                .accessibilityLabel(Text(String(localized: "Adapt \(day.name) to me", bundle: L10n.bundle)))
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .innerSurface(padding: 12)
          Text("Adapt to me previews one day against your equipment, injuries and time. It never saves or activates the program.", bundle: L10n.bundle)
            .forgeCaption()
        }
      }

      if preview.hasBlockingErrors {
        Text("Fix \(preview.errorCount) error\(L10n.pluralSuffix(preview.errorCount)) first — this file cannot be activated as it stands.", bundle: L10n.bundle)
          .forgeLabel()
      } else if let selectedVersion, profile?.activeProgramVersion?.number == selectedVersion {
        Text("Version \(selectedVersion) is already active.", bundle: L10n.bundle).forgeCaption()
      }

      VStack(spacing: 10) {
        Button {
          // Replacing an active program is destructive; a first activation replaces nothing.
          if profile?.activeProgramVersion == nil {
            activateSelectedVersion()
          } else {
            confirmingActivation = true
          }
        } label: {
          Text("Activate version \(selectedVersion.map { "\($0)" } ?? "—")", bundle: L10n.bundle)
        }
        .buttonStyle(PillButtonStyle())
        .disabled(!preview.isActivatable || selectedVersion == nil)
        Button { saveWithoutActivating() } label: {
          Text(String(localized: "Save to library without activating", bundle: L10n.bundle))
        }
        .buttonStyle(PillSecondaryButtonStyle())
        .disabled(!preview.isActivatable)
      }

      if let status { statusRow(status) }
    }
    .card()
  }

  private func statusRow(_ status: StatusMessage) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: status.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        .foregroundStyle(status.isError ? Theme.negative : Theme.positive)
        .frame(width: 22)
        .accessibilityHidden(true)
      Text(status.text).forgeLabel()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .innerSurface(padding: 12)
    .accessibilityElement(children: .combine)
  }

  // MARK: - On device

  private var onDeviceCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("On this device", bundle: L10n.bundle).forgeSection()
        .accessibilityAddTraits(.isHeader)
      if let imported = profile?.importedProgram {
        plainRow(
          "shippingbox", String(localized: "In your library", bundle: L10n.bundle),
          String(
            localized:
              "\(imported.title.isEmpty ? String(localized: "Untitled program", bundle: L10n.bundle) : imported.title) · \(imported.versions.count) version\(L10n.pluralSuffix(imported.versions.count)) · imported \(dateText(imported.importedAt))",
            bundle: L10n.bundle))
        if let active = profile?.activeProgramVersion {
          plainRow(
            "checkmark.seal", String(localized: "Active version", bundle: L10n.bundle),
            String(
              localized:
                "Version \(active.number) · \(active.days.count) day\(L10n.pluralSuffix(active.days.count)) · \(active.exerciseCount) exercise\(L10n.pluralSuffix(active.exerciseCount)) · \(dateText(active.createdAt))",
              bundle: L10n.bundle))
          Text("Recommendations recorded against an older version are marked stale.", bundle: L10n.bundle)
            .forgeCaption()
        } else {
          Text("Nothing here is active. Your plan is still the one built from your profile.", bundle: L10n.bundle)
            .forgeBody()
        }
      } else {
        Text("No program file has been imported on this device. Your plan is the one built from your profile.", bundle: L10n.bundle)
          .forgeBody()
      }
    }
    .card()
  }

  private func plainRow(_ symbol: String, _ label: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol)
        .foregroundStyle(Theme.accent)
        .frame(width: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(label).forgeOverline()
        Text(value).forgeBody()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  // MARK: - Opening a shared code

  private var openCodeCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Open a shared program", bundle: L10n.bundle).forgeSection()
        .accessibilityAddTraits(.isHeader)
      Text(
        "Paste an import code or a Regulift link. It opens as a private draft you can review here — nothing becomes active until you activate it below.",
        bundle: L10n.bundle
      )
      .forgeCaption()
      TextField(String(localized: "Import code or link", bundle: L10n.bundle), text: $sharedCodeInput)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(.URL)
        .submitLabel(.go)
        .onSubmit { Task { await fetchSharedCode() } }
        .font(.forge(14, .regular))
        .foregroundStyle(Theme.text)
        .innerSurface(padding: 12)
        .accessibilityLabel(Text(String(localized: "Import code or Regulift link", bundle: L10n.bundle)))
        .focused($focusedField, equals: .shareCode)
      Button {
        Task { await fetchSharedCode() }
      } label: {
        if isFetching {
          HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Opening…", bundle: L10n.bundle)
          }
        } else {
          Text(String(localized: "Open draft", bundle: L10n.bundle))
        }
      }
      .buttonStyle(PillSecondaryButtonStyle())
      .disabled(isFetching || ProgramShareClient.importCode(from: sharedCodeInput) == nil)

      if let fetchError {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Theme.negative)
            .frame(width: 24)
            .accessibilityHidden(true)
          Text(fetchError).forgeLabel()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
      }
    }
    .card()
  }

  // MARK: - Sharing

  private var shareCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Share a redacted copy", bundle: L10n.bundle).forgeSection()
        .accessibilityAddTraits(.isHeader)
      Text(
        "The copy contains training days only. Workout history, coach memory, your notes and your profile identity are never included.",
        bundle: L10n.bundle
      )
      .forgeCaption()

      if candidate != nil {
        Text("Sharing version \(selectedVersion.map { "\($0)" } ?? "—")", bundle: L10n.bundle)
          .forgeLabel()

        if let redacted {
          reviewedContent(redacted)
          publishControls(redacted)
          offlineExport(redacted)
        } else {
          TextField(
            String(localized: "Optional note for the recipient", bundle: L10n.bundle),
            text: $shareNote, axis: .vertical)
            .lineLimit(1...3)
            .font(.forge(15, .regular))
            .foregroundStyle(Theme.text)
            .innerSurface(padding: 12)
            .accessibilityLabel(Text(String(localized: "Optional note for the recipient", bundle: L10n.bundle)))
            .focused($focusedField, equals: .shareNote)

          Button { createShare() } label: {
            Text(String(localized: "Review redacted copy", bundle: L10n.bundle))
          }
          .buttonStyle(PillButtonStyle())
          Text("Reviewing builds the copy in memory. Nothing is published and nothing is sent.", bundle: L10n.bundle)
            .forgeCaption()
        }
      } else {
        Text("Analyse a program first — sharing is built from the version you previewed.", bundle: L10n.bundle)
          .forgeBody()
      }

      if let status { statusRow(status) }
      tokenSection
    }
    .card()
  }

  /// The exact content that would be published, itemised. The payload is built from this
  /// same `ShareableProgram`, so this is not a summary of something else.
  private func reviewedContent(_ redacted: SharedProgram) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Divider().overlay(Theme.ring)
      HStack(spacing: 10) {
        Image(systemName: "doc.text.magnifyingglass")
          .foregroundStyle(Theme.accent)
          .frame(width: 24)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text("What will be published", bundle: L10n.bundle).forgeBodyStrong()
          Text(
            "\(redacted.title.isEmpty ? String(localized: "Untitled program", bundle: L10n.bundle) : redacted.title) · \(redacted.program.days.count) day\(L10n.pluralSuffix(redacted.program.days.count))",
            bundle: L10n.bundle
          )
          .forgeCaption()
        }
      }
      // Positional: an imported program may name two days the same.
      ForEach(Array(redacted.program.days.enumerated()), id: \.offset) { _, day in
        VStack(alignment: .leading, spacing: 3) {
          Text("\(day.name) · \(day.exercises.count) exercises", bundle: L10n.bundle).forgeLabel()
          // Positional by design: a day can list the same exercise twice, and this preview is
          // read-only.
          ForEach(Array(day.exercises.enumerated()), id: \.offset) { _, entry in
            HStack(spacing: 6) {
              Text(ProgramShareClient.displayName(for: entry))
                .font(.forge(12, .regular, relativeTo: .caption))
                .foregroundStyle(Theme.textSecondary)
              Spacer(minLength: 6)
              Text(exerciseDetail(entry)).forgeCaption().monospacedDigit()
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .innerSurface(padding: 10)
      }
      Text("Days, exercise names, set counts and rep ranges are the entire payload — nothing else is sent.", bundle: L10n.bundle)
        .forgeCaption()
    }
    .accessibilityElement(children: .contain)
  }

  private func exerciseDetail(_ entry: ProgramExerciseEntry) -> String {
    guard let reps = ProgramShareClient.repsLabel(entry) else {
      return String(localized: "\(entry.sets) sets", bundle: L10n.bundle)
    }
    return String(localized: "\(entry.sets) × \(reps)", bundle: L10n.bundle)
  }

  private func publishControls(_ redacted: SharedProgram) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Divider().overlay(Theme.ring)

      Picker("Link expires", selection: $expiryDays) {
        ForEach(Self.expiryChoices, id: \.self) { days in
          Text("\(days) days", bundle: L10n.bundle).tag(days)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityLabel(Text(String(localized: "How long the unlisted link stays active", bundle: L10n.bundle)))

      unlistedWarning

      Toggle(isOn: $rightsConfirmed) {
        Text("I have the rights to share this program.", bundle: L10n.bundle).forgeBody()
      }
      .tint(Theme.accent)
      .accessibilityHint(Text(String(localized: "Required before an unlisted link can be published", bundle: L10n.bundle)))

      if let published {
        publishedResult(published, title: redacted.title)
      } else {
        Button {
          Task { await publishShare(redacted) }
        } label: {
          if isPublishing {
            HStack(spacing: 8) {
              ProgressView().controlSize(.small)
              Text("Publishing…", bundle: L10n.bundle)
            }
          } else {
            Text(String(localized: "Publish unlisted link", bundle: L10n.bundle))
          }
        }
        .buttonStyle(PillButtonStyle())
        .disabled(
          isPublishing || !rightsConfirmed || !redacted.sensitiveKeys.isEmpty
            || !ProgramShareClient.isConfigured)

        if !ProgramShareClient.isConfigured {
          Text("Publishing is unavailable on this build. The redacted file below still works offline.", bundle: L10n.bundle)
            .forgeCaption()
        }
      }

      if let publishError {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(Theme.negative)
            .frame(width: 24)
            .accessibilityHidden(true)
          Text(publishError).forgeLabel()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
      }
    }
  }

  private var unlistedWarning: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "eye.slash.fill")
        .foregroundStyle(Theme.metricTime)
        .frame(width: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text("Anyone with the link can open it", bundle: L10n.bundle).forgeBodyStrong()
        Text(
          "The link is unlisted — it is not searchable and never appears in a feed — but it is a bearer link: whoever holds the code can read and import the program. Revoke it any time to stop future access.",
          bundle: L10n.bundle
        )
        .forgeCaption()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .innerSurface(padding: 12)
    .accessibilityElement(children: .combine)
  }

  private func publishedResult(_ published: ProgramShareClient.PublishedShare, title: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "link.badge.plus")
          .foregroundStyle(Theme.positive)
          .frame(width: 24)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text("Unlisted link is live", bundle: L10n.bundle).forgeBodyStrong()
          Text("Expires \(dateText(published.expiresAt)). Revoke it below to stop future access.", bundle: L10n.bundle)
            .forgeCaption()
        }
      }
      Text(published.url.absoluteString)
        .font(.forge(12, .regular, relativeTo: .caption))
        .foregroundStyle(Theme.textSecondary)
        .textSelection(.enabled)
      Text("Import code  \(published.code)", bundle: L10n.bundle)
        .monospacedDigit()
        .font(.forge(12, .medium, relativeTo: .caption))
        .foregroundStyle(Theme.text)
        .textSelection(.enabled)
      ShareLink(
        item: published.url,
        preview: SharePreview(
          String(
            localized: "Training program — \(title.isEmpty ? String(localized: "Program", bundle: L10n.bundle) : title)",
            bundle: L10n.bundle))
      ) {
        Label(String(localized: "Share the link", bundle: L10n.bundle), systemImage: "square.and.arrow.up")
      }
      .buttonStyle(PillButtonStyle())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .innerSurface(padding: 12)
  }

  /// The on-device export. It never depends on the server, so a failed publish can never
  /// take it away.
  private func offlineExport(_ redacted: SharedProgram) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Divider().overlay(Theme.ring)
      Text("Or save the file", bundle: L10n.bundle).forgeBodyStrong()
      if redacted.sensitiveKeys.isEmpty {
        ShareLink(
          item: redacted.json,
          preview: SharePreview(
            String(localized: "Training program — \(redacted.title)", bundle: L10n.bundle))
        ) {
          Label(String(localized: "Share program file", bundle: L10n.bundle), systemImage: "square.and.arrow.up")
        }
        .buttonStyle(PillSecondaryButtonStyle())
        Text("The same redacted copy as a file, sent with the system share sheet. Works offline.", bundle: L10n.bundle)
          .forgeCaption()
      } else {
        Text("Sharing is blocked: the copy still contained \(redacted.sensitiveKeys.joined(separator: ", ")).", bundle: L10n.bundle)
          .forgeLabel()
      }
    }
  }

  @ViewBuilder private var tokenSection: some View {
    if let profile, !profile.shareTokens.isEmpty {
      Divider().overlay(Theme.ring)
      Text("Unlisted links", bundle: L10n.bundle).forgeBodyStrong()
      Text(
        "Each link expires on its own date and can be revoked. Revoking stops future access; a copy already saved by someone else cannot be recalled.",
        bundle: L10n.bundle
      )
      .forgeCaption()
      ForEach(profile.shareTokens.sorted { $0.createdAt > $1.createdAt }) { token in
        tokenRow(token)
      }
    }
  }

  private func tokenRow(_ token: ShareTokenMetadata) -> some View {
    let tokenStatus = token.status(at: now)
    return HStack(alignment: .top, spacing: 10) {
      Image(systemName: tokenStatus == .active ? "link" : (tokenStatus == .revoked ? "nosign" : "hourglass"))
        .foregroundStyle(tokenStatus == .active ? Theme.positive : Theme.textTertiary)
        .frame(width: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(tokenStatusText(tokenStatus)).forgeBodyStrong()
        Text("Unlisted link · expires \(dateText(token.expiresAt))", bundle: L10n.bundle)
          .forgeCaption()
          .monospacedDigit()
        if let revokedAt = token.revokedAt {
          Text("Revoked \(dateText(revokedAt))", bundle: L10n.bundle).forgeCaption()
        }
      }
      Spacer(minLength: 8)
      if tokenStatus == .active {
        Button {
          revokingToken = token
        } label: {
          Text(String(localized: "Revoke", bundle: L10n.bundle))
            .font(.forge(13, .semibold))
            .foregroundStyle(Theme.negative)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(isRevoking == token.id)
        .accessibilityLabel(
          Text(
            String(
              localized: "Revoke unlisted link, expires \(dateText(token.expiresAt))",
              bundle: L10n.bundle)))
      } else {
        Button {
          removingToken = token
        } label: {
          Text(String(localized: "Remove", bundle: L10n.bundle))
            .font(.forge(13, .medium))
            .foregroundStyle(Theme.textSecondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(Text(String(localized: "Remove expired link record", bundle: L10n.bundle)))
      }
    }
    .innerSurface(padding: 12)
  }

  private func tokenStatusText(_ status: ShareTokenStatus) -> String {
    switch status {
    case .active: return String(localized: "Active", bundle: L10n.bundle)
    case .expired: return String(localized: "Expired", bundle: L10n.bundle)
    case .revoked: return String(localized: "Revoked", bundle: L10n.bundle)
    }
  }

  // MARK: - Actions

  /// Step 1 and 2 of the contract. Performs zero writes.
  private func analyze() {
    failure = nil
    status = nil
    preview = nil
    candidate = nil

    let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      failure = ImportFailure(
        headline: String(localized: "Nothing to analyse", bundle: L10n.bundle),
        detail: String(localized: "Paste a program file or choose one from Files. Nothing was changed.", bundle: L10n.bundle))
      return
    }
    guard let data = trimmed.data(using: .utf8) else {
      failure = ImportFailure(
        headline: String(localized: "Unreadable text", bundle: L10n.bundle),
        detail: String(localized: "The pasted text could not be read. Nothing was changed.", bundle: L10n.bundle))
      return
    }

    do {
      let program = try ProgramImportDecoder.decode(data)
      candidate = program
      selectedVersion = program.activeVersion?.number ?? program.versions.last?.number
      redacted = nil
      published = nil
      publishError = nil
      rightsConfirmed = false
      preview = ProgramImportPreview.make(
        imported: program, previous: profile?.importedProgram?.activeVersion)
    } catch let error as ProgramImportError {
      switch error {
      case .malformedJSON:
        failure = ImportFailure(
          headline: String(localized: "That is not a valid program file", bundle: L10n.bundle),
          detail: String(
            localized: "The JSON could not be read as a program. Check that it is complete and unmodified.",
            bundle: L10n.bundle))
      case .containsSensitiveContent(let keys):
        failure = ImportFailure(
          headline: String(localized: "This file carries personal data", bundle: L10n.bundle),
          detail: String(
            localized: "It contains \(keys.joined(separator: ", ")) — history, coach notes or identity that Regulift never imports.",
            bundle: L10n.bundle))
      }
    } catch {
      failure = ImportFailure(
        headline: String(localized: "Import failed", bundle: L10n.bundle),
        detail: String(
          localized: "\(error.localizedDescription) Nothing was changed.", bundle: L10n.bundle))
    }
  }

  /// Step 3. The only path that makes a version live, and it always names the version.
  private func activateSelectedVersion() {
    guard let candidate, let selectedVersion, let profile else { return }
    let previousVersion = profile.activeProgramVersion

    switch ProgramActivationPolicy.activate(candidate, version: selectedVersion, at: .now) {
    case .activated(let activated):
      profile.importedProgram = activated
      if let version = activated.activeVersion {
        profile.activeProgramVersion = version
        var ledger = profile.recommendationLedger
        ledger.advanceProgramVersion(to: UserProfile.programVersionID(for: version))
        profile.recommendationLedger = ledger
      }
      try? modelContext.save()
      self.candidate = activated
      self.preview = ProgramImportPreview.make(imported: activated, previous: previousVersion)
      self.redacted = nil
      self.published = nil
      status = StatusMessage(
        text: String(
          localized: "Version \(selectedVersion) is now active. Recommendations recorded against an older version are marked stale.",
          bundle: L10n.bundle),
        isError: false)

    case .rejected(let blockers):
      status = StatusMessage(
        text: String(
          localized: "Activation blocked: \(blockers.map(\.message).joined(separator: " "))",
          bundle: L10n.bundle),
        isError: true)

    case .versionNotFound(let number):
      status = StatusMessage(
        text: String(
          localized: "Version \(number) is not in this file, so nothing was activated.",
          bundle: L10n.bundle),
        isError: true)
    }
  }

  /// Saves the file to the library with no active version — activation stays a separate,
  /// explicit step.
  private func saveWithoutActivating() {
    guard let candidate, let profile else { return }
    let stored = ImportedProgram(
      id: candidate.id,
      formatVersion: candidate.formatVersion,
      title: candidate.title,
      source: candidate.source,
      importedAt: .now,
      versions: candidate.versions,
      activeVersionNumber: nil)
    profile.importedProgram = stored
    try? modelContext.save()
    self.candidate = stored
    status = StatusMessage(
      text: String(
        localized: "Saved to your library. Nothing is active until you activate a version.",
        bundle: L10n.bundle),
      isError: false)
  }

  /// Step 4, the first boundary: redaction, then a refusal to offer anything that still
  /// carries sensitive keys. No network call happens here — publishing is separate.
  private func createShare() {
    guard let candidate else { return }
    let note = shareNote.trimmingCharacters(in: .whitespacesAndNewlines)
    let payload = ProgramRedactor.redact(
      candidate,
      note: note.isEmpty ? nil : note,
      version: selectedVersion,
      at: .now)
    let json = payload.json()

    let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [])) ?? [:]
    let offending = ProgramImportDecoder.sensitiveKeys(in: object)
    redacted = SharedProgram(program: payload, json: json, title: payload.title, sensitiveKeys: offending)
    published = nil
    publishError = nil
    rightsConfirmed = false
    status = StatusMessage(
      text:
        offending.isEmpty
        ? String(
          localized: "Redacted copy ready. Review it, then publish an unlisted link or save the file.",
          bundle: L10n.bundle)
        : String(
          localized: "Sharing was blocked: the copy still contained \(offending.joined(separator: ", ")).",
          bundle: L10n.bundle),
      isError: !offending.isEmpty)
  }

  /// Step 5. The only path that publishes. It refuses to send without a rights
  /// confirmation, mirrors the server's bounds locally, and keeps the draft on failure.
  private func publishShare(_ redacted: SharedProgram) async {
    guard let profile else { return }
    publishError = nil
    guard rightsConfirmed else {
      publishError = "Confirm you have the rights to share this program."
      return
    }
    guard redacted.sensitiveKeys.isEmpty else {
      publishError = "Sharing is blocked: the copy still contained \(redacted.sensitiveKeys.joined(separator: ", "))."
      return
    }

    isPublishing = true
    defer { isPublishing = false }
    do {
      let published = try await ProgramShareClient.publish(
        redacted.program, expiresInDays: expiryDays, rightsConfirmed: true)
      self.published = published
      let token = ShareTokenMetadata(
        id: published.code,
        programID: candidate?.id ?? "",
        scope: .readOnly,
        createdAt: .now,
        expiresAt: published.expiresAt)
      profile.shareTokens = profile.shareTokens + [token]
      try? modelContext.save()
      status = StatusMessage(
        text: String(
          localized: "Published. The unlisted link expires \(dateText(published.expiresAt)) and can be revoked below.",
          bundle: L10n.bundle),
        isError: false)
    } catch {
      let message = (error as? LocalizedError)?.errorDescription
        ?? String(localized: "Publishing failed. Your copy is unchanged.", bundle: L10n.bundle)
      publishError = message
      status = StatusMessage(text: message, isError: true)
    }
  }

  /// Step 6. Opening someone else's code. The fetched program becomes a private draft and
  /// reuses `ProgramImportPreview`; nothing is written and no version is activated.
  private func fetchSharedCode() async {
    fetchError = nil
    isFetching = true
    defer { isFetching = false }
    do {
      let share = try await ProgramShareClient.fetch(codeOrLink: sharedCodeInput)
      let draft = ProgramShareClient.draft(from: share)
      candidate = draft
      selectedVersion = draft.activeVersion?.number
      redacted = nil
      published = nil
      publishError = nil
      rightsConfirmed = false
      failure = nil
      preview = ProgramImportPreview.make(imported: draft, previous: profile?.importedProgram?.activeVersion)
      status = StatusMessage(
        text: String(
          localized: "Opened “\(draft.title)” as a private draft. Nothing is active until you activate a version.",
          bundle: L10n.bundle),
        isError: false)
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? String(localized: "Could not open that code.", bundle: L10n.bundle)
      fetchError = message
      status = StatusMessage(text: message, isError: true)
    }
  }

  /// Owner revoke. It talks to the server and only marks the token revoked when the server
  /// confirms — a failed revoke leaves the link recorded as active, because it is.
  private func revoke(_ token: ShareTokenMetadata) async {
    guard let profile else { return }
    isRevoking = token.id
    do {
      try await ProgramShareClient.revoke(codeOrLink: token.id)
      profile.shareTokens = profile.shareTokens.map { $0.id == token.id ? $0.revoking(at: .now) : $0 }
      if published?.code == token.id { published = nil }
      try? modelContext.save()
      status = StatusMessage(
        text: String(
          localized: "Link revoked. A copy already saved by someone else cannot be recalled.",
          bundle: L10n.bundle),
        isError: false)
    } catch {
      status = StatusMessage(
        text: (error as? LocalizedError)?.errorDescription ?? String(localized: "Could not revoke that link.", bundle: L10n.bundle),
        isError: true)
    }
    isRevoking = nil
  }

  private func remove(_ token: ShareTokenMetadata) {
    guard let profile else { return }
    profile.shareTokens = profile.shareTokens.filter { $0.id != token.id }
    if published?.code == token.id { published = nil }
    try? modelContext.save()
  }

  // MARK: - Text helpers

  private func displayName(_ exerciseID: String) -> String {
    ExerciseDB.find(exerciseID)?.localizedName ?? exerciseID
  }

  private func dateText(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(L10n.locale))
  }
}

private extension ProgramImportPreview {
  /// "2 versions" — spelled once so the preview card stays readable.
  var versionsLabel: String {
    String(localized: "\(versionCount) version\(L10n.pluralSuffix(versionCount))", bundle: L10n.bundle)
  }
}
