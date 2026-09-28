import ForgeCore
import SwiftData
import SwiftUI

struct ProgramRoadmapView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \DecisionLogEntry.date, order: .reverse) private var decisions: [DecisionLogEntry]
  @Namespace private var weekSelection
  @State private var selectedWeek: Int?
  @State private var grown = false
  @State private var tool: Tool?

  private enum Tool: Hashable, Identifiable {
    case goal, importShare, library
    var id: Self { self }
  }

  private struct WeekStats: Identifiable {
    let week: Int
    let planned: Int
    let logged: Int
    /// Logged for done weeks, planned otherwise — the number the column shows.
    let value: Int
    /// First trained session's date; `nil` for a past week with no sessions (no date label).
    let start: Date?
    var id: Int { week }
  }

  private var profile: UserProfile? { profiles.first }
  private var currentWeek: Int { profile?.currentWeek(sessions: sessions) ?? 1 }
  private var peakWeek: Int { Mesocycle.deloadWeek - 1 }
  private var selection: Int { selectedWeek ?? currentWeek }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if let profile {
          VStack(alignment: .leading, spacing: 0) {
            Text("\(goalLabel) · \(daysLabel(profile))")
              .forge(13, .semibold)
              .foregroundStyle(Theme.textSecondary)
            header
              .padding(.top, 6)
            Text(lede)
              .forge(15)
              .foregroundStyle(Theme.textSecondary)
              .padding(.top, 6)
            roadStrip(profile)
              .padding(.top, 18)
            setsChart
              .padding(.top, 22)
            ZStack(alignment: .topLeading) { weekPanel(profile) }
          }
          .padding(.horizontal, Theme.margin)
        }
        if !decisions.isEmpty { Theme.pageGrey.frame(height: 8) }
        adjustments
          .padding(.horizontal, Theme.margin)
      }
      .padding(.bottom, 32)
    }
    .background(Theme.page)
    .navigationTitle("Program roadmap")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      ToolbarItem(placement: .topBarLeading) {
        Menu {
          Button("Goal roadmap", systemImage: "target") { tool = .goal }
          Button("Import or share program", systemImage: "square.and.arrow.down.on.square") {
            tool = .importShare
          }
          Button("Routine library", systemImage: "doc.on.doc") { tool = .library }
        } label: {
          Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Plan tools")
        .accessibilityIdentifier("roadmap.tools")
      }
    }
    .navigationDestination(item: $tool) { tool in
      switch tool {
      case .goal: GoalRoadmapView()
      case .importShare: ProgramImportAnalysisView()
      case .library: RoutineLibraryView()
      }
    }
    .sensoryFeedback(.selection, trigger: selectedWeek)
    .onAppear { grown = true }
  }

  // MARK: hero

  private var goalLabel: String {
    switch Goal(rawValue: profile?.goal ?? "") ?? .hypertrophy {
    case .hypertrophy: return String(localized: "Build muscle", bundle: L10n.bundle)
    case .strength: return String(localized: "Move more weight", bundle: L10n.bundle)
    case .both: return String(localized: "Size and strength", bundle: L10n.bundle)
    }
  }

  private func daysLabel(_ profile: UserProfile) -> String {
    String(localized: "\(profile.daysPerWeek) days a week", bundle: L10n.bundle)
  }

  private var lede: String {
    if currentWeek == Mesocycle.deloadWeek {
      return String(localized: "Deload week. Recover before the next block.", bundle: L10n.bundle)
    }
    if currentWeek == peakWeek {
      return String(localized: "Peak week. A deload follows.", bundle: L10n.bundle)
    }
    if currentWeek == peakWeek - 1 {
      return String(localized: "Peak week next, then a deload.", bundle: L10n.bundle)
    }
    return String(localized: "Volume builds each week, then a deload.", bundle: L10n.bundle)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("Week \(currentWeek)")
        .forge(44, .bold, tracking: -1)
        .foregroundStyle(Theme.text)
        .monospacedDigit()
      Text("of \(Mesocycle.weeks)")
        .forge(22, .medium)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Week \(currentWeek) of \(Mesocycle.weeks)"))
    .accessibilityAddTraits(.isHeader)
    .accessibilityIdentifier("roadmap.header")
  }

  // MARK: road strip

  /// Block number of the roadmap's road strip. A block with no logged session yet (fresh
  /// mesoStart after completed history) still counts as its own block.
  private func blockNumber(_ profile: UserProfile) -> Int {
    max(
      1,
      ProgressData.mesoBlockCount(sessions)
        + (profile.mesoSessions(sessions) == 0 && sessions.contains(where: \.completed) ? 1 : 0))
  }

  private func nextBlockStart(_ profile: UserProfile) -> Date {
    let calendar = TrainingMetrics.reportingCalendar()
    let current = TrainingMetrics.reportingWeek(containing: .now, calendar: calendar).start
    return calendar.date(
      byAdding: .day, value: (Mesocycle.weeks - currentWeek + 1) * 7, to: current) ?? current
  }

  /// Sessions the current block still holds after an early deload: what was trained before
  /// the deload plus the deload week's `daysPerWeek`; a full block otherwise.
  private func roadStripTotal(_ profile: UserProfile) -> Int {
    guard let deloadStart = profile.deloadStartedAt else {
      return profile.daysPerWeek * Mesocycle.weeks
    }
    let before = sessions.filter {
      $0.completed && $0.date >= profile.mesoStart && $0.date < deloadStart
    }.count
    return before + profile.daysPerWeek
  }

  private func roadStrip(_ profile: UserProfile) -> some View {
    let n = blockNumber(profile)
    let trained = profile.mesoSessions(sessions)
    let done = max(0, trained + profile.mesoSessionOffset)
    let total = roadStripTotal(profile)
    return HStack(spacing: 4) {
      if n > 1 {
        segment(
          fraction: 1,
          name: String(localized: "Block \(n - 1)", bundle: L10n.bundle),
          status: String(localized: "Complete", bundle: L10n.bundle),
          isCurrent: false)
      }
      segment(
        fraction: total > 0 ? Double(done) / Double(total) : 0,
        name: String(localized: "Block \(n)", bundle: L10n.bundle),
        status: String(localized: "\(trained) of \(total) sessions", bundle: L10n.bundle),
        isCurrent: true)
      segment(
        fraction: 0,
        name: String(localized: "Block \(n + 1)", bundle: L10n.bundle),
        status: String(
          localized: "Starts \(nextBlockStart(profile).formatted(.dateTime.month(.abbreviated).day()))",
          bundle: L10n.bundle),
        isCurrent: false)
    }
    .accessibilityElement(children: .combine)
  }

  private func segment(fraction: Double, name: String, status: String, isCurrent: Bool) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule().fill(Theme.track)
          Capsule()
            .fill(.mark(Theme.gradExercise))
            .frame(width: geometry.size.width * min(1, max(0, fraction)))
        }
      }
      .frame(height: 6)
      Text(name)
        .forge(12, .semibold)
        .foregroundStyle(isCurrent ? Theme.text : Theme.textSecondary)
        .padding(.top, 8)
      Text(status)
        .forge(12)
        .foregroundStyle(Theme.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: sets-per-week chart (the week picker)

  private var weekStats: [WeekStats] {
    guard let profile else { return [] }
    let accepted = acceptedWeekDays(profile)
    return (1...Mesocycle.weeks).map { week in
      let planned: Int
      if week == currentWeek, let accepted {
        planned = accepted.reduce(0) { $0 + $1.plannedSetCount }
      } else {
        planned = Program.week(week, profile: profile.profileInput)
          .flatMap(\.exercises).reduce(0) { $0 + $1.sets }
      }
      let logged = loggedSets(week, profile: profile)
      return WeekStats(
        week: week,
        planned: planned,
        logged: logged,
        value: week < currentWeek ? logged : planned,
        start: weekStart(week, profile: profile))
    }
  }

  /// Completed sessions of this block in `week`, in date order — what was actually trained.
  private func completedSessions(week: Int, profile: UserProfile) -> [WorkoutSession] {
    sessions
      .filter { $0.completed && $0.date >= profile.mesoStart && $0.week == week }
      .sorted { $0.date < $1.date }
  }

  private func loggedSets(_ week: Int, profile: UserProfile) -> Int {
    guard week <= currentWeek else { return 0 }
    return TrainingMetrics.sets(
      completedSessions(week: week, profile: profile).metricSets(),
      in: nil,
      scope: .allRecorded
    ).count
  }

  /// Column date for a week, following the training: past weeks anchor to the date of their
  /// first completed session. `nil` (a past week with nothing trained) shows no date label.
  private func weekStart(_ week: Int, profile: UserProfile) -> Date? {
    if week < currentWeek {
      return completedSessions(week: week, profile: profile).first?.date
    }
    let calendar = TrainingMetrics.reportingCalendar()
    let now = TrainingMetrics.reportingWeek(containing: .now, calendar: calendar).start
    let anchor: Date
    if let first = completedSessions(week: currentWeek, profile: profile).first {
      anchor = first.date
    } else {
      // Clamp: without it, a week advanced by session count can anchor before the previous
      // week's first session, putting the column dates backwards.
      let lastTrained = sessions
        .filter { $0.completed && $0.date >= profile.mesoStart && $0.week < currentWeek }
        .map(\.date).max()
      let floor = lastTrained.flatMap {
        calendar.date(byAdding: .day, value: 1, to: $0).map { calendar.startOfDay(for: $0) }
      }
      let nowStart = calendar.startOfDay(for: now)
      anchor = max(nowStart, floor ?? nowStart)
    }
    return calendar.date(byAdding: .day, value: (week - currentWeek) * 7, to: anchor)
  }

  private var setsChart: some View {
    let stats = weekStats
    let maxValue = max(1, stats.map(\.value).max() ?? 1)
    return VStack(alignment: .leading, spacing: 0) {
      Text("Sets per week")
        .forge(13)
        .foregroundStyle(Theme.textSecondary)
      HStack(alignment: .bottom, spacing: 0) {
        ForEach(stats) { stat in
          weekColumn(stat, maxValue: maxValue)
        }
      }
      .padding(.top, 10)
    }
  }

  private func weekColumn(_ stat: WeekStats, maxValue: Int) -> some View {
    let selected = selection == stat.week
    let entrance: Animation? =
      reduceMotion ? nil : .easeOut(duration: 0.5).delay(Double(stat.week - 1) * 0.06)
    // A past week with nothing logged reads as history: its "0" never takes the selected tint.
    let emptyPast = stat.week < currentWeek && stat.logged == 0
    return Button {
      guard selection != stat.week else { return }
      withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { selectedWeek = stat.week }
    } label: {
      VStack(spacing: 0) {
        Text("\(stat.value)")
          .forge(13, .semibold)
          .monospacedDigit()
          .foregroundStyle(selected && !emptyPast ? Theme.text : Theme.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .padding(.bottom, 6)
          .opacity(grown || reduceMotion ? 1 : 0)
          .animation(entrance, value: grown)
        chartBar(stat, maxValue: maxValue)
          .frame(height: 100, alignment: .bottom)
        Rectangle()
          .fill(Theme.ring)
          .frame(height: 1)
        ZStack {
          if let start = stat.start {
            Text(start.formatted(.dateTime.month(.abbreviated).day()))
              .forge(12)
              .monospacedDigit()
              .foregroundStyle(selected ? Theme.text : Theme.textSecondary)
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
        }
        .frame(height: 16, alignment: .top)
        .padding(.top, 9)
        ZStack { weekStatusLabel(stat.week) }
          .frame(height: 16)
          .padding(.top, 2)
      }
      .frame(maxWidth: .infinity)
      .contentShape(Rectangle())
      .background {
        if selected {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.innerSurface)
            .matchedGeometryEffect(id: "roadmap.week.selection", in: weekSelection)
            .padding(.horizontal, 2)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Week \(stat.week), \(stat.value) sets"))
    .accessibilityValue(stat.week == currentWeek ? Text("This week") : Text(""))
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("roadmap.week.\(stat.week)")
  }

  @ViewBuilder
  private func weekStatusLabel(_ week: Int) -> some View {
    // History carries no status: after an early deload the passed "Peak" week is just a week.
    if week >= currentWeek {
      if week == currentWeek {
        Text("Now").forge(12, .semibold).foregroundStyle(Theme.text)
          .lineLimit(1).minimumScaleFactor(0.7)
      } else if week == peakWeek {
        Text("Peak").forge(12).foregroundStyle(Theme.textSecondary)
          .lineLimit(1).minimumScaleFactor(0.7)
      } else if week == Mesocycle.deloadWeek {
        Text("Deload").forge(12).foregroundStyle(Theme.textSecondary)
          .lineLimit(1).minimumScaleFactor(0.7)
      }
    }
  }

  /// One chart bar: done weeks solid, this week an outline filling as sets are logged,
  /// planned weeks dashed. Entrance grows each bar from zero, left to right.
  private func chartBar(_ stat: WeekStats, maxValue: Int) -> some View {
    // A current week with nothing planned but sets logged reads as done: solid, logged height.
    let solidCurrent = stat.week == currentWeek && stat.planned == 0 && stat.logged > 0
    let full = 100.0 * Double(solidCurrent ? stat.logged : stat.value) / Double(maxValue)
    let grownHeight = grown || reduceMotion ? full : 0
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: 8, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 8,
      style: .continuous)
    return Group {
      if stat.week < currentWeek || solidCurrent {
        shape.fill(.mark(Theme.gradExercise, startPoint: .bottom, endPoint: .top))
      } else if stat.week == currentWeek {
        ZStack(alignment: .bottom) {
          Rectangle().fill(
            colorScheme == .dark ? Color.clear : Theme.gradExercise[0].opacity(0.12))
          if stat.logged > 0 {
            Rectangle()
              .fill(.mark(Theme.gradExercise, startPoint: .bottom, endPoint: .top))
              .frame(
                height: grown || reduceMotion
                  ? full * min(1, Double(stat.logged) / Double(max(stat.planned, 1))) : 0)
          }
        }
        .clipShape(shape)
        .overlay(shape.stroke(Theme.gradExercise[0], lineWidth: 1.5))
      } else {
        shape.stroke(
          Theme.gradExercise[0].opacity(0.75),
          style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
      }
    }
    .frame(width: 28, height: grownHeight)
    .clipped()
    .animation(
      reduceMotion ? nil : .easeOut(duration: 0.5).delay(Double(stat.week - 1) * 0.06),
      value: grown)
  }

  // MARK: selected-week panel

  @ViewBuilder
  private func weekPanel(_ profile: UserProfile) -> some View {
    let week = selection
    VStack(alignment: .leading, spacing: 0) {
      panelHeader(week, profile: profile)
      if let note = panelNote(week) {
        Text(note)
          .forge(14)
          .foregroundStyle(Theme.textSecondary)
          .padding(.top, 2)
          .padding(.trailing, 8)
      }
      weekRows(week, profile: profile)
      panelFooter(week)
    }
    .id(week)
    .transition(.opacity)
  }

  private func panelHeader(_ week: Int, profile: UserProfile) -> some View {
    let calendar = TrainingMetrics.reportingCalendar()
    let start = weekStart(week, profile: profile)
    let end = start.flatMap { calendar.date(byAdding: .day, value: 6, to: $0) }
    return HStack(alignment: .firstTextBaseline) {
      panelTitle(week)
      Spacer(minLength: 8)
      if let start, let end {
        Text((start..<end).formatted(.interval.month(.abbreviated).day()))
          .forge(14)
          .monospacedDigit()
          .foregroundStyle(Theme.textSecondary)
      }
    }
    .padding(.top, 22)
  }

  @ViewBuilder
  private func panelTitle(_ week: Int) -> some View {
    if week == currentWeek {
      Text("This week").forge(18, .semibold).foregroundStyle(Theme.text)
    } else if week == peakWeek {
      Text("Week \(week) · Peak").forge(18, .semibold).foregroundStyle(Theme.text)
    } else if week == Mesocycle.deloadWeek {
      Text("Week \(week) · Deload").forge(18, .semibold).foregroundStyle(Theme.text)
    } else {
      Text("Week \(week)").forge(18, .semibold).foregroundStyle(Theme.text)
    }
  }

  private func panelNote(_ week: Int) -> String? {
    if week == Mesocycle.deloadWeek {
      let cap = Mesocycle.deloadRPECap.formatted(.number.precision(.fractionLength(0)))
      return String(
        localized: "Half the sets, effort capped at RPE \(cap), so fatigue can fall before the next block.",
        bundle: L10n.bundle)
    }
    if week == peakWeek && week != currentWeek {
      return String(
        localized: "The most volume of the block, added only when recovery and performance allow.",
        bundle: L10n.bundle)
    }
    return nil
  }

  @ViewBuilder
  private func weekRows(_ week: Int, profile: UserProfile) -> some View {
    if week == currentWeek, let accepted = acceptedWeekDays(profile), let plan = profile.weekPlan {
      ForEach(accepted) { day in
        acceptedRow(day, plan: plan, profile: profile)
        if day.id != accepted.last?.id {
          Divider().overlay(Theme.ring).padding(.leading, 70)
        }
      }
    } else if week < currentWeek {
      // History shows what was trained: one row per completed session of that week.
      let completed = completedSessions(week: week, profile: profile)
      if completed.isEmpty {
        Text("No sessions logged this week", bundle: L10n.bundle)
          .forge(14)
          .foregroundStyle(Theme.textSecondary)
          .padding(.top, 12)
          .padding(.bottom, 18)
      } else {
        let template = Program.week(week, profile: profile.profileInput)
        ForEach(completed) { session in
          loggedRow(session, templateDay: template.first { $0.name == session.dayName })
          if session !== completed.last {
            Divider().overlay(Theme.ring).padding(.leading, 70)
          }
        }
      }
    } else {
      // Positional: `Program.split` legitimately repeats day names within a week, so the
      // name is not a unique id here.
      let days = Program.week(week, profile: profile.profileInput)
      let logged = matchedSessionDates(week, days: days, profile: profile)
      ForEach(Array(days.enumerated()), id: \.offset) { index, day in
        NavigationLink {
          SessionMusclePreviewView(day: day, showsDoneButton: false)
        } label: {
          rowContent(
            exercise: day.exercises.first?.exercise,
            name: localizedDayName(day.name),
            focus: focusLine(day),
            caption: nil,
            showsChevron: true,
            trailing: { doneTrailing(logged[index]) })
        }
        .buttonStyle(RowPressStyle())
        if index < days.count - 1 {
          Divider().overlay(Theme.ring).padding(.leading, 70)
        }
      }
    }
  }

  /// Completed sessions of this block in `week`, matched to day rows in date order so
  /// each session marks at most one row. Keyed by row position — `Program.split`
  /// legitimately repeats day names within a week, and each row needs its own match.
  private func matchedSessionDates(_ week: Int, days: [PlannedDay], profile: UserProfile)
    -> [Int: Date]
  {
    guard week <= currentWeek else { return [:] }
    var used: Set<ObjectIdentifier> = []
    var dates: [Int: Date] = [:]
    for (index, day) in days.enumerated() {
      if let hit = sessions.first(where: {
        $0.completed && $0.date >= profile.mesoStart && $0.week == week
          && $0.dayName == day.name && !used.contains(ObjectIdentifier($0))
      }) {
        used.insert(ObjectIdentifier(hit))
        dates[index] = hit.date
      }
    }
    return dates
  }

  /// One trained session of a past week. It links to the template day of the same name when
  /// that week's split still contains it; otherwise it is a plain row without a chevron.
  @ViewBuilder
  private func loggedRow(_ session: WorkoutSession, templateDay: PlannedDay?) -> some View {
    let content = rowContent(
      exercise: firstLoggedExercise(session),
      name: localizedDayName(session.dayName),
      focus: loggedFocus(session),
      caption: nil,
      showsChevron: templateDay != nil,
      trailing: { doneTrailing(session.date) })
    if let templateDay {
      NavigationLink {
        SessionMusclePreviewView(day: templateDay, showsDoneButton: false)
      } label: { content }
        .buttonStyle(RowPressStyle())
    } else {
      content
    }
  }

  /// The exercise of the session's first logged set — the tile of what was actually trained.
  private func firstLoggedExercise(_ session: WorkoutSession) -> Exercise? {
    session.sets.min {
      $0.loggedAt != $1.loggedAt ? $0.loggedAt < $1.loggedAt : $0.setIndex < $1.setIndex
    }.flatMap { ExerciseDB.find($0.exerciseID) }
  }

  /// The two primary muscles that carried the most logged sets, e.g. "Quads + Glutes".
  private func loggedFocus(_ session: WorkoutSession) -> String {
    var counts: [Muscle: Int] = [:]
    for set in session.sets {
      guard let exercise = ExerciseDB.find(set.exerciseID) else { continue }
      counts[exercise.primary, default: 0] += 1
    }
    return counts
      .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
      .prefix(2).map(\.key.a11yName).joined(separator: " + ")
  }

  /// One accepted day of the current week. Rows without a trustworthy preview stay
  /// noninteractive and honest rather than linking to a generated detail.
  @ViewBuilder
  private func acceptedRow(_ day: WeekPlanDay, plan: WeekPlan, profile: UserProfile) -> some View {
    let preview = acceptedPreview(day, plan: plan, profile: profile)
    if let preview {
      NavigationLink {
        SessionMusclePreviewView(day: preview, showsDoneButton: false)
      } label: {
        rowContent(
          exercise: preview.exercises.first?.exercise
            ?? day.exerciseIDs.first.flatMap(ExerciseDB.find),
          name: localizedDayName(day.sessionName),
          focus: focusLine(preview),
          caption: nil,
          showsChevron: true,
          trailing: { acceptedTrailing(day) })
      }
      .buttonStyle(RowPressStyle())
    } else {
      rowContent(
        exercise: day.exerciseIDs.first.flatMap(ExerciseDB.find),
        name: localizedDayName(day.sessionName),
        focus: String(
          localized: "\(day.exerciseIDs.count) exercises · \(day.plannedSetCount) sets",
          bundle: L10n.bundle),
        caption: unavailableReason(day, plan: plan, profile: profile),
        showsChevron: false,
        trailing: { acceptedTrailing(day) })
    }
  }

  private func focusLine(_ day: PlannedDay) -> String {
    SessionMusclePreviewView.breakdown(day).prefix(2).map(\.muscle.a11yName)
      .joined(separator: " + ")
  }

  private func rowContent<Trailing: View>(
    exercise: Exercise?,
    name: String,
    focus: String,
    caption: String?,
    showsChevron: Bool,
    @ViewBuilder trailing: () -> Trailing
  ) -> some View {
    HStack(spacing: 14) {
      if let exercise {
        WorkoutArtTile(exercise: exercise, size: 56)
      } else {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Theme.innerSurface)
          .frame(width: 56, height: 56)
      }
      VStack(alignment: .leading, spacing: 3) {
        Text(name).forge(17, .semibold).foregroundStyle(Theme.text)
        Text(focus).forge(14).foregroundStyle(Theme.textSecondary)
        if let caption {
          Text(caption).forgeCaption()
        }
      }
      Spacer(minLength: 8)
      trailing()
      if showsChevron {
        Image(systemName: "chevron.right")
          .forge(13, .semibold)
          .foregroundStyle(Theme.textTertiary)
      }
    }
    .frame(minHeight: 76)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func acceptedTrailing(_ day: WeekPlanDay) -> some View {
    switch day.state {
    case .completed:
      Image(systemName: "checkmark")
        .forge(13, .semibold)
        .foregroundStyle(Theme.positive)
        .accessibilityLabel(Text("Completed"))
    case .moved:
      if let movedTo = day.movedToDate {
        Text(
          "Moved to \(movedTo.formatted(.dateTime.month(.abbreviated).day()))",
          bundle: L10n.bundle)
          .forge(14)
          .monospacedDigit()
          .foregroundStyle(Theme.textSecondary)
      } else {
        Text("Moved").forge(14).foregroundStyle(Theme.textSecondary)
      }
    case .skipped:
      Text("Skipped").forge(14).foregroundStyle(Theme.textSecondary)
    default:
      if Calendar.current.isDateInToday(day.date) {
        Text("Today").forge(15, .semibold).foregroundStyle(Theme.text)
      } else {
        Text(day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
          .forge(14)
          .monospacedDigit()
          .foregroundStyle(Theme.textSecondary)
      }
    }
  }

  @ViewBuilder
  private func doneTrailing(_ date: Date?) -> some View {
    if let date {
      HStack(spacing: 4) {
        Image(systemName: "checkmark").forge(13, .semibold).foregroundStyle(Theme.positive)
        Text(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
          .forge(14)
          .monospacedDigit()
          .foregroundStyle(Theme.textSecondary)
      }
    }
  }

  @ViewBuilder
  private func panelFooter(_ week: Int) -> some View {
    if week == currentWeek {
      NavigationLink {
        WeekDesignerView()
      } label: {
        HStack(spacing: 2) {
          Text("Edit in Week designer")
          Image(systemName: "chevron.right").forge(13, .semibold)
        }
        .forge(15, .medium)
        .foregroundStyle(Theme.accentText)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("roadmap.weekDesigner")
      .padding(.top, 4)
      .padding(.bottom, 22)
    } else if week > currentWeek {
      Text("Planned, may adapt to your check-ins")
        .forge(14)
        .foregroundStyle(Theme.textSecondary)
        .padding(.top, 4)
        .padding(.bottom, 22)
    }
  }

  // MARK: accepted-week helpers (unchanged logic)

  /// The current week's accepted days, in plan order. Today sums this same list for its
  /// week target, so the roadmap and Today can never disagree about the prescription.
  /// `nil` when no week plan is stored, which keeps the generated template display.
  private func acceptedWeekDays(_ profile: UserProfile) -> [WeekPlanDay]? {
    guard let plan = profile.weekPlan else { return nil }
    let interval = TrainingMetrics.reportingWeek(
      containing: .now, calendar: TrainingMetrics.reportingCalendar())
    return plan.days.filter { TrainingMetrics.contains(interval, $0.date) }
  }

  private func appliedRecord(for day: WeekPlanDay, plan: WeekPlan, profile: UserProfile)
    -> UserProfile.AppliedRoutine?
  {
    profile.appliedRoutines.last {
      $0.planID == plan.id
        && (day.routineApplicationID == nil
          ? $0.planDayID == day.id : $0.id == day.routineApplicationID)
        && $0.blockStart == profile.mesoStart
    }
  }

  /// Preview for an accepted current-week day. Applied rows render the stored
  /// prescription — also once the day is completed — and never a regenerated stand-in;
  /// plain rows fall back to the same generated day Today would train.
  private func acceptedPreview(_ day: WeekPlanDay, plan: WeekPlan, profile: UserProfile) -> PlannedDay? {
    if RoutineAdaptationService.routineDataUnreadable(profile) { return nil }
    if let applicationID = day.routineApplicationID,
      appliedRecord(for: day, plan: plan, profile: profile)?.id != applicationID { return nil }
    if let applied = appliedRecord(for: day, plan: plan, profile: profile) {
      guard applied.acceptanceID == plan.acceptanceID,
        !RoutineAdaptationService.needsReview(day, profile: profile, sessions: sessions)
      else { return nil }
      return RoutineAdaptation.plannedDay(applied.day)
    }
    guard !RoutineAdaptationService.needsReview(day, profile: profile, sessions: sessions)
    else { return nil }
    return RoutineAdaptationService.generatedDay(day, profile: profile, sessions: sessions)
  }

  /// Why an accepted row has no preview. Honest by construction — never a generated
  /// stand-in for a row the lifter needs to review or that cannot be read.
  private func unavailableReason(_ day: WeekPlanDay, plan: WeekPlan, profile: UserProfile) -> String {
    if RoutineAdaptationService.routineDataUnreadable(profile) {
      return String(
        localized: "The saved routine detail can't be read in this version.", bundle: L10n.bundle)
    }
    if appliedRecord(for: day, plan: plan, profile: profile) != nil {
      return String(
        localized:
          "Something changed since this routine was applied — pick it again in the routine library.",
        bundle: L10n.bundle)
    }
    return String(
      localized:
        "This device does not have the accepted session's routine detail. Import its routine file or regenerate the week.",
      bundle: L10n.bundle)
  }

  // MARK: recent adjustments

  @ViewBuilder
  private var adjustments: some View {
    if let latest = decisions.first {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline) {
          Text("Recent adjustments").forge(18, .semibold).foregroundStyle(Theme.text)
          Spacer(minLength: 8)
          NavigationLink {
            RecommendationEffectivenessView()
          } label: {
            Text("See all").forge(15, .medium).foregroundStyle(Theme.accentText)
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("roadmap.adjustments.all")
        }
        .padding(.top, 20)
        .padding(.bottom, 4)
        HStack(spacing: 14) {
          ZStack {
            Circle().fill(Theme.accentTint)
            Image(systemName: "slider.horizontal.3")
              .forge(18)
              .foregroundStyle(Theme.accentText)
          }
          .frame(width: 44, height: 44)
          .frame(width: 56)
          VStack(alignment: .leading, spacing: 2) {
            Text(latest.humanSummary)
              .forge(16, .semibold)
              .foregroundStyle(Theme.text)
              .lineLimit(2)
            Text(latest.date.formatted(date: .abbreviated, time: .omitted))
              .forge(14)
              .foregroundStyle(Theme.textSecondary)
          }
        }
        .frame(minHeight: 72, alignment: .center)
        .padding(.vertical, 12)
      }
    }
  }
}

struct SessionMusclePreviewView: View {
  @Environment(\.dismiss) private var dismiss
  let day: PlannedDay
  var showsDoneButton = true

  struct Emphasis: Identifiable {
    let muscle: Muscle
    let sets: Int
    let fraction: Double
    var id: Muscle { muscle }
  }

  static func breakdown(_ day: PlannedDay) -> [Emphasis] {
    var counts: [Muscle: Int] = [:]
    for planned in day.exercises { counts[planned.exercise.primary, default: 0] += planned.sets }
    let total = max(1, counts.values.reduce(0, +))
    return counts.map {
      Emphasis(muscle: $0.key, sets: $0.value, fraction: Double($0.value) / Double(total))
    }
    .sorted { $0.sets != $1.sets ? $0.sets > $1.sets : $0.muscle.rawValue < $1.muscle.rawValue }
  }

  private var emphasis: [Emphasis] { Self.breakdown(day) }
  private var intensity: [Muscle: Double] {
    let peak = max(1, emphasis.map(\.sets).max() ?? 1)
    return Dictionary(
      uniqueKeysWithValues: emphasis.map { ($0.muscle, Double($0.sets) / Double(peak)) })
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        VStack(alignment: .leading, spacing: 8) {
          Text(localizedDayName(day.name)).forgeTitle()
          Text("Planned set share, not a physiological activation score.").forgeCaption()
          MuscleMapView(intensity: intensity)
            .frame(height: 260)
            .frame(maxWidth: .infinity)
        }
        .card()
        VStack(spacing: 0) {
          ForEach(Array(emphasis.enumerated()), id: \.element.id) { index, item in
            HStack(spacing: 12) {
              Circle().fill(Theme.rampColor(item.fraction)).frame(width: 12, height: 12)
              Text(item.muscle.a11yName).forgeBodyStrong()
              Spacer()
              Text("\(item.sets) sets").forgeCaption().monospacedDigit()
              MetricValue(
                value: "\(Int((item.fraction * 100).rounded()))", unit: "%", size: 20,
                color: Theme.metricSets)
            }
            .padding(.vertical, 10)
            if index < emphasis.count - 1 { Divider().overlay(Theme.ring) }
          }
        }
        .card()
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Muscle emphasis")
    .toolbar {
      if showsDoneButton {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
  }
}
