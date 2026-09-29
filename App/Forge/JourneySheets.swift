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
    .background(Capsule().fill(Theme.accentStrong))
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
          linkChips
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
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
  }

  private var dayRow: some View {
    HStack(spacing: 10) {
      Image(systemName: "calendar")
        .font(.system(size: 20, weight: .regular))
        .foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
      Text("Day").forge(17, .semibold)
      Spacer(minLength: 0)
      DatePicker("Day", selection: $day, in: ...Date.now, displayedComponents: .date)
        .labelsHidden()
        .accessibilityLabel("Day of the note")
        .accessibilityIdentifier("journey.reflection.day")
    }
    .frame(minHeight: 48)
    .padding(.horizontal, 12)
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.card))
  }

  /// Same-day quick links. The Menu below (`linkRow`) still offers every candidate,
  /// including records on other days; these chips are the three nearest taps for the day the
  /// note sits on, plus the explicit no-link choice.
  @ViewBuilder private var linkChips: some View {
    let candidates = Array(
      linkCandidates.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }.prefix(3))
    if !candidates.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text("Link to")
          .forge(15, .semibold)
          .foregroundStyle(Theme.textSecondary)
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) { candidateChips(candidates) }
          VStack(alignment: .leading, spacing: 8) { candidateChips(candidates) }
        }
      }
    }
  }

  @ViewBuilder private func candidateChips(_ candidates: [JourneyEvent]) -> some View {
    ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
      chip(
        label: chipLabel(candidate),
        selected: link == candidate.sourceReference,
        identifier: "journey.reflection.linkChip.\(index)"
      ) { link = candidate.sourceReference }
    }
    chip(
      label: String(localized: "No link", bundle: L10n.bundle),
      selected: link == nil,
      identifier: "journey.reflection.linkChip.none"
    ) { link = nil }
  }

  /// One link chip: capsule, 36pt tall visual, 44pt hit area. The selected chip carries the
  /// accent fill and a checkmark; the rest sit on the recessed inner surface.
  private func chip(
    label: String, selected: Bool, identifier: String, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if selected {
          Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
        }
        Text(label)
      }
      .forge(15, .semibold)
      .foregroundStyle(selected ? Theme.onAccent : Theme.text)
      .padding(.horizontal, 14)
      .frame(minHeight: 36)
      .background(Capsule().fill(selected ? Theme.accentStrong : Theme.innerSurface))
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityAddTraits(selected ? [.isSelected] : [])
    .accessibilityIdentifier(identifier)
  }

  private func chipLabel(_ candidate: JourneyEvent) -> String {
    guard candidate.precision == .timestamp, let instant = candidate.instant else {
      return candidate.title
    }
    return candidate.title + " · "
      + instant.formatted(.dateTime.hour().minute().locale(L10n.locale))
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
            ForEach(Array(items.enumerated()), id: \.element.id) { index, event in
              row(event)
              if index < items.count - 1 {
                Divider().padding(.leading, 44)
              }
            }
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: "eye")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 2)
              Text(
                "Hiding never deletes a workout, measurement, photo or note."
              )
              .forge(13, .regular)
              .foregroundStyle(Theme.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
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
    HStack(spacing: 12) {
      rowIcon(event)
      VStack(alignment: .leading, spacing: 1) {
        Text(event.title).forge(17, .semibold).fixedSize(horizontal: false, vertical: true)
        Text(
          event.day.formatted(
            .dateTime.weekday(.abbreviated).month(.abbreviated).day().year().locale(L10n.locale))
        )
        .forge(14, .regular)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
        .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        restore(event)
      } label: {
        Text("Restore")
          .forge(15, .semibold)
          .foregroundStyle(Theme.accentText)
          .padding(.horizontal, 16)
          .frame(height: 36)
          .background(Capsule().fill(Theme.accentTint))
          .frame(minHeight: 44)
          .contentShape(Capsule())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel("Restore \(event.title)")
      .accessibilityIdentifier("journey.hidden.restore.\(event.id.rawValue)")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
  }

  /// The hidden row's icon: the same glyph family the timeline's rail nodes use.
  private func rowIcon(_ event: JourneyEvent) -> some View {
    let symbol: String
    let tint: Color
    switch event.kind {
    case .workout: symbol = "checkmark"; tint = Theme.metricEffort
    case .programChange: symbol = "slider.horizontal.3"; tint = Theme.accent
    case .bodyMeasurement: symbol = "scalemass"; tint = Theme.accent
    case .progressPhoto: symbol = "camera.fill"; tint = Theme.accent
    case .reflection: symbol = "pencil"; tint = Theme.accent
    }
    return Image(systemName: symbol)
      .font(.system(size: 18, weight: .semibold))
      .foregroundStyle(tint)
      .frame(width: 32, height: 32)
      .background(Circle().fill(tint.opacity(0.14)))
      .accessibilityHidden(true)
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
/// date at all, and the date is never derived from the first workout. The read-only rows
/// underneath restate what the plan already says; the body rows show the values recorded at
/// the start, only when a measurement exists there.
struct JourneyPrivateProfileSheet: View {
  let repository: JourneyRepository

  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var hasStart = false
  @State private var start = Date.now
  @State private var revision: Int?
  @State private var failure: String?
  @State private var plan: JourneyPlanFacts?
  @State private var bodyStart: JourneyBodyStartFacts?
  @State private var loaded = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          VStack(alignment: .leading, spacing: 12) {
            lead
            VStack(alignment: .leading, spacing: 6) {
              Text("Name on your timeline")
                .forge(13, .medium)
                .foregroundStyle(Theme.textSecondary)
              TextField("Name shown on your timeline", text: $name)
                .forge(17, .regular)
                .foregroundStyle(Theme.text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(
                  RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
                    .fill(Theme.innerSurface))
                .accessibilityLabel("Display name")
                .accessibilityIdentifier("journey.profile.name")
            }
            VStack(spacing: 0) {
              Toggle(isOn: $hasStart) {
                Text("Training start date").forge(17, .regular)
              }
              .frame(minHeight: 52)
              .accessibilityIdentifier("journey.profile.startToggle")
              if hasStart {
                HStack {
                  Text("Started")
                    .forge(17, .regular)
                  Spacer(minLength: 12)
                  DatePicker(
                    "Started training",
                    selection: $start,
                    in: ...Date.now,
                    displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityLabel("Started training")
                    .accessibilityIdentifier("journey.profile.startDate")
                }
                .frame(minHeight: 52)
              }
            }
            Text(
              "Set by you. The timeline never guesses it from your first workout."
            )
            .forge(13, .regular)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.horizontal, 20)

          if let failure {
            Text(failure)
              .forgeLabel()
              .foregroundStyle(Theme.negative)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.horizontal, 20)
              .padding(.top, 12)
              .accessibilityIdentifier("journey.profile.failure")
          }

          if let plan, plan.goal != nil || plan.level != nil || plan.schedule != nil {
            sectionHeader("From your plan")
            VStack(spacing: 0) {
              if let goal = plan.goal {
                kvRow("Goal", goal)
                Divider()
              }
              if let level = plan.level {
                kvRow("Level", level)
                Divider()
              }
              if let schedule = plan.schedule {
                kvRow("Schedule", schedule)
              }
            }
            .padding(.horizontal, 20)
            Text("Change these in Settings.")
              .forge(13, .regular)
              .foregroundStyle(Theme.textSecondary)
              .padding(.horizontal, 20)
              .padding(.top, 4)
          }

          if let bodyStart {
            sectionHeader("Body at the start")
            VStack(spacing: 0) {
              if let weight = bodyStart.weight {
                kvRow("Bodyweight", "\(weight) · \(startLabel(bodyStart.startDate))")
              }
              if bodyStart.waist != nil, bodyStart.weight != nil {
                Divider()
              }
              if let waist = bodyStart.waist {
                kvRow("Waist", "\(waist) · \(startLabel(bodyStart.startDate))")
              }
            }
            .padding(.horizontal, 20)
            if let now = nowLine(bodyStart) {
              Text(verbatim: now)
                .forge(13, .regular)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
          }
        }
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
        plan = repository.planFacts()
        bodyStart = repository.bodyStartFacts(trainingStart: repository.privateProfile()?.trainingStartDate)
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

  private var lead: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "lock")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Theme.textSecondary)
        .padding(.top, 2)
      Text(
        "Only on this iPhone. Never uploaded, shared or used by your coach."
      )
      .forge(15, .regular)
      .foregroundStyle(Theme.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func sectionHeader(_ title: LocalizedStringKey) -> some View {
    Text(title)
      .forge(18, .semibold)
      .foregroundStyle(Theme.text)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, 4)
  }

  private func kvRow(_ key: LocalizedStringKey, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(key).forge(17, .regular)
      Spacer(minLength: 12)
      Text(verbatim: value)
        .forge(17, .regular)
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.trailing)
    }
    .frame(minHeight: 48, alignment: .top)
    .accessibilityElement(children: .combine)
  }

  private func startLabel(_ date: Date) -> String {
    date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
  }

  /// "Now 80.6 kg and 84 cm. Body stats keeps every entry." — only the parts that exist.
  private func nowLine(_ body: JourneyBodyStartFacts) -> String? {
    switch (body.nowWeight, body.nowWaist) {
    case let (weight?, waist?):
      return String(
        localized: "Now \(weight) and \(waist). Body stats keeps every entry.",
        bundle: L10n.bundle)
    case let (weight?, nil):
      return String(
        localized: "Now \(weight). Body stats keeps every entry.", bundle: L10n.bundle)
    case let (nil, waist?):
      return String(
        localized: "Now \(waist). Body stats keeps every entry.", bundle: L10n.bundle)
    case (nil, nil):
      return nil
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

// MARK: - About

/// What the timeline shows and what it deliberately does not do, said once. The same facts the
/// timeline's footnotes state, gathered behind one sheet instead of scrolled beneath the feed.
struct JourneyAboutSheet: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text(
            "The timeline shows finished workouts, body check-ins, progress photos, program changes and your own notes. Nothing else is invented here."
          )
          .forge(15, .regular)
          .foregroundStyle(Theme.text)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 20)

          section("What shows up")
          VStack(spacing: 0) {
            iconRow("checkmark", Theme.metricEffort, "Workouts", "Finished sessions, records in gold")
            Divider().padding(.leading, 44)
            avatarRow("Plan changes", "Your coach's picture marks the ones they made")
            Divider().padding(.leading, 44)
            iconRow("moon.fill", Theme.metricSleep, "Check-ins and weigh-ins", "One quiet line each")
            Divider().padding(.leading, 44)
            iconRow("camera.fill", Theme.accent, "Progress photos", "Private until you tap to reveal them")
            Divider().padding(.leading, 44)
            iconRow("pencil", Theme.accent, "Notes", "Written by you, linked to a day or a workout")
          }
          .padding(.horizontal, 20)

          section("Stays on this iPhone")
          Text(
            "Works offline. Notes, photos and your private profile never leave this device. Hiding an entry never deletes the record behind it."
          )
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 20)

          section("Not in this timeline")
          VStack(alignment: .leading, spacing: 8) {
            capabilityRow("flag.checkered", "Milestones are not detected automatically")
            capabilityRow("doc.text.magnifyingglass", "No monthly review is written for you")
            capabilityRow("trophy", "Personal records stay on their own charts")
            capabilityRow("lock.shield", "Notes and body entries are never shared or published")
            capabilityRow("text.badge.xmark", "No generated advice about your results")
          }
          .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
      }
      .background(Theme.page)
      .navigationTitle(String(localized: "About this timeline", bundle: L10n.bundle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: "Done", bundle: L10n.bundle)) { dismiss() }
        }
      }
      .presentationDetents([.medium, .large])
      .accessibilityIdentifier("journey.about")
    }
  }

  private func section(_ title: LocalizedStringKey) -> some View {
    Text(title)
      .forge(18, .semibold)
      .foregroundStyle(Theme.text)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, 4)
  }

  private func iconRow(
    _ symbol: String, _ tint: Color, _ title: LocalizedStringKey, _ detail: LocalizedStringKey
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 32, height: 32)
        .background(Circle().fill(tint.opacity(0.14)))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).forge(16, .semibold)
        Text(detail)
          .forge(14, .regular)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(minHeight: 58, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func avatarRow(_ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
    HStack(spacing: 12) {
      CoachAvatar(size: 32)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).forge(16, .semibold)
        Text(detail)
          .forge(14, .regular)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(minHeight: 58, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func capabilityRow(_ symbol: String, _ text: LocalizedStringKey) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
        .frame(width: 16)
      Text(text)
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }
}
