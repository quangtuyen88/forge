import ForgeCore
import SwiftData
import SwiftUI

// MARK: - Device-local Journey preferences

/// Keys and values for the device-local Journey preferences. The Progress tab owns the
/// Overview/Timeline switch and the timeline owns the month, the filter, the scroll anchor and
/// the photo-detail preference; every one of them lives in this device's `UserDefaults` and is
/// never synced, because they describe how *this phone* draws the lifter's own records.
///
/// The values live in one place so the switch and the timeline cannot disagree about them, and
/// so any other surface that wants the lifter to land on the timeline (a just-saved session, a
/// deep link) only has to write `segmentKey`.
enum JourneyPref {
  /// Which Progress segment is showing. Written by the Progress segmented control, read by
  /// anything that wants the lifter to start on the timeline.
  static let segmentKey = "journey.progress.segment"
  static let segmentOverview = "overview"
  static let segmentTimeline = "timeline"

  /// Remembered timeline position: month (`YYYY-MM`), category selection (sorted raw values,
  /// `,` joined — empty means All), and the day section at the top of the list.
  static let monthKey = "journey.timeline.month"
  static let filterKey = "journey.timeline.filter"
  static let anchorKey = "journey.timeline.anchor"

  /// Device-local photo-detail preference. **Default hidden**: a photo entry never loads image
  /// bytes, and until it is revealed the card hides even the pose label.
  static let photoDetailsKey = "journey.timeline.photoDetails"
}

/// One presentation of the reflection editor. `reflectionID == nil` composes a new note;
/// otherwise the sheet edits the stored note behind that id.
struct ReflectionEditorTarget: Identifiable, Equatable {
  let reflectionID: UUID?
  let day: Date
  var id: String { reflectionID?.uuidString ?? "new-note" }
}

/// The event's own clock time, locale-aware. `nil` when the record carries only a day, so the
/// card shows no time instead of inventing a precision the source never had.
func journeyEventTime(_ event: JourneyEvent) -> String? {
  guard event.precision == .timestamp, let instant = event.instant else { return nil }
  return instant.formatted(.dateTime.hour().minute().locale(L10n.locale))
}

func journeyDayLabel(_ day: Date) -> String {
  day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(L10n.locale))
}

// MARK: - Timeline space

private enum TimelineSpace { static let name = "timeline" }

/// Facts per card, keyed by source id. Filled by `loadFacts(for:)` after every page load.
private struct TimelineFactsCache {
  var workouts: [String: JourneyWorkoutFacts] = [:]
  var changes: [String: JourneyChangeFacts] = [:]
  var noteLinks: [String: String] = [:]
  var bodies: [String: JourneyBodyFacts] = [:]
  var records: [String: [JourneyRecordFact]] = [:]
  var checkIns: [JourneyCheckInFact] = []
  var nextSession: JourneyNextSessionFacts?
}

/// The "<day> is next" facts for the summary sentence: the session Today itself would start.
private struct JourneyNextSessionFacts: Equatable {
  let name: String
  let lift: String?
  let load: String?
  let unit: String?
  let reps: Int?
}

// MARK: - Timeline

/// The month timeline: the lifter's own records, projected one month at a time into immutable
/// cards. Nothing here is generated, scored or inferred — a card exists because a workout, a
/// measurement, a photo, an applied program change or a note exists.
///
/// The view owns its own scroll view, so the field header and chips scroll away; a pinned
/// week pill with the chips replaces them. Month, filter, anchor and the photo-detail
/// preference are device-local `@AppStorage`, so leaving the tab and coming back reopens the
/// same month, the same filter and the same day.
struct JourneyTimelineView: View {
  let usesLb: Bool
  /// The coach's pending volume increase (Needs your OK), shown in today's group of the current month.
  var pendingAsk: VolumeAskRow.Ask? = nil

  @Environment(\.modelContext) private var modelContext
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(AuthClient.self) private var auth

  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
  @Query private var measurements: [BodyMeasurement]
  @Query private var photos: [ProgressPhoto]
  @Query private var decisions: [DecisionLogEntry]
  @Query private var reflections: [JourneyReflection]

  @AppStorage(JourneyPref.monthKey) private var monthRaw = ""
  @AppStorage(JourneyPref.filterKey) private var filterRaw = ""
  @AppStorage(JourneyPref.anchorKey) private var anchorRaw = ""
  @AppStorage(JourneyPref.photoDetailsKey) private var photoDetailsEnabled = false

  @State private var repository: JourneyRepository?
  @State private var page: JourneyPage?
  @State private var coverage: [JourneyMonth] = []
  @State private var hiddenCount = 0
  @State private var limit = JourneyRepository.pageSize
  @State private var state: JourneyTimelineState = .loading
  @State private var failure: String?
  @State private var acknowledged: String?
  /// Temporary reveal. In memory only: the photo-detail *preference* is stored on this device,
  /// but the act of revealing one photo is not — backgrounding the app or switching profiles
  /// clears it, so a handed-over phone never comes back with a photo still revealed.
  @State private var revealedPhotos: Set<String> = []
  @State private var showAbout = false
  @State private var showHidden = false
  @State private var showProfile = false
  @State private var editor: ReflectionEditorTarget?
  @State private var selectedEvent: JourneyEvent?
  @State private var ownerID = ""
  @State private var hasLoaded = false
  @State private var passedDays: Set<Date> = []
  @State private var pinned = false
  @State private var facts = TimelineFactsCache()
  @State private var proxy: ScrollViewProxy?
  @State private var viewportHeight: CGFloat = 0

  // MARK: Body

  var body: some View {
    ZStack(alignment: .top) {
      ScrollViewReader { reader in
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            header
            content
              .padding(.horizontal, Theme.margin)
              .padding(.bottom, 120)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(Theme.page)
          }
        }
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        // A new month or filter is a different list: open it at its top, not at the old offset.
        .id([AnyHashable(month.identifier), AnyHashable(filterRaw)])
        .accessibilityIdentifier("journey.list")
        .onAppear { proxy = reader }
        .modifier(JourneyPinnedBarHost(pinned: pinned) { pinnedBar })
      }
      if pinned, !pinsWithSafeAreaBar {
        pinnedBar
          .transition(.opacity)
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: pinned)
    .coordinateSpace(name: TimelineSpace.name)
    .overlay(alignment: .bottom) { acknowledgement }
    .animation(reduceMotion ? nil : .spring(duration: 0.28), value: acknowledged)
    .task(id: reloadKey) { await project() }
    .onChange(of: sourceSignature) { _, _ in reload() }
    .onChange(of: scenePhase) { _, phase in
      if phase != .active {
        clearReveal()
      }
    }
    .onChange(of: ownerID) { _, _ in clearReveal() }
    .onChange(of: accountID) { _, _ in resetOwnerScope() }
    .onChange(of: selectedDay) { _, day in
      guard let day else {
        anchorRaw = ""
        return
      }
      anchorRaw =
        visibleSectionDays.contains(where: passedDays.contains)
        ? "day-\(Int(day.timeIntervalSince1970))" : ""
    }
    .sheet(isPresented: $showHidden) {
      if let repository {
        JourneyHiddenItemsSheet(repository: repository) { event in
          showRestored(event)
        }
      }
    }
    .sheet(isPresented: $showProfile) {
      if let repository {
        JourneyPrivateProfileSheet(repository: repository)
      }
    }
    .sheet(isPresented: $showAbout) {
      JourneyAboutSheet()
    }
    .sheet(item: $editor) { target in
      if let repository {
        JourneyReflectionSheet(
          repository: repository,
          target: target,
          linkCandidates: linkCandidates,
          onSaved: { isNew in
            acknowledge(
              String(localized: isNew ? "Note added" : "Note updated", bundle: L10n.bundle))
            reload()
          },
          onDeleted: {
            acknowledge(String(localized: "Note deleted", bundle: L10n.bundle))
            reload()
          })
      }
    }
    .navigationDestination(item: $selectedEvent) { event in
      destination(for: event)
    }
    .accessibilityIdentifier("journey.timeline")
  }

  // MARK: Header — week row, summary, filter chips, failure banner

  private var month: JourneyMonth {
    JourneyMonth(identifier: monthRaw) ?? JourneyMonth(containing: .now)
  }

  private var monthTitle: String {
    month.startDate().formatted(.dateTime.month(.wide).year().locale(L10n.locale))
  }

  private var isCurrentMonth: Bool { month == JourneyMonth(containing: .now) }

  /// The week or month sentence under the week pill.
  private var summary: AttributedString {
    if isCurrentMonth {
      let cal = TrainingMetrics.reportingCalendar()
      let stats = weekStats(
        weekStart: TrainingMetrics.reportingWeek(containing: .now, calendar: cal).start)
      var text: AttributedString
      if stats.done == 0 {
        text = AttributedString(localized: "No workouts yet this week.", bundle: L10n.bundle)
      } else {
        text = AttributedString(
          localized: "This week you trained **\(stats.done) of \(stats.planned)** days and set **\(stats.records) record\(L10n.pluralSuffix(stats.records))**.",
          bundle: L10n.bundle)
      }
      if let next = facts.nextSession {
        text += AttributedString(" ")
        if let lift = next.lift, let load = next.load, let unit = next.unit, let reps = next.reps {
          text += AttributedString(
            localized: "\(next.name) is next: \(lift) **\(load) \(unit) × \(reps)**.",
            bundle: L10n.bundle)
        } else {
          text += AttributedString(localized: "\(next.name) is next.", bundle: L10n.bundle)
        }
      }
      return text
    }
    let monthName = month.startDate().formatted(.dateTime.month(.wide).locale(L10n.locale))
    let interval = month.interval(calendar: .current)
    let inMonth = sessions.filter {
      $0.completed && !$0.tombstoned && interval.contains($0.date)
    }
    if inMonth.isEmpty {
      return AttributedString(localized: "No workouts in \(monthName).", bundle: L10n.bundle)
    }
    let records = inMonth.reduce(0) { $0 + (facts.records[$1.remoteID]?.count ?? 0) }
    return AttributedString(
      localized: "In \(monthName) you logged **\(inMonth.count) workout\(L10n.pluralSuffix(inMonth.count))** and set **\(records) record\(L10n.pluralSuffix(records))**.",
      bundle: L10n.bundle)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 0) {
      FieldSection(bottom: 20) {
        VStack(alignment: .leading, spacing: 6) {
          TimelineWeekRowV5(
            label: isCurrentMonth ? weekInterval(around: .now, template: "MMMd") : monthTitle,
            monthTitle: monthTitle,
            monthMenu: { monthMenuContent },
            moreMenu: { moreMenuContent })
          TimelineSummaryV5(text: summary)
        }
      }
      .onGeometryChange(for: Bool.self) {
        $0.frame(in: .named(TimelineSpace.name)).maxY < 0
      } action: { pinned = $0 }
      VStack(alignment: .leading, spacing: 12) {
        TimelineChipsV5(filter: filter, onChange: applyFilter)
          .accessibilityHidden(pinned)
        if let failure {
          failureBanner(failure)
            .padding(.horizontal, Theme.margin)
        }
      }
      .padding(.top, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.page)
    }
    .id("header")
  }

  private var pinnedBar: some View {
    let stats = weekStats(
      weekStart: TrainingMetrics.reportingWeek(
        containing: weekAnchorDay, calendar: TrainingMetrics.reportingCalendar()).start)
    return TimelinePinnedBarV5(
      label: weekInterval(around: weekAnchorDay, template: "MMMd"),
      monthTitle: monthTitle,
      stat: String(
        localized: "\(stats.done) of \(stats.planned) · \(stats.records) record\(L10n.pluralSuffix(stats.records))",
        bundle: L10n.bundle),
      opaqueBackground: !pinsWithSafeAreaBar,
      monthMenu: { monthMenuContent },
      chips: { TimelineChipsV5(filter: filter, onChange: applyFilter) })
  }

  /// Months the chooser can offer: every month that actually holds content, plus the month being
  /// shown and the current month, so a lifter who has never recorded anything can still open
  /// today's month and write a note. Months before the first entry are omitted — there is
  /// nothing to show there — but the current month always stays reachable.
  private var coverageOptions: [JourneyMonth] {
    var options = Set(coverage)
    options.insert(month)
    options.insert(JourneyMonth(containing: .now))
    let earliest = repository?.earliestMonth
    let current = JourneyMonth(containing: .now)
    return options
      .filter { candidate in
        earliest.map { candidate >= $0 || candidate == current } ?? true
      }
      .sorted(by: >)
  }

  private func covered(_ candidate: JourneyMonth) -> Bool {
    coverage.contains(candidate) || candidate == JourneyMonth(containing: .now)
  }

  private var monthMenuContent: some View {
    ForEach(coverageOptions, id: \.identifier) { candidate in
      Button {
        selectMonth(candidate)
      } label: {
        VStack(alignment: .leading, spacing: 1) {
          if candidate == month {
            Label(monthLabel(candidate), systemImage: "checkmark")
          } else {
            Text(monthLabel(candidate))
          }
          Text(verbatim: monthSubtitle(candidate))
            .forge(13, .regular)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        }
      }
    }
  }

  /// "11 workouts" — the month's finished sessions, never a guess; the first covered month
  /// says so, so the list visibly starts where the records start.
  private func monthSubtitle(_ candidate: JourneyMonth) -> String {
    let count = repository?.workoutCount(in: candidate) ?? 0
    let workouts = String(
      localized: "\(count) workout\(L10n.pluralSuffix(count))", bundle: L10n.bundle)
    if let earliest = repository?.earliestMonth, candidate == earliest, coverageOptions.count > 1 {
      return String(
        localized: "\(workouts) · first month", bundle: L10n.bundle)
    }
    return workouts
  }

  @ViewBuilder private var moreMenuContent: some View {
    Button(action: composeNote) {
      Label(String(localized: "Add a note about today", bundle: L10n.bundle), systemImage: "square.and.pencil")
    }
    Divider()
    Button {
      showProfile = true
    } label: {
      Label("Private profile", systemImage: "person.crop.circle")
    }
    Button {
      showHidden = true
    } label: {
      Label(
        hiddenCount == 0
          ? String(localized: "Hidden items", bundle: L10n.bundle)
          : String(localized: "Hidden items (\(hiddenCount))", bundle: L10n.bundle),
        systemImage: "eye.slash")
    }
    if let page, !page.events.isEmpty {
      Menu {
        ForEach(page.events) { event in
          Button {
            hide([event])
          } label: {
            // Several events in a month share a title; the date tells them apart. Hiding is
            // reversible from Hidden items, so the row is a normal action, not destructive.
            let dateText = event.day.formatted(.dateTime.month().day().locale(L10n.locale))
            Label("\(event.title) · \(dateText)", systemImage: "eye.slash")
              .accessibilityLabel(
                String(localized: "Hide \(event.title) · \(dateText)", bundle: L10n.bundle))
          }
        }
      } label: {
        Label("Hide an item", systemImage: "eye.slash")
      }
    }
    Toggle(isOn: $photoDetailsEnabled) {
      Label("Show pose labels", systemImage: "tag")
    }
    Divider()
    Button {
      showAbout = true
    } label: {
      Label(String(localized: "About this timeline", bundle: L10n.bundle), systemImage: "info.circle")
    }
  }

  private func monthLabel(_ candidate: JourneyMonth) -> String {
    let title = candidate.startDate().formatted(.dateTime.month(.wide).year().locale(L10n.locale))
    return covered(candidate)
      ? title
      : String(localized: "\(title) — no entries", bundle: L10n.bundle)
  }

  /// The nearest month with content in that direction, or `nil` when there is none, so the
  /// month-end footer's continue button never walks into an empty month.
  private func neighbourMonth(_ delta: Int) -> JourneyMonth? {
    let options = coverageOptions.filter { covered($0) }
    return delta < 0
      ? options.filter { $0 < month }.max()
      : options.filter { $0 > month }.min()
  }

  private func selectMonth(_ candidate: JourneyMonth) {
    monthRaw = candidate.identifier
    limit = JourneyRepository.pageSize
    anchorRaw = ""
  }

  // MARK: Week anchor

  private var selectedDay: Date? {
    let sections = visibleSectionDays
    return sections.last(where: { passedDays.contains($0) }) ?? sections.first
  }

  /// The page's day sections, newest first, plus the synthetic today section the view itself
  /// adds (a pending ask or today's check-in).
  private var visibleSectionDays: [Date] {
    guard let page else { return [] }
    return composedSections(page).map(\.day)
  }

  private var showsPendingAsk: Bool {
    pendingAsk != nil && isCurrentMonth && (filter.isAll || filter.categories.contains(.programChange))
  }

  /// Check-ins join the Body filter: one quiet line for today.
  private var showsCheckIns: Bool {
    filter.matches(.body) && !facts.checkIns.isEmpty
  }

  /// The day in view, else the open month's newest day (today in the current month).
  private var weekAnchorDay: Date {
    if let selectedDay { return selectedDay }
    let start = month.startDate()
    let end = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
    return min(Date.now, end)
  }

  /// "Sep 21 – 27" for the reporting week containing `day`.
  private func weekInterval(around day: Date, template: String) -> String {
    let cal = TrainingMetrics.reportingCalendar()
    let week = TrainingMetrics.reportingWeek(containing: day, calendar: cal)
    let lastDay = cal.date(byAdding: .day, value: 6, to: week.start) ?? week.start
    let formatter = DateIntervalFormatter()
    formatter.calendar = cal
    // After the calendar: assigning a calendar resets the formatter's locale to the calendar's.
    formatter.locale = L10n.locale
    formatter.dateTemplate = template
    return formatter.string(from: week.start, to: lastDay)
  }

  // MARK: Jump anchor

  /// Lands a jump target 116pt below the viewport top, just under the pinned bar.
  private var jumpAnchor: UnitPoint {
    UnitPoint(x: 0.5, y: viewportHeight > 224 ? 116 / viewportHeight : 0)
  }

  /// iOS 26 hosts the pinned bar in the scroll view's own safe area; earlier versions overlay it.
  private var pinsWithSafeAreaBar: Bool {
    if #available(iOS 26, *) { return true }
    return false
  }

  // MARK: Content

  @ViewBuilder private var content: some View {
    switch state {
    case .loading:
      loadingCard
    case .unavailable(let message):
      unavailableCard(message)
    case .ready:
      if let page, !page.isEmpty || showsPendingAsk || showsCheckIns {
        days(page)
      } else {
        emptyState
      }
    }
  }

  private var loadingCard: some View {
    VStack(spacing: 10) {
      ProgressView()
      Text("Loading this month").forgeLabel()
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 28)
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(
        Theme.timelineRow))
    .padding(.top, 12)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("journey.loading")
  }

  private func unavailableCard(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("The timeline could not be read", systemImage: "exclamationmark.triangle.fill")
        .forgeBodyStrong()
        .foregroundStyle(Theme.negative)
      Text(message)
        .forgeLabel()
        .fixedSize(horizontal: false, vertical: true)
      Button("Try again") { Task { await project() } }
        .buttonStyle(PillButtonStyle(minHeight: 44))
        .accessibilityIdentifier("journey.retry")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(
        Theme.timelineRow))
    .padding(.top, 12)
    .accessibilityIdentifier("journey.error")
  }

  private func failureBanner(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "exclamationmark.circle.fill")
        .scaledSystemFont(13, weight: .semibold)
        .foregroundStyle(Theme.negative)
      Text(message)
        .forgeLabel()
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      Button {
        failure = nil
      } label: {
        Image(systemName: "xmark")
          .scaledSystemFont(11, weight: .bold)
          .foregroundStyle(Theme.textSecondary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Dismiss")
    }
    .padding(.horizontal, 14)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(
        Theme.negative.opacity(0.12))
    )
    .accessibilityIdentifier("journey.failure")
  }

  private var emptyState: some View {
    TimelineEmptyV5(
      title: filter.isAll
        ? String(localized: "Nothing recorded in \(monthTitle)", bundle: L10n.bundle)
        : String(localized: "No matching entries in \(monthTitle)", bundle: L10n.bundle),
      message: hiddenCount > 0
        ? String(
          localized: "Find \(hiddenCount) hidden item\(L10n.pluralSuffix(hiddenCount)) under Hidden items.",
          bundle: L10n.bundle)
        : String(
          localized: "The timeline shows finished workouts, body check-ins, progress photos, program changes and your own notes. Nothing else is invented here.",
          bundle: L10n.bundle)
    ) {
      if !filter.isAll {
        Button { applyFilter(.all) } label: {
          TimelinePillLabelV5(
            title: String(localized: "Clear filter", bundle: L10n.bundle), systemImage: "xmark")
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("journey.clearFilter")
      }
      Button(action: composeNote) {
        TimelinePillLabelV5(
          title: String(localized: "Add a note", bundle: L10n.bundle), systemImage: "plus")
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("journey.empty.addNote")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("journey.empty")
  }

  private var filter: JourneyFilter {
    JourneyFilter(
      categories: Set(
        filterRaw.split(separator: ",").compactMap { JourneyCategory(rawValue: String($0)) }))
  }

  // MARK: Day sections

  /// Whether the rail gives way to a full-width layout. The app caps Dynamic Type at
  /// `.xxLarge`; at and beyond that the narrow gutter would crowd the cards, so the section
  /// collapses to a heading above the cards instead of clipping content.
  private var useCollapsedRail: Bool {
    dynamicTypeSize.isAccessibilitySize || dynamicTypeSize == .xxLarge
      || dynamicTypeSize == .xxxLarge
  }

  private func composedSections(_ page: JourneyPage) -> [JourneyDaySection] {
    var sections = page.daySections
    if showsPendingAsk || showsCheckIns {
      let today = Calendar.current.startOfDay(for: .now)
      if !sections.contains(where: { $0.day == today }) {
        sections.insert(JourneyDaySection(day: today, events: []), at: 0)
      }
    }
    sections.sort { $0.day > $1.day }
    return sections
  }

  /// One reporting week's consecutive day sections.
  private struct TimelineWeekGroup: Identifiable {
    let start: Date
    var sections: [JourneyDaySection]
    var id: Date { start }
  }

  private func days(_ page: JourneyPage) -> some View {
    let sections = composedSections(page)
    let cal = TrainingMetrics.reportingCalendar()
    var weeks: [TimelineWeekGroup] = []
    for section in sections {
      let start = TrainingMetrics.reportingWeek(containing: section.day, calendar: cal).start
      if weeks.last?.start == start {
        weeks[weeks.count - 1].sections.append(section)
      } else {
        weeks.append(TimelineWeekGroup(start: start, sections: [section]))
      }
    }
    return VStack(alignment: .leading, spacing: 0) {
      ForEach(weeks) { week in
        if week.start != weeks.first?.start {
          let boundary = weekBoundary(weekStart: week.start)
          TimelineWeekLabelV5(title: boundary.title, detail: boundary.detail)
        }
        TimelineRailGroupV5(showsRail: !useCollapsedRail) {
          ForEach(Array(week.sections.enumerated()), id: \.element.id) { index, section in
            sectionView(section)
              .padding(.top, index == 0 ? 0 : 16)
          }
        }
      }
      if page.hasMore {
        loadMore(page)
      } else {
        monthEnd
      }
    }
    .padding(.top, 12)
  }

  /// "Week 3 · Sep 21 – 27" + "3 of 3 sessions · 8 records". The number is the sessions' own
  /// program week; a week with no sessions keeps the number that was current when it passed,
  /// and weeks before any session show only the range. Planned is the profile's own schedule;
  /// done is capped at it like the consistency card. Records are the record marks those
  /// sessions set.
  private func weekBoundary(weekStart: Date) -> (title: String, detail: String?) {
    let cal = TrainingMetrics.reportingCalendar()
    let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
    let startOf = { cal.startOfDay(for: $0) }
    let inWeek = sessions.filter {
      $0.completed && !$0.tombstoned && startOf($0.date) >= weekStart && startOf($0.date) <= weekEnd
    }
    var weekNumber = inWeek.map(\.week).max()
    if weekNumber == nil {
      weekNumber = sessions
        .filter { $0.completed && !$0.tombstoned && $0.date < weekStart }
        .max { $0.date < $1.date }?.week
    }
    let range = weekInterval(around: weekStart, template: "MMMd")
    let title = weekNumber.map {
      String(localized: "Week \($0) · \(range)", bundle: L10n.bundle)
    } ?? range
    let stats = weekStats(weekStart: weekStart)
    let detail = String(
      localized: "\(stats.done) of \(stats.planned) session\(L10n.pluralSuffix(stats.planned)) · \(stats.records) record\(L10n.pluralSuffix(stats.records))",
      bundle: L10n.bundle)
    return (title, detail)
  }

  /// Sessions done (capped at the plan), planned per week, and records set, for one reporting week.
  private func weekStats(weekStart: Date) -> (done: Int, planned: Int, records: Int) {
    let cal = TrainingMetrics.reportingCalendar()
    let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
    let startOf = { cal.startOfDay(for: $0) }
    let inWeek = sessions.filter {
      $0.completed && !$0.tombstoned && startOf($0.date) >= weekStart && startOf($0.date) <= weekEnd
    }
    let planned = max(profiles.first?.daysPerWeek ?? 3, 1)
    let done = min(inWeek.count, planned)
    let records = inWeek.reduce(0) { $0 + (facts.records[$1.remoteID]?.count ?? 0) }
    return (done, planned, records)
  }

  private func sectionView(_ section: JourneyDaySection) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      // A jump lands the heading just under the pinned bar, not flush with the screen top.
      Color.clear
        .frame(height: 0)
        .id("jump-\(Int(section.day.timeIntervalSince1970))")
      heading(section.day)
        .padding(.leading, useCollapsedRail ? 0 : 20)
      let items = rowItems(section.events, on: section.day)
      ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
        TimelineEntryV5(showsRail: !useCollapsedRail) {
          cardContent(item)
        }
        .padding(.top, index == 0 ? 6 : 8)
      }
    }
    .id("day-\(Int(section.day.timeIntervalSince1970))")
  }

  private func isToday(_ day: Date) -> Bool {
    Calendar.current.isDateInToday(day)
  }

  private func heading(_ day: Date) -> some View {
    TimelineDayHeadingV5(word: headingWord(day), date: headingDate(day))
      .accessibilityLabel(headingAccessibilityLabel(day))
      .onGeometryChange(for: Bool.self) {
        $0.frame(in: .named(TimelineSpace.name)).minY < 116
      } action: { passed in
        if passed {
          passedDays.insert(day)
        } else {
          passedDays.remove(day)
        }
      }
  }

  private func headingWord(_ day: Date) -> String? {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return String(localized: "Today", bundle: L10n.bundle) }
    if calendar.isDateInYesterday(day) {
      return String(localized: "Yesterday", bundle: L10n.bundle)
    }
    return nil
  }

  private func headingDate(_ day: Date) -> String {
    day.formatted(
      .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
  }

  /// "Today, Monday, September 29, 2025" — the word the heading shows is part of its label.
  private func headingAccessibilityLabel(_ day: Date) -> String {
    guard let word = headingWord(day) else { return journeyDayLabel(day) }
    return "\(word), \(journeyDayLabel(day))"
  }

  // MARK: Event rows

  /// One rendered row: a single event, a run of program changes grouped into one card, or a
  /// quiet line. Rank fixes the visual hierarchy inside a day — workouts are the strongest
  /// entries, quiet lines sit last — with the page's own order kept within a rank.
  private enum TimelineRowItem: Identifiable {
    case needsOK
    case workout(JourneyEvent)
    case changeGroup([JourneyEvent])
    case note(JourneyEvent)
    case photo(JourneyEvent)
    case weighIn(JourneyEvent)
    case waist(JourneyEvent)
    case checkIn(JourneyCheckInFact)

    var id: String {
      switch self {
      case .needsOK: return "ask"
      case .workout(let event): return "w-\(event.id.rawValue)"
      case .changeGroup(let events): return "c-\(events[0].id.rawValue)"
      case .note(let event): return "n-\(event.id.rawValue)"
      case .photo(let event): return "p-\(event.id.rawValue)"
      case .weighIn(let event): return "bw-\(event.id.rawValue)"
      case .waist(let event): return "bt-\(event.id.rawValue)"
      case .checkIn(let fact): return "k-\(Int(fact.date.timeIntervalSince1970))"
      }
    }
  }

  private func rowItems(_ events: [JourneyEvent], on day: Date) -> [TimelineRowItem] {
    var ranked: [(rank: Int, seq: Int, item: TimelineRowItem)] = []
    if isToday(day) && showsPendingAsk {
      ranked.append((-1, -1, .needsOK))
    }
    var index = 0
    while index < events.count {
      let event = events[index]
      switch event.kind {
      case .workout:
        ranked.append((0, index, .workout(event)))
      case .programChange:
        if let firstFacts = facts.changes[event.sourceID] {
          let type = firstFacts.type
          let minute = Int(firstFacts.date.timeIntervalSince1970 / 60)
          var run = [event]
          var next = index + 1
          while next < events.count, events[next].kind == .programChange,
            let nextFacts = facts.changes[events[next].sourceID],
            nextFacts.type == type,
            nextFacts.isUserChange == firstFacts.isUserChange,
            type != "load_change" || (nextFacts.fromValue == nil) == (firstFacts.fromValue == nil),
            Int(nextFacts.date.timeIntervalSince1970 / 60) == minute
          {
            run.append(events[next])
            next += 1
          }
          index = next - 1
          ranked.append((1, index, .changeGroup(run)))
        } else {
          ranked.append((1, index, .changeGroup([event])))
        }
      case .reflection:
        ranked.append((2, index, .note(event)))
      case .progressPhoto:
        ranked.append((3, index, .photo(event)))
      case .bodyMeasurement:
        let body = facts.bodies[event.sourceID]
        if body?.weight != nil {
          ranked.append((4, index, .weighIn(event)))
        }
        if body?.waist != nil {
          ranked.append((5, index, .waist(event)))
        }
      }
      index += 1
    }
    if filter.matches(.body) {
      let calendar = Calendar.current
      for fact in facts.checkIns where calendar.isDate(fact.date, inSameDayAs: day) {
        ranked.append((6, ranked.count, .checkIn(fact)))
      }
    }
    return ranked
      .sorted { $0.rank == $1.rank ? $0.seq < $1.seq : $0.rank < $1.rank }
      .map(\.item)
  }

  /// The card, its button wrapper, accessibility and context menu.
  @ViewBuilder
  private func cardContent(_ item: TimelineRowItem) -> some View {
    switch item {
    case .needsOK:
      if let pendingAsk {
        TimelineAskRowV5(
          title: pendingAsk.title, detail: pendingAsk.detail, onReview: pendingAsk.onReview
        )
        .accessibilityIdentifier("journey.needsOK")
      }
    case .workout(let event):
      Button {
        selectedEvent = event
      } label: {
        workoutRow(event)
      }
      .buttonStyle(RowPressStyle())
      .journeyCardAccessibility(
        for: event, revealsDetail: true, isRevealed: false,
        record: workoutRecordLine(event).map {
          String(localized: "Record: \($0)", bundle: L10n.bundle)
        })
      .contentShape(
        .contextMenuPreview, RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
      .contextMenu { rowMenu([event], open: { selectedEvent = event }) }
    case .changeGroup(let events):
      let card = Button {
        selectedEvent = events[0]
      } label: {
        changeRow(events)
      }
      .buttonStyle(RowPressStyle())
      if events.count == 1 {
        card
          .journeyCardAccessibility(
            for: events[0], revealsDetail: true, isRevealed: false, author: changeAuthor(events))
          .contextMenu { rowMenu(events) }
      } else {
        card
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(changeGroupAccessibilityLabel(events))
          .accessibilityHint(journeyCardHint(for: events[0], isRevealed: false))
          .accessibilityIdentifier("journey.card.programChange.\(events[0].sourceID)")
          .contextMenu { rowMenu(events) }
      }
    case .note(let event):
      Button {
        editor = ReflectionEditorTarget(
          reflectionID: UUID(uuidString: event.sourceID), day: event.day)
      } label: {
        TimelineRowV5(
          lead: .glyph("pencil", Theme.accent),
          title: "\u{201C}\(event.detail ?? "")\u{201D}",
          isQuote: true,
          detail: facts.noteLinks[event.sourceID].map {
            String(localized: "Linked to \($0)", bundle: L10n.bundle)
          } ?? journeyEventTime(event))
      }
      .buttonStyle(RowPressStyle())
      .journeyCardAccessibility(for: event, revealsDetail: true, isRevealed: false)
      .contextMenu { hideMenu(event) }
    case .photo(let event):
      photoCard(event)
    case .weighIn(let event):
      bodyLine(event, weight: true)
    case .waist(let event):
      bodyLine(event, weight: false)
    case .checkIn(let fact):
      checkInLine(fact)
    }
  }

  /// "6:20 PM · 62 min · 22 sets" and the gold "Back Squat 115 kg × 8 · +2 more" line.
  private func workoutRow(_ event: JourneyEvent) -> TimelineRowV5<EmptyView> {
    let stored = facts.workouts[event.sourceID]
    var parts: [String] = []
    if let time = journeyEventTime(event) { parts.append(time) }
    if let minutes = stored?.minutes, minutes > 0 {
      parts.append(String(localized: "\(minutes) min", bundle: L10n.bundle))
    }
    if let workingSets = stored?.workingSets, workingSets > 0 {
      parts.append(
        String(
          localized: "\(workingSets) set\(L10n.pluralSuffix(workingSets))", bundle: L10n.bundle))
    }
    var record: String? = nil
    if let first = facts.records[event.sourceID]?.first {
      record = "\(first.name) \(first.weight) \(first.unit) × \(first.reps)"
      if let count = facts.records[event.sourceID]?.count, count > 1 {
        record? += " · " + String(localized: "+\(count - 1) more", bundle: L10n.bundle)
      }
    }
    return TimelineRowV5(
      lead: .glyph("dumbbell.fill", Theme.metricLoad),
      title: event.title,
      detail: parts.isEmpty ? nil : parts.joined(separator: " · "),
      record: record)
  }

  /// The gold record line a workout card shows: the first record mark and "+N more".
  private func workoutRecordLine(_ event: JourneyEvent) -> String? {
    guard let first = facts.records[event.sourceID]?.first else { return nil }
    var line = "\(first.name) \(first.weight) \(first.unit) × \(first.reps)"
    if let count = facts.records[event.sourceID]?.count, count > 1 {
      line += " · " + String(localized: "+\(count - 1) more", bundle: L10n.bundle)
    }
    return line
  }

  /// Whether the coach or the lifter made this program change.
  private func changeAuthor(_ events: [JourneyEvent]) -> String? {
    guard let change = facts.changes[events[0].sourceID] else { return nil }
    return change.isUserChange
      ? String(localized: "Changed by you", bundle: L10n.bundle)
      : String(localized: "Changed by your coach", bundle: L10n.bundle)
  }

  /// Coach avatar for the coach's own changes, the first change as "Bench Press 80 → 82.5 kg", "+N more", time.
  private func changeRow(_ events: [JourneyEvent]) -> TimelineRowV5<EmptyView> {
    let byCoach = facts.changes[events[0].sourceID].map { !$0.isUserChange } ?? false
    var summary = changeSummary(events[0])
    if events.count > 1 {
      summary += " · " + String(localized: "+\(events.count - 1) more", bundle: L10n.bundle)
    }
    let detail = [summary, journeyEventTime(events[0])].compactMap { $0 }.joined(separator: " · ")
    return TimelineRowV5(
      lead: byCoach ? .coach : .glyph("slider.horizontal.3", Theme.accent),
      title: changeGroupTitle(events),
      detail: detail)
  }

  /// One change's own line: load changes name the exercise and the numbers.
  private func changeSummary(_ event: JourneyEvent) -> String {
    let stored = facts.changes[event.sourceID]
    if stored?.type == "load_change", let to = stored?.toValue {
      let name = stored?.exerciseID.flatMap { ExerciseDB.find($0) }?.localizedName
        ?? stored?.humanSummary ?? event.title
      let unit = stored?.unit ?? ""
      if let from = stored?.fromValue {
        return "\(name) \(Fmt.num(from)) → \(Fmt.num(to)) \(unit)"
      }
      return "\(name) \(Fmt.num(to)) \(unit)"
    }
    return stored?.humanSummary ?? event.detail ?? event.title
  }

  /// Open (workouts), note on the day, or hide: the row's own context menu.
  @ViewBuilder
  private func rowMenu(_ events: [JourneyEvent], open: (() -> Void)? = nil) -> some View {
    if let open {
      Button(action: open) {
        Label(String(localized: "Open workout", bundle: L10n.bundle), systemImage: "dumbbell")
      }
    }
    Button {
      editor = ReflectionEditorTarget(reflectionID: nil, day: events[0].day)
    } label: {
      Label(String(localized: "Add a note", bundle: L10n.bundle), systemImage: "pencil")
    }
    Divider()
    Button {
      hide(events)
    } label: {
      Label("Hide from timeline", systemImage: "eye.slash")
    }
  }

  /// One quiet body line — a weigh-in or a waist reading — straight from the measurement's own
  /// facts, tapping into Body stats like the card it replaces.
  @ViewBuilder
  private func bodyLine(_ event: JourneyEvent, weight: Bool) -> some View {
    let body = facts.bodies[event.sourceID]
    let value = weight ? body?.weight : body?.waist
    if let value {
      let title = weight
        ? String(localized: "Weigh-in \(value.value) \(value.unit)", bundle: L10n.bundle)
        : String(localized: "Waist \(value.value) cm", bundle: L10n.bundle)
      Button {
        selectedEvent = event
      } label: {
        TimelineRowV5(
          lead: .glyph(weight ? "scalemass.fill" : "ruler.fill", Theme.positive),
          title: title,
          detail: value.delta)
      }
      .buttonStyle(RowPressStyle())
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        [title, value.delta, journeyDayLabel(event.day), journeyCardActionText(for: event)]
          .compactMap { $0 }
          .joined(separator: ", "))
      .accessibilityHint(journeyCardHint(for: event, isRevealed: false))
      .accessibilityIdentifier("journey.card.\(event.kind.rawValue).\(event.sourceID)")
      .contextMenu { rowMenu([event]) }
    }
  }

  /// The check-in quiet line. Not an event and not a button: it is one line about the day it
  /// happened on, readable as text.
  private func checkInLine(_ fact: JourneyCheckInFact) -> some View {
    let combinedTitle =
      fact.sleepHours > 0
      ? String(
        localized: "Checked in · slept \(Fmt.num(fact.sleepHours)) h", bundle: L10n.bundle)
      : String(localized: "Checked in", bundle: L10n.bundle)
    let time = fact.date.formatted(.dateTime.hour().minute().locale(L10n.locale))
    let detail =
      fact.sleepHours > 0
      ? "\(time) · \(String(localized: "slept \(Fmt.num(fact.sleepHours)) h", bundle: L10n.bundle))"
      : time
    return TimelineRowV5(
      lead: .glyph("moon.fill", Theme.metricSleep),
      title: String(localized: "Checked in", bundle: L10n.bundle),
      detail: detail
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(combinedTitle), \(time), \(journeyDayLabel(Calendar.current.startOfDay(for: fact.date)))")
    .accessibilityIdentifier("journey.card.checkIn.\(Int(fact.date.timeIntervalSince1970))")
  }

  private func hideMenu(_ event: JourneyEvent) -> some View {
    Button { hide([event]) } label: {
      Label("Hide from timeline", systemImage: "eye.slash")
    }
  }

  @ViewBuilder
  private func photoCard(_ event: JourneyEvent) -> some View {
    let revealed = revealedPhotos.contains(event.id.rawValue)
    let revealsDetail = revealed || photoDetailsEnabled
    let title =
      revealsDetail && event.detail != nil ? "\(event.title) · \(event.detail!)" : event.title
    let subtitle =
      revealed
      ? String(localized: "Revealed on this device", bundle: L10n.bundle)
      : (photoDetailsEnabled
        ? String(localized: "Private", bundle: L10n.bundle)
        : String(localized: "Private · tap to reveal", bundle: L10n.bundle))
    if revealed {
      NavigationLink {
        ProgressPhotosView()
      } label: {
        TimelineRowV5(
          lead: .glyph("eye.fill", Theme.accent), title: title, detail: subtitle)
      }
      .journeyCardAccessibility(for: event, revealsDetail: true, isRevealed: true)
      .contextMenu { rowMenu([event]) }
    } else {
      Button {
        revealedPhotos.insert(event.id.rawValue)
        acknowledge(String(localized: "Photo revealed on this device", bundle: L10n.bundle))
      } label: {
        TimelineRowV5(
          lead: .glyph("camera.fill", Theme.accent), title: title, detail: subtitle)
      }
      .buttonStyle(RowPressStyle())
      .journeyCardAccessibility(
        for: event, revealsDetail: photoDetailsEnabled, isRevealed: false)
      .contextMenu { rowMenu([event]) }
    }
  }

  // MARK: Card facts (cache reads only, never the repository)

  /// Kind, title, full date, every row's detail, time and action, like a single card.
  private func changeGroupAccessibilityLabel(_ events: [JourneyEvent]) -> String {
    var parts = [events[0].kind.name, changeGroupTitle(events), journeyDayLabel(events[0].day)]
    parts += events.map { $0.detail ?? $0.title }
    if let time = journeyEventTime(events[0]) { parts.append(time) }
    if let author = changeAuthor(events) { parts.append(author) }
    parts.append(journeyCardActionText(for: events[0]))
    return parts.joined(separator: ", ")
  }

  private func changeGroupTitle(_ events: [JourneyEvent]) -> String {
    guard events.count > 1 else { return events[0].title }
    let groupFacts = events.compactMap { facts.changes[$0.sourceID] }
    let n = events.count
    if let type = groupFacts.first?.type {
      switch type {
      case "load_change" where groupFacts.allSatisfy({ $0.fromValue == nil }):
        return String(localized: "\(n) starting loads", bundle: L10n.bundle)
      case "load_change":
        return String(localized: "\(n) loads changed", bundle: L10n.bundle)
      case "volume_change":
        return String(localized: "\(n) volume changes", bundle: L10n.bundle)
      case "swap":
        return String(localized: "\(n) exercises swapped", bundle: L10n.bundle)
      default:
        break
      }
    }
    return "\(events[0].title) · \(n)"
  }

  // MARK: Load more, month end

  private func loadMore(_ page: JourneyPage) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        limit += JourneyRepository.pageSize
      } label: {
        Text("Load more")
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
          .padding(.horizontal, 18)
          .frame(height: 40)
          .background(Capsule().fill(Theme.innerSurface))
          .frame(minHeight: 44)
          .contentShape(Capsule())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityIdentifier("journey.loadMore")
      Text(
        String(
          localized: "Showing \(page.events.count) of \(page.visibleCount) entries",
          bundle: L10n.bundle)
      )
      .forgeCaption()
      .monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.leading, useCollapsedRail ? 0 : 20)
    .padding(.top, 6)
  }

  private var monthEnd: some View {
    let monthName = month.startDate().formatted(.dateTime.month(.wide).locale(L10n.locale))
    let previous = neighbourMonth(-1)
    return TimelineMonthEndV5(
      title: String(localized: "Start of \(monthName)", bundle: L10n.bundle),
      caption: String(localized: "Only your own records appear here. Works offline.", bundle: L10n.bundle),
      continueTitle: previous.map {
        String(
          localized: "Continue to \($0.startDate().formatted(.dateTime.month(.wide).locale(L10n.locale)))",
          bundle: L10n.bundle)
      },
      onContinue: {
        if let previous { selectMonth(previous) }
      }
    )
    .id("footer")
  }

  private var acknowledgement: some View {
    Group {
      if let acknowledged {
        JourneyToast(text: acknowledged)
          .padding(.bottom, 12)
          .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
          .task(id: acknowledged) {
            try? await Task.sleep(for: .seconds(2.4))
            if self.acknowledged == acknowledged { self.acknowledged = nil }
          }
      }
    }
  }

  // MARK: Navigation

  @ViewBuilder private func destination(for event: JourneyEvent) -> some View {
    switch event.kind {
    case .workout:
      if let session = sessions.first(where: { $0.remoteID == event.sourceID }) {
        SessionDetailView(session: session, usesLb: usesLb)
      } else {
        JourneyMissingSourceView()
      }
    case .bodyMeasurement:
      MeasurementsView(usesLb: usesLb)
    case .progressPhoto:
      ProgressPhotosView()
    case .programChange:
      if JourneyProgramChangeSurface.isStructural(title: event.title) {
        ProgramRoadmapView()
      } else {
        AdjustmentsView()
      }
    case .reflection:
      JourneyMissingSourceView()
    }
  }

  // MARK: Actions

  private func composeNote() {
    editor = ReflectionEditorTarget(reflectionID: nil, day: .now)
  }

  /// Real records from the loaded page, never another note: a typed link points at a workout, a
  /// body check-in, a photo or an applied program change.
  private var linkCandidates: [JourneyEvent] {
    guard let page else { return [] }
    var seen = Set<String>()
    return page.events.filter { event in
      event.kind != .reflection && seen.insert(event.id.rawValue).inserted
    }
  }

  /// Hides every event, then reloads once.
  private func hide(_ events: [JourneyEvent]) {
    guard let repository else { return }
    do {
      for event in events { try repository.hide(event.id) }
      acknowledge(String(localized: "Hidden from your timeline", bundle: L10n.bundle))
      reload()
    } catch {
      failure = message(for: error)
    }
  }

  private func showRestored(_ event: JourneyEvent) {
    acknowledge(String(localized: "Restored to your timeline", bundle: L10n.bundle))
    hiddenCount = max(0, hiddenCount - 1)
    guard let current = page,
      current.month == JourneyMonth(containing: event.day),
      current.filter.matches(event.category)
    else { return }
    var events = current.events.filter { $0.id != event.id }
    events.append(event.hidden(false))
    let sorted = JourneySortKey.sorted(events)
    let restored = JourneyPage(
      month: current.month,
      filter: current.filter,
      events: Array(sorted.prefix(current.limit)),
      visibleCount: max(current.visibleCount, sorted.count),
      limit: current.limit)
    page = restored
    loadFacts(for: restored)
    Task { @MainActor in
      await Task.yield()
      repository = nil
      prepare()
      reload()
    }
  }

  private func applyFilter(_ filter: JourneyFilter) {
    filterRaw = filter.categories.map(\.rawValue).sorted().joined(separator: ",")
    limit = JourneyRepository.pageSize
    anchorRaw = ""
  }

  private func acknowledge(_ text: String) {
    acknowledged = text
    AccessibilityNotification.Announcement(text).post()
  }

  private func message(for error: Error) -> String {
    if let repositoryError = error as? JourneyRepositoryError {
      return repositoryError.errorDescription ?? String(describing: repositoryError)
    }
    return error.localizedDescription
  }

  private func clearReveal() {
    revealedPhotos.removeAll()
  }

  private func resetOwnerScope() {
    clearReveal()
    repository = nil
    page = nil
    coverage = []
    hiddenCount = 0
    ownerID = ""
    anchorRaw = ""
    hasLoaded = false
    limit = JourneyRepository.pageSize
    editor = nil
    showHidden = false
    prepare()
  }

  // MARK: Projection

  private var accountID: String { auth.user?.id ?? "" }

  private var sourceSignature: String {
    let sessionRevision = sessions.map {
      "\($0.remoteID):\($0.updatedAt.timeIntervalSinceReferenceDate):\($0.date.timeIntervalSinceReferenceDate):\($0.dayName)"
    }.joined(separator: "|")
    let measurementRevision = measurements.map {
      "\($0.remoteID):\($0.updatedAt.timeIntervalSinceReferenceDate):\($0.date.timeIntervalSinceReferenceDate)"
    }.joined(separator: "|")
    let photoRevision = photos.map {
      "\($0.fileName):\($0.date.timeIntervalSinceReferenceDate):\($0.pose)"
    }.joined(separator: "|")
    let decisionRevision = decisions.map { "\($0.record.id):\($0.record.humanSummary)" }.joined(
      separator: "|")
    let reflectionRevision = reflections.map {
      "\($0.reflectionID.uuidString):\($0.revision):\($0.updatedAt.timeIntervalSinceReferenceDate):\($0.tombstoned)"
    }.joined(separator: "|")
    return [
      accountID, sessionRevision, measurementRevision, photoRevision, decisionRevision,
      reflectionRevision,
    ].joined(separator: "#")
  }

  private var reloadKey: String {
    "\(monthRaw)|\(filterRaw)|\(limit)|\(ownerID)|\(accountID)"
  }

  /// Builds the repository once, then picks the month to open when this device has no
  /// remembered one: the current month when it holds something, otherwise the newest month that
  /// does. The lifter's own choice always wins after that.
  private func prepare() {
    guard repository == nil, let profile = profiles.first else { return }
    let created = JourneyRepository(
      context: modelContext, profile: profile, accountID: auth.user?.id)
    repository = created
    ownerID = created.ownerID
    if JourneyMonth(identifier: monthRaw) == nil {
      let current = JourneyMonth(containing: .now)
      if created.hasContent(in: current) {
        monthRaw = current.identifier
      } else if let latest = created.latestMonth {
        monthRaw = latest.identifier
      } else {
        monthRaw = current.identifier
      }
    }
  }

  private func project() async {
    prepare()
    guard let repository, let month = JourneyMonth(identifier: monthRaw) else {
      state = .unavailable("This device has no training profile yet.")
      return
    }
    if !hasLoaded {
      state = .loading
      await Task.yield()
    }
    do {
      let result = try repository.page(month: month, filter: filter, limit: limit)
      // Capture the saved anchor before the page lands: assigning `page` recomputes
      // selectedDay, whose onChange would otherwise overwrite it before the scroll runs.
      let savedAnchor = anchorRaw
      page = result
      coverage = repository.coveredMonths()
      hiddenCount = repository.hiddenItems().count
      state = .ready
      hasLoaded = true
      failure = nil
      loadFacts(for: result)
      if !savedAnchor.isEmpty,
        result.daySections.contains(where: {
          "day-\(Int($0.day.timeIntervalSince1970))" == savedAnchor
        })
      {
        // Scroll after the sections exist in the hierarchy; at project() time they have
        // not been drawn yet (and `proxy` may not have been captured on first load).
        Task { @MainActor in
          await Task.yield()
          proxy?.scrollTo(
            savedAnchor.replacingOccurrences(of: "day-", with: "jump-"), anchor: jumpAnchor)
        }
      }
    } catch {
      state = .unavailable(message(for: error))
    }
  }

  /// Re-reads the current page in place. Used after a hide, a restore or a note edit, where a
  /// loading state would only flicker.
  private func reload() {
    guard let repository, let month = JourneyMonth(identifier: monthRaw) else { return }
    do {
      let result = try repository.page(month: month, filter: filter, limit: limit)
      page = result
      coverage = repository.coveredMonths()
      hiddenCount = repository.hiddenItems().count
      state = .ready
      hasLoaded = true
      failure = nil
      loadFacts(for: result)
    } catch {
      // Keep the last good page on screen; surface the read failure instead of an empty month.
      failure = message(for: error)
    }
  }

  /// Fills the facts cache for every card of the page. One repository call per event, never
  /// from `body`, so rendering reads plain values only.
  private func loadFacts(for page: JourneyPage) {
    guard let repository else {
      facts = TimelineFactsCache()
      return
    }
    var workouts: [String: JourneyWorkoutFacts] = [:]
    var changes: [String: JourneyChangeFacts] = [:]
    var noteLinks: [String: String] = [:]
    var bodies: [String: JourneyBodyFacts] = [:]
    for event in page.events {
      switch event.kind {
      case .workout:
        if let stored = repository.workoutFacts(sessionID: event.sourceID) {
          workouts[event.sourceID] = stored
        }
      case .programChange:
        if let stored = repository.changeFacts(decisionID: event.sourceID) {
          changes[event.sourceID] = stored
        }
      case .bodyMeasurement:
        bodies[event.sourceID] = repository.bodyFacts(measurementID: event.sourceID)
      case .reflection:
        noteLinks[event.sourceID] = repository.noteLinkLabel(reflectionID: event.sourceID)
      case .progressPhoto:
        break
      }
    }
    facts = TimelineFactsCache(
      workouts: workouts,
      changes: changes,
      noteLinks: noteLinks,
      bodies: bodies,
      records: repository.recordMarks(),
      checkIns: page.month == JourneyMonth(containing: .now)
        ? repository.checkIns(
          in: Calendar.current.dateInterval(of: .day, for: .now)
            ?? page.month.interval(calendar: .current))
        : [],
      nextSession: nextSessionFacts())
  }

  /// "Full A is next" — the session Today itself would offer to start, resolved through the
  /// same service Today uses. No facts when a session is already done or open today, or when
  /// there is nothing scheduled.
  private func nextSessionFacts() -> JourneyNextSessionFacts? {
    guard let profile = profiles.first else { return nil }
    let calendar = Calendar.current
    let doneToday = sessions.contains {
      $0.completed && !$0.tombstoned && calendar.isDateInToday($0.date)
    }
    let openToday = sessions.contains { !$0.completed && !$0.tombstoned }
    guard !doneToday, !openToday,
      let day = RoutineAdaptationService.currentDay(profile: profile, sessions: sessions)
    else { return nil }
    var lift: String? = nil
    var load: String? = nil
    var unit: String? = nil
    var reps: Int? = nil
    if let first = day.exercises.first {
      let kg = suggestedStartKg(
        for: first, last: lastSets(first.exercise.id, in: sessions), profile: profile)
      let display = profile.display(kg: kg, for: first.exercise.id)
      lift = first.exercise.localizedName
      load = Fmt.num(display)
      unit = profile.isLb(for: first.exercise.id) ? "lb" : "kg"
      reps = first.repRange.lowerBound
    }
    return JourneyNextSessionFacts(
      name: localizedDayName(day.name), lift: lift, load: load, unit: unit, reps: reps)
  }
}

// MARK: - Load state

enum JourneyTimelineState: Equatable {
  case loading
  case ready
  /// Nothing could be projected, with the reason stated instead of an empty month.
  case unavailable(String)
}

// MARK: - Card accessibility

/// The trailing text action, one of the six truthful verbs, matched to the card's source and
/// the destination it opens. Program changes distinguish structural program screens from
/// load/volume change screens — never an applied/scheduled/reverted claim the receipt did not make.
private func journeyCardActionText(for event: JourneyEvent) -> String {
  switch event.kind {
  case .workout: return String(localized: "View workout", bundle: L10n.bundle)
  case .bodyMeasurement: return String(localized: "View body record", bundle: L10n.bundle)
  case .progressPhoto: return String(localized: "View privately", bundle: L10n.bundle)
  case .programChange:
    return JourneyProgramChangeSurface.isStructural(title: event.title)
      ? String(localized: "View program", bundle: L10n.bundle)
      : String(localized: "View change", bundle: L10n.bundle)
  case .reflection: return String(localized: "Edit note", bundle: L10n.bundle)
  }
}

/// The combined accessibility label for one card's outer actionable wrapper: kind, title, the
/// full locale-aware date, the detail line when the card reveals it, the timestamp when there is
/// one, the photo privacy state, and the truthful action.
private func journeyCardLabel(
  for event: JourneyEvent, revealsDetail: Bool, isRevealed: Bool, record: String? = nil,
  author: String? = nil
)
  -> String
{
  var parts: [String] = [event.kind.name, event.title, journeyDayLabel(event.day)]
  if revealsDetail, let detail = event.detail {
    parts.append(detail)
  }
  if event.precision == .timestamp, let instant = event.instant {
    parts.append(instant.formatted(.dateTime.hour().minute().locale(L10n.locale)))
  }
  if let record {
    parts.append(record)
  }
  if let author {
    parts.append(author)
  }
  if event.kind == .progressPhoto {
    parts.append(
      isRevealed
        ? String(localized: "revealed on this device", bundle: L10n.bundle)
        : String(localized: "private, not revealed", bundle: L10n.bundle))
  }
  parts.append(journeyCardActionText(for: event))
  return parts.joined(separator: ", ")
}

/// The accessibility hint for the same wrapper, kept truthful to the destination it opens.
private func journeyCardHint(for event: JourneyEvent, isRevealed: Bool) -> String {
  switch event.kind {
  case .reflection: return String(localized: "Opens the note editor", bundle: L10n.bundle)
  case .progressPhoto:
    return isRevealed
      ? String(localized: "Opens Photos", bundle: L10n.bundle)
      : String(localized: "Reveals this entry on this device", bundle: L10n.bundle)
  case .workout: return String(localized: "Opens the session", bundle: L10n.bundle)
  case .bodyMeasurement: return String(localized: "Opens body stats", bundle: L10n.bundle)
  case .programChange: return String(localized: "Opens the program record", bundle: L10n.bundle)
  }
}

/// Attaches the combined label, hint and the source-specific identifier to the *outer*
/// actionable wrapper, so the wrapper owns the VoiceOver element and its default activation.
/// The inner visual card stays semantically transparent and carries no button traits of its own.
private struct JourneyCardAccessibilityModifier: ViewModifier {
  let event: JourneyEvent
  let revealsDetail: Bool
  let isRevealed: Bool
  var record: String? = nil
  var author: String? = nil

  func body(content: Content) -> some View {
    content.accessibilityElement(children: .ignore).accessibilityLabel(
      journeyCardLabel(
        for: event, revealsDetail: revealsDetail, isRevealed: isRevealed, record: record,
        author: author)
    ).accessibilityHint(journeyCardHint(for: event, isRevealed: isRevealed))
      .accessibilityIdentifier("journey.card.\(event.kind.rawValue).\(event.sourceID)")
  }
}

extension View {
  fileprivate func journeyCardAccessibility(
    for event: JourneyEvent, revealsDetail: Bool, isRevealed: Bool, record: String? = nil,
    author: String? = nil
  )
    -> some View
  {
    modifier(
      JourneyCardAccessibilityModifier(
        event: event, revealsDetail: revealsDetail, isRevealed: isRevealed, record: record,
        author: author))
  }
}

// MARK: - Pinned bar hosting

/// Hosts the pinned bar in the scroll view's top safe area on iOS 26, where the system draws
/// the scroll-edge effect behind it; earlier versions keep today's plain overlay instead.
private struct JourneyPinnedBarHost<Bar: View>: ViewModifier {
  let pinned: Bool
  @ViewBuilder let bar: () -> Bar

  func body(content: Content) -> some View {
    if #available(iOS 26, *) {
      content.safeAreaBar(edge: .top) { if pinned { bar() } }
    } else {
      content
    }
  }
}

// MARK: - Missing source

/// A screen shown when a card's source record is gone. Reachable only if a record disappears
/// between the projection and the tap; the copy says exactly that instead of a blank screen.
private struct JourneyMissingSourceView: View {
  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "questionmark.folder")
        .scaledSystemFont(32, weight: .semibold)
        .foregroundStyle(Theme.textSecondary)
      Text("This record is no longer on this device")
        .forgeBodyStrong()
        .multilineTextAlignment(.center)
      Text("It was deleted after the timeline was read.")
        .forgeLabel()
        .multilineTextAlignment(.center)
    }
    .padding(24)
    .frame(maxWidth: .infinity)
    .background(Theme.page)
  }
}

// MARK: - Program-change surfaces

/// Which existing screen a program-change card opens. The card carries only the title produced
/// by `JourneyProgramChangePolicy.title(for:)`, so routing is by that title, and every unmapped
/// type lands on the effectiveness surface — where a `DecisionLogEntry` is accounted for.
private enum JourneyProgramChangeSurface {
  static let structuralTitles: Set<String> = [
    JourneyProgramChangePolicy.title(for: "weekplan"),
    JourneyProgramChangePolicy.title(for: "session"),
    JourneyProgramChangePolicy.title(for: "import_plan"),
    JourneyProgramChangePolicy.title(for: "deload"),
  ]

  static func isStructural(title: String) -> Bool {
    structuralTitles.contains(title)
  }
}
