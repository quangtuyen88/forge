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

  private var logged: [WorkoutSession] {
    sessions.filter { $0.completed && !$0.tombstoned }
  }

  private var profile: UserProfile? { profiles.first }

  private var blocks: [LogV3.BlockGroup] {
    LogV3.blocks(sessions: sessions, profile: profile)
  }

  private var recordCounts: [ObjectIdentifier: Int] {
    LogV3.recordCounts(sessions: sessions)
  }

  // MARK: summary

  private struct PlanSummary {
    let planned: Int
    let missed: Int
    let groups: [LogDotGrid.BlockDots]
  }

  /// Planned and missed run on calendar weeks against `daysPerWeek`: program weeks are
  /// session-count based and hold exactly `daysPerWeek` sessions by construction, so a
  /// program-week deficit would always read zero.
  private var planSummary: PlanSummary? {
    guard let profile, profile.daysPerWeek > 0, !blocks.isEmpty else { return nil }
    let daysPerWeek = profile.daysPerWeek
    var groups: [LogDotGrid.BlockDots] = []
    var planned = 0
    var missed = 0
    for block in blocks {
      let columns = LogV3.weekColumns(block: block, daysPerWeek: daysPerWeek)
      var weeks: [LogDotGrid.Week] = []
      for column in columns {
        var dots: [LogDotGrid.Dot] = Array(repeating: .done, count: column.done)
        dots += Array(repeating: .missed, count: column.missed)
        if column.isCurrent {
          let remaining = daysPerWeek - column.done
          if remaining > 0 { dots.append(.today) }
          dots += Array(repeating: .planned, count: max(0, remaining - 1))
        }
        weeks.append(LogDotGrid.Week(dots: dots))
        planned += max(daysPerWeek, column.done)
        missed += column.missed
      }
      guard !weeks.isEmpty else { continue }
      groups.append(
        LogDotGrid.BlockDots(
          label: String(localized: "Block \(block.number)", bundle: L10n.bundle), weeks: weeks))
    }
    return PlanSummary(planned: planned, missed: missed, groups: groups)
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
      LazyVStack(spacing: 0) {
        ProgressLargeTitle(
          title: "History",
          subtitle: headerSubtitle,
          art: "art-schedule"
        )
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 8)

        if logged.isEmpty {
          emptyCard
        } else {
          if let summary = planSummary {
            summaryRow(summary)
          }
          LogBand()
          ForEach(Array(blocks.reversed()), id: \.number) { block in
            blockSection(block)
              .padding(.bottom, 20)
            LogBand()
          }
          if let endnote = endnoteText {
            Text(endnote)
              .forge(14)
              .foregroundStyle(Theme.textSecondary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal, Theme.margin)
              .padding(.top, 20)
          }
        }
      }
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .progressTitleNavigation("History")
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

  private var loggedLast: [Date] {
    logged.map(\.date).sorted()
  }

  private var headerSubtitle: String? {
    guard let first = loggedLast.first else { return nil }
    return String(
      localized: "\(logged.count) sessions since \(first.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))",
      bundle: L10n.bundle)
  }

  private var firstSessionText: String? {
    loggedLast.first.map {
      $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
    }
  }

  private var endnoteText: String? {
    firstSessionText.map {
      String(localized: "Your first session was \($0).", bundle: L10n.bundle)
    }
  }

  private func summaryRow(_ summary: PlanSummary) -> some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text(
          String(
            localized: "\(logged.count) of \(summary.planned) planned", bundle: L10n.bundle)
        )
        .forge(17, .semibold, tracking: -0.17)
        .monospacedDigit()
        if summary.missed > 0 {
          Text(String(localized: "Missed \(summary.missed)", bundle: L10n.bundle))
            .forge(14)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        }
      }
      Spacer(minLength: 16)
      LogDotGrid(groups: summary.groups)
    }
    .padding(.horizontal, Theme.margin)
    .padding(.vertical, 18)
  }

  // MARK: blocks

  private func blockSection(_ block: LogV3.BlockGroup) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 2) {
        Text(String(localized: "Block \(block.number)", bundle: L10n.bundle))
          .forge(22, .bold, tracking: -0.33)
        Text(blockSubLine(block))
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 22)
      ForEach(block.weeks.reversed(), id: \.week) { week in
        weekGroup(week)
      }
    }
  }

  /// "Now · week 4 of 6 · 9 of 18 sessions" for the running block, date range and totals for
  /// finished ones.
  private func blockSubLine(_ block: LogV3.BlockGroup) -> String {
    let count = block.sessions.count
    guard let profile, profile.daysPerWeek > 0, let first = block.firstDate,
      let last = block.lastDate
    else {
      return String(localized: "\(count) sessions", bundle: L10n.bundle)
    }
    let daysPerWeek = profile.daysPerWeek
    if block.isCurrent {
      let weeks = max(
        Mesocycle.weeks,
        LogV3.weekColumns(block: block, daysPerWeek: daysPerWeek).count)
      let planned = weeks * daysPerWeek
      let week = profile.currentWeek(sessions: sessions)
      return String(
        localized: "Now · week \(week) of \(Mesocycle.weeks) · \(count) of \(planned) sessions",
        bundle: L10n.bundle)
    }
    let weeks = max(
      Mesocycle.weeks,
      LogV3.weekColumns(block: block, daysPerWeek: daysPerWeek).count)
    let planned = weeks * daysPerWeek
    let range = LogV3.spanText(
      from: LogV3.weekStart(containing: first),
      to: LogV3.weekStart(containing: last).addingTimeInterval(6 * 86400))
    return String(
      localized: "\(range) · \(count) of \(planned) sessions", bundle: L10n.bundle)
  }

  private func weekGroup(_ week: LogV3.WeekGroup) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
          Text(String(localized: "Week \(week.week)", bundle: L10n.bundle))
            .forge(15, .semibold)
          Text(" · \(weekSpanText(week))")
            .forge(15)
            .foregroundStyle(Theme.textSecondary)
        }
        Spacer(minLength: 12)
        if let right = weekRight(week) {
          Text(right)
            .forge(14)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 16)
      .padding(.bottom, 8)

      VStack(spacing: 0) {
        let rows = weekRows(week)
        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
          row
          if index < rows.count - 1 {
            rowDivider
          }
        }
      }
      .padding(.horizontal, Theme.margin)
    }
  }

  @ViewBuilder
  private var rowDivider: some View {
    Rectangle().fill(Theme.ring).frame(height: 1).padding(.leading, 70)
  }

  /// Sessions newest first; a missed planned day, when the week's own template proves one,
  /// closes the week as a greyed row.
  private func weekRows(_ week: LogV3.WeekGroup) -> [AnyView] {
    var rows = week.sessions.map { session in
      AnyView(
        sessionRow(session, records: recordCounts[ObjectIdentifier(session)] ?? 0))
    }
    for day in week.missedDays {
      rows.append(AnyView(missedRow(day)))
    }
    return rows
  }

  /// The week's real span: first to last session date. Program weeks are not calendar
  /// weeks, so a calendar range would mislabel every week that slipped.
  private func weekSpanText(_ week: LogV3.WeekGroup) -> String {
    Calendar.current.isDate(week.firstDate, inSameDayAs: week.lastDate)
      ? week.firstDate.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
      : LogV3.spanText(from: week.firstDate, to: week.lastDate)
  }

  private func weekRight(_ week: LogV3.WeekGroup) -> String? {
    if week.week == Mesocycle.deloadWeek { return String(localized: "Deload", bundle: L10n.bundle) }
    guard let profile, profile.daysPerWeek > 0,
      week.sessions.count < profile.daysPerWeek
    else { return nil }
    return String(
      localized: "\(week.sessions.count) of \(profile.daysPerWeek)", bundle: L10n.bundle)
  }

  // MARK: rows

  /// One session. Delete is reachable three ways — swipe, long-press menu, and a VoiceOver
  /// custom action — because a drag-only destructive action is unavailable to anyone who
  /// cannot drag (WCAG 2.2 "Dragging Movements").
  private func sessionRow(_ session: WorkoutSession, records: Int) -> some View {
    SwipeDeleteRow(onDelete: { pendingDelete = session }, surface: Theme.page) {
      NavigationLink {
        SessionDetailView(session: session, usesLb: usesLb)
      } label: {
        sessionRowLabel(session, records: records)
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

  private func sessionRowLabel(_ session: WorkoutSession, records: Int) -> some View {
    HStack(spacing: 14) {
      firstExerciseTile(session)
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 8) {
          Text(localizedDayName(session.dayName))
            .forge(17, .semibold, tracking: -0.17)
            .foregroundStyle(Theme.text)
          if records > 0 {
            LogRecordChip(count: records)
          }
        }
        Text(
          String(
            localized: "\(session.sets.count) sets · \(SessionMath.totalMinutes([session])) min",
            bundle: L10n.bundle)
        )
        .forge(15)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 2) {
        Text(
          session.date.formatted(
            .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
        )
        .forge(15)
        .foregroundStyle(Theme.text)
        .monospacedDigit()
        Text(startTime(session))
          .forge(14)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
    }
    .frame(minHeight: 76)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  /// Art tile of the session's first logged set — what was actually trained.
  @ViewBuilder
  private func firstExerciseTile(_ session: WorkoutSession) -> some View {
    if let exercise = session.sets.min(by: {
      $0.loggedAt != $1.loggedAt ? $0.loggedAt < $1.loggedAt : $0.setIndex < $1.setIndex
    }).flatMap({ ExerciseDB.find($0.exerciseID) }) {
      WorkoutArtTile(exercise: exercise, size: 56)
    } else {
      RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
        .fill(Theme.innerSurface)
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
  }

  private func startTime(_ session: WorkoutSession) -> String {
    let times = session.sets.map(\.loggedAt)
    let date = times.min() ?? session.date
    return date.formatted(.dateTime.hour().minute().locale(L10n.locale))
  }

  /// A planned day the week never logged, greyed and inert. Its date is not recorded
  /// anywhere, so the row states the miss without inventing one.
  private func missedRow(_ day: PlannedDay) -> some View {
    HStack(spacing: 14) {
      Group {
        if let exercise = day.exercises.first?.exercise {
          WorkoutArtTile(exercise: exercise, size: 56)
        } else {
          RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
            .fill(Theme.innerSurface)
            .frame(width: 56, height: 56)
        }
      }
      .saturation(0)
      .opacity(0.35)
      VStack(alignment: .leading, spacing: 2) {
        Text(localizedDayName(day.name))
          .forge(17, .medium, tracking: -0.17)
          .foregroundStyle(Theme.textSecondary)
        Text("Missed, not logged")
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
      }
      Spacer(minLength: 8)
    }
    .frame(minHeight: 76)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      String(
        localized: "\(localizedDayName(day.name)), missed, not logged", bundle: L10n.bundle))
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
        "Every workout you finish lands here with its sets and duration — grouped by training block, and editable afterwards."
      )
      .forgeLabel()
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(Theme.margin)
    .padding(.vertical, 20)
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
  @State private var workoutChat: WorkoutCoachScope?
  @Namespace private var chatZoom

  private var coach: Coach { Coach.from(coachID) }

  /// The chat scope behind the debrief card. Nil when the coach service is not configured or
  /// the session has nothing to talk about — then the card shows no question chips.
  private var chatScope: WorkoutCoachScope? {
    guard AppSecret.value != nil, session.completed, !session.sets.isEmpty else { return nil }
    return WorkoutCoachScope.make(
      session: session, sessions: allSessions, profile: profiles.first,
      debrief: debrief, usesLb: usesLb)
  }

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

  /// Tracked lifts get a set table; exercises the lifter added on the day are compact
  /// accessories.
  private var accessoryIDs: [String] {
    orderedIDs.filter { session.extraExerciseIDs.contains($0) }
  }

  private var trackedIDs: [String] {
    orderedIDs.filter { !session.extraExerciseIDs.contains($0) }
  }

  private func sets(of id: String) -> [LoggedSet] {
    session.sets.filter { $0.exerciseID == id }.sorted { $0.setIndex < $1.setIndex }
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

  private var headerSubtitle: String {
    let date = session.date.formatted(
      .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
    let block = LogV3.blockNumber(of: session, sessions: allSessions)
    let place: String
    if let block {
      place = String(localized: "Block \(block), week \(session.week)", bundle: L10n.bundle)
    } else {
      place = String(localized: "Week \(session.week)", bundle: L10n.bundle)
    }
    return String(
      localized: "\(date) · \(timeRange) · \(place)", bundle: L10n.bundle)
  }

  private var stats: [LogStatsRow.Item] {
    [
      LogStatsRow.Item(
        label: String(localized: "Duration", bundle: L10n.bundle),
        value: durationValue,
        unit: durationUnit,
        color: Theme.metricTime),
      LogStatsRow.Item(
        label: String(localized: "Sets", bundle: L10n.bundle),
        value: "\(session.sets.count)",
        color: Theme.metricSets),
      LogStatsRow.Item(
        label: String(localized: "Tonnage", bundle: L10n.bundle),
        value: SessionMath.tonnageText([session], usesLb: usesLb),
        unit: usesLb ? "lb" : "kg",
        color: Theme.metricLoad),
      LogStatsRow.Item(
        label: String(localized: "Records", bundle: L10n.bundle),
        value: "\(prs.count)",
        trophy: true),
    ]
  }

  private var durationValue: String {
    let seconds = SessionMath.totalSeconds([session])
    if seconds <= 0 { return String(localized: "—", bundle: L10n.bundle) }
    if seconds < 60 { return String(localized: "Under 1 min", bundle: L10n.bundle) }
    return "\(seconds / 60)"
  }

  private var durationUnit: String? {
    let seconds = SessionMath.totalSeconds([session])
    guard seconds >= 60 else { return nil }
    return String(localized: "min", bundle: L10n.bundle)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        ProgressLargeTitle(
          title: LocalizedStringKey(localizedDayName(session.dayName)),
          subtitle: headerSubtitle)
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 8)

        LogStatsRow(items: stats)
          .padding(.horizontal, Theme.margin)
          .padding(.top, 10)
          .padding(.bottom, 18)

        if !debrief.isEmpty {
          DebriefCard(
            debrief: debrief, coachName: coach.name, hasPR: !prs.isEmpty,
            questions: chatScope?.questions ?? [],
            onAsk: chatScope == nil
              ? nil
              : { question in
                guard var scope = chatScope else { return }
                scope.firstQuestion = question
                workoutChat = scope
              })
            .modifier(WorkoutChatZoomSource(id: "debrief", namespace: chatZoom))
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 16)
        }
        if !session.notes.isEmpty {
          VStack(alignment: .leading, spacing: 2) {
            Text("Notes").forgeCaption()
            Text(session.notes).forge(15).foregroundStyle(Theme.text)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 16)
        }
        captionBlock

        LogBand()

        ForEach(Array(trackedIDs.enumerated()), id: \.element) { index, id in
          if let exercise = ExerciseDB.find(id) {
            exerciseSection(exercise, sets: sets(of: id))
            if index < trackedIDs.count - 1 {
              Rectangle().fill(Theme.ring).frame(height: 1)
            }
          }
        }

        if !accessoryIDs.isEmpty {
          LogBand()
          accessoriesSection
        }

        LogBand()
        options
      }
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    // The bar title is the string the E2E flows and VoiceOver read after opening a finished
    // session; the content keeps the day name as its one large title.
    .navigationTitle("Workout details")
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
    .fullScreenCover(item: $workoutChat) { scope in
      CoachView(scope: scope)
        .modifier(WorkoutChatZoomDestination(id: "debrief", namespace: chatZoom))
    }
  }

  /// The quiet scope notes the detail owes the lifter: unrated effort, unverified loads,
  /// equipment context, separate baselines.
  private var captionBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      if session.sets.contains(where: { !$0.effortReported }) && !session.sets.isEmpty {
        // The RPE field is pre-filled from the plan, so most sets are never rated. A
        // dash means "you didn't tell us", not "we lost it" — say which.
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
        Text(context).forgeCaption()
      }
      if hasIncomparableInstances {
        Text(
          String(
            localized: "Loads on different equipment are kept as separate baselines.",
            bundle: L10n.bundle)
        )
        .forgeCaption()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Theme.margin)
    .padding(.bottom, 16)
  }

  // MARK: exercises

  /// Best comparable e1RM of this exercise in this session, and the best before it, for the
  /// "Est. max · change" line. nil change for a first-time exercise.
  private func estMax(sets: [LoggedSet]) -> (best: Double, previous: Double?)? {
    guard let best = sets.map({ Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }).max()
    else { return nil }
    let history = LogV3.e1rmHistory(exerciseID: sets[0].exerciseID, sessions: allSessions)
    let previous = history.last(where: { $0.date < session.date })?.e1rm
    return (best, previous)
  }

  /// The set rows flagged as records: those whose e1rm equals the session PR of that exercise.
  private func recordSetIDs(_ sets: [LoggedSet]) -> Set<PersistentIdentifier> {
    let byExercise = Dictionary(grouping: prs, by: \.exercise.id)
    var out = Set<PersistentIdentifier>()
    for set in sets {
      guard let records = byExercise[set.exerciseID] else { continue }
      let value = Strength.epley(weightKg: set.weightKg, reps: set.reps)
      if records.contains(where: { abs($0.e1rm - value) < 0.01 }) {
        out.insert(set.persistentModelID)
      }
    }
    return out
  }

  private func exerciseSection(_ exercise: Exercise, sets: [LoggedSet]) -> some View {
    let lb = profiles.first?.isLb(for: exercise.id) ?? usesLb
    let est = estMax(sets: sets)
    let records = recordSetIDs(sets)
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 14) {
        WorkoutArtTile(exercise: exercise, size: 56)
        VStack(alignment: .leading, spacing: 2) {
          Text(exercise.localizedName)
            .forge(17, .semibold, tracking: -0.17)
            .foregroundStyle(Theme.text)
          HStack(spacing: 4) {
            if let est {
              Text(
                String(
                  localized: "Est. max \(UnitFormat.weight(est.best, usesLb: lb))",
                  bundle: L10n.bundle)
              )
              .forge(15)
              .foregroundStyle(Theme.textSecondary)
              .monospacedDigit()
              if let previous = est.previous {
                Text("·").forge(15).foregroundStyle(Theme.textSecondary)
                TrendChangeText(
                  changeKg: est.best - previous, isLb: lb, size: 15)
              }
            }
          }
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 18)
      setTable(sets, lb: lb, records: records)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
  }

  @ViewBuilder
  private func setTable(_ sets: [LoggedSet], lb: Bool, records: Set<PersistentIdentifier>) -> some View {
    VStack(spacing: 0) {
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
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 6)
        } else {
          setRow(set, lb: lb, isRecord: records.contains(set.persistentModelID))
        }
        if let note = SetFeedbackAnalysisPolicy.historyNote(for: set.setFeedback) {
          Text(note)
            .forgeCaption()
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.margin)
        }
      }
    }
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

  private func setRow(_ set: LoggedSet, lb: Bool, isRecord: Bool) -> some View {
    HStack(spacing: 0) {
      Text("\(set.setIndex + 1)")
        .forge(14, .medium)
        .monospacedDigit()
        .foregroundStyle(Theme.textSecondary)
        .frame(width: 34, alignment: .center)
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(Fmt.num(UnitFormat.plain(set.weightKg, usesLb: lb), max: 2))
          .forge(16, .semibold)
          .monospacedDigit()
          .foregroundStyle(Theme.text)
        Text(lb ? "lb" : "kg")
          .forge(14)
          .foregroundStyle(Theme.textSecondary)
        Text("×").forge(14).foregroundStyle(Theme.textSecondary)
        Text("\(set.reps)")
          .forge(16, .semibold)
          .monospacedDigit()
          .foregroundStyle(Theme.text)
        if set.variant != "straight", let label = SetVariant(rawValue: set.variant)?.label {
          Text(label)
            .forge(11, .semibold)
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
              RoundedRectangle(cornerRadius: Theme.radiusChip).fill(Theme.accentTint))
            .padding(.leading, 6)
        }
        if isRecord {
          HStack(spacing: 3) {
            Image(systemName: "trophy.fill")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(Theme.recordRing)
            Text("Record")
              .forge(13, .semibold)
              .foregroundStyle(Theme.recordInk)
          }
          .padding(.leading, 8)
          .accessibilityHidden(true)
        }
      }
      Spacer(minLength: 8)
      if let reported = set.reportedRPE {
        Text("RPE \(Fmt.num(reported))")
          .forge(15)
          .monospacedDigit()
          .foregroundStyle(Theme.textSecondary)
      }
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
    .padding(.trailing, 12)
    .frame(minHeight: 44)
    .background {
      if isRecord {
        RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
          .fill(Theme.recordTint)
          .padding(.horizontal, 6)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Self.setRowAccessibilityLabel(set, lb: lb))
  }

  // MARK: accessories

  private var accessoriesSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text("Accessories").forge(18, .semibold, tracking: -0.18)
        Spacer(minLength: 12)
        Text(
          String(
            localized: "\(accessoryIDs.reduce(0) { $0 + sets(of: $1).count }) sets",
            bundle: L10n.bundle)
        )
        .forge(15)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 20)
      .padding(.bottom, 4)

      ForEach(Array(accessoryIDs.enumerated()), id: \.element) { index, id in
        if let exercise = ExerciseDB.find(id) {
          if editing {
            setTable(sets(of: id), lb: profiles.first?.isLb(for: id) ?? usesLb, records: [])
          } else {
            accessoryRow(exercise, sets: sets(of: id))
          }
          if index < accessoryIDs.count - 1 {
            Rectangle().fill(Theme.ring).frame(height: 1)
          }
        }
      }

      let accessorySets = accessoryIDs.flatMap { sets(of: $0) }
      if !accessorySets.isEmpty, !accessorySets.contains(where: \.effortReported) {
        Text("You didn't rate effort on these sets.")
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .padding(.horizontal, Theme.margin)
          .padding(.top, 12)
      }
    }
  }

  private func accessoryRow(_ exercise: Exercise, sets: [LoggedSet]) -> some View {
    let lb = profiles.first?.isLb(for: exercise.id) ?? usesLb
    let weights = Set(sets.map { Fmt.num(UnitFormat.plain($0.weightKg, usesLb: lb), max: 2) })
    let bodyweight = exercise.equipment == .bodyweight || exercise.equipment == .bands
    let load: String
    if bodyweight && Set(sets.map(\.weightKg)).isSubset(of: [0]) {
      load = String(localized: "Bodyweight", bundle: L10n.bundle)
    } else if weights.count == 1, let only = weights.first {
      load = "\(only) \(lb ? "lb" : "kg")"
    } else {
      load = sets.map {
        "\(Fmt.num(UnitFormat.plain($0.weightKg, usesLb: lb), max: 2))×\($0.reps)"
      }.joined(separator: ", ")
    }
    let reps = sets.map(\.reps).map(String.init).joined(separator: ", ")
    return VStack(alignment: .leading, spacing: 2) {
      Text(exercise.localizedName)
        .forge(16, .semibold, tracking: -0.16)
        .foregroundStyle(Theme.text)
      if load == String(localized: "Bodyweight", bundle: L10n.bundle) {
        Text(reps)
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      } else if weights.count == 1 {
        Text("\(load) × \(reps)")
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      } else {
        Text(load)
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Theme.margin)
    .padding(.vertical, 12)
    .accessibilityElement(children: .combine)
  }

  // MARK: options

  @ViewBuilder
  private var options: some View {
    VStack(spacing: 0) {
      if session.completed, !session.tombstoned, !session.sets.isEmpty, !editing {
        // Copy routine is offered on finished sessions only: it reads the logged order
        // and working-set counts into a reusable, load-free routine.
        Button {
          copyRoutine = true
        } label: {
          optionLabel(
            systemImage: "doc.on.doc", tint: Theme.accent, title: String(
              localized: "Copy routine", bundle: L10n.bundle), showsChevron: true)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("routinecopy.entry")
        Rectangle().fill(Theme.ring).frame(height: 1).padding(.leading, 66)
      }
      if !editing {
        Button(role: .destructive) {
          confirmDelete = true
        } label: {
          optionLabel(
            systemImage: "trash", tint: Theme.negative, title: String(
              localized: "Delete session", bundle: L10n.bundle), showsChevron: false)
        }
        .buttonStyle(RowPressStyle())
      }
    }
    .padding(.horizontal, Theme.margin)
    .padding(.top, 12)
  }

  private func optionLabel(
    systemImage: String, tint: Color, title: String, showsChevron: Bool
  ) -> some View {
    HStack(spacing: 14) {
      LogIconBadge(symbol: systemImage, tint: tint)
      Text(title)
        .forge(17, .regular, tracking: -0.17)
        .foregroundStyle(tint == Theme.negative ? Theme.negative : Theme.text)
      Spacer()
      if showsChevron {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.textTertiary)
      }
    }
    .frame(minHeight: 60)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  // MARK: editing

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
