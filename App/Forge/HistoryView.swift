import ForgeCore
import SwiftData
import SwiftUI

enum UnitFormat {
  static func plain(_ kg: Double, usesLb: Bool) -> Double {
    usesLb ? Plates.kgToLb(kg) : kg
  }

  static func weight(_ kg: Double, usesLb: Bool) -> String {
    String(
      localized: "\(Int(plain(kg, usesLb: usesLb).rounded()).formatted()) \(usesLb ? "lb" : "kg")",
      bundle: L10n.bundle)
  }
}

/// Session arithmetic the screens share. Internal, not private, so the duration policy can
/// be asserted in tests rather than re-implemented in each view.
enum SessionMath {
  static func tonnageText(_ sessions: [WorkoutSession], usesLb: Bool) -> String {
    let kg = sessions.flatMap(\.sets).reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    return Fmt.grouped(usesLb ? Plates.kgToLb(kg) : kg)
  }

  static func totalMinutes(_ sessions: [WorkoutSession]) -> Int {
    sessions.reduce(0) { total, session in
      let times = session.sets.map(\.loggedAt)
      guard let lo = times.min(), let hi = times.max(), hi > lo else { return total }
      return total + (Int(hi.timeIntervalSince(lo)) + 59) / 60
    }
  }

  /// Seconds between the first and last logged set. One definition of "how long", so the
  /// summary and History cannot round the same session to 0 in one place and 1 in another.
  static func totalSeconds(_ sessions: [WorkoutSession]) -> Int {
    sessions.reduce(0) { total, session in
      let times = session.sets.map(\.loggedAt)
      guard let lo = times.min(), let hi = times.max(), hi > lo else { return total }
      return total + Int(hi.timeIntervalSince(lo))
    }
  }

  /// How a duration is written. Under a minute is stated as such rather than shown as "0 min"
  /// — two sets a few seconds apart are a real workout, just a short one.
  static func durationText(_ sessions: [WorkoutSession]) -> String {
    let seconds = totalSeconds(sessions)
    if seconds <= 0 { return String(localized: "—", bundle: L10n.bundle) }
    if seconds < 60 { return String(localized: "Under 1 min", bundle: L10n.bundle) }
    return String(localized: "\(seconds / 60) min", bundle: L10n.bundle)
  }
}

struct HistoryView: View {
  let usesLb: Bool
  @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
  @Query private var profiles: [UserProfile]
  @Environment(\.modelContext) private var modelContext
  @State private var pendingDelete: WorkoutSession?

  private var months: [(date: Date, sessions: [WorkoutSession])] {
    let cal = Calendar.current
    let groups = Dictionary(grouping: sessions.filter { $0.completed && !$0.tombstoned }) {
      cal.dateInterval(of: .month, for: $0.date)?.start ?? $0.date
    }
    return
      groups
      .map { (date: $0.key, sessions: $0.value.sorted { $0.date > $1.date }) }
      .sorted { $0.date > $1.date }
  }

  /// What the delete confirmation is about to destroy, named. A destructive confirm that says
  /// only "this session" makes the lifter re-derive which row they swiped.
  private var pendingDeleteTitle: String {
    guard let session = pendingDelete else {
      return String(localized: "Delete this session?", bundle: L10n.bundle)
    }
    return String(
      localized:
        "Delete \(localizedDayName(session.dayName)) · \(session.date.formatted(.dateTime.month().day().locale(L10n.locale)))?",
      bundle: L10n.bundle)
  }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: Theme.groupGap, pinnedViews: [.sectionHeaders]) {
        WeekStrip(sessions: sessions, plannedDays: profiles.first?.daysPerWeek ?? 0)
          .padding(.horizontal, 6)
        if months.isEmpty {
          emptyCard
        }
        ForEach(months, id: \.date) { month in
          Section {
            monthBody(month)
          } header: {
            monthHeader(month.date)
          }
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("History")
    .confirmationDialog(
      pendingDeleteTitle,
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete session", role: .destructive) {
        guard let session = pendingDelete else { return }
        Analytics.track("session_deleted")
        Task { await SessionDetailView.delete(session, context: modelContext) }
      }
    } message: {
      Text("The sets in it are removed too. This cannot be undone.")
    }
  }

  /// Pinned month title. It carries the page fill because a pinned header scrolls over content.
  private func monthHeader(_ date: Date) -> some View {
    Text(date, format: .dateTime.month(.wide).year().locale(L10n.locale))
      .forgeTitle()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 6)
      .background(Theme.page)
      .accessibilityAddTraits(.isHeader)
  }

  private func monthBody(_ month: (date: Date, sessions: [WorkoutSession])) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      MonthTotalsRow(
        sessions: month.sessions.count,
        minutes: SessionMath.totalMinutes(month.sessions),
        sets: month.sessions.reduce(0) { $0 + $1.sets.count },
        tonnage: SessionMath.tonnageText(month.sessions, usesLb: usesLb),
        unit: usesLb ? "lb" : "kg")
      VStack(spacing: 0) {
        ForEach(Array(month.sessions.enumerated()), id: \.element.persistentModelID) {
          index, session in
          sessionRow(session)
          if index < month.sessions.count - 1 {
            Rectangle().fill(Theme.ring).frame(height: 1)
          }
        }
      }
      .card()
    }
  }

  /// One session. Delete is reachable three ways — swipe, long-press menu, and a VoiceOver
  /// custom action — because a drag-only destructive action is unavailable to anyone who
  /// cannot drag (WCAG 2.2 "Dragging Movements").
  private func sessionRow(_ session: WorkoutSession) -> some View {
    SwipeDeleteRow {
      pendingDelete = session
    } content: {
      NavigationLink {
        SessionDetailView(session: session, usesLb: usesLb)
      } label: {
        SessionRow(
          title: localizedDayName(session.dayName),
          value: SessionMath.tonnageText([session], usesLb: usesLb),
          unit: usesLb ? "lb" : "kg",
          trailing: String(
            localized:
              "\(session.date.formatted(.dateTime.month().day().locale(L10n.locale))) · \(session.sets.count) sets",
            bundle: L10n.bundle))
      }
      .buttonStyle(RowPressStyle())
    }
    .contextMenu {
      Button(role: .destructive) { pendingDelete = session } label: {
        Label("Delete session", systemImage: "trash")
      }
    }
    .accessibilityAction(named: Text("Delete session")) { pendingDelete = session }
  }

  /// Nothing finished yet. The tab used to render an empty week strip over blank space, which
  /// reads as a failed load; this says what lands here and how to put the first thing in it.
  private var emptyCard: some View {
    VStack(spacing: 12) {
      Illustration(name: "art-empty-progress", height: 120)
      Text("No finished workouts yet")
        .forgeBodyStrong()
        .multilineTextAlignment(.center)
      Text(
        "Every workout you finish lands here with its sets, tonnage and duration — grouped by month, and editable afterwards."
      )
      .forgeLabel()
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 20)
    .card()
    .accessibilityIdentifier("history.empty")
  }
}

struct SessionDetailView: View {
  let session: WorkoutSession
  let usesLb: Bool
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Query(sort: \WorkoutSession.date) private var allSessions: [WorkoutSession]
  @Query private var profiles: [UserProfile]
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @State private var editing = false
  @State private var confirmDelete = false
  @State private var editTracked = false
  @State private var feedbackSet: LoggedSet?
  /// In-flight edits. Historical metrics, PRs and projections are computed from the model, so
  /// nothing typed here reaches them until Save — an intermediate "664" can no longer rewrite
  /// a finished session's tonnage and e1RM while the lifter is still typing.
  @State private var drafts: [PersistentIdentifier: LoggedSetDraft] = [:]
  @State private var pendingSetDeletes: Set<PersistentIdentifier> = []
  @State private var copyRoutine = false

  private var coach: Coach { Coach.from(coachID) }

  private var prs: [PRRecord] { compatibleSessionPRs() }

  /// Session PRs restricted to baselines whose recorded equipment context is compatible with
  /// this session's set. A different machine, or a legacy-unknown load, can never stand as the
  /// predecessor, so incompatible verified instances are not merged into one baseline.
  private func compatibleSessionPRs() -> [PRRecord] {
    guard session.verified else { return [] }
    let earlier = allSessions.filter { $0.completed && $0 !== session && $0.date < session.date }
    let e1rm: (LoggedSet) -> Double = { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }
    return Set(session.analysisSets(.achievements).map(\.exerciseID)).compactMap {
      id -> PRRecord? in
      guard let exercise = ExerciseDB.find(id) else { return nil }
      let mine = session.analysisSets(.achievements).filter { $0.exerciseID == id }
      guard let reference = mine.max(by: { e1rm($0) < e1rm($1) }) else { return nil }
      let best = e1rm(reference)
      let previous = earlier.flatMap { $0.analysisSets(.achievements) }
        .filter { $0.exerciseID == id && $0.isComparableForBaseline(to: reference) }
        .map(e1rm).max()
      guard let previous, best > previous else { return nil }
      return PRRecord(exercise: exercise, e1rm: best, previous: previous)
    }
    .sorted { $0.exercise.localizedName < $1.exercise.localizedName }
  }

  /// Human-readable equipment context for this session's loads, when passport instances were
  /// recorded. Absent for legacy/imported sets, which stay unlabeled rather than guessed.
  private var equipmentContextLine: String? {
    let ids = Set(session.sets.compactMap(\.equipmentInstanceID))
    guard !ids.isEmpty, let profile = profiles.first else { return nil }
    let names = ids.compactMap { profile.equipmentPassport.instance(id: $0)?.name }.sorted()
    guard !names.isEmpty else { return nil }
    return String(localized: "Equipment: \(names.joined(separator: ", "))", bundle: L10n.bundle)
  }

  /// True when this session recorded verified loads on more than one instance for a single
  /// exercise — those must never be merged into one baseline.
  private var hasIncomparableInstances: Bool {
    Dictionary(
      grouping: session.sets.filter { $0.comparisonContext.normalizationStatus == .verified },
      by: \.exerciseID
    ).values.contains { sets in
      guard let first = sets.first else { return false }
      return !sets.allSatisfy { $0.isComparableForBaseline(to: first) }
    }
  }

  private var debrief: [DebriefLine] {
    guard session.completed, !session.sets.isEmpty else { return [] }
    return debriefLines(
      session: session, sessions: allSessions, prs: prs, profile: profiles.first, usesLb: usesLb)
  }

  private var orderedIDs: [String] {
    var seen: [String] = []
    for set in session.sets.sorted(by: { $0.setIndex < $1.setIndex })
    where !seen.contains(set.exerciseID) {
      seen.append(set.exerciseID)
    }
    return seen
  }

  private var timeRange: String {
    let times = session.sets.sorted { $0.loggedAt < $1.loggedAt }.map(\.loggedAt)
    guard let first = times.first, let last = times.last else {
      return session.date.formatted(.dateTime.hour().minute().locale(L10n.locale))
    }
    if times.count == 1 { return first.formatted(.dateTime.hour().minute().locale(L10n.locale)) }
    return
      "\(first.formatted(.dateTime.hour().minute().locale(L10n.locale)))–\(last.formatted(.dateTime.hour().minute().locale(L10n.locale)))"
  }

  private var detailItems: [MetricItem] {
    var items = [
      MetricItem(
        String(localized: "Duration", bundle: L10n.bundle),
        SessionMath.durationText([session]), color: Theme.metricTime),
      MetricItem(
        String(localized: "Sets", bundle: L10n.bundle), "\(session.sets.count)",
        color: Theme.metricSets),
      MetricItem(
        String(localized: "Tonnage", bundle: L10n.bundle),
        SessionMath.tonnageText([session], usesLb: usesLb), unit: usesLb ? "lb" : "kg",
        color: Theme.metricLoad),
      MetricItem(String(localized: "Exercises", bundle: L10n.bundle), "\(orderedIDs.count)"),
    ]
    // Effort is an observation, not a field that always holds a number. Averaging every
    // set's `rpe` turned the plan's target into a reported average for sets nobody rated —
    // the tile now counts only what the lifter actually reported, and says how many.
    let rated = session.sets.filter(\.effortReported)
    if !session.sets.isEmpty {
      if rated.isEmpty {
        items.append(
          MetricItem(
            String(localized: "Avg RPE", bundle: L10n.bundle),
            String(localized: "—", bundle: L10n.bundle),
            caption: String(localized: "you didn't rate these", bundle: L10n.bundle),
            color: Theme.metricEffort))
      } else {
        items.append(
          MetricItem(
            String(localized: "Avg RPE", bundle: L10n.bundle),
            Fmt.num(rated.reduce(0.0) { $0 + $1.rpe } / Double(rated.count)),
            caption: rated.count == session.sets.count
              ? nil
              : String(localized: "\(rated.count) of \(session.sets.count) sets", bundle: L10n.bundle),
            color: Theme.metricEffort))
      }
    }
    return items
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        SessionHeader(
          symbol: "dumbbell.fill", title: localizedDayName(session.dayName), subtitle: timeRange,
          caption: "Week \(session.week)")
        VStack(alignment: .leading, spacing: 10) {
          Text("Workout details").forgeSection()
          MetricGrid(items: detailItems)
          if session.sets.contains(where: { !$0.effortReported }) && !session.sets.isEmpty {
            // The RPE field is pre-filled from the plan, so most sets are never rated. A
            // dash here means "you didn't tell us", not "we lost it" — say which.
            Text(
              String(
                localized:
                  "RPE starts on your plan's target. Only sets you rated yourself count toward effort.",
                bundle: L10n.bundle)
            )
            .forgeCaption()
            .accessibilityIdentifier("history.effortExplainer")
          }
          if !session.verified {
            Text(
              String(
                localized:
                  "Not counted for PRs, badges or Crew: sets came in too fast or a load jumped.",
                bundle: L10n.bundle)
            )
            .forgeCaption()
          }
          if let context = equipmentContextLine {
            Text(context)
              .forgeCaption()
              .foregroundStyle(Theme.textSecondary)
          }
          if hasIncomparableInstances {
            Text(
              String(
                localized: "Loads on different equipment are kept as separate baselines.",
                bundle: L10n.bundle)
            )
            .forgeCaption()
            .foregroundStyle(Theme.textSecondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        // Copy routine is offered on finished sessions only: it reads the logged order
        // and working-set counts into a reusable, load-free routine. Started or deleted
        // sessions never show it.
        if session.completed, !session.tombstoned, !session.sets.isEmpty, !editing {
          Button {
            copyRoutine = true
          } label: {
            Label("Copy routine", systemImage: "doc.on.doc")
          }
          .buttonStyle(PillSecondaryButtonStyle())
          .accessibilityIdentifier("routinecopy.entry")
        }
        if !session.notes.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Notes").forgeSection()
            Text(session.notes).forgeLabel()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
        }
        if !debrief.isEmpty {
          DebriefCard(debrief: debrief, coachName: coach.name, hasPR: !prs.isEmpty)
        }
        ForEach(orderedIDs, id: \.self) { id in
          if let exercise = ExerciseDB.find(id) {
            exerciseCard(
              exercise,
              sets: session.sets.filter { $0.exerciseID == id }.sorted { $0.setIndex < $1.setIndex }
            )
          }
        }
        if editing {
          Button(role: .destructive) {
            confirmDelete = true
          } label: {
            Text("Delete session")
              .forgeBody()
              .foregroundStyle(Theme.negative)
              .frame(maxWidth: .infinity, minHeight: 44)
              .background(
                RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
                  .fill(Theme.innerSurface))
              .contentShape(Rectangle())
          }
          .buttonStyle(RowPressStyle())
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle(localizedDayName(session.dayName))
    .navigationBarBackButtonHidden(editing)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if editing {
        ToolbarItem(placement: .topBarLeading) {
          Button(String(localized: "Cancel", bundle: L10n.bundle), role: .cancel) {
            cancelEdits()
          }
          .accessibilityIdentifier("session.edit.cancel")
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        // Edit → Done, the iOS convention for an inline editor that already offers Cancel as
        // the escape. It read "Save" while every other surface (and the journey regression)
        // expected "Done", so the same control was named two things in one app.
        Button(
          editing
            ? String(localized: "Done", bundle: L10n.bundle)
            : String(localized: "Edit", bundle: L10n.bundle)
        ) {
          if editing { commitEdits() } else { beginEditing() }
        }
        .bold()
        .disabled(editing && !editsAreValid)
        .accessibilityIdentifier("session.edit.toggle")
      }
    }
    .confirmationDialog(
      "Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible
    ) {
      Button("Delete session", role: .destructive) {
        Analytics.track("session_deleted")
        Task { await deleteSession() }
      }
    }
    .sheet(item: $feedbackSet) { set in
      SetFeedbackSheet(
        set: set,
        exerciseName: ExerciseDB.find(set.exerciseID)?.localizedName ?? set.exerciseID,
        usesLb: profiles.first?.isLb(for: set.exerciseID) ?? usesLb,
        onSaved: { touch() })
    }
    .sheet(isPresented: $copyRoutine) {
      RoutineCopyView(session: session)
    }
  }

  private func touch() {
    session.updatedAt = .now
    try? modelContext.save()
    if !editTracked {
      Analytics.track("set_edited")
      editTracked = true
    }
  }

  private func lbFor(_ set: LoggedSet) -> Bool {
    profiles.first?.isLb(for: set.exerciseID) ?? usesLb
  }

  private func beginEditing() {
    var seeded: [PersistentIdentifier: LoggedSetDraft] = [:]
    for set in session.sets { seeded[set.persistentModelID] = LoggedSetDraft(set, lb: lbFor(set)) }
    drafts = seeded
    pendingSetDeletes = []
    editing = true
  }

  /// Cancel abandons the whole draft. Nothing was written, so there is nothing to undo.
  private func cancelEdits() {
    drafts = [:]
    pendingSetDeletes = []
    editTracked = false
    editing = false
  }

  /// One write, after validation. Dependent displays refresh from the model afterwards.
  private func commitEdits() {
    for set in session.sets where !pendingSetDeletes.contains(set.persistentModelID) {
      guard let draft = drafts[set.persistentModelID] else { continue }
      // Only a typed load is written back; an untouched row keeps its stored precision (62.56 ≠ 62.6).
      if draft.weightText != draft.seededWeightText,
        let value = LoadEntry.parse(draft.weightText, allowsZero: allowsZero(set))
      {
        set.weightKg = lbFor(set) ? Plates.lbToKg(value) : value
      }
      set.reps = draft.reps
      set.rpe = draft.rpe
      set.effortReported = draft.effortReported
    }
    for key in pendingSetDeletes {
      guard let set = session.sets.first(where: { $0.persistentModelID == key }) else { continue }
      session.sets.removeAll { $0.persistentModelID == key }
      modelContext.delete(set)
    }
    drafts = [:]
    pendingSetDeletes = []
    editing = false
    touch()
  }

  /// Save stays disabled while any draft holds unusable text; an untouched row stays valid.
  private var editsAreValid: Bool {
    drafts.allSatisfy { key, draft in
      if pendingSetDeletes.contains(key) { return true }
      if draft.weightText == draft.seededWeightText { return true }
      guard let set = session.sets.first(where: { $0.persistentModelID == key }) else {
        return false
      }
      return LoadEntry.parse(draft.weightText, allowsZero: allowsZero(set)) != nil
    }
  }

  /// Bodyweight and band movements legitimately log 0; everything else carries external load.
  private func allowsZero(_ set: LoggedSet) -> Bool {
    guard let equipment = ExerciseDB.find(set.exerciseID)?.equipment else { return true }
    return equipment == .bodyweight || equipment == .bands
  }

  /// Tombstone + sync when signed in, then local delete. Shared by swipe-delete and the detail view.
  @MainActor static func delete(_ session: WorkoutSession, context: ModelContext) async {
    if AuthClient.shared.user != nil {
      session.tombstoned = true
      session.updatedAt = .now
      try? context.save()
      await SyncEngine.shared.sync()
    }
    context.delete(session)
    try? context.save()
  }

  @MainActor private func deleteSession() async {
    dismiss()
    await SessionDetailView.delete(session, context: modelContext)
  }

  /// A set row states load and reps, and effort **only when the lifter reported it**. The RPE
  /// field is pre-filled from the plan, so rendering `set.rpe` unconditionally turned every
  /// unrated set into a report — on the same screen whose header says 1 of 2 sets were rated.
  /// The load keeps its decimals: a saved 62.5 that reads back as 63 is a different set.
  static func setRowText(_ set: LoggedSet, lb: Bool) -> String {
    let load = Fmt.num(UnitFormat.plain(set.weightKg, usesLb: lb), max: 2)
    guard let reported = set.reportedRPE else { return "\(load) × \(set.reps)" }
    return "\(load) × \(set.reps) @ \(Fmt.num(reported))"
  }

  /// VoiceOver says which of the two a row is, because the visual difference is an absent suffix.
  static func setRowAccessibilityLabel(_ set: LoggedSet, lb: Bool) -> String {
    let load = Fmt.num(UnitFormat.plain(set.weightKg, usesLb: lb), max: 2)
    let unit = lb ? "lb" : "kg"
    guard let reported = set.reportedRPE else {
      return String(
        localized: "\(load) \(unit), \(set.reps) reps, effort not recorded", bundle: L10n.bundle)
    }
    return String(
      localized: "\(load) \(unit), \(set.reps) reps, reported RPE \(Fmt.num(reported))",
      bundle: L10n.bundle)
  }

  private func exerciseCard(_ exercise: Exercise, sets: [LoggedSet]) -> some View {
    let lb = profiles.first?.isLb(for: exercise.id) ?? usesLb
    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(exercise.localizedName).forgeBodyStrong()
        Spacer()
        if let best = sets.map({ Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }).max() {
          HStack(spacing: 4) {
            Text("e1RM").forgeCaption()
            MetricValue(
              value: Fmt.num(UnitFormat.plain(best, usesLb: lb)), unit: lb ? "lb" : "kg", size: 16,
              color: Theme.accentValue)
          }
        }
      }
      ForEach(
        sets.filter { !pendingSetDeletes.contains($0.persistentModelID) },
        id: \.persistentModelID
      ) { set in
        if editing, drafts[set.persistentModelID] != nil {
          EditSetRow(
            draft: Binding(
              get: { drafts[set.persistentModelID] ?? LoggedSetDraft(set, lb: lb) },
              set: { drafts[set.persistentModelID] = $0 }),
            setNumber: set.setIndex + 1,
            usesLb: lb,
            onDelete: { pendingSetDeletes.insert(set.persistentModelID) })
        } else {
          HStack(spacing: 8) {
              Text(Self.setRowText(set, lb: lb))
                .forgeLabel()
                .monospacedDigit()
                .accessibilityLabel(Self.setRowAccessibilityLabel(set, lb: lb))
            if set.variant != "straight", let label = SetVariant(rawValue: set.variant)?.label {
              Text(label)
                .forge(11, .semibold)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: Theme.radiusChip).fill(Theme.accentTint))
            }
            Spacer()
            Button {
              feedbackSet = set
            } label: {
              Image(systemName: set.setFeedback == nil ? "text.bubble" : "text.bubble.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(set.setFeedback == nil ? Theme.textTertiary : Theme.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(ControlPressStyle())
            .accessibilityLabel(
              set.setFeedback == nil
                ? String(
                  localized: "Add set feedback for set \(set.setIndex + 1)", bundle: L10n.bundle)
                : String(
                  localized: "Edit set feedback for set \(set.setIndex + 1)", bundle: L10n.bundle))
          }
        }
        if let note = SetFeedbackAnalysisPolicy.historyNote(for: set.setFeedback) {
          Text(note)
            .forgeCaption()
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 4)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }
}

/// One set's pending edit. Kept out of the model until Save.
struct LoggedSetDraft: Equatable {
  var weightText: String
  /// What `weightText` was seeded with — an untouched row is never rewritten on Save.
  let seededWeightText: String
  var reps: Int
  var rpe: Double
  var effortReported: Bool

  init(_ set: LoggedSet, lb: Bool) {
    let load = Fmt.num(UnitFormat.plain(set.weightKg, usesLb: lb), max: 2)
    weightText = load
    seededWeightText = load
    reps = set.reps
    rpe = set.rpe
    effortReported = set.effortReported
  }

  /// Comma or dot decimal separator, both accepted.
  static func parse(_ text: String) -> Double? {
    LoadEntry.parse(text, allowsZero: true)
  }
}

private struct EditSetRow: View {
  @Binding var draft: LoggedSetDraft
  let setNumber: Int
  let usesLb: Bool
  let onDelete: () -> Void

  var body: some View {
    ViewThatFits(in: .horizontal) {
      oneLine
      twoLines
    }
  }

  /// Today's single-line layout, unchanged.
  private var oneLine: some View {
    HStack(spacing: 10) {
      weightField
      unitLabel
      repsStepper
      effortMenu
      deleteButton
    }
  }

  /// Two-line fallback for narrower widths and larger text sizes.
  private var twoLines: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        weightField
        unitLabel
        Spacer()
        deleteButton
      }
      HStack(spacing: 10) {
        repsStepper
        Spacer()
        effortMenu
      }
    }
  }

  private var weightField: some View {
    TextField("Weight", text: $draft.weightText)
      .keyboardType(.decimalPad)
      .multilineTextAlignment(.center)
      .frame(width: 72)
      .innerSurface(padding: 8)
      .forgeLabel()
      .accessibilityLabel(String(localized: "Weight for set \(setNumber)", bundle: L10n.bundle))
  }

  private var unitLabel: some View {
    Text(usesLb ? "lb" : "kg").forgeCaption()
  }

  private var repsStepper: some View {
    Stepper(value: $draft.reps, in: 1...50) {
      Text("\(draft.reps) reps").forgeLabel().monospacedDigit().fixedSize()
    }
  }

  private var effortMenu: some View {
    Menu {
      Button(String(localized: "Not recorded", bundle: L10n.bundle)) {
        draft.effortReported = false
      }
      ForEach([6.0, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10], id: \.self) { rpe in
        Button(Fmt.num(rpe)) {
          draft.rpe = rpe
          draft.effortReported = true
        }
      }
    } label: {
      Text(effortLabel)
        .forgeLabel()
        .monospacedDigit()
        .innerSurface(padding: 8)
    }
  }

  private var deleteButton: some View {
    Button(action: onDelete) {
      Image(systemName: "trash")
        .foregroundStyle(Theme.negative)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(ControlPressStyle())
    .accessibilityLabel(String(localized: "Remove set \(setNumber)", bundle: L10n.bundle))
  }

  /// Opening the editor must not turn a suggested target into a report.
  private var effortLabel: String {
    draft.effortReported
      ? String(localized: "RPE \(Fmt.num(draft.rpe))", bundle: L10n.bundle)
      : String(localized: "RPE not recorded", bundle: L10n.bundle)
  }
}

