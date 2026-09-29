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

// MARK: - Scroll-linked dock

/// Frames that move every scroll frame. Only the week-card host, the docked bar and the
/// travelling stamps read them, so scrolling never re-renders the list.
@Observable private final class TimelineDock {
  @ObservationIgnored var stripFrame: CGRect = .zero { didSet { update() } }
  @ObservationIgnored var barStampsFrame: CGRect = .zero { didSet { update() } }
  /// 0 while the week card rests in the list, 1 once its stamps have reached the bar.
  private(set) var progress: Double = 0

  /// Writes `progress` only when it changes, so the hosts redraw during docking only.
  private func update() {
    var next = 0.0
    if stripFrame != .zero, barStampsFrame != .zero {
      let start = barStampsFrame.midY + 60, end = barStampsFrame.midY - 6
      let t = min(1, max(0, (start - stripFrame.midY) / (start - end)))
      next = t * t * (3 - 2 * t)
    }
    if next != progress { progress = next }
  }
}

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

/// The "<day> is next" card in the today group: the session Today itself would start.
private struct JourneyNextSessionFacts: Equatable {
  let title: String
  let subtitle: String?
}

// MARK: - Timeline

/// The month timeline: the lifter's own records, projected one month at a time into immutable
/// cards. Nothing here is generated, scored or inferred — a card exists because a workout, a
/// measurement, a photo, an applied program change or a note exists.
///
/// The view owns its own scroll view, so the week card can dock into a pinned glass bar while
/// the Progress header and the Overview/Timeline switch stay pinned above it. Month, filter,
/// anchor and the photo-detail preference are device-local `@AppStorage`, so leaving the tab
/// and coming back reopens the same month, the same filter and the same day.
struct JourneyTimelineView: View {
  let usesLb: Bool

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
  @AppStorage("journey.timeline.stampedAt") private var stampedAt: Double = 0

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
  @State private var dock = TimelineDock()
  @State private var facts = TimelineFactsCache()
  @State private var proxy: ScrollViewProxy?
  @State private var stampingWorkoutID: String?
  @State private var stampLanded = true
  @State private var arrivalDay: Date?
  @State private var viewportHeight: CGFloat = 0

  // MARK: Body

  var body: some View {
    ZStack(alignment: .top) {
      ScrollViewReader { reader in
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            header
            content
          }
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        // A new month or filter is a different list: open it at its top, not at the old offset.
        .id([AnyHashable(month.identifier), AnyHashable(filterRaw)])
        .accessibilityIdentifier("journey.list")
        .onAppear { proxy = reader }
      }
      dockedBar
      travellingStamps
    }
    .coordinateSpace(name: TimelineSpace.name)
    .overlay(alignment: .top) { acknowledgement }
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

  // MARK: Header — week card, filter chips, failure banner

  private var month: JourneyMonth {
    JourneyMonth(identifier: monthRaw) ?? JourneyMonth(containing: .now)
  }

  private var monthTitle: String {
    month.startDate().formatted(.dateTime.month(.wide).year().locale(L10n.locale))
  }

  private var header: some View {
    VStack(spacing: 12) {
      WeekCardHost(
        dock: dock,
        reduceMotion: reduceMotion,
        monthTitle: monthTitle,
        days: weekDays,
        selectedDay: selectedDay,
        onSelectDay: jump(to:),
        monthMenu: { monthMenuContent },
        moreMenu: { moreMenuContent })
      TimelineFilterChips(filter: filter, onChange: applyFilter)
        .padding(.horizontal, -Theme.margin)
      if let failure {
        failureBanner(failure)
      }
    }
    .padding(.top, 4)
    .padding(.bottom, 20)
    .id("header")
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

  // MARK: Docking

  private var dockedBar: some View {
    DockedBarHost(
      dock: dock,
      reduceMotion: reduceMotion,
      label: weekInterval(template: "MMMd"),
      shortLabel: weekInterval(template: "MMM"),
      days: weekDays,
      selectedDay: selectedDay,
      onSelectDay: jump(to:))
  }

  private var travellingStamps: some View {
    TravellingStampsHost(dock: dock, reduceMotion: reduceMotion, days: weekDays)
  }

  private func weekInterval(template: String) -> String {
    weekInterval(around: weekAnchorDay, template: template)
  }

  /// "Sep 21 – 27" for the reporting week containing `day`.
  private func weekInterval(around day: Date, template: String) -> String {
    let cal = TrainingMetrics.reportingCalendar()
    let week = TrainingMetrics.reportingWeek(containing: day, calendar: cal)
    let lastDay = cal.date(byAdding: .day, value: 6, to: week.start) ?? week.start
    let formatter = DateIntervalFormatter()
    formatter.locale = L10n.locale
    formatter.calendar = cal
    formatter.dateTemplate = template
    return formatter.string(from: week.start, to: lastDay)
  }

  // MARK: Week days

  private var selectedDay: Date? {
    let sections = visibleSectionDays
    return sections.last(where: { passedDays.contains($0) }) ?? sections.first
  }

  /// The page's day sections, newest first, plus the synthetic sections the view itself adds:
  /// the composer's today, the next-session card's today, and check-in-only days.
  private var visibleSectionDays: [Date] {
    guard let page else { return [] }
    return composedSections(page).map(\.day)
  }

  private var showsComposer: Bool {
    month == JourneyMonth(containing: .now) && filter.matches(.note)
  }

  /// Check-ins join the Body filter: one quiet line per check-in day.
  private var showsCheckIns: Bool {
    filter.matches(.body) && !facts.checkIns.isEmpty
  }

  /// The "<day> is next" card shows under All and Workouts — under Body or Notes it would be
  /// noise beside entries it does not belong to.
  private var showsNextSession: Bool {
    month == JourneyMonth(containing: .now)
      && facts.nextSession != nil
      && (filter.isAll || filter.categories.contains(.workout))
  }

  /// The day in view, else the open month's newest day (today in the current month).
  private var weekAnchorDay: Date {
    if let selectedDay { return selectedDay }
    let start = month.startDate()
    let end = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
    return min(Date.now, end)
  }

  /// The day's session letter: "Full A" → "A", the last word's first character. `nil` when the
  /// plan day has no name.
  private func sessionLetter(_ name: String) -> String? {
    guard let last = name.split(separator: " ").last, let first = last.first else { return nil }
    return String(first).uppercased()
  }

  private var weekDays: [TimelineWeekDayV3] {
    let cal = TrainingMetrics.reportingCalendar()
    var symbolCal = Calendar(identifier: .gregorian)
    symbolCal.locale = L10n.locale
    let week = TrainingMetrics.reportingWeek(containing: weekAnchorDay, calendar: cal)
    let today = cal.startOfDay(for: .now)
    let doneDays = Set(
      sessions
        .filter { $0.completed && !$0.tombstoned }
        .map { cal.startOfDay(for: $0.date) })
    var entryDays = Set<Date>()
    if let page {
      for section in page.daySections {
        entryDays.insert(section.day)
      }
    }
    for fact in facts.checkIns where filter.matches(.body) {
      entryDays.insert(cal.startOfDay(for: fact.date))
    }
    // Planned session letters come from the accepted week plan — only it names which day
    // carries which session. Past weeks have no plan, so their days stay plain.
    var plannedNames: [Date: String] = [:]
    if let plan = profiles.first?.weekPlan {
      for planDay in plan.days {
        let start = cal.startOfDay(for: planDay.date)
        guard !planDay.state.isSettled, planDay.completedSessionID == nil,
          TrainingMetrics.reportingWeek(containing: planDay.date, calendar: cal).start == week.start
        else { continue }
        plannedNames[start] = planDay.sessionName
      }
    }
    return (0..<7).map { offset in
      let date = cal.date(byAdding: .day, value: offset, to: week.start) ?? week.start
      let start = cal.startOfDay(for: date)
      let symbol = symbolCal.veryShortWeekdaySymbols[
        max(0, cal.component(.weekday, from: date) - 1)]
      let isDone = doneDays.contains(start)
      let isToday = cal.isDateInToday(date)
      let isFuture = start > today
      let plannedName = plannedNames[start]
      let shape: TimelineStampV3.Shape =
        isDone
        ? .done
        : (plannedName != nil ? .planned : .restDot)
      let dayWide = date.formatted(.dateTime.weekday(.wide).locale(L10n.locale))
      let label: String
      if isDone {
        label = String(localized: "\(dayWide), workout done", bundle: L10n.bundle)
      } else if let plannedName, isToday {
        label = String(
          localized: "\(dayWide), today, \(localizedDayName(plannedName)) planned",
          bundle: L10n.bundle)
      } else if isToday {
        label = String(localized: "\(dayWide), today, no workout yet", bundle: L10n.bundle)
      } else if let plannedName {
        label = String(
          localized: "\(dayWide), \(localizedDayName(plannedName)) planned", bundle: L10n.bundle)
      } else if isFuture {
        label = String(localized: "\(dayWide), upcoming", bundle: L10n.bundle)
      } else {
        label = String(localized: "\(dayWide), no workout", bundle: L10n.bundle)
      }
      return TimelineWeekDayV3(
        date: start,
        initial: symbol.uppercased(),
        number: String(cal.component(.day, from: date)),
        shape: shape,
        isToday: isToday,
        hasEntries: entryDays.contains(start)
          || (isToday && (showsComposer || showsNextSession)),
        sessionLetter: plannedName.flatMap(sessionLetter),
        accessibilityLabel: label)
    }
  }

  // MARK: Jump to a day

  /// Lands a jump target 64pt below the viewport top, just under the docked bar.
  private var jumpAnchor: UnitPoint {
    UnitPoint(x: 0.5, y: viewportHeight > 128 ? 64 / viewportHeight : 0)
  }

  private func jump(to day: Date) {
    anchorRaw = "day-\(Int(day.timeIntervalSince1970))"
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.42)) {
      proxy?.scrollTo("jump-\(Int(day.timeIntervalSince1970))", anchor: jumpAnchor)
    }
    arrivalDay = day
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(0.9))
      if arrivalDay == day {
        withAnimation(.easeOut(duration: 0.7)) { arrivalDay = nil }
      }
    }
  }

  // MARK: Content

  @ViewBuilder private var content: some View {
    switch state {
    case .loading:
      loadingCard
    case .unavailable(let message):
      unavailableCard(message)
    case .ready:
      if let page, !page.isEmpty || showsComposer || showsCheckIns || showsNextSession {
        days(page)
      } else {
        emptyCard
      }
    }
  }

  private var loadingCard: some View {
    SkyCard {
      VStack(spacing: 10) {
        ProgressView()
        Text("Loading this month").forgeLabel()
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 28)
    }
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("journey.loading")
  }

  private func unavailableCard(_ message: String) -> some View {
    SkyCard {
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
    }
    .accessibilityIdentifier("journey.error")
  }

  private func failureBanner(_ message: String) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "exclamationmark.circle.fill")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.negative)
      Text(message)
        .forgeLabel()
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      Button {
        failure = nil
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .bold))
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

  private var emptyCard: some View {
    SkyCard {
      VStack(spacing: 10) {
        Image(systemName: "calendar")
          .font(.system(size: 34, weight: .semibold))
          .foregroundStyle(Theme.metricTime)
          .frame(width: 72, height: 72)
          .background(Circle().fill(Theme.metricTime.opacity(0.12)))
        Text(
          filter.isAll
            ? "Nothing recorded in \(monthTitle)"
            : "No matching entries in \(monthTitle)"
        )
        .forgeBodyStrong()
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        Text(
          "The timeline shows finished workouts, body check-ins, progress photos, program changes and your own notes. Nothing else is invented here."
        )
        .forgeLabel()
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        if !filter.isAll {
          Button("Clear filter") { applyFilter(.all) }
            .buttonStyle(PillButtonStyle(minHeight: 44))
            .accessibilityIdentifier("journey.clearFilter")
        }
        Button(action: composeNote) {
          Label("Add note", systemImage: "square.and.pencil")
        }
        .buttonStyle(PillButtonStyle(minHeight: 44))
        .accessibilityIdentifier("journey.empty.addNote")
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 20)
    }
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
    if showsComposer || showsNextSession {
      let today = Calendar.current.startOfDay(for: .now)
      if !sections.contains(where: { $0.day == today }) {
        sections.insert(JourneyDaySection(day: today, events: []), at: 0)
      }
    }
    if showsCheckIns {
      // A check-in day with no other entry still shows its one quiet line.
      for fact in facts.checkIns {
        let day = Calendar.current.startOfDay(for: fact.date)
        if !sections.contains(where: { $0.day == day }) {
          sections.append(JourneyDaySection(day: day, events: []))
        }
      }
      sections.sort { $0.day > $1.day }
    }
    return sections
  }

  private func days(_ page: JourneyPage) -> some View {
    let sections = composedSections(page)
    let cal = TrainingMetrics.reportingCalendar()
    return VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
        // A week boundary row sits between day groups crossing into an older reporting week;
        // the newest group carries none (the week card above already names this week).
        let boundary: (title: String, detail: String?)? =
          index > 0
          ? {
            let week = TrainingMetrics.reportingWeek(containing: section.day, calendar: cal).start
            let previous = sections[index - 1]
            let previousWeek = TrainingMetrics.reportingWeek(containing: previous.day, calendar: cal)
              .start
            guard week != previousWeek else { return nil }
            return weekBoundary(weekStart: week)
          }()
          : nil
        sectionView(
          section, boundary: boundary, isLastSection: index == sections.count - 1,
          hasMore: page.hasMore)
      }
      if page.hasMore {
        loadMore(page)
      } else {
        monthEnd
      }
    }
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
    let planned = max(profiles.first?.daysPerWeek ?? 3, 1)
    let done = min(inWeek.count, planned)
    let records = inWeek.reduce(0) { $0 + (facts.records[$1.remoteID]?.count ?? 0) }
    let detail = String(
      localized: "\(done) of \(planned) session\(L10n.pluralSuffix(planned)) · \(records) record\(L10n.pluralSuffix(records))",
      bundle: L10n.bundle)
    return (title, detail)
  }

  private func sectionView(
    _ section: JourneyDaySection,
    boundary: (title: String, detail: String?)?,
    isLastSection: Bool,
    hasMore: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      // A jump lands the heading just under the docked bar, not flush with the screen top.
      Color.clear
        .frame(height: 0)
        .id("jump-\(Int(section.day.timeIntervalSince1970))")
      if useCollapsedRail {
        VStack(alignment: .leading, spacing: 12) {
          if let boundary {
            TimelineWeekBoundary(title: boundary.title, detail: boundary.detail)
          }
          heading(section.day)
          todayExtras(section, collapsed: true)
          ForEach(rowItems(section.events, on: section.day)) { item in
            cardContent(item)
          }
        }
      } else {
        if let boundary {
          TimelineRailRowV3(node: .boundary, nodeCenterY: 15, bottomSpacing: 6) {
            TimelineWeekBoundary(title: boundary.title, detail: boundary.detail)
          }
        }
        headingRail(section.day)
        todayExtras(section, collapsed: false)
        eventRows(section, isLastSection: isLastSection, hasMore: hasMore)
      }
    }
    .id("day-\(Int(section.day.timeIntervalSince1970))")
  }

  private func isToday(_ day: Date) -> Bool {
    Calendar.current.isDateInToday(day)
  }

  private func headingRail(_ day: Date) -> some View {
    TimelineRailRowV3(node: .none, nodeCenterY: 13, bottomSpacing: 10) {
      heading(day)
    }
  }

  private func heading(_ day: Date) -> some View {
    TimelineDayHeadingV3(
      word: headingWord(day), date: headingDate(day), highlighted: arrivalDay == day
    )
    .accessibilityLabel(journeyDayLabel(day))
    .onGeometryChange(for: Bool.self) {
      $0.frame(in: .named(TimelineSpace.name)).minY < 76
    } action: { passed in
      if passed {
        passedDays.insert(day)
      } else {
        passedDays.remove(day)
      }
    }
  }

  // MARK: Today group extras

  /// The "<day> is next" card and the note composer, in the today group. The next card posts
  /// the same notification the lift screen uses, so the session starts through Today's own
  /// begin/resume path — nothing is duplicated here.
  @ViewBuilder
  private func todayExtras(_ section: JourneyDaySection, collapsed: Bool) -> some View {
    if isToday(section.day) {
      if showsNextSession, let next = facts.nextSession {
        nextSessionCard(next, section: section, collapsed: collapsed)
      }
      if showsComposer {
        if collapsed {
          TimelineComposerRow(action: composeNote)
        } else {
          TimelineRailRowV3(
            node: .composer, nodeCenterY: 22,
            bottomSpacing: section.events.isEmpty ? 24 : 12
          ) {
            TimelineComposerRow(action: composeNote)
          }
        }
      }
    }
  }

  private func nextSessionCard(
    _ next: JourneyNextSessionFacts, section: JourneyDaySection, collapsed: Bool
  ) -> some View {
    let card = Button {
      NotificationCenter.default.post(name: .forgeStartWorkout, object: nil)
    } label: {
      TimelineNextSessionCard(title: next.title, subtitle: next.subtitle)
    }
    .buttonStyle(RowPressStyle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      next.subtitle.map { "\(next.title), \($0)" } ?? next.title
    )
    .accessibilityHint(String(localized: "Starts the session in Today", bundle: L10n.bundle))
    .accessibilityIdentifier("journey.today.next")
    return Group {
      if collapsed {
        card
      } else {
        TimelineRailRowV3(
          node: .planned, nodeCenterY: 28,
          bottomSpacing: section.events.isEmpty && !showsComposer ? 24 : 12
        ) {
          card
        }
      }
    }
  }

  private func headingWord(_ day: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return String(localized: "Today", bundle: L10n.bundle) }
    if calendar.isDateInYesterday(day) {
      return String(localized: "Yesterday", bundle: L10n.bundle)
    }
    return day.formatted(.dateTime.weekday(.wide).locale(L10n.locale))
  }

  private func headingDate(_ day: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) || calendar.isDateInYesterday(day) {
      return day.formatted(
        .dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(L10n.locale))
    }
    return day.formatted(.dateTime.day().month(.abbreviated).locale(L10n.locale))
  }

  // MARK: Event rows

  /// One rendered row: a single event, a run of program changes grouped into one card, or a
  /// quiet line. Rank fixes the visual hierarchy inside a day — workouts are the strongest
  /// entries, quiet lines sit last — with the page's own order kept within a rank.
  private enum TimelineRowItem: Identifiable {
    case workout(JourneyEvent)
    case changeGroup([JourneyEvent])
    case note(JourneyEvent)
    case photo(JourneyEvent)
    case weighIn(JourneyEvent)
    case waist(JourneyEvent)
    case checkIn(JourneyCheckInFact)

    var isQuiet: Bool {
      switch self {
      case .weighIn, .waist, .checkIn: return true
      default: return false
      }
    }

    var id: String {
      switch self {
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

  @ViewBuilder
  private func eventRows(_ section: JourneyDaySection, isLastSection: Bool, hasMore: Bool) -> some View {
    let items = rowItems(section.events, on: section.day)
    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
      let isLastRow = index == items.count - 1
      let drawsLine = !(isLastSection && isLastRow && hasMore)
      let spacing: CGFloat = isLastRow ? 24 : (item.isQuiet ? 2 : 12)
      eventRow(item, bottomSpacing: spacing, drawsLine: drawsLine)
    }
  }

  /// The card, its button wrapper, accessibility and context menu — shared by the railed
  /// layout and the collapsed large-type layout, which draws it full width with no rail.
  @ViewBuilder
  private func cardContent(_ item: TimelineRowItem) -> some View {
    switch item {
    case .workout(let event):
      Button {
        selectedEvent = event
      } label: {
        TimelineWorkoutCardV3(facts: workoutCardFacts(for: event))
      }
      .buttonStyle(RowPressStyle())
      .journeyCardAccessibility(for: event, revealsDetail: true, isRevealed: false)
      .contextMenu { hideMenu(event) }
    case .changeGroup(let events):
      let groupFacts = changeGroupFacts(for: events)
      let card = Button {
        selectedEvent = events[0]
      } label: {
        TimelineChangeCardV3(facts: groupFacts)
      }
      .buttonStyle(RowPressStyle())
      if events.count == 1 {
        card
          .journeyCardAccessibility(for: events[0], revealsDetail: true, isRevealed: false)
          .contextMenu { hideMenu(events[0]) }
      } else {
        card
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(changeGroupAccessibilityLabel(events, facts: groupFacts))
          .accessibilityHint(journeyCardHint(for: events[0], isRevealed: false))
          .accessibilityIdentifier("journey.card.programChange.\(events[0].sourceID)")
          .contextMenu {
            Button {
              hide(events)
            } label: {
              Label("Hide from timeline", systemImage: "eye.slash")
            }
          }
      }
    case .note(let event):
      Button {
        editor = ReflectionEditorTarget(
          reflectionID: UUID(uuidString: event.sourceID), day: event.day)
      } label: {
        TimelineNoteV3(text: event.detail ?? "", link: facts.noteLinks[event.sourceID])
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

  @ViewBuilder
  private func eventRow(_ item: TimelineRowItem, bottomSpacing: CGFloat, drawsLine: Bool) -> some View {
    switch item {
    case .workout(let event):
      let stamping = event.id.rawValue == stampingWorkoutID
      TimelineRailRowV3(
        node: .stamp,
        stampScale: stamping && !stampLanded ? 0.35 : 1,
        stampRotation: stamping && !stampLanded ? -14 : 0,
        stampOpacity: stamping && !stampLanded ? 0 : 1,
        nodeCenterY: 28,
        bottomSpacing: bottomSpacing,
        drawsLineBelow: drawsLine
      ) {
        cardContent(item)
      }
    case .changeGroup(let events):
      let byCoach = facts.changes[events[0].sourceID].map { !$0.isUserChange } ?? false
      TimelineRailRowV3(
        node: byCoach
          ? .coach
          : .quietIcon(symbol: "slider.horizontal.3", tint: Theme.accent),
        nodeCenterY: 28, bottomSpacing: bottomSpacing,
        drawsLineBelow: drawsLine
      ) {
        cardContent(item)
      }
    case .note:
      TimelineRailRowV3(
        node: .quietIcon(symbol: "pencil", tint: Theme.accent), nodeCenterY: 14,
        bottomSpacing: bottomSpacing, drawsLineBelow: drawsLine
      ) {
        cardContent(item)
      }
    case .photo:
      TimelineRailRowV3(
        node: .quietIcon(symbol: "camera.fill", tint: Theme.accent), nodeCenterY: 30,
        bottomSpacing: bottomSpacing, drawsLineBelow: drawsLine
      ) {
        cardContent(item)
      }
    case .weighIn:
      TimelineRailRowV3(
        node: .quietIcon(symbol: "scalemass", tint: Theme.accent), nodeCenterY: 22,
        bottomSpacing: bottomSpacing, drawsLineBelow: drawsLine
      ) {
        cardContent(item)
      }
    case .waist:
      TimelineRailRowV3(
        node: .quietIcon(symbol: "figure.stand", tint: Theme.accent), nodeCenterY: 22,
        bottomSpacing: bottomSpacing, drawsLineBelow: drawsLine
      ) {
        cardContent(item)
      }
    case .checkIn:
      TimelineRailRowV3(
        node: .quietIcon(symbol: "moon.fill", tint: Theme.metricSleep), nodeCenterY: 22,
        bottomSpacing: bottomSpacing, drawsLineBelow: drawsLine
      ) {
        cardContent(item)
      }
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
        TimelineQuietLine(title: title, trailing: value.delta)
      }
      .buttonStyle(RowPressStyle())
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        [title, value.delta, journeyDayLabel(event.day), journeyCardActionText(for: event)]
          .compactMap { $0 }
          .joined(separator: ", "))
      .accessibilityHint(journeyCardHint(for: event, isRevealed: false))
      .accessibilityIdentifier("journey.card.\(event.kind.rawValue).\(event.sourceID)")
      .contextMenu { hideMenu(event) }
    }
  }

  /// The check-in quiet line. Not an event and not a button: it is one line about the day it
  /// happened on, readable as text.
  private func checkInLine(_ fact: JourneyCheckInFact) -> some View {
    let title =
      fact.sleepHours > 0
      ? String(
        localized: "Checked in · slept \(Fmt.num(fact.sleepHours)) h", bundle: L10n.bundle)
      : String(localized: "Checked in", bundle: L10n.bundle)
    let time = fact.date.formatted(.dateTime.hour().minute().locale(L10n.locale))
    return TimelineQuietLine(title: title, trailing: time)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "\(title), \(time), \(journeyDayLabel(Calendar.current.startOfDay(for: fact.date)))")
      .accessibilityIdentifier("journey.card.checkIn.\(Int(fact.date.timeIntervalSince1970))")
  }

  private func hideMenu(_ event: JourneyEvent) -> some View {
    Button(role: .destructive) { hide([event]) } label: {
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
        TimelinePhotoCard(title: title, subtitle: subtitle, revealed: revealed)
      }
      .journeyCardAccessibility(for: event, revealsDetail: true, isRevealed: true)
      .contextMenu { hideMenu(event) }
    } else {
      Button {
        revealedPhotos.insert(event.id.rawValue)
        acknowledge(String(localized: "Photo revealed on this device", bundle: L10n.bundle))
      } label: {
        TimelinePhotoCard(title: title, subtitle: subtitle, revealed: revealed)
      }
      .buttonStyle(RowPressStyle())
      .journeyCardAccessibility(
        for: event, revealsDetail: photoDetailsEnabled, isRevealed: false)
      .contextMenu { hideMenu(event) }
    }
  }

  // MARK: Card facts (cache reads only, never the repository)

  private func workoutCardFacts(for event: JourneyEvent) -> TimelineWorkoutCardFacts {
    let stored = facts.workouts[event.sourceID]
    var metaParts: [String] = []
    if let stored {
      if stored.week > 0 {
        metaParts.append(String(localized: "Week \(stored.week)", bundle: L10n.bundle))
      }
      if stored.workingSets > 0 {
        metaParts.append(
          String(
            localized: "\(stored.workingSets) set\(L10n.pluralSuffix(stored.workingSets))",
            bundle: L10n.bundle))
      }
      if stored.minutes > 0 {
        metaParts.append(String(localized: "\(stored.minutes) min", bundle: L10n.bundle))
      }
    }
    let marks = facts.records[event.sourceID] ?? []
    let recordIDs = Set(marks.map(\.exerciseID))
    let exercises = stored?.exerciseIDs.compactMap(ExerciseDB.find) ?? []
    return TimelineWorkoutCardFacts(
      title: event.title,
      time: journeyEventTime(event),
      meta: metaParts.joined(separator: " · "),
      tokens: exercises.prefix(3).map {
        TimelineLiftToken(exercise: $0, record: recordIDs.contains($0.id))
      },
      extraTokenCount: max(0, exercises.count - 3),
      records: marks.map {
        TimelineRecordRow(name: $0.name, weight: $0.weight, unit: $0.unit, reps: "\($0.reps)")
      })
  }

  /// Kind, title, full date, every row's detail, time and action, like a single card.
  private func changeGroupAccessibilityLabel(
    _ events: [JourneyEvent], facts groupFacts: TimelineChangeCardFacts
  ) -> String {
    var parts = [events[0].kind.name, groupFacts.title, journeyDayLabel(events[0].day)]
    parts += events.map { $0.detail ?? $0.title }
    if let time = groupFacts.time { parts.append(time) }
    parts.append(journeyCardActionText(for: events[0]))
    return parts.joined(separator: ", ")
  }

  private func changeGroupFacts(for events: [JourneyEvent]) -> TimelineChangeCardFacts {
    TimelineChangeCardFacts(
      title: changeGroupTitle(events),
      time: journeyEventTime(events[0]),
      rows: events.map { event in
        let stored = facts.changes[event.sourceID]
        let exercise = stored?.exerciseID.flatMap { ExerciseDB.find($0) }
        let isLoad = stored?.type == "load_change"
        let name =
          isLoad
          ? (exercise?.localizedName ?? stored?.humanSummary ?? event.title)
          : (stored?.humanSummary ?? event.title)
        return TimelineChangeRowV3(
          id: event.id.rawValue,
          exercise: exercise,
          name: name,
          from: isLoad ? stored?.fromValue.map { Fmt.num($0) } : nil,
          to: isLoad ? stored?.toValue.map { Fmt.num($0) } : nil,
          unit: isLoad ? stored?.unit : nil)
      })
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
    .padding(.leading, 44)
    .padding(.top, 6)
  }

  private var monthEnd: some View {
    let monthName = month.startDate().formatted(.dateTime.month(.wide).locale(L10n.locale))
    let previous = neighbourMonth(-1)
    return TimelineMonthEnd(
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
          .padding(.top, 6)
          .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
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
        RecommendationEffectivenessView()
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
      stampInIfNeeded(result)
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
      checkIns: repository.checkIns(in: page.month.interval(calendar: .current)),
      nextSession: nextSessionFacts())
  }

  /// "Full A is next" — the session Today itself would offer to start, resolved through the
  /// same service Today uses. No card when a session is already done or open today, or when
  /// there is nothing scheduled; the tap posts the same start notification the lift screen
  /// uses, so Today's own begin/resume path runs.
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
    let name = localizedDayName(day.name)
    var subtitle: String? = nil
    if let first = day.exercises.first {
      let kg = suggestedStartKg(
        for: first, last: lastSets(first.exercise.id, in: sessions), profile: profile)
      let display = profile.display(kg: kg, for: first.exercise.id)
      let unit = profile.isLb(for: first.exercise.id) ? "lb" : "kg"
      subtitle = String(
        localized: "\(day.exercises.count) lift\(L10n.pluralSuffix(day.exercises.count)) · \(first.exercise.localizedName) target \(Fmt.num(display)) \(unit) × \(first.repRange.lowerBound)",
        bundle: L10n.bundle)
    }
    return JourneyNextSessionFacts(
      title: String(localized: "\(name) is next", bundle: L10n.bundle), subtitle: subtitle)
  }

  /// Stamps in a workout newer than any stamped before; the first run stamps only today's.
  private func stampInIfNeeded(_ page: JourneyPage) {
    guard month == JourneyMonth(containing: .now),
      let first = page.events.first(where: { $0.kind == .workout })
    else { return }
    let at = (first.instant ?? first.day).timeIntervalSince1970
    guard at > stampedAt else { return }
    let isNew = stampedAt > 0 || Calendar.current.isDateInToday(first.day)
    stampedAt = at
    guard isNew, !reduceMotion else { return }
    stampingWorkoutID = first.id.rawValue
    stampLanded = false
    Task { @MainActor in
      await Task.yield()
      withAnimation(.spring(duration: 0.5, bounce: 0.4).delay(0.35)) { stampLanded = true }
    }
  }
}

// MARK: - Docking hosts

/// Renders the week card, feeding it the dock's scroll-linked values so the list itself never
/// re-renders while scrolling.
private struct WeekCardHost<MonthMenu: View, MoreMenu: View>: View {
  let dock: TimelineDock
  let reduceMotion: Bool
  let monthTitle: String
  let days: [TimelineWeekDayV3]
  let selectedDay: Date?
  let onSelectDay: (Date) -> Void
  @ViewBuilder let monthMenu: () -> MonthMenu
  @ViewBuilder let moreMenu: () -> MoreMenu

  init(
    dock: TimelineDock,
    reduceMotion: Bool,
    monthTitle: String,
    days: [TimelineWeekDayV3],
    selectedDay: Date?,
    onSelectDay: @escaping (Date) -> Void,
    @ViewBuilder monthMenu: @escaping () -> MonthMenu,
    @ViewBuilder moreMenu: @escaping () -> MoreMenu
  ) {
    self.dock = dock
    self.reduceMotion = reduceMotion
    self.monthTitle = monthTitle
    self.days = days
    self.selectedDay = selectedDay
    self.onSelectDay = onSelectDay
    self.monthMenu = monthMenu
    self.moreMenu = moreMenu
  }

  var body: some View {
    TimelineWeekCardV3(
      monthTitle: monthTitle,
      days: days,
      selectedDay: selectedDay,
      stampsVisible: reduceMotion || dock.progress == 0,
      detailOpacity: reduceMotion ? 1 : 1 - min(1, dock.progress * 2),
      onSelectDay: onSelectDay,
      onStripFrame: { new in
        if abs(dock.stripFrame.midY - new.midY) > 0.5 || dock.stripFrame.size != new.size {
          dock.stripFrame = new
        }
      },
      monthMenu: monthMenu,
      moreMenu: moreMenu)
  }
}

/// The pinned glass bar. Always laid out (opacity 0 at rest, never removed) so its stamp
/// frames are known before the docking transition starts.
private struct DockedBarHost: View {
  let dock: TimelineDock
  let reduceMotion: Bool
  let label: String
  let shortLabel: String
  let days: [TimelineWeekDayV3]
  let selectedDay: Date?
  let onSelectDay: (Date) -> Void

  private var barOpacity: Double {
    reduceMotion ? (dock.progress > 0.5 ? 1 : 0) : dock.progress
  }

  var body: some View {
    TimelineDockedBarV3(
      label: label,
      shortLabel: shortLabel,
      days: days,
      selectedDay: selectedDay,
      stampsVisible: reduceMotion || dock.progress >= 1,
      onSelectDay: onSelectDay,
      onStampsFrame: { dock.barStampsFrame = $0 }
    )
    .padding(.horizontal, Theme.margin)
    .padding(.top, 4)
    .opacity(barOpacity)
    .allowsHitTesting(barOpacity > 0.5)
    .accessibilityHidden(barOpacity < 0.5)
  }
}

/// The stamps that travel from the week card into the docked bar. Drawn only during the
/// transition; at rest and when docked each stamp exists exactly once. The card shape and the
/// bar shape cross-fade while the stamp itself scales and travels.
private struct TravellingStampsHost: View {
  let dock: TimelineDock
  let reduceMotion: Bool
  let days: [TimelineWeekDayV3]

  /// The docked-bar shape for a day: a check, the planned letter, or the day number with an
  /// accent dot when the day holds entries.
  private func barShape(_ day: TimelineWeekDayV3) -> TimelineStampV3.Shape {
    switch day.shape {
    case .done: return .done
    case .planned: return .planned
    default: return day.hasEntries ? .entryNumber : .quietNumber
    }
  }

  var body: some View {
    let m = dock.progress
    if !reduceMotion, m > 0, m < 1 {
      ZStack {
        ForEach(0..<7, id: \.self) { i in
          let s = dock.stripFrame
          let b = dock.barStampsFrame
          let cardX = s.minX + s.width / 7 * (Double(i) + 0.5)
          let barX = b.minX + b.width / 7 * (Double(i) + 0.5)
          let size = CGFloat(34 + (26 - 34) * m)
          ZStack {
            TimelineStampV3(
              shape: days[i].shape, isToday: days[i].isToday, letter: days[i].sessionLetter,
              size: 34, haloOpacity: 1 - m
            )
            .opacity(1 - m)
            TimelineStampV3(
              shape: barShape(days[i]), isToday: days[i].isToday,
              letter: days[i].sessionLetter, size: 26, number: days[i].number, haloOpacity: 0
            )
            .scaleEffect(size / 26)
            .opacity(m)
          }
          .position(
            x: CGFloat(cardX + (barX - cardX) * m),
            y: CGFloat(s.midY + (b.midY - s.midY) * m))
        }
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
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
private func journeyCardLabel(for event: JourneyEvent, revealsDetail: Bool, isRevealed: Bool)
  -> String
{
  var parts: [String] = [event.kind.name, event.title, journeyDayLabel(event.day)]
  if revealsDetail, let detail = event.detail {
    parts.append(detail)
  }
  if event.precision == .timestamp, let instant = event.instant {
    parts.append(instant.formatted(.dateTime.hour().minute().locale(L10n.locale)))
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

  func body(content: Content) -> some View {
    content.accessibilityElement(children: .ignore).accessibilityLabel(
      journeyCardLabel(for: event, revealsDetail: revealsDetail, isRevealed: isRevealed)
    ).accessibilityHint(journeyCardHint(for: event, isRevealed: isRevealed))
      .accessibilityIdentifier("journey.card.\(event.kind.rawValue).\(event.sourceID)")
  }
}

extension View {
  fileprivate func journeyCardAccessibility(
    for event: JourneyEvent, revealsDetail: Bool, isRevealed: Bool
  )
    -> some View
  {
    modifier(
      JourneyCardAccessibilityModifier(
        event: event, revealsDetail: revealsDetail, isRevealed: isRevealed))
  }
}

// MARK: - Missing source

/// A screen shown when a card's source record is gone. Reachable only if a record disappears
/// between the projection and the tap; the copy says exactly that instead of a blank screen.
private struct JourneyMissingSourceView: View {
  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: "questionmark.folder")
        .font(.system(size: 32, weight: .semibold))
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
