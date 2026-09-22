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
    .navigationTitle("Program import")
    .scrollDismissesKeyboard(.interactively)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
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
          let data = try Data(contentsOf: url)
          jsonText = String(data: data, encoding: .utf8) ?? ""
          analyze()
        } catch {
          failure = ImportFailure(
            headline: "Could not read that file",
            detail: "\(error.localizedDescription) Nothing was changed.")
        }
      case .failure(let error):
        failure = ImportFailure(headline: "Could not open the file", detail: error.localizedDescription)
      }
    }
    .onAppear { now = .now }
  }

  // MARK: - Input

  private var inputCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Program file").forgeTitle()
      Text(
        "A structured program file: format version, versions and training days. Paste it below, or open one from Files."
      )
      .forgeCaption()
      TextEditor(text: $jsonText)
        .font(.forge(12, .regular, relativeTo: .footnote))
        .scrollContentBackground(.hidden)
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
        .accessibilityLabel("Program file contents")
      HStack(spacing: 10) {
        Button("Choose file…") { isImportingFile = true }
          .buttonStyle(PillSecondaryButtonStyle())
        Button("Analyse") { analyze() }
          .buttonStyle(PillButtonStyle())
          .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      Text("Analysing only reads the file. Nothing is saved, and nothing is activated, until you tap it below.")
        .forgeCaption()
    }
    .card()
  }

  private func errorCard(_ failure: ImportFailure) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Theme.negative)
          .frame(width: 26)
          .accessibilityHidden(true)
        Text(failure.headline).forgeSection()
      }
      Text(failure.detail).forgeBody()
      Text("Nothing was saved and nothing was activated.").forgeCaption()
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
          Text(preview.title.isEmpty ? "Untitled program" : preview.title).forgeSection()
          Text("Format v\(preview.formatVersion) · \(preview.versionsLabel)")
            .forgeCaption()
        }
        Spacer(minLength: 8)
        if preview.hasBlockingErrors {
          Text("BLOCKED")
            .forge(9, .bold, tracking: 0.7)
            .foregroundStyle(Theme.negative)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.negative.opacity(0.14)))
        }
      }
      LazyVGrid(columns: Self.columns, spacing: 8) {
        metricTile("Training days", "\(preview.dayCount)")
        metricTile("Exercises", "\(preview.exerciseCount)")
        metricTile("Errors", "\(preview.errorCount)")
        metricTile("Warnings", "\(preview.warningCount)")
      }
      Text("Nothing has been saved yet. This is a preview.")
        .forgeCaption()

      if !preview.warnings.isEmpty {
        Divider().overlay(Theme.ring)
        Text("Check before you continue").forgeBodyStrong()
        ForEach(preview.warnings) { warning in
          HStack(alignment: .top, spacing: 10) {
            Image(
              systemName: warning.severity == .error
                ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill"
            )
            .font(.system(size: 13))
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
      Text("What changes").forgeBodyStrong()
      Text(diffHeadline(diff)).forgeLabel()
      if diff.isEmpty {
        Text("Identical days, exercises and set counts.").forgeCaption()
      }
      if !diff.addedExerciseIDs.isEmpty {
        diffRow("plus", "Added", diff.addedExerciseIDs.map(displayName), Theme.metricSets)
      }
      if !diff.removedExerciseIDs.isEmpty {
        diffRow("minus", "Removed", diff.removedExerciseIDs.map(displayName), Theme.negative)
      }
      if !diff.setCountChanges.isEmpty {
        setChangeRow(diff.setCountChanges)
      }
      if !diff.changedDays.isEmpty {
        diffRow("calendar", "Days changed", diff.changedDays, Theme.metricTime)
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
        Text("\(label) · \(values.count)").forgeBodyStrong()
        Text(values.prefix(8).joined(separator: ", ")).forgeCaption()
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
        Text("Set changes · \(changes.count)").forgeBodyStrong()
        ForEach(changes.prefix(6), id: \.self) { change in
          Text("\(change.day) · \(displayName(change.exerciseID)): \(change.fromSets) → \(change.toSets) sets")
            .forgeCaption()
            .monospacedDigit()
        }
      }
    }
  }

  private func diffHeadline(_ diff: ProgramVersionDiff) -> String {
    guard let toVersion = diff.toVersion else {
      return "This file has no versions, so there is nothing to compare."
    }
    let from = diff.fromVersion.map { "imported v\($0)" } ?? "no previously imported version"
    if diff.isEmpty {
      return "Against \(from): no exercise or set change (v\(toVersion))."
    }
    return "\(from) → v\(toVersion)"
  }

  private func contextLine(_ context: ImportWarningContext) -> String {
    var parts: [String] = []
    if let day = context.day { parts.append("Day: \(day)") }
    if let exerciseID = context.exerciseID { parts.append("Exercise: \(displayName(exerciseID))") }
    if let index = context.index { parts.append("Version \(index)") }
    return parts.joined(separator: " · ")
  }

  // MARK: - Activation

  private func activationCard(_ preview: ProgramImportPreview) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Activation").forgeSection()
      Text(
        "Importing never changes your plan. An imported version becomes your program only when you activate it here."
      )
      .forgeCaption()

      if let candidate {
        if candidate.versions.count > 1 {
          Picker("Version", selection: $selectedVersion) {
            ForEach(candidate.versions, id: \.number) { version in
              Text("Version \(version.number) · \(version.days.count) days").tag(Optional(version.number))
            }
          }
          .pickerStyle(.menu)
          .tint(Theme.accent)
          .accessibilityLabel("Version to activate")
        } else if let only = candidate.activeVersion {
          Text("Version \(only.number) · \(only.days.count) days").forgeBodyStrong()
        }

        if let selectedVersion, let version = candidate.versions.first(where: { $0.number == selectedVersion }) {
          VStack(alignment: .leading, spacing: 4) {
            // Positional: an imported program may name two days the same.
      ForEach(Array(version.days.enumerated()), id: \.offset) { _, day in
              Text("\(day.name) · \(day.exercises.count) exercises · \(day.totalSets) sets")
                .forgeCaption()
                .monospacedDigit()
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .innerSurface(padding: 12)
        }
      }

      if preview.hasBlockingErrors {
        Text("Fix \(preview.errorCount) error\(preview.errorCount == 1 ? "" : "s") first — this file cannot be activated as it stands.")
          .forgeLabel()
      } else if let selectedVersion, profile?.activeProgramVersion?.number == selectedVersion {
        Text("Version \(selectedVersion) is already active.").forgeCaption()
      }

      VStack(spacing: 10) {
        Button("Activate version \(selectedVersion.map { "\($0)" } ?? "—")") { activateSelectedVersion() }
          .buttonStyle(PillButtonStyle())
          .disabled(!preview.isActivatable || selectedVersion == nil)
        Button("Save to library without activating") { saveWithoutActivating() }
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
      Text("On this device").forgeSection()
      if let imported = profile?.importedProgram {
        plainRow(
          "shippingbox", "In your library",
          "\(imported.title.isEmpty ? "Untitled program" : imported.title) · \(imported.versions.count) version\(imported.versions.count == 1 ? "" : "s") · imported \(dateText(imported.importedAt))")
        if let active = profile?.activeProgramVersion {
          plainRow(
            "checkmark.seal", "Active version",
            "Version \(active.number) · \(active.days.count) days · \(active.exerciseCount) exercises · \(dateText(active.createdAt))")
          Text("Recommendations recorded against an older version are marked stale.")
            .forgeCaption()
        } else {
          Text("Nothing here is active. Your plan is still the one built from your profile.")
            .forgeBody()
        }
      } else {
        Text("No program file has been imported on this device. Your plan is the one built from your profile.")
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
      Text("Open a shared program").forgeSection()
      Text(
        "Paste an import code or a Regulift link. It opens as a private draft you can review here — nothing becomes active until you activate it below."
      )
      .forgeCaption()
      TextField("Import code or link", text: $sharedCodeInput)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.forge(14, .regular))
        .foregroundStyle(Theme.text)
        .innerSurface(padding: 12)
        .accessibilityLabel("Import code or Regulift link")
      Button {
        Task { await fetchSharedCode() }
      } label: {
        if isFetching {
          HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Opening…")
          }
        } else {
          Text("Open draft")
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
      Text("Share a redacted copy").forgeSection()
      Text(
        "The copy contains training days only. Workout history, coach memory, your notes and your profile identity are never included."
      )
      .forgeCaption()

      if candidate != nil {
        Text("Sharing version \(selectedVersion.map { "\($0)" } ?? "—")")
          .forgeLabel()

        if let redacted {
          reviewedContent(redacted)
          publishControls(redacted)
          offlineExport(redacted)
        } else {
          TextField("Optional note for the recipient", text: $shareNote, axis: .vertical)
            .lineLimit(1...3)
            .font(.forge(15, .regular))
            .foregroundStyle(Theme.text)
            .innerSurface(padding: 12)
            .accessibilityLabel("Optional note for the recipient")

          Button("Review redacted copy") { createShare() }
            .buttonStyle(PillButtonStyle())
          Text("Reviewing builds the copy in memory. Nothing is published and nothing is sent.")
            .forgeCaption()
        }
      } else {
        Text("Analyse a program first — sharing is built from the version you previewed.")
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
          Text("What will be published").forgeBodyStrong()
          Text(
            "\(redacted.title.isEmpty ? "Untitled program" : redacted.title) · \(redacted.program.days.count) day\(redacted.program.days.count == 1 ? "" : "s")"
          )
          .forgeCaption()
        }
      }
      // Positional: an imported program may name two days the same.
      ForEach(Array(redacted.program.days.enumerated()), id: \.offset) { _, day in
        VStack(alignment: .leading, spacing: 3) {
          Text("\(day.name) · \(day.exercises.count) exercises").forgeLabel()
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
      Text("Days, exercise names, set counts and rep ranges are the entire payload — nothing else is sent.")
        .forgeCaption()
    }
    .accessibilityElement(children: .contain)
  }

  private func exerciseDetail(_ entry: ProgramExerciseEntry) -> String {
    guard let reps = ProgramShareClient.repsLabel(entry) else { return "\(entry.sets) sets" }
    return "\(entry.sets) × \(reps)"
  }

  private func publishControls(_ redacted: SharedProgram) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Divider().overlay(Theme.ring)

      Picker("Link expires", selection: $expiryDays) {
        ForEach(Self.expiryChoices, id: \.self) { days in
          Text("\(days) days").tag(days)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityLabel("How long the unlisted link stays active")

      unlistedWarning

      Toggle(isOn: $rightsConfirmed) {
        Text("I have the rights to share this program.").forgeBody()
      }
      .tint(Theme.accent)
      .accessibilityHint("Required before an unlisted link can be published")

      if let published {
        publishedResult(published, title: redacted.title)
      } else {
        Button {
          Task { await publishShare(redacted) }
        } label: {
          if isPublishing {
            HStack(spacing: 8) {
              ProgressView().controlSize(.small)
              Text("Publishing…")
            }
          } else {
            Text("Publish unlisted link")
          }
        }
        .buttonStyle(PillButtonStyle())
        .disabled(
          isPublishing || !rightsConfirmed || !redacted.sensitiveKeys.isEmpty
            || !ProgramShareClient.isConfigured)

        if !ProgramShareClient.isConfigured {
          Text("Publishing is unavailable on this build. The redacted file below still works offline.")
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
        Text("Anyone with the link can open it").forgeBodyStrong()
        Text(
          "The link is unlisted — it is not searchable and never appears in a feed — but it is a bearer link: whoever holds the code can read and import the program. Revoke it any time to stop future access."
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
          Text("Unlisted link is live").forgeBodyStrong()
          Text("Expires \(dateText(published.expiresAt)). Revoke it below to stop future access.")
            .forgeCaption()
        }
      }
      Text(published.url.absoluteString)
        .font(.forge(12, .regular, relativeTo: .caption))
        .foregroundStyle(Theme.textSecondary)
        .textSelection(.enabled)
      Text("Import code  \(published.code)")
        .monospacedDigit()
        .font(.forge(12, .medium, relativeTo: .caption))
        .foregroundStyle(Theme.text)
        .textSelection(.enabled)
      ShareLink(
        item: published.url,
        preview: SharePreview("Training program — \(title.isEmpty ? "Program" : title)")
      ) {
        Label("Share the link", systemImage: "square.and.arrow.up")
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
      Text("Or save the file").forgeBodyStrong()
      if redacted.sensitiveKeys.isEmpty {
        ShareLink(
          item: redacted.json,
          preview: SharePreview("Training program — \(redacted.title)")
        ) {
          Label("Share program file", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(PillSecondaryButtonStyle())
        Text("The same redacted copy as a file, sent with the system share sheet. Works offline.")
          .forgeCaption()
      } else {
        Text("Sharing is blocked: the copy still contained \(redacted.sensitiveKeys.joined(separator: ", ")).")
          .forgeLabel()
      }
    }
  }

  @ViewBuilder private var tokenSection: some View {
    if let profile, !profile.shareTokens.isEmpty {
      Divider().overlay(Theme.ring)
      Text("Unlisted links").forgeBodyStrong()
      Text(
        "Each link expires on its own date and can be revoked. Revoking stops future access; a copy already saved by someone else cannot be recalled."
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
        Text("Unlisted link · expires \(dateText(token.expiresAt))")
          .forgeCaption()
          .monospacedDigit()
        if let revokedAt = token.revokedAt {
          Text("Revoked \(dateText(revokedAt))").forgeCaption()
        }
      }
      Spacer(minLength: 8)
      if tokenStatus == .active {
        Button("Revoke") { Task { await revoke(token) } }
          .buttonStyle(RowPressStyle())
          .font(.forge(13, .semibold))
          .foregroundStyle(Theme.negative)
          .frame(minWidth: 44, minHeight: 44)
          .disabled(isRevoking == token.id)
          .accessibilityLabel("Revoke unlisted link, expires \(dateText(token.expiresAt))")
      } else {
        Button("Remove") { remove(token) }
          .buttonStyle(RowPressStyle())
          .font(.forge(13, .medium))
          .foregroundStyle(Theme.textSecondary)
          .frame(minWidth: 44, minHeight: 44)
          .accessibilityLabel("Remove expired link record")
      }
    }
    .innerSurface(padding: 12)
  }

  private func tokenStatusText(_ status: ShareTokenStatus) -> String {
    switch status {
    case .active: return "Active"
    case .expired: return "Expired"
    case .revoked: return "Revoked"
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
        headline: "Nothing to analyse",
        detail: "Paste a program file or choose one from Files. Nothing was changed.")
      return
    }
    guard let data = trimmed.data(using: .utf8) else {
      failure = ImportFailure(
        headline: "Unreadable text",
        detail: "The pasted text could not be read. Nothing was changed.")
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
          headline: "That is not a valid program file",
          detail: "The JSON could not be read as a program. Check that it is complete and unmodified.")
      case .containsSensitiveContent(let keys):
        failure = ImportFailure(
          headline: "This file carries personal data",
          detail: "It contains \(keys.joined(separator: ", ")) — history, coach notes or identity that Regulift never imports.")
      }
    } catch {
      failure = ImportFailure(
        headline: "Import failed",
        detail: "\(error.localizedDescription) Nothing was changed.")
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
        text: "Version \(selectedVersion) is now active. Recommendations recorded against an older version are marked stale.",
        isError: false)

    case .rejected(let blockers):
      status = StatusMessage(
        text: "Activation blocked: " + blockers.map(\.message).joined(separator: " "),
        isError: true)

    case .versionNotFound(let number):
      status = StatusMessage(
        text: "Version \(number) is not in this file, so nothing was activated.",
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
      text: "Saved to your library. Nothing is active until you activate a version.",
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
      text: offending.isEmpty
        ? "Redacted copy ready. Review it, then publish an unlisted link or save the file."
        : "Sharing was blocked: the copy still contained \(offending.joined(separator: ", ")).",
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
        text: "Published. The unlisted link expires \(dateText(published.expiresAt)) and can be revoked below.",
        isError: false)
    } catch {
      let message = (error as? LocalizedError)?.errorDescription
        ?? "Publishing failed. Your copy is unchanged."
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
        text: "Opened “\(draft.title)” as a private draft. Nothing is active until you activate a version.",
        isError: false)
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? "Could not open that code."
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
        text: "Link revoked. A copy already saved by someone else cannot be recalled.",
        isError: false)
    } catch {
      status = StatusMessage(
        text: (error as? LocalizedError)?.errorDescription ?? "Could not revoke that link.",
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
    date.formatted(date: .abbreviated, time: .omitted)
  }
}

private extension ProgramImportPreview {
  /// "2 versions" — spelled once so the preview card stays readable.
  var versionsLabel: String {
    "\(versionCount) version\(versionCount == 1 ? "" : "s")"
  }
}
