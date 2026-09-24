import ForgeCore
import SwiftData
import SwiftUI

/// The dated, editable projection of the week the program intends.
///
/// One source of truth: `WeekPlan`, evaluated by `WeekPlanStatusPolicy`. Nothing here
/// writes a derived state — `remaining` and `missed` are computed from the day's date,
/// the enrollment moment and the grace window, so a session that still has time left is
/// never presented as missed, and a day that predates the plan is never presented as a
/// failure. Only the four *recorded* states (completed, moved, skipped, and the absence
/// of a record) are ever stored, and only when the lifter explicitly says so.
struct WeekDesignerView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

  /// What is persisted. `draft` diverges from it until the lifter saves.
  @State private var persisted: WeekPlan?
  @State private var draft: WeekPlan?
  @State private var didLoad = false
  @State private var actionDayID: String?
  @State private var movingDay: WeekPlanDay?
  @State private var showsRegenerate = false
  @State private var showsReset = false
  @State private var savedNote: String?

  private var profile: UserProfile? { profiles.first }
  private var isDirty: Bool { draft != nil && draft != persisted }

  /// Monday of the week the designer is allowed to author, in the app's language calendar.
  static func monday(of date: Date, calendar: Calendar = Calendar(identifier: .iso8601)) -> Date {
    var calendar = calendar
    calendar.locale = L10n.locale
    let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    return calendar.startOfDay(for: start)
  }

  private var currentWeekStart: Date { Self.monday(of: .now) }

  private var plan: WeekPlan? { draft }
  private var evaluation: WeekPlanEvaluation? { draft?.evaluation(now: .now) }
  private var isPastWeek: Bool {
    guard let draft else { return false }
    let calendar = draft.resolvedCalendar(Calendar.current)
    return calendar.startOfDay(for: draft.weekStart) != currentWeekStart
  }

  var body: some View {
    let evaluation = self.evaluation
    return ScrollView {
      VStack(spacing: Theme.groupGap) {
        if let plan = draft, let evaluation {
          if isPastWeek { staleWeekCard(plan) }
          statusCard(plan, evaluation)
          daysCard(plan, evaluation)
          if let issues = validationIssues(plan), !issues.isEmpty { planCheckCard(issues) }
          rulesCard(plan)
        } else {
          emptyCard
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Week designer")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { optionsMenu }
      ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
    }
    .safeAreaInset(edge: .bottom) { saveBar }
    .onAppear { load() }
    .onChange(of: profiles.count) { _, _ in load() }
    .sheet(item: $movingDay) { day in
      WeekDesignerMoveSheet(plan: draft, day: day) { date in moveDay(day.id, to: date) }
    }
    .confirmationDialog(
      actionTitle, isPresented: actionsPresented, titleVisibility: .visible
    ) {
      dayActions
    } message: {
      Text(actionMessage)
    }
    .alert("Regenerate this week?", isPresented: $showsRegenerate) {
      Button("Regenerate", role: .destructive) { regenerate() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Sessions you haven't done yet are rebuilt from your current program, gym and time budget. Completed, moved and skipped days stay as they are."
      )
    }
    .alert("Reset recorded states?", isPresented: $showsReset) {
      Button("Reset", role: .destructive) { resetRecords() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Clears what was recorded this week — completed, moved and skipped. Dates, sessions, gym and time budget stay as they are."
      )
    }
  }

  // MARK: - Loading

  private func load() {
    guard !didLoad, let profile else { return }
    didLoad = true
    if let stored = profile.weekPlan {
      persisted = stored
      draft = stored
    } else {
      // First authoring moment: nothing recorded before now is judged, so no day can be
      // called missed for a plan the lifter had not seen yet.
      persisted = nil
      draft = build(
        with: profile, programWeek: profile.currentWeek(sessions: sessions),
        enrollmentDate: .now)
    }
  }

  private func build(with profile: UserProfile, programWeek: Int, enrollmentDate: Date) -> WeekPlan {
    WeekPlanBuilder.plan(
      programWeek: programWeek,
      profile: profile.profileInput,
      constraints: profile.trainingConstraints,
      startingOn: currentWeekStart,
      enrollmentDate: enrollmentDate,
      calendar: Calendar.current)
  }

  /// Keeps an earlier enrollment when it belongs to this week, so regenerating can never
  /// quietly excuse days that were already being tracked.
  private func enrollmentDate(forWeekStarting start: Date) -> Date {
    guard let persisted, persisted.enrollmentDate > start, persisted.enrollmentDate <= .now else {
      return start
    }
    return persisted.enrollmentDate
  }

  private func regenerate() {
    guard let profile else { return }
    let base = draft ?? persisted
    if let base, let revised = profile.revisedWeekPlan(base, sessions: sessions) {
      draft = revised
    } else {
      draft = build(
        with: profile, programWeek: profile.currentWeek(sessions: sessions),
        enrollmentDate: enrollmentDate(forWeekStarting: currentWeekStart))
    }
    savedNote = nil
  }

  /// Clears recorded states without touching dates, sessions or budgets.
  private func resetRecords() {
    guard var plan = draft else { return }
    // Days that only exist because a session was moved onto them go away with the move.
    plan.days.removeAll { $0.movedFromDate != nil }
    for index in plan.days.indices {
      plan.days[index].state = .planned
      plan.days[index].completedSessionID = nil
      plan.days[index].movedToDate = nil
      plan.days[index].receivedSessionIDs = []
    }
    draft = plan
    savedNote = nil
  }

  private func save() {
    guard let profile, let plan = draft else { return }
    let evaluation = plan.evaluation(now: .now)
    profile.weekPlan = plan
    modelContext.insert(
      DecisionLogEntry(
        DecisionRecord(
          id: "weekplan-\(Int(Date.now.timeIntervalSince1970))",
          date: .now,
          type: "weekplan",
          exerciseID: nil,
          muscle: nil,
          fromValue: nil,
          toValue: Double(evaluation.counts.scheduled),
          reasonCodes: [DecisionSignal.userOverride.code, DecisionSignal.timeBudget.code],
          evidence: [
            plan.mode.name,
            "\(plan.days.count) planned days",
            "\(evaluation.counts.completed) completed",
            "\(evaluation.counts.moved) moved",
            "\(evaluation.counts.skipped) skipped",
          ],
          humanSummary:
            "Week plan saved for the week of \(WeekDesignerText.shortDate(plan.weekStart)): "
            + "\(evaluation.counts.completed) of \(evaluation.counts.scheduled) planned sessions recorded.")))
    try? modelContext.save()
    persisted = plan
    savedNote = "Saved. Evaluation runs on your recorded sessions."
    Analytics.track(
      "week_plan_saved",
      [
        "mode": plan.mode.rawValue,
        "days": "\(plan.days.count)",
        "moved": "\(evaluation.counts.moved)",
        "skipped": "\(evaluation.counts.skipped)",
      ])
  }

  // MARK: - Recorded transitions

  private func moveDay(_ dayID: String, to date: Date) {
    guard var plan = draft else { return }
    let calendar = plan.resolvedCalendar(Calendar.current)
    guard plan.move(dayID: dayID, to: date, calendar: calendar) else { return }
    draft = plan
    savedNote = nil
    Analytics.track("week_plan_move", ["days": "\(plan.days.count)"])
  }

  private func skipDay(_ dayID: String) {
    guard var plan = draft else { return }
    _ = plan.skip(dayID: dayID)
    draft = plan
    savedNote = nil
  }

  private func completeDay(_ dayID: String, session: WorkoutSession) {
    guard var plan = draft else { return }
    _ = plan.complete(dayID: dayID, sessionID: Self.sessionIdentifier(session))
    draft = plan
    savedNote = nil
  }

  /// Removes a record: the day returns to "planned" and its state is derived again.
  private func clearRecord(_ dayID: String) {
    guard var plan = draft, let index = plan.days.firstIndex(where: { $0.id == dayID }) else {
      return
    }
    if plan.days[index].movedFromDate != nil {
      plan.days.remove(at: index)
    } else {
      plan.days[index].state = .planned
      plan.days[index].completedSessionID = nil
      plan.days[index].movedToDate = nil
      plan.days[index].receivedSessionIDs = []
    }
    draft = plan
    savedNote = nil
  }

  /// Stable identity for a recorded session, so a plan day can point at real evidence.
  /// One definition, shared with the workout logger, which writes the same reference when
  /// it records a finished session against its plan day.
  static func sessionIdentifier(_ session: WorkoutSession) -> String {
    WeekPlanCompletionPolicy.sessionReference(session)
  }

  private func recordedSession(on date: Date, in plan: WeekPlan) -> WorkoutSession? {
    let calendar = plan.resolvedCalendar(Calendar.current)
    return sessions.first { $0.completed && calendar.isDate($0.date, inSameDayAs: date) }
  }

  // MARK: - Day actions

  private var actionDay: WeekPlanDay? {
    guard let actionDayID, let plan = draft else { return nil }
    return plan.days.first { $0.id == actionDayID }
  }

  private var actionsPresented: Binding<Bool> {
    Binding(get: { actionDayID != nil }, set: { if !$0 { actionDayID = nil } })
  }

  private var actionTitle: String {
    guard let day = actionDay else { return "Session" }
    return "\(WeekDesignerText.shortDate(day.date)) · \(localizedDayName(day.sessionName))"
  }

  private var actionMessage: String {
    guard let day = actionDay, let plan = draft else { return "" }
    if let evaluation = self.evaluation?.day(day.id), !evaluation.isCountedInPlan {
      return "This day is before your plan started, so it is not counted."
    }
    switch evaluationFor(day, in: plan).state {
    case .missed:
      return plan.mode.relaxesMissedSessions
        ? "This week is relaxed, so a session not done here is not held against you."
        : "The grace window closed with nothing recorded. Skipping is still an explicit choice, not a default."
    case .remaining:
      return "Still owed. You can move it, skip it deliberately, or save the plan and let the evaluation decide."
    default:
      return "Recorded state and date can still be changed."
    }
  }

  private func evaluationFor(_ day: WeekPlanDay, in plan: WeekPlan) -> WeekPlanDayEvaluation {
    evaluation?.day(day.id)
      ?? WeekPlanDayEvaluation(
        dayID: day.id, date: day.date, state: day.state, reason: .upcoming, isCountedInPlan: true,
        plannedSessionID: day.plannedSessionID,
        deadline: plan.resolvedCalendar(Calendar.current).startOfDay(for: day.date))
  }

  @ViewBuilder
  private var dayActions: some View {
    if let day = actionDay {
      Button("Move to another day") {
        actionDayID = nil
        movingDay = day
      }
      if let session = recordedSession(on: day.date, in: draft ?? WeekPlan(
        id: "", weekStart: day.date, enrollmentDate: day.date)) {
        Button("Record this day as completed with \(localizedDayName(session.dayName))") {
          completeDay(day.id, session: session)
          actionDayID = nil
        }
      }
      Button("Record as skipped", role: .destructive) {
        skipDay(day.id)
        actionDayID = nil
      }
      if day.state != .planned || day.completedSessionID != nil || day.movedToDate != nil {
        Button("Clear this day's record") {
          clearRecord(day.id)
          actionDayID = nil
        }
      }
      Button("Cancel", role: .cancel) { actionDayID = nil }
    }
  }

  // MARK: - Cards

  private func statusCard(_ plan: WeekPlan, _ evaluation: WeekPlanEvaluation) -> some View {
    let counts = evaluation.counts
    let relaxed = plan.mode.relaxesMissedSessions
    return VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Week of \(WeekDesignerText.shortDate(plan.weekStart))").forgeTitle()
        Text(planModeLine(plan)).forgeLabel()
      }
      HStack(alignment: .top, spacing: 0) {
        summaryCell("Completed", counts.completed, Theme.metricSets)
        summaryDivider
        summaryCell("Remaining", counts.remaining, Theme.metricTime)
        summaryDivider
        summaryCell(relaxed ? "Not done" : "Missed", counts.missed, missedColor(plan))
      }
      Divider().overlay(Theme.ring)
      if let adherence = evaluation.adherence {
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text("Adherence").forgeOverline()
            Spacer()
            MetricValue(
              value: "\(Int((adherence * 100).rounded()))", unit: "%", size: 20,
              color: Theme.metricSets)
          }
          WeekDesignerBar(fraction: adherence, color: Theme.metricSets)
          Text("Completed share of the sessions that have come due: \(counts.completed) of \(counts.completed + counts.missed).")
            .forgeCaption()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Adherence")
        .accessibilityValue("\(counts.completed) of \(counts.completed + counts.missed) due sessions completed")
      } else {
        Text("Adherence appears once a session has either been completed or missed — a percentage with nothing settled would be invented.")
          .forgeCaption()
      }
      if evaluation.atRisk > 0 {
        Label(
          "\(evaluation.atRisk) session\(L10n.pluralSuffix(evaluation.atRisk)) still owed today",
          systemImage: "clock"
        )
        .forgeCaption()
        .foregroundStyle(Theme.metricTime)
      }
      if counts.beforeEnrollment > 0 {
        Text(
          "\(counts.beforeEnrollment) day\(L10n.pluralSuffix(counts.beforeEnrollment)) before \(WeekDesignerText.shortDate(plan.enrollmentDate)) are not counted — the plan had not started yet."
        )
        .forgeCaption()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func staleWeekCard(_ plan: WeekPlan) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("This plan is not this week", systemImage: "calendar.badge.clock")
        .forgeBodyStrong()
        .foregroundStyle(Theme.metricTime)
      Text(
        "You are looking at the week of \(WeekDesignerText.shortDate(plan.weekStart)). Regenerate to lay out the week starting \(WeekDesignerText.shortDate(currentWeekStart))."
      )
      .forgeCaption()
      Button("Regenerate for this week") { showsRegenerate = true }
        .buttonStyle(PillButtonStyle(minHeight: 44))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card(fill: Theme.metricTime.opacity(0.08))
  }

  private func daysCard(_ plan: WeekPlan, _ evaluation: WeekPlanEvaluation) -> some View {
    let days = plan.days.sorted { $0.date < $1.date }
    return VStack(alignment: .leading, spacing: 10) {
      Text("Sessions").forgeSection()
      VStack(spacing: 0) {
        ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
          dayRow(day, in: plan)
          if index < days.count - 1 { Divider().overlay(Theme.ring) }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card(padding: 16)
  }

  private func dayRow(_ day: WeekPlanDay, in plan: WeekPlan) -> some View {
    let evaluated = evaluationFor(day, in: plan)
    let state = evaluated.state
    let symbol = stateSymbol(state, reason: evaluated.reason)
    let color = stateColor(state, reason: evaluated.reason, plan: plan)
    let label = stateLabel(state, reason: evaluated.reason, plan: plan)
    let detail = stateDetail(state, reason: evaluated.reason)
    return Button {
      actionDayID = day.id
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 10) {
          VStack(alignment: .leading, spacing: 2) {
            Text(WeekDesignerText.shortDate(day.date)).forgeBodyStrong()
            Text(localizedDayName(day.sessionName)).forgeLabel()
          }
          Spacer(minLength: 8)
          WeekDesignerStateChip(label: label, detail: detail, color: color, symbol: symbol)
        }
        Text(dayMetaLine(day, plan: plan)).forgeCaption()
        if let note = moveNote(day) {
          Text(note).forgeCaption()
        }
        if state != .completed, let session = recordedSession(on: day.date, in: plan) {
          Label(
            "Recorded \(localizedDayName(session.dayName)) on this day",
            systemImage: "checkmark.circle"
          )
          .forgeCaption()
          .foregroundStyle(Theme.metricSets)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: 56)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(dayAccessibilityLabel(day, evaluated, label: label, detail: detail, plan: plan))
    .accessibilityHint("Double tap to reschedule, skip or record this session")
    .accessibilityAction(named: "Move to another day") {
      actionDayID = nil
      movingDay = day
    }
    .accessibilityAction(named: "Record as skipped") { skipDay(day.id) }
  }

  private func planCheckCard(_ issues: [WeekPlanValidationIssue]) -> some View {
    let errors = issues.filter { $0.severity == .error }.count
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: errors > 0 ? "exclamationmark.triangle.fill" : "info.circle")
          .foregroundStyle(errors > 0 ? Theme.negative : Theme.textSecondary)
        Text("Plan check").forgeSection()
      }
      Text(
        errors > 0
          ? "\(errors) problem\(L10n.pluralSuffix(errors)) would make this week evaluate incorrectly."
          : "Nothing here blocks evaluation, but these are worth a look."
      )
      .forgeCaption()
      ForEach(issues.prefix(3)) { issue in
        VStack(alignment: .leading, spacing: 2) {
          Text(issueTitle(issue)).forgeBodyStrong()
          Text(issue.message).forgeCaption()
        }
      }
      if issues.count > 3 {
        Text("+\(issues.count - 3) more").forgeCaption()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func rulesCard(_ plan: WeekPlan) -> some View {
    let hours = plan.graceWindow / 3600
    return VStack(alignment: .leading, spacing: 10) {
      Text("How this week is judged").forgeSection()
      ruleRow(
        "circle.dashed", "Remaining",
        "A session is remaining until its day ends. It is only missed after midnight plus \(Fmt.num(hours)) h, so a session you have not done yet is never reported as missed.",
        Theme.metricTime)
      ruleRow(
        "exclamationmark.circle", plan.mode.relaxesMissedSessions ? "Not done" : "Missed",
        plan.mode.relaxesMissedSessions
          ? "\(plan.mode.name) weeks are allowed to fall short — a shortfall is shown as not done, never as failure."
          : "Once the grace window closes with nothing recorded, the session counts as missed in the adherence figure.",
        missedColor(plan))
      ruleRow(
        "arrow.right.circle", "Moved",
        "Moving a session records where it went. Both days stay in the week; nothing is silently deleted.",
        Theme.metricTime)
      ruleRow(
        "minus.circle", "Skipped",
        "Skipping is only ever recorded by you, so it reads as a decision rather than as a missed session.",
        Theme.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func ruleRow(_ symbol: String, _ title: String, _ text: String, _ color: Color) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol).foregroundStyle(color).frame(width: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeBodyStrong()
        Text(text).forgeCaption()
      }
    }
  }

  private var emptyCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("No plan yet").forgeSection()
      Text("A week plan appears once your profile is loaded. It is built from your program, gym and time budget.")
        .forgeCaption()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  // MARK: - Save bar

  private var saveBar: some View {
    VStack(spacing: 6) {
      if isDirty {
        Text("Unsaved changes").forgeCaption()
      } else if let savedNote {
        Text(savedNote).forgeCaption()
      } else {
        Text("All changes saved").forgeCaption()
      }
      Button("Save week plan") { save() }
        .buttonStyle(PillButtonStyle())
        .disabled(!isDirty || draft == nil)
        .opacity(isDirty && draft != nil ? 1 : 0.45)
    }
    .padding(.horizontal, Theme.barMargin)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(Theme.page.opacity(0.92))
    .background(.ultraThinMaterial)
  }

  private var optionsMenu: some View {
    Menu {
      Button {
        showsRegenerate = true
      } label: {
        Label("Regenerate from current plan", systemImage: "arrow.clockwise")
      }
      Button {
        showsReset = true
      } label: {
        Label("Reset recorded states", systemImage: "eraser")
      }
      if isDirty {
        Button(role: .destructive) {
          draft = persisted
          savedNote = nil
        } label: {
          Label("Discard changes", systemImage: "arrow.uturn.backward")
        }
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .accessibilityLabel("Week plan options")
  }

  // MARK: - Shared pieces

  private func summaryCell(_ title: String, _ value: Int, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title).forgeOverline()
      MetricValue(value: "\(value)", size: 26, color: color)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue("\(value)")
  }

  private var summaryDivider: some View {
    Rectangle().fill(Theme.ring).frame(width: 1, height: 34)
  }

  private func planModeLine(_ plan: WeekPlan) -> String {
    let open = plan.days.filter { !$0.state.isSettled }
    let budget = (open.isEmpty ? plan.days : open).map(\.timeBudgetMinutes).max() ?? 0
    let gym = plan.days.compactMap(\.gymProfileName).first ?? "No gym set"
    return "\(plan.mode.name) week · \(gym) · \(budget) min sessions"
  }

  private func dayMetaLine(_ day: WeekPlanDay, plan: WeekPlan) -> String {
    let gym = day.gymProfileName ?? "No gym set"
    return
      "\(gym) · \(day.timeBudgetMinutes) min · \(day.exerciseIDs.count) exercises · \(day.mode.name)"
  }

  private func moveNote(_ day: WeekPlanDay) -> String? {
    if let destination = day.movedToDate {
      return "Moved to \(WeekDesignerText.shortDate(destination))"
    }
    if let origin = day.movedFromDate {
      return "Moved here from \(WeekDesignerText.shortDate(origin))"
    }
    if !day.receivedSessionIDs.isEmpty {
      let count = day.receivedSessionIDs.count
      return "Also holds \(count) moved session\(count == 1 ? "" : "s") on this day"
    }
    return nil
  }

  private func missedColor(_ plan: WeekPlan) -> Color {
    plan.mode.relaxesMissedSessions ? Theme.textSecondary : Theme.negative
  }

  private func stateColor(_ state: WeekPlanDayState, reason: WeekPlanDayStatusReason, plan: WeekPlan)
    -> Color
  {
    if reason == .beforeEnrollment { return Theme.textTertiary }
    switch state {
    case .completed: return Theme.metricSets
    case .remaining: return Theme.metricTime
    case .missed: return missedColor(plan)
    case .moved: return Theme.metricTime
    case .skipped: return Theme.textSecondary
    case .planned: return Theme.textTertiary
    }
  }

  private func stateSymbol(_ state: WeekPlanDayState, reason: WeekPlanDayStatusReason) -> String {
    if reason == .beforeEnrollment { return "calendar" }
    switch state {
    case .completed: return "checkmark.circle.fill"
    case .remaining: return reason == .dueToday ? "clock" : "calendar"
    case .missed: return "exclamationmark.circle"
    case .moved: return "arrow.right.circle"
    case .skipped: return "minus.circle"
    case .planned: return "circle"
    }
  }

  private func stateLabel(_ state: WeekPlanDayState, reason: WeekPlanDayStatusReason, plan: WeekPlan)
    -> String
  {
    if reason == .beforeEnrollment { return "Not tracked" }
    switch state {
    case .completed: return "Completed"
    case .remaining: return reason == .dueToday ? "Due today" : "Remaining"
    case .missed: return plan.mode.relaxesMissedSessions ? "Not done" : "Missed"
    case .moved: return "Moved"
    case .skipped: return "Skipped"
    case .planned: return "Planned"
    }
  }

  private func stateDetail(_ state: WeekPlanDayState, reason: WeekPlanDayStatusReason) -> String? {
    switch state {
    case .remaining:
      switch reason {
      case .upcoming: return "Not started yet"
      case .dueToday: return "Still open"
      case .withinGraceWindow: return "Grace window open"
      default: return nil
      }
    case .missed: return "Grace window closed"
    case .moved: return "Rescheduled"
    case .skipped: return "Your choice"
    case .completed: return "Recorded"
    case .planned: return "No record yet"
    }
  }

  private func dayAccessibilityLabel(
    _ day: WeekPlanDay, _ evaluated: WeekPlanDayEvaluation, label: String, detail: String?,
    plan: WeekPlan
  ) -> String {
    var parts: [String] = [
      WeekDesignerText.longDate(day.date),
      localizedDayName(day.sessionName),
      label,
    ]
    if let detail { parts.append(detail) }
    parts.append(day.gymProfileName ?? "No gym set")
    parts.append("\(day.timeBudgetMinutes) minute session")
    parts.append("\(day.mode.name) week")
    if !evaluated.isCountedInPlan {
      parts.append("Before this plan started, so it is not counted")
    }
    return parts.joined(separator: ". ")
  }

  private func validationIssues(_ plan: WeekPlan) -> [WeekPlanValidationIssue]? {
    let issues = plan.validation(now: .now).issues
    return issues.isEmpty ? nil : issues
  }

  private func issueTitle(_ issue: WeekPlanValidationIssue) -> String {
    guard let dayID = issue.dayID, let day = draft?.days.first(where: { $0.id == dayID }) else {
      return "This week"
    }
    return WeekDesignerText.shortDate(day.date)
  }
}

// MARK: - Pieces

private struct WeekDesignerStateChip: View {
  let label: String
  let detail: String?
  let color: Color
  let symbol: String

  var body: some View {
    VStack(alignment: .trailing, spacing: 3) {
      HStack(spacing: 5) {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
        Text(label).forge(12, .semibold)
      }
      .foregroundStyle(color)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Capsule().fill(color.opacity(0.14)))
      if let detail {
        Text(detail).forgeOverline().multilineTextAlignment(.trailing)
      }
    }
    .accessibilityHidden(true)
  }
}

private struct WeekDesignerBar: View {
  let fraction: Double
  let color: Color

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Capsule().fill(Theme.track)
        Capsule().fill(color)
          .frame(width: geometry.size.width * min(max(fraction, 0), 1))
      }
    }
    .frame(height: 8)
    .accessibilityHidden(true)
  }
}

private struct WeekDesignerMoveSheet: View {
  @Environment(\.dismiss) private var dismiss
  let plan: WeekPlan?
  let day: WeekPlanDay
  let onMove: (Date) -> Void

  private var calendar: Calendar { plan?.resolvedCalendar(Calendar.current) ?? .current }

  private var destinations: [Date] {
    let start = calendar.startOfDay(for: plan?.weekStart ?? day.date)
    return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
  }

  private var sourceStart: Date { calendar.startOfDay(for: day.date) }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Theme.groupGap) {
          VStack(alignment: .leading, spacing: 6) {
            Text(localizedDayName(day.sessionName)).forgeTitle()
            Text("Currently scheduled \(WeekDesignerText.longDate(day.date)). Pick the day it should move to.")
              .forgeLabel()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
          VStack(spacing: 0) {
            ForEach(Array(destinations.enumerated()), id: \.element) { index, date in
              destinationRow(date)
              if index < destinations.count - 1 { Divider().overlay(Theme.ring) }
            }
          }
          .card(padding: 16)
          Text(
            "If the destination already has a session, both sessions share that day. Nothing is deleted, and the moved session keeps its history."
          )
          .forgeCaption()
        }
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 24)
      }
      .background(Theme.page)
      .navigationTitle("Move session")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
    }
  }

  private func destinationRow(_ date: Date) -> some View {
    let isSource = calendar.isDate(date, inSameDayAs: sourceStart)
    let occupied = plan?.day(on: date, calendar: calendar)
    let existing = occupied.map { localizedDayName($0.sessionName) }
    return Button {
      onMove(date)
      dismiss()
    } label: {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(WeekDesignerText.shortDate(date)).forgeBodyStrong()
          Text(existing.map { "Shares the day with \($0)" } ?? "No session planned")
            .forgeCaption()
        }
        Spacer(minLength: 8)
        if isSource {
          Text("Current day").forgeCaption()
        } else {
          Image(systemName: "arrow.right.circle").foregroundStyle(Theme.accent)
        }
      }
      .frame(minHeight: 56)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .disabled(isSource)
    .accessibilityLabel(
      "\(WeekDesignerText.longDate(date)). \(existing.map { "Shares the day with \($0)" } ?? "No session planned")")
    .accessibilityHint(isSource ? "This is the current day" : "Double tap to move the session here")
  }
}

private enum WeekDesignerText {
  static func shortDate(_ date: Date) -> String {
    Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated).locale(L10n.locale)
      .format(date)
  }

  static func longDate(_ date: Date) -> String {
    Date.FormatStyle().weekday(.wide).day().month(.wide).locale(L10n.locale).format(date)
  }
}
