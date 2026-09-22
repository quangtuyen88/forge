import ForgeCore
import SwiftData
import SwiftUI

// MARK: - Transient acknowledgement

/// The acknowledgement shown over the timeline after an action that changes what is displayed
/// (hiding, restoring, saving or deleting a note). Deliberately transient: it never claims the
/// underlying record changed, because hiding and restoring never touch a source record.
struct JourneyToast: View {
  let text: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "checkmark.circle.fill")
      Text(text)
        .forge(13, .semibold)
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(Theme.onAccent)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Capsule().fill(Theme.accent))
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isStaticText)
  }
}

// MARK: - Filter

/// The one filter sheet: All, Workouts, Program changes, Body, Notes. Multiple types OR
/// together, and an empty selection resolves to All — which is why "All" is a row that clears
/// the selection rather than a fifth category.
struct JourneyFilterSheet: View {
  let initial: JourneyFilter
  let onApply: (JourneyFilter) -> Void
  let onAddNote: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var draft: JourneyFilter = .all
  @State private var seeded = false

  private var summary: String {
    if draft.isAll {
      return String(localized: "Showing every type.", bundle: L10n.bundle)
    }
    if draft.selectionCount == JourneyCategory.allCases.count {
      return String(
        localized: "Every type is selected, which resolves to All.", bundle: L10n.bundle)
    }
    return String(
      localized: "Showing \(draft.selectionCount) of 4 types; an entry matches any of them.",
      bundle: L10n.bundle)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          Text("Entry types").forgeSection()

          selectionRow(
            symbol: "square.grid.2x2",
            tint: Theme.accent,
            title: String(localized: "All", bundle: L10n.bundle),
            subtitle: String(localized: "Workouts, program changes, body and notes", bundle: L10n.bundle),
            selected: draft.isAll,
            identifier: "journey.filter.all"
          ) {
            draft = draft.cleared()
          }

          ForEach(JourneyCategory.allCases, id: \.rawValue) { category in
            selectionRow(
              symbol: symbol(for: category),
              tint: tint(for: category),
              title: category.name,
              subtitle: subtitle(for: category),
              selected: !draft.isAll && draft.categories.contains(category),
              identifier: "journey.filter.category.\(category.rawValue)"
            ) {
              draft = draft.toggling(category)
            }
          }

          Text(summary)
            .forgeCaption()
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("journey.filter.summary")

          Button {
            dismiss()
            onAddNote()
          } label: {
            Label("Add note", systemImage: "square.and.pencil")
          }
          .buttonStyle(PillButtonStyle(minHeight: 44))
          .accessibilityIdentifier("journey.filter.addNote")
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 12)
      }
      .background(Theme.page)
      .navigationTitle("Filter")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            onApply(draft)
            dismiss()
          }
          .accessibilityIdentifier("journey.filter.apply")
        }
      }
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
      .accessibilityIdentifier("journey.filterSheet")
      .task {
        if !seeded {
          draft = initial
          seeded = true
        }
      }
    }
  }

  private func selectionRow(
    symbol: String,
    tint: Color,
    title: String,
    subtitle: String,
    selected: Bool,
    identifier: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: symbol)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(tint)
          .frame(width: 32, height: 32)
          .background(Circle().fill(tint.opacity(0.12)))
        VStack(alignment: .leading, spacing: 2) {
          Text(title).forgeBodyStrong().fixedSize(horizontal: false, vertical: true)
          Text(subtitle).forgeCaption().fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(selected ? Theme.accent : Theme.track)
          .accessibilityHidden(true)
      }
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.card))
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityAddTraits(selected ? [.isSelected] : [])
    .accessibilityIdentifier(identifier)
  }

  private func symbol(for category: JourneyCategory) -> String {
    switch category {
    case .workout: return "dumbbell.fill"
    case .programChange: return "arrow.triangle.2.circlepath"
    case .body: return "scalemass"
    case .note: return "text.bubble"
    }
  }

  private func tint(for category: JourneyCategory) -> Color {
    switch category {
    case .workout: return Theme.metricSets
    case .programChange: return Theme.metricLoad
    case .body: return Theme.metricTime
    case .note: return Theme.accent
    }
  }

  private func subtitle(for category: JourneyCategory) -> String {
    switch category {
    case .workout: return String(localized: "Finished sessions", bundle: L10n.bundle)
    case .programChange: return String(localized: "Applied changes to your program", bundle: L10n.bundle)
    case .body: return String(localized: "Body check-ins and progress photos", bundle: L10n.bundle)
    case .note: return String(localized: "Notes you wrote", bundle: L10n.bundle)
    }
  }
}

// MARK: - Reflection editor

/// Add or edit one private note. Validation is the repository's — the same 2,000-grapheme,
/// non-blank, no-future-day rules — so this screen cannot accept something storage would reject,
/// and every failure the validator reports is shown at once.
struct JourneyReflectionSheet: View {
  let repository: JourneyRepository
  let target: ReflectionEditorTarget
  /// Real records behind the timeline's current page. A link points at a record that exists;
  /// nothing is created by linking.
  let linkCandidates: [JourneyEvent]
  let onSaved: (Bool) -> Void
  let onDeleted: () -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var existing: JourneyReflection?
  @State private var text = ""
  @State private var day = Date.now
  @State private var link: JourneySourceReference?
  @State private var failures: [JourneyValidationFailure] = []
  /// Idempotency key: a repeated save of the same draft returns the first record instead of
  /// inserting a second note.
  @State private var clientRequestID = UUID().uuidString
  @State private var confirmDelete = false
  @State private var loaded = false

  private var count: Int {
    JourneyText.graphemeClusterCount(JourneyText.trimmed(text))
  }

  private var overLimit: Bool {
    count > JourneyText.maximumGraphemeClusterCount
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          editor

          HStack(spacing: 8) {
            Text(String(localized: "\(Fmt.grouped(Double(count))) / 2,000 characters", bundle: L10n.bundle))
              .forgeCaption()
              .monospacedDigit()
              .foregroundStyle(overLimit ? Theme.negative : Theme.textTertiary)
            Spacer(minLength: 0)
          }
          .accessibilityIdentifier("journey.reflection.counter")

          dayRow
          linkRow

          if !failures.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
              ForEach(failures, id: \.message) { failure in
                Label(failure.message, systemImage: "exclamationmark.circle.fill")
                  .forgeLabel()
                  .foregroundStyle(Theme.negative)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
                .fill(Theme.negative.opacity(0.12)))
            .accessibilityIdentifier("journey.reflection.failures")
          }

          if existing != nil {
            Button {
              confirmDelete = true
            } label: {
              Label("Delete note", systemImage: "trash")
                .forge(15, .semibold)
                .foregroundStyle(Theme.negative)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                  RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
                    .fill(Theme.negative.opacity(0.12)))
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("journey.reflection.delete")
          }

          Text(
            "Notes stay on this device. They are never posted, shared or used to judge a session, and a note never changes a workout."
          )
          .forgeCaption()
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 12)
      }
      .background(Theme.page)
      .navigationTitle(existing == nil ? "New note" : "Edit note")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save)
            .accessibilityIdentifier("journey.reflection.save")
        }
      }
      .confirmationDialog(
        "Delete this note?",
        isPresented: $confirmDelete,
        titleVisibility: .visible
      ) {
        Button("Delete note", role: .destructive, action: delete)
        Button("Keep it", role: .cancel) {}
      } message: {
        Text("The note is removed from your timeline. Nothing else on this device changes.")
      }
      .animation(reduceMotion ? nil : .default, value: failures)
      .accessibilityIdentifier("journey.reflection.editor")
      .task {
        guard !loaded else { return }
        loaded = true
        guard let id = target.reflectionID, let record = repository.reflection(id: id) else {
          day = target.day
          return
        }
        existing = record
        text = record.text
        day = record.day
        link = record.sourceReference
        clientRequestID = record.clientRequestID ?? clientRequestID
      }
    }
  }

  // MARK: Pieces

  private var editor: some View {
    ZStack(alignment: .topLeading) {
      if text.isEmpty {
        Text("What happened, how it felt, what to change next time.")
          .forgeLabel()
          .padding(.top, 10)
          .padding(.leading, 4)
          .allowsHitTesting(false)
      }
      TextEditor(text: $text)
        .forge(15)
        .foregroundStyle(Theme.text)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 150)
        .accessibilityLabel("Note")
        .accessibilityIdentifier("journey.reflection.text")
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.card))
  }

  private var dayRow: some View {
    HStack(spacing: 8) {
      Text("Day").forgeBodyStrong()
      Spacer(minLength: 0)
      DatePicker("Day", selection: $day, in: ...Date.now, displayedComponents: .date)
        .labelsHidden()
        .accessibilityLabel("Day of the note")
        .accessibilityIdentifier("journey.reflection.day")
    }
    .frame(minHeight: 44)
    .padding(.horizontal, 12)
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.card))
  }

  private var linkRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      Menu {
        Button("None") { link = nil }
        ForEach(linkCandidates) { candidate in
          Button(candidateLabel(candidate)) { link = candidate.sourceReference }
        }
        if let link, !linkCandidates.contains(where: { $0.sourceReference == link }) {
          Button("Clear the link to an item that is gone") { self.link = nil }
        }
      } label: {
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Linked entry").forgeBodyStrong()
            Text(linkLabel).forgeCaption().lineLimit(2).fixedSize(horizontal: false, vertical: true)
          }
          Spacer(minLength: 0)
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .accessibilityLabel("Linked entry, \(linkLabel)")
      .accessibilityIdentifier("journey.reflection.link")

      Text("Optional. A link points at a record you already have and never changes it.")
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.card))
  }

  private var linkLabel: String {
    guard let link else { return String(localized: "None", bundle: L10n.bundle) }
    if let match = linkCandidates.first(where: { $0.sourceReference == link }) {
      return "\(match.kind.name) · \(match.title)"
    }
    return repository.sourceExists(link)
      ? link.kind.name
      : String(localized: "\(link.kind.name) — no longer on this device", bundle: L10n.bundle)
  }

  private func candidateLabel(_ candidate: JourneyEvent) -> String {
    let date = candidate.day.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
    return "\(candidate.kind.name) · \(date) · \(candidate.title)"
  }

  // MARK: Actions

  private func save() {
    let draft = JourneyReflectionDraft(
      text: text, day: day, source: link, clientRequestID: clientRequestID)
    do {
      if let existing {
        _ = try repository.updateReflection(
          id: existing.reflectionID, draft: draft, expectedRevision: existing.revision)
        onSaved(false)
      } else {
        _ = try repository.createReflection(draft)
        onSaved(true)
      }
      dismiss()
    } catch let error as JourneyRepositoryError {
      failures = reported(error)
    } catch {
      failures = [JourneyValidationFailure(code: .emptyContent, message: error.localizedDescription)]
    }
  }

  private func delete() {
    guard let existing else { return }
    do {
      try repository.deleteReflection(id: existing.reflectionID, expectedRevision: existing.revision)
      onDeleted()
      dismiss()
    } catch let error as JourneyRepositoryError {
      failures = reported(error)
    } catch {
      failures = [JourneyValidationFailure(code: .emptyContent, message: error.localizedDescription)]
    }
  }

  /// A validation failure carries every problem at once; anything else becomes one message. The
  /// carrier code is not displayed, only the text is.
  private func reported(_ error: JourneyRepositoryError) -> [JourneyValidationFailure] {
    if case .validation(let validation) = error {
      return validation.failures
    }
    return [
      JourneyValidationFailure(
        code: .emptyContent,
        message: error.errorDescription ?? String(describing: error))
    ]
  }
}

// MARK: - Hidden items

/// Everything hidden from the timeline, with a restore for each. Hiding is display-only, so the
/// sheet also states what was *not* touched, and a hidden card whose source record was deleted
/// simply does not appear (the repository resolves each override back to a live record).
struct JourneyHiddenItemsSheet: View {
  let repository: JourneyRepository
  let onRestored: (JourneyEvent) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var items: [JourneyEvent] = []
  @State private var failure: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          if items.isEmpty {
            emptyState
          } else {
            Text(summary).forgeCaption().fixedSize(horizontal: false, vertical: true)
            ForEach(items) { event in
              row(event)
            }
          }
          if let failure {
            Text(failure)
              .forgeLabel()
              .foregroundStyle(Theme.negative)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("journey.hidden.failure")
          }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 12)
      }
      .background(Theme.page)
      .navigationTitle("Hidden items")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .accessibilityIdentifier("journey.hidden.sheet")
      .task { load() }
    }
  }

  private var summary: String {
    String(
      localized:
        "\(items.count) hidden. Hiding only removes an entry from the timeline — the record behind it stays exactly where it was.",
      bundle: L10n.bundle)
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: "eye")
        .font(.system(size: 30, weight: .semibold))
        .foregroundStyle(Theme.textSecondary)
        .frame(width: 68, height: 68)
        .background(Circle().fill(Theme.track.opacity(0.3)))
      Text("Nothing is hidden")
        .forgeBodyStrong()
        .multilineTextAlignment(.center)
      Text(
        "Hiding an entry only takes it out of the timeline. The workout, measurement, photo or note behind it is never deleted — it stays in History, Body stats and Photos."
      )
      .forgeLabel()
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 20)
    .card()
    .accessibilityIdentifier("journey.hidden.empty")
  }

  private func row(_ event: JourneyEvent) -> some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(event.title).forgeBodyStrong().fixedSize(horizontal: false, vertical: true)
        Text(
          "\(event.kind.name) · \(event.day.formatted(.dateTime.month(.abbreviated).day().year().locale(L10n.locale)))"
        )
        .forgeCaption()
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        restore(event)
      } label: {
        Text("Restore").forge(14, .semibold)
          .foregroundStyle(Theme.accent)
          .padding(.horizontal, 14)
          .frame(minHeight: 44)
          .background(Capsule().fill(Theme.accent.opacity(0.12)))
          .contentShape(Capsule())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel("Restore \(event.title)")
      .accessibilityIdentifier("journey.hidden.restore.\(event.id.rawValue)")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.card))
    .accessibilityElement(children: .contain)
  }

  private func load() {
    items = repository.hiddenItems()
  }

  private func restore(_ event: JourneyEvent) {
    do {
      try repository.restore(event.id)
      onRestored(event)
      load()
    } catch let error as JourneyRepositoryError {
      failure = error.errorDescription ?? String(describing: error)
    } catch {
      failure = error.localizedDescription
    }
  }
}

// MARK: - Private profile

/// The Journey identity card: what the timeline calls the lifter, and the training start date
/// **they** set. Nothing here is inferred — with no saved record the timeline shows no start
/// date at all, and the date is never derived from the first workout.
struct JourneyPrivateProfileSheet: View {
  let repository: JourneyRepository

  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var hasStart = false
  @State private var start = Date.now
  @State private var revision: Int?
  @State private var failure: String?
  @State private var loaded = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Display name").forgeBodyStrong()
            TextField("Name shown on your timeline", text: $name)
              .forge(15)
              .foregroundStyle(Theme.text)
              .textInputAutocapitalization(.words)
              .autocorrectionDisabled()
              .padding(.horizontal, 12)
              .frame(minHeight: 44)
              .background(
                RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
                  .fill(Theme.innerSurface))
              .accessibilityLabel("Display name")
              .accessibilityIdentifier("journey.profile.name")
          }
          .padding(12)
          .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.card))

          VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $hasStart) {
              Text("Training start date").forgeBodyStrong()
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("journey.profile.startToggle")

            if hasStart {
              DatePicker(
                "Started training",
                selection: $start,
                in: ...Date.now,
                displayedComponents: .date)
                .accessibilityLabel("Started training")
                .accessibilityIdentifier("journey.profile.startDate")
            } else {
              Text("Not set. The timeline shows no start date until you set one — it is never guessed from your first workout.")
                .forgeCaption()
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          .padding(12)
          .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.card))

          if let failure {
            Text(failure)
              .forgeLabel()
              .foregroundStyle(Theme.negative)
              .fixedSize(horizontal: false, vertical: true)
              .accessibilityIdentifier("journey.profile.failure")
          }

          Text("Stored on this device only. Your private profile is never uploaded, shared or used as a coach profile.")
            .forgeCaption()
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 12)
      }
      .background(Theme.page)
      .navigationTitle("Private profile")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save)
            .accessibilityIdentifier("journey.profile.save")
        }
      }
      .accessibilityIdentifier("journey.profile.sheet")
      .task {
        guard !loaded else { return }
        loaded = true
        guard let record = repository.privateProfile() else { return }
        name = record.displayName
        if let day = record.trainingStartDate {
          hasStart = true
          start = day
        }
        revision = record.revision
      }
    }
  }

  private func save() {
    do {
      _ = try repository.savePrivateProfile(
        displayName: name,
        trainingStartDate: hasStart ? start : nil,
        expectedRevision: revision ?? 0)
      dismiss()
    } catch let error as JourneyRepositoryError {
      failure = error.errorDescription ?? String(describing: error)
    } catch {
      failure = error.localizedDescription
    }
  }
}
