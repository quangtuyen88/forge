import ForgeCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Source

/// Where an adaptation starts from: a saved routine (library) or a training day of an
/// explicitly fetched/validated import candidate. Opening a link alone never produces
/// one of these — the user picks the day on a previewed candidate.
enum RoutineAdaptationSource {
  case savedRoutine(UserProfile.SavedRoutine)
  case importedDay(ProgramDay, programTitle: String)

  var day: ProgramDay {
    switch self {
    case .savedRoutine(let routine): return routine.day
    case .importedDay(let day, _): return day
    }
  }

  var title: String {
    switch self {
    case .savedRoutine(let routine): return routine.name
    case .importedDay(let day, let programTitle):
      return programTitle.isEmpty ? day.name : "\(programTitle) · \(day.name)"
    }
  }

  /// One line naming where the routine came from. Never personal data — a session
  /// label or a program title only.
  var originLine: String {
    switch self {
    case .savedRoutine(let routine):
      let saved = routine.createdAt.formatted(date: .abbreviated, time: .omitted)
      switch routine.sourceKind {
      case .history:
        return "Copied from your session \(routine.sourceName ?? "") · saved \(saved)"
      case .importCandidate:
        return "From “\(routine.sourceName ?? "imported program")” · saved \(saved)"
      }
    case .importedDay(_, let programTitle):
      return "From the previewed program “\(programTitle.isEmpty ? "Untitled" : programTitle)”"
    }
  }

  var defaultSavedName: String {
    switch self {
    case .savedRoutine(let routine): return routine.name
    case .importedDay(let day, let programTitle):
      return programTitle.isEmpty ? day.name : "\(programTitle) · \(day.name)"
    }
  }
}

// MARK: - Shared UI helpers (file-private)

/// Inline error row shared by the routine surfaces. File-private so each view stays
/// self-contained without scope games.
fileprivate struct RoutineErrorRow: View {
  let text: String
  let id: String

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(Theme.negative)
        .frame(width: 22)
        .accessibilityHidden(true)
      Text(text).forgeLabel().fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .innerSurface(padding: 12)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier(id)
  }
}

/// A routine as an actual JSON file for offline export: the redacted
/// `ShareableProgram` shape, carrying the visible routine name and its exercises only
/// — no session labels, saved dates or provenance.
fileprivate struct RoutineFileDocument: FileDocument {
  static let readableContentTypes: [UTType] = [.json]

  let json: String

  init(json: String) {
    self.json = json
  }

  init(configuration: ReadConfiguration) throws {
    json = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: Data(json.utf8))
  }

  static func make(routine: UserProfile.SavedRoutine) -> RoutineFileDocument {
    let payload = ShareableProgram(
      formatVersion: ProgramImportValidator.supportedFormatVersion,
      title: routine.name,
      createdAt: .now,
      days: [ProgramDay(name: routine.name, exercises: routine.day.exercises)])
    return RoutineFileDocument(json: payload.json())
  }
}

// MARK: - Copy routine (from a finished session)

/// Extracts a load-free routine from one finished session and saves it to the library.
/// The preview is honest about what was dropped or capped; nothing is written until
/// Save, a failed save leaves the library exactly as it was, and a successful save
/// shows a visible receipt.
struct RoutineCopyView: View {
  let session: WorkoutSession
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Query private var profiles: [UserProfile]
  @State private var name: String = ""
  @State private var isSaving = false
  @State private var errorText: String?
  @State private var savedReceipt = false

  private var extraction: RoutineExtraction {
    RoutineAdaptationService.extract(from: session)
  }

  /// The session's exercises in the order the lifter actually trained: the stored
  /// exercise order when it is meaningful, otherwise first appearance in logged
  /// chronology. Never a global sort by per-exercise set index.
  private var loggedRows: [(name: String, sets: Int)] {
    let sets = session.sets.sorted {
      $0.loggedAt != $1.loggedAt ? $0.loggedAt < $1.loggedAt : $0.setIndex < $1.setIndex
    }
    let storedOrder = session.order.filter { id in session.sets.contains { $0.exerciseID == id } }
    var order: [String] = []
    var counts: [String: Int] = [:]
    for set in sets {
      if counts[set.exerciseID] == nil { order.append(set.exerciseID) }
      counts[set.exerciseID, default: 0] += 1
    }
    if !storedOrder.isEmpty {
      // Stored order wins; anything logged outside it follows in chronology.
      let extras = order.filter { !storedOrder.contains($0) }
      order = storedOrder + extras
    }
    return order.compactMap { id in
      guard let count = counts[id] else { return nil }
      return (ExerciseDB.find(id)?.localizedName ?? id, count)
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Theme.groupGap) {
          if savedReceipt {
            receiptCard
          } else {
            sourceCard
            previewCard
            if let errorText {
              RoutineErrorRow(text: errorText, id: "routinecopy.error")
            }
            saveButton
          }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 24)
      }
      .background(Theme.page)
      .navigationTitle("Copy routine")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          if !savedReceipt {
            Button("Cancel") { dismiss() }
          }
        }
      }
      .onAppear {
        if name.isEmpty { name = RoutineAdaptationService.defaultName(for: session) }
      }
    }
  }

  private var sourceCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("This session").forgeSection()
      Text(
        "Loads, effort, notes and equipment are never copied — only the exercise order, set counts and rep ranges."
      )
      .forgeCaption()
      VStack(spacing: 0) {
        ForEach(Array(loggedRows.enumerated()), id: \.offset) { index, row in
          HStack {
            Text(row.name).forgeBody()
            Spacer()
            Text("\(row.sets) sets").forgeCaption().monospacedDigit()
          }
          .frame(minHeight: 36)
          if index < loggedRows.count - 1 { Divider().overlay(Theme.ring) }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .innerSurface(padding: 12)
    }
    .card()
    .accessibilityIdentifier("routinecopy.source")
  }

  private var previewCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Reusable routine").forgeSection()
      if let day = extraction.day {
        ForEach(Array(day.exercises.enumerated()), id: \.offset) { _, entry in
          HStack(alignment: .firstTextBaseline) {
            Text(ProgramShareClient.displayName(for: entry)).forgeBody()
            Spacer()
            Text(entryLabel(entry)).forgeCaption().monospacedDigit()
          }
          .frame(minHeight: 32)
        }
      } else {
        Text("This session has no valid working sets to copy.")
          .forgeBody()
      }
      ForEach(extraction.notes) { note in
        Text(noteLine(note)).forgeCaption().fixedSize(horizontal: false, vertical: true)
      }
    }
    .card()
    .accessibilityIdentifier("routinecopy.preview")
  }

  private var saveButton: some View {
    VStack(spacing: 10) {
      TextField("Routine name", text: $name)
        .font(.forge(15, .regular))
        .foregroundStyle(Theme.text)
        .innerSurface(padding: 12)
        .accessibilityLabel("Routine name")
        .accessibilityIdentifier("routinecopy.name")
      Button {
        save()
      } label: {
        if isSaving {
          HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Saving…")
          }
        } else {
          Text("Save to routine library")
        }
      }
      .buttonStyle(PillButtonStyle())
      .disabled(extraction.day == nil || isSaving)
      .accessibilityIdentifier("routinecopy.save")
      Text("Saving adds it to your library. Your plan and history stay as they are.")
        .forgeCaption()
    }
    .card()
  }

  /// Visible, honest success — never a silent dismiss that could hide a failed save.
  private var receiptCard: some View {
    VStack(spacing: 12) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(Theme.positive)
          .frame(width: 24)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text("Saved to your routine library").forgeBodyStrong()
          Text("Find it under Program roadmap → Routine library to adapt it to your equipment, injuries and time.")
            .forgeCaption()
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Button("Done") { dismiss() }
        .buttonStyle(PillButtonStyle())
        .accessibilityIdentifier("routinecopy.done")
    }
    .card()
    .accessibilityIdentifier("routinecopy.receipt")
  }

  private func save() {
    guard !isSaving, let profile = profiles.first, let day = extraction.day else { return }
    isSaving = true
    do {
      _ = try RoutineAdaptationService.saveRoutine(
        day: day,
        name: name,
        sourceKind: .history,
        sourceName: localizedDayName(session.dayName),
        profile: profile,
        context: modelContext,
        sourceSession: session)
      Analytics.track("routine_copied", ["exercises": "\(day.exercises.count)"])
      errorText = nil
      savedReceipt = true
    } catch {
      errorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
    isSaving = false
  }

  private func entryLabel(_ entry: ProgramExerciseEntry) -> String {
    let reps = ProgramShareClient.repsLabel(entry) ?? "—"
    var label = "\(entry.sets) × \(reps)"
    if let rpe = entry.targetRPE { label += " · Target RPE \(Fmt.num(rpe))" }
    return label
  }

  private func noteLine(_ note: RoutineExtractionNote) -> String {
    switch note.code {
    case .noWorkingSets:
      return "\(note.exerciseName): no valid working sets — left out."
    case .unknownExercise:
      return "\(note.exerciseName): not in the catalogue. It is kept in the routine, but it cannot be auto-planned."
    case .setCountCapped:
      return "\(note.exerciseName): set count capped at \(note.value.map(String.init) ?? "20")."
    case .invalidSetsDropped:
      return "\(note.exerciseName): \(note.value ?? 0) set\(L10n.pluralSuffix(note.value ?? 0)) outside the valid rep bounds were not counted."
    case .targetRPEDropped:
      return "\(note.exerciseName): sets disagreed on the target RPE, so no target is carried over."
    }
  }
}

// MARK: - Adapt to me

/// Source → preview (Before / After / Why) → explicit save or replace confirmation.
///
/// The preview reads live profile, plan and history; when a destination is selected it
/// is computed against that session's own gym, minute budget and weekly volume.
/// Tapping Replace freezes a service-built preview and only that frozen value may be
/// applied — if anything changed in between, apply refuses, the error says so, and the
/// flow requires another Replace/confirmation.
struct RoutineAdaptationView: View {
  let source: RoutineAdaptationSource
  @Environment(\.modelContext) private var modelContext
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @State private var selectedDayID: String?
  @State private var confirmApply = false
  /// The frozen preview the confirmation dialog is about. Set on Replace, cleared on
  /// cancel, destination change, stale refusal and success.
  @State private var heldPreview: RoutineAdaptationService.Preview?
  /// The destination the held preview was frozen for — used only for the applied summary.
  @State private var heldDestination: WeekPlanDay?
  @State private var isApplying = false
  @State private var isSaving = false
  @State private var errorText: String?
  @State private var appliedSummary: String?

  private var profile: UserProfile? { profiles.first }

  private var result: RoutineAdaptationResult? {
    guard let profile else { return nil }
    return RoutineAdaptationService.adapt(
      day: source.day, profile: profile, sessions: sessions, toDayID: selectedDayID)
  }

  private struct DestinationRow: Identifiable {
    let day: WeekPlanDay
    let issues: [RoutineAdaptation.RoutineDestinationIssue]
    var id: String { day.id }
  }

  private var destinations: [DestinationRow] {
    guard let profile else { return [] }
    return RoutineAdaptationService.eligibleDestinations(profile: profile, sessions: sessions)
      .map { day in
        DestinationRow(
          day: day,
          issues: RoutineAdaptationService.destinationIssues(
            for: day, profile: profile, replacingWith: result?.adaptedDay))
      }
  }

  private var selectedDestination: WeekPlanDay? {
    destinations.first { $0.day.id == selectedDayID }?.day
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        sourceCard
        if let result { previewCard(result) }
        if let errorText {
          RoutineErrorRow(text: errorText, id: "routineadapt.error")
        }
        if let appliedSummary { appliedRow(appliedSummary) }
        destinationCard
        actionsCard
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Adapt to me")
    .navigationBarTitleDisplayMode(.inline)
    .alert(
      confirmTitle,
      isPresented: Binding(
        get: { confirmApply },
        set: { shown in
          confirmApply = shown
          // Cancel (or any close without a confirmed apply) discards the frozen preview.
          if !shown {
            heldPreview = nil
            heldDestination = nil
          }
        })
    ) {
      Button("Replace session") { apply() }
        .accessibilityIdentifier("routineadapt.confirm")
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "The adapted routine replaces this session's exercises in your accepted week plan. Nothing is logged yet, and your history is untouched."
      )
    }
    .onChange(of: selectedDayID) { _ in
      heldPreview = nil
      heldDestination = nil
      confirmApply = false
    }
  }

  private var confirmTitle: String {
    guard let destination = selectedDestination else { return "Replace this session?" }
    let date = destination.date.formatted(date: .abbreviated, time: .omitted)
    return "Replace \(destination.sessionName) on \(date)?"
  }

  // MARK: Source / Before

  private var sourceCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Source routine").forgeSection()
      Text(source.originLine).forgeCaption()
      ForEach(Array(source.day.exercises.enumerated()), id: \.offset) { _, entry in
        HStack(alignment: .firstTextBaseline) {
          Text(ProgramShareClient.displayName(for: entry)).forgeBody()
          Spacer()
          Text("\(entry.sets) sets · \(ProgramShareClient.repsLabel(entry) ?? "—") reps")
            .forgeCaption()
            .monospacedDigit()
        }
        .frame(minHeight: 32)
      }
    }
    .card()
    .accessibilityIdentifier("routineadapt.source")
  }

  // MARK: After / Why

  private func previewCard(_ result: RoutineAdaptationResult) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text("Adapted to you").forgeSection()
        Spacer()
        Text("\(result.adaptedDay.exercises.count) exercises · \(result.adaptedDay.totalSets) sets · ~\(result.estimatedMinutes) min")
          .forgeCaption()
          .monospacedDigit()
      }

      ForEach(result.entries) { entry in
        entryRow(entry)
      }

      ForEach(result.volumeFlags) { flag in
        Text(
          "\(Muscle(rawValue: flag.muscleRaw)?.a11yName ?? flag.muscleRaw): \(flag.weeklySetsIncludingRoutine) weekly sets including this routine — over the planner's current volume cap of \(flag.mrv) weekly sets for this muscle."
        )
        .forgeCaption()
        .foregroundStyle(Theme.metricEffort)
        .fixedSize(horizontal: false, vertical: true)
      }

      if result.isExecutable, result.blockers.isEmpty, result.volumeFlags.isEmpty {
        Text(
          "No changes beyond the list above: your configured equipment, exclusions, session time and the planner's current volume caps all hold."
        )
        .forgeCaption()
      }
    }
    .card()
    .accessibilityIdentifier("routineadapt.preview")
  }

  @ViewBuilder
  private func entryRow(_ entry: RoutineEntryAdaptation) -> some View {
    if let adapted = entry.adapted, let profile {
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .firstTextBaseline) {
          Text(displayName(adapted.exerciseID)).forgeBodyStrong()
          Spacer()
          Text(
            "\(adapted.sets) × \(adapted.repRangeLower)-\(adapted.repRangeUpper)"
              + (adapted.targetRPE.map { " · Target RPE \(Fmt.num($0))" } ?? "")
          )
          .forgeCaption()
          .monospacedDigit()
        }
        if let estimate = RoutineAdaptationService.loadEstimate(
          for: adapted, resolvedID: adapted.exerciseID, profile: profile, sessions: sessions)
        {
          Text(loadLine(estimate, for: adapted.exerciseID, profile: profile))
            .forgeCaption()
            .monospacedDigit()
        }
        ForEach(Array(entry.changes.enumerated()), id: \.offset) { _, change in
          Text(changeLine(change)).forgeCaption().fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 4)
    } else {
      blockedRow(entry)
    }
  }

  private func blockedRow(_ entry: RoutineEntryAdaptation) -> some View {
    let label = ProgramShareClient.displayName(for: entry.source)
    let reason: String
    if let blocker = result?.blockers.first(where: { $0.exerciseID == entry.source.exerciseID }) {
      reason = blockerLine(blocker)
    } else if entry.changes.contains(where: { $0.kind == .exerciseLimitDropped }) {
      reason = "Beyond the exercise limit for this session length."
    } else {
      reason = "No room in this session's time budget."
    }
    return HStack(alignment: .top, spacing: 10) {
      Image(systemName: "nosign")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.negative)
        .frame(width: 22)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(label).forgeBodyStrong()
        Text(reason).forgeCaption().fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }

  private func loadLine(
    _ estimate: RoutineAdaptationService.LoadEstimate,
    for exerciseID: String,
    profile: UserProfile
  ) -> String {
    func value(_ kg: Double) -> String {
      Fmt.num(profile.display(kg: kg, for: exerciseID), max: 1)
        + (profile.isLb(for: exerciseID) ? " lb" : " kg")
    }
    switch estimate.basis {
    case .userOverride:
      return estimate.kg.map { "Your load override · \(value($0))" } ?? "Your load override"
    default:
      guard let kg = estimate.kg else {
        return "Choose a starting load · no comparable history for this equipment"
      }
      switch estimate.basis {
      case .history:
        return "Next load \(value(kg)) · from your history"
      case .startingRule:
        return "First time on this lift · start \(value(kg)) (estimated, not a verified baseline)"
      case .heldNoEffort:
        return "Hold \(value(kg)) · effort not recorded on your last sets"
      default:
        return "Estimated start \(value(kg))"
      }
    }
  }

  private func changeLine(_ change: RoutineChange) -> String {
    switch change.kind {
    case .kept:
      return "Kept as written."
    case .injurySwap:
      return "Swapped to \(displayName(change.to)) — your injury flag replaces \(displayName(change.from))."
    case .equipmentSwap:
      return "Swapped to \(displayName(change.to)) — your equipment does not include \(displayName(change.from))."
    case .repRangeFromYourOverride:
      return "Rep range \(change.from ?? "—") → \(change.to ?? "—") — your saved override."
    case .weeklyVolumeTrimmedSets:
      return "Sets trimmed \(change.from ?? "") → \(change.to ?? "") to stay inside the planner's weekly volume cap."
    case .weeklyVolumeDroppedExercise:
      return "Dropped — the planner's weekly volume cap is already full for this muscle."
    case .timeBudgetTrimmedSets:
      return "Sets trimmed \(change.from ?? "") → \(change.to ?? "") to fit this session's time budget."
    case .timeBudgetDroppedExercise:
      return "Dropped — no room left in this session's time budget."
    case .exerciseLimitDropped:
      return "Dropped — beyond the exercise limit for this session length."
    default:
      return "Adjusted to fit your configured constraints."
    }
  }

  private func blockerLine(_ blocker: RoutineBlocker) -> String {
    switch blocker.kind {
    case .unknownExercise:
      return "Unknown exercise — not in the catalogue, so it cannot be planned."
    case .excludedExercise:
      return "Excluded by you — a replacement would violate your exclusion."
    case .invalidPrescription:
      return "Sets, rep range or target RPE are outside what the planner can prescribe."
    case .duplicateExercise:
      return "The same exercise appears twice; the logger cannot keep both prescriptions apart."
    case .injurySubstitutionUnavailable:
      return "Your injury flag replaces this lift, and the substitute is not on your equipment."
    case .noReplacementEquipment:
      return "Needs equipment your gym profile does not have, and no replacement fits."
    case .lockedWorkConflict:
      return "Locked work cannot survive your time budget or volume caps intact."
    default:
      return "This routine cannot run under your current constraints."
    }
  }

  // MARK: Destination

  private var destinationCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Replace which session?").forgeSection()
      if appliedSummary != nil {
        Text("This routine is already applied. Start the session from Today, or adapt it again after the plan changes.")
          .forgeCaption()
      } else if destinations.isEmpty {
        Text(planExplainer)
          .forgeCaption()
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("Applying replaces one unstarted session of your accepted week plan. Started, completed, moved and skipped sessions are never touched.")
          .forgeCaption()
          .fixedSize(horizontal: false, vertical: true)
        ForEach(destinations) { item in
          destinationRow(item)
        }
      }
    }
    .card()
    .accessibilityIdentifier("routineadapt.destination")
  }

  private var planExplainer: String {
    if profile?.weekPlan == nil {
      return "You have no accepted week plan yet. Save this routine, then plan a week from Today — once a week is accepted, come back and replace one of its sessions."
    }
    return "No unstarted session is left in your accepted week plan. Save this routine, then plan a new week from Today and replace one of its sessions."
  }

  private func destinationRow(_ item: DestinationRow) -> some View {
    let day = item.day
    let blocked = !item.issues.isEmpty
    let selected = selectedDayID == day.id
    let date = day.date.formatted(date: .abbreviated, time: .omitted)
    return Button {
      selectedDayID = selected ? nil : day.id
    } label: {
      HStack(spacing: 10) {
        Image(systemName: blocked ? "lock.fill" : "figure.strengthtraining.traditional")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(selected ? Theme.onAccent : (blocked ? Theme.textTertiary : Theme.accent))
          .frame(width: 26)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(day.sessionName)
            .forgeBodyStrong()
            .foregroundStyle(selected ? Theme.onAccent : Theme.text)
          Text(
            blocked
              ? "Contains a locked exercise — replacing it would remove locked work"
              : "\(date) · \(day.plannedSetCount) planned sets"
          )
          .forgeCaption()
          .foregroundStyle(selected ? Theme.onAccent.opacity(0.8) : Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        if selected {
          Image(systemName: "checkmark")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .accessibilityHidden(true)
        }
      }
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
          .fill(selected ? Theme.accent : Theme.innerSurface))
      .contentShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
    }
    .buttonStyle(RowPressStyle())
    .disabled(blocked)
    .accessibilityAddTraits(selected ? [.isSelected] : [])
    .accessibilityIdentifier("routineadapt.destination.\(day.id)")
    .accessibilityHint(blocked ? "Unavailable: locked exercise in this session" : "Replaces this session with the adapted routine")
  }

  // MARK: Actions

  private var actionsCard: some View {
    VStack(spacing: 10) {
      if case .savedRoutine = source {
        // A saved routine is already in the library; saving again would duplicate it.
        EmptyView()
      } else if let result, result.isExecutable {
        Button {
          saveRoutine(result.adaptedDay)
        } label: {
          if isSaving {
            HStack(spacing: 8) {
              ProgressView().controlSize(.small)
              Text("Saving…")
            }
          } else {
            Text("Save routine to library")
          }
        }
        .buttonStyle(PillSecondaryButtonStyle())
        .disabled(isSaving || isApplying)
        .accessibilityIdentifier("routineadapt.save")
        Text("Save only adds it to your library. Your plan, week and history stay as they are.")
          .forgeCaption()
      }

      Button {
        requestConfirmation()
      } label: {
        Text(applyTitle)
      }
      .buttonStyle(PillButtonStyle())
      .disabled(
        selectedDestination == nil || isApplying || isSaving || appliedSummary != nil
          || result?.isExecutable != true)
      .accessibilityIdentifier("routineadapt.apply")

      if let destination = selectedDestination, result?.isExecutable == true {
        Text(
          "Replaces \(destination.sessionName) in your accepted plan. Loads, progression and fatigue adjustments continue from your own history."
        )
        .forgeCaption()
        .fixedSize(horizontal: false, vertical: true)
      }
    }
    .card()
  }

  private var applyTitle: String {
    if isApplying { return "Replacing…" }
    guard let destination = selectedDestination else { return "Replace a session" }
    return "Replace \(destination.sessionName)"
  }

  /// Freezes the preview the confirmation will be about — built by the service against
  /// the live destination — before the dialog appears.
  private func requestConfirmation() {
    guard !isApplying, let profile, let destination = selectedDestination else { return }
    do {
      heldPreview = try RoutineAdaptationService.preview(
        day: source.day,
        routineID: routineID,
        toDayID: destination.id,
        profile: profile,
        sessions: sessions)
      heldDestination = destination
      errorText = nil
      confirmApply = true
    } catch {
      heldPreview = nil
      heldDestination = nil
      errorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
  }

  private func apply() {
    guard !isApplying, let profile, let preview = heldPreview else { return }
    isApplying = true
    defer { isApplying = false }
    do {
      let fresh = try RoutineAdaptationService.apply(
        preview: preview,
        sourceName: source.title,
        profile: profile,
        context: modelContext)
      let name = heldDestination?.sessionName ?? "the session"
      let date = heldDestination?
        .date.formatted(date: .abbreviated, time: .omitted) ?? ""
      appliedSummary =
        "Replaced \(name) on \(date): \(fresh.adaptedDay.exercises.count) exercises, \(fresh.adaptedDay.totalSets) working sets. Start it from Today."
      errorText = nil
      selectedDayID = nil
    } catch {
      // Nothing was written. The live preview above is the regenerated one — review
      // and confirm again.
      errorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
    heldPreview = nil
    heldDestination = nil
  }

  private func saveRoutine(_ adaptedDay: ProgramDay) {
    guard !isSaving, let profile else { return }
    isSaving = true
    do {
      _ = try RoutineAdaptationService.saveRoutine(
        day: adaptedDay,
        name: source.defaultSavedName,
        sourceKind: .importCandidate,
        sourceName: source.title,
        profile: profile,
        context: modelContext)
      errorText = nil
    } catch {
      errorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
    isSaving = false
  }

  private var routineID: String? {
    if case .savedRoutine(let routine) = source { return routine.id }
    return nil
  }

  private func appliedRow(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(Theme.positive)
        .frame(width: 22)
        .accessibilityHidden(true)
      Text(text).forgeLabel().fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .innerSurface(padding: 12)
    .accessibilityElement(children: .combine)
  }

  // MARK: Shared helpers

  private func displayName(_ id: String?) -> String {
    guard let id else { return "—" }
    return ExerciseDB.find(id)?.localizedName ?? id
  }
}

/// Sheet wrapper for entries that present the flow modally (import candidate). The
/// pushed variant from the library uses the plain view inside the existing stack.
struct RoutineAdaptationSheet: View {
  let source: RoutineAdaptationSource
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      RoutineAdaptationView(source: source)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
    }
  }
}

// MARK: - Routine library

/// Saved routines: reopen to adapt, export a redacted JSON file, or delete. The export
/// is the redacted `ShareableProgram` shape — the routine's visible name and its
/// exercises only, never session labels, saved dates or provenance.
struct RoutineLibraryView: View {
  @Environment(\.modelContext) private var modelContext
  @Query private var profiles: [UserProfile]
  @State private var errorText: String?
  @State private var exportRoutine: UserProfile.SavedRoutine?

  private var routines: [UserProfile.SavedRoutine] {
    profiles.first?.routineLibrary.sorted { $0.createdAt > $1.createdAt } ?? []
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        if routines.isEmpty {
          emptyCard
        } else {
          VStack(spacing: 0) {
            ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
              if index > 0 { Divider().overlay(Theme.ring) }
              row(routine)
            }
          }
          .card()
        }
        if let errorText {
          RoutineErrorRow(text: errorText, id: "routine.library.error")
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Routine library")
    .fileExporter(
      isPresented: Binding(
        get: { exportRoutine != nil },
        set: { if !$0 { exportRoutine = nil } }),
      document: exportRoutine.map { RoutineFileDocument.make(routine: $0) },
      contentType: .json,
      defaultFilename: exportRoutine.map { "\($0.name).json" }
    ) { outcome in
      switch outcome {
      case .success:
        Analytics.track("routine_exported")
        errorText = nil
      case .failure(let error):
        errorText = error.localizedDescription
      }
    }
  }

  private var emptyCard: some View {
    VStack(spacing: 12) {
      Illustration(name: "art-empty-progress", height: 120)
      Text("No saved routines yet")
        .forgeBodyStrong()
        .multilineTextAlignment(.center)
      Text(
        "Copy a routine from any finished workout in History, or save a training day from an imported program. Adapt one to your equipment, injuries and time whenever you like."
      )
      .forgeCaption()
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 20)
    .card()
    .accessibilityIdentifier("routine.library.empty")
  }

  /// NavigationLink carries the row's tap; the export button sits outside it so the
  /// two gestures can never be confused.
  private func row(_ routine: UserProfile.SavedRoutine) -> some View {
    HStack(spacing: 8) {
      NavigationLink {
        RoutineAdaptationView(source: .savedRoutine(routine))
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "doc.text")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 26)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text(routine.name).forgeBodyStrong()
            Text(summary(routine)).forgeCaption()
          }
          Spacer(minLength: 4)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .contextMenu {
        Button(role: .destructive) {
          delete(routine)
        } label: {
          Label("Delete routine", systemImage: "trash")
        }
      }
      .accessibilityIdentifier("routine.library.item.\(routine.id)")

      Button {
        exportRoutine = routine
      } label: {
        Image(systemName: "square.and.arrow.up")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Theme.accent)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(ControlPressStyle())
      .accessibilityLabel("Export \(routine.name) as a program file")
      .accessibilityIdentifier("routine.library.export.\(routine.id)")
    }
  }

  private func summary(_ routine: UserProfile.SavedRoutine) -> String {
    let date = routine.createdAt.formatted(date: .abbreviated, time: .omitted)
    let origin =
      routine.sourceKind == .history
      ? "copied from a session" : "from an imported program"
    return "\(routine.day.exercises.count) exercises · \(routine.day.totalSets) sets · \(origin) · \(date)"
  }

  private func delete(_ routine: UserProfile.SavedRoutine) {
    guard let profile = profiles.first else { return }
    do {
      try RoutineAdaptationService.deleteRoutine(
        id: routine.id, profile: profile, context: modelContext)
      errorText = nil
    } catch {
      errorText = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
  }
}
