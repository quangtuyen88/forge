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
  /// `,` joined — empty means All), and the event id at the top of the list.
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

/// One presentation of the program-change detail sheet, built only at the moment a row is
/// tapped so the (history-walking) detail assembly never runs inside `body`.
private struct ProgramChangeTarget: Identifiable {
  let detail: ProgramChangeDetail
  var id: String { "\(detail.state == .applied ? "applied" : "scheduled")-\(detail.row.id)" }
}

/// The one semantic accent per source kind, shared by the timeline rail and the cards.
private func journeyTint(_ kind: JourneySourceKind) -> Color {
  switch kind {
  case .workout: return Theme.metricSets
  case .bodyMeasurement: return Theme.metricLoad
  case .progressPhoto: return Theme.metricTime
  case .programChange: return Theme.metricLoad
  case .reflection: return Theme.accent
  }
}

/// The event's own clock time, locale-aware. `nil` when the record carries only a day.
func journeyEventTime(_ event: JourneyEvent) -> String? {
  guard event.precision == .timestamp, let instant = event.instant else { return nil }
  return instant.formatted(.dateTime.hour().minute().locale(L10n.locale))
}

/// A full, locale-aware day label for VoiceOver and the day-circle buttons.
func journeyDayLabel(_ day: Date) -> String {
  day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(L10n.locale))
}

// MARK: - Timeline

/// The month timeline: the lifter's own records, projected one month at a time into typed
/// cards on a week-oriented rail. Nothing here is generated, scored or inferred — a card
/// exists because a workout, a measurement, a photo, an applied program change or a note
/// exists.
///
/// The view owns its own scroll view so the page can remember the card it was scrolled to
/// (`.scrollPosition`), while the month row stays pinned above it. Month, filter, anchor and
/// the photo-detail preference are device-local `@AppStorage`, so leaving the tab and coming
/// back reopens the same month, the same filter and the nearest card.
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
  @State private var scrollTarget: String?
  @State private var showFilter = false
  @State private var showHidden = false
  @State private var showProfile = false
  @State private var editor: ReflectionEditorTarget?
  @State private var selectedEvent: JourneyEvent?
  @State private var ownerID = ""
  @State private var hasLoaded = false
  /// The day/section model the list draws: events plus grouped program-change cards.
  @State private var sections: [JourneySection] = []
  /// Applied and scheduled program-change groups, computed once per reload — both walks cross
  /// the whole history, so they never run inside `body`.
  @State private var appliedGroups: [ProgramChangeGroup] = []
  @State private var scheduledGroups: [ProgramChangeGroup] = []
  /// The week the week card is showing, or `nil` to derive it from the month and the page.
  @State private var shownWeekStart: Date?
  @State private var changeTarget: ProgramChangeTarget?

  // MARK: Body

  var body: some View {
    VStack(spacing: Theme.groupGap) {
      monthHeader
      if let failure {
        failureBanner(failure)
      }
      timelineList
    }
    .padding(.horizontal, Theme.margin)
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
    .onChange(of: scrollTarget) { _, value in if let value { anchorRaw = value } }
    .onChange(of: overridesStamp) { _, _ in rebuildProgramChangeGroups() }
    .sheet(isPresented: $showFilter) {
      JourneyFilterSheet(initial: filter, onApply: applyFilter, onAddNote: composeNote)
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
    .sheet(item: $changeTarget) { target in
      ProgramChangeSheet(detail: target.detail)
    }
    .navigationDestination(item: $selectedEvent) { event in
      destination(for: event)
    }
    .accessibilityIdentifier("journey.timeline")
  }

  // MARK: Header — month chooser, filter

  private var month: JourneyMonth {
    JourneyMonth(identifier: monthRaw) ?? JourneyMonth(containing: .now)
  }

  private var monthTitle: String {
    month.startDate().formatted(.dateTime.month(.wide).year().locale(L10n.locale))
  }

  /// Months the chooser can offer: every month that actually holds content, plus the month being
  /// shown and the current month, so a lifter who has never recorded anything can still open
  /// today's month and write a note.
  private var coverageOptions: [JourneyMonth] {
    var options = Set(coverage)
    options.insert(month)
    options.insert(JourneyMonth(containing: .now))
    return options.sorted(by: >)
  }

  private func covered(_ candidate: JourneyMonth) -> Bool {
    coverage.contains(candidate) || candidate == JourneyMonth(containing: .now)
  }

  private var monthHeader: some View {
    HStack(spacing: 8) {
      Menu {
        ForEach(coverageOptions, id: \.identifier) { candidate in
          Button {
            selectMonth(candidate)
          } label: {
            if candidate == month {
              Label(monthLabel(candidate), systemImage: "checkmark")
            } else {
              Text(monthLabel(candidate))
            }
          }
        }
      } label: {
        HStack(spacing: 5) {
          Text(monthTitle)
            .forgeSection()
            .monospacedDigit()
          Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .accessibilityLabel("Month, \(monthTitle)")
      .accessibilityHint("Choose a month that has entries")
      .accessibilityIdentifier("journey.month.coverage")

      Spacer(minLength: 0)

      Button {
        showFilter = true
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "line.3.horizontal.decrease")
            .font(.system(size: 16, weight: .medium))
          Text(filterTitle)
            .forge(15, .medium)
            .lineLimit(1)
          Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
        }
        .foregroundStyle(Theme.text)
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(height: 36)
        .background(Capsule().fill(Theme.innerSurface))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel(
        filter.isAll ? "Filter, all entry types" : "Filter, \(filterTitle) entry types selected"
      )
      .accessibilityIdentifier("journey.filter")
    }
    .accessibilityIdentifier("journey.month.title")
  }

  private func monthLabel(_ candidate: JourneyMonth) -> String {
    let title = candidate.startDate().formatted(.dateTime.month(.wide).year().locale(L10n.locale))
    return covered(candidate)
      ? title
      : String(localized: "\(title) — no entries", bundle: L10n.bundle)
  }

  private func selectMonth(_ candidate: JourneyMonth) {
    monthRaw = candidate.identifier
    limit = JourneyRepository.pageSize
    anchorRaw = ""
    scrollTarget = nil
    shownWeekStart = nil
  }

  // MARK: Filter

  private var filter: JourneyFilter {
    JourneyFilter(
      categories: Set(
        filterRaw.split(separator: ",").compactMap { JourneyCategory(rawValue: String($0)) }))
  }

  private var filterTitle: String {
    filter.isAll
      ? String(localized: "All", bundle: L10n.bundle)
      : String(localized: "\(filter.selectionCount) of 4", bundle: L10n.bundle)
  }

  // MARK: Scroll content — week card, controls, sections, footer

  private var timelineList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 12) {
        weekCard
        controls
        switch state {
        case .loading:
          loadingCard
        case .unavailable(let message):
          unavailableCard(message)
        case .ready:
          if let page, !page.isEmpty {
            ForEach(sections) { section in
              daySection(section)
            }
            if page.hasMore {
              loadMore(page)
            }
          } else {
            emptyCard
          }
        }
        footer
      }
      .scrollTargetLayout()
      .padding(.bottom, 24)
    }
    .scrollPosition(id: $scrollTarget, anchor: .top)
    // A new month or filter is a different list: open it at its top, not at the old offset.
    .id([AnyHashable(month), AnyHashable(filter)])
    .accessibilityIdentifier("journey.list")
  }

  // MARK: Week card

  private var reportingCal: Calendar { TrainingMetrics.reportingCalendar() }

  private var currentWeekStart: Date {
    TrainingMetrics.reportingWeek(containing: .now, calendar: reportingCal).start
  }

  /// Today's week when the shown month is the current month, else the week of the month's
  /// latest day with entries in the loaded page.
  private var weekStart: Date {
    if let shownWeekStart { return shownWeekStart }
    if month == JourneyMonth(containing: .now) { return currentWeekStart }
    if let latest = sections.first(where: { month.contains($0.day) })?.day {
      return TrainingMetrics.reportingWeek(containing: latest, calendar: reportingCal).start
    }
    return TrainingMetrics.reportingWeek(containing: month.startDate(), calendar: reportingCal).start
  }

  private var isCurrentWeek: Bool { weekStart == currentWeekStart }

  private var weekTitle: String {
    let formatter = DateIntervalFormatter()
    formatter.locale = L10n.locale
    formatter.dateTemplate = "dMMM"
    let end = reportingCal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
    return formatter.string(from: weekStart, to: end)
  }

  private var weekCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(weekTitle)
          .forge(15, .semibold)
          .monospacedDigit()
        Spacer(minLength: 8)
        HStack(spacing: 14) {
          weekArrow(symbol: "chevron.left", label: String(localized: "Previous week", bundle: L10n.bundle)) {
            stepWeek(-1)
          }
          weekArrow(symbol: "chevron.right", label: String(localized: "Next week", bundle: L10n.bundle)) {
            stepWeek(1)
          }
          .disabled(isCurrentWeek)
        }
      }
      HStack(alignment: .top, spacing: 0) {
        ForEach(weekDays) { day in
          dayColumn(day)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card(padding: 12)
    .accessibilityIdentifier("journey.week")
  }

  private func weekArrow(symbol: String, label: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.text)
        .frame(width: 32, height: 32)
        .background(Circle().fill(Theme.innerSurface))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityLabel(label)
  }

  /// Moves one reporting week; the month follows the week's Thursday, the day the ISO week
  /// is anchored to.
  private func stepWeek(_ delta: Int) {
    guard let start = reportingCal.date(byAdding: .weekOfYear, value: delta, to: weekStart)
    else { return }
    if let thursday = reportingCal.date(byAdding: .day, value: 3, to: start) {
      let owner = JourneyMonth(containing: thursday, calendar: reportingCal)
      if owner != month {
        selectMonth(owner)
      }
    }
    shownWeekStart = start
  }

  private var weekDays: [JourneyWeekDay] {
    let calendar = reportingCal
    // Every finished workout counts, not only the loaded month's page: a week can span two months.
    let workoutDays = Set(
      sessions.filter { $0.completed && !$0.tombstoned }.map { calendar.startOfDay(for: $0.date) })
    return (0..<7)
      .compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
      .map { date in
        let day = calendar.startOfDay(for: date)
        return JourneyWeekDay(
          date: day,
          hasWorkout: workoutDays.contains(day),
          isToday: calendar.isDateInToday(date),
          isFuture: JourneyDate.isFutureDay(date, now: .now, calendar: calendar))
      }
  }

  private func dayColumn(_ day: JourneyWeekDay) -> some View {
    VStack(spacing: 6) {
      Text(day.date.formatted(.dateTime.weekday(.narrow).locale(L10n.locale)))
        .forge(12, .medium)
        .foregroundStyle(Theme.textSecondary)
      Button {
        scrollTarget = dayAnchor(day.date)
      } label: {
        dayCircle(day)
      }
      .buttonStyle(RowPressStyle())
      .disabled(!sections.contains { $0.day == day.date })
      .accessibilityLabel(dayCircleLabel(day))
    }
    .frame(maxWidth: .infinity)
  }

  private func dayCircle(_ day: JourneyWeekDay) -> some View {
    Text("\(reportingCal.component(.day, from: day.date))")
      .forge(15, .semibold)
      .monospacedDigit()
      .foregroundStyle(
        day.hasWorkout ? Theme.onAccent : day.isFuture
          ? Theme.textSecondary.opacity(0.55) : Theme.text)
      .frame(width: 36, height: 36)
      .background {
        if day.hasWorkout {
          Circle().fill(Theme.metricSets)
        }
      }
      .overlay {
        if !day.hasWorkout && !day.isFuture {
          Circle().strokeBorder(Theme.track, lineWidth: 2)
        }
      }
      .overlay {
        if day.isToday {
          Circle().stroke(Theme.accent, lineWidth: 2)
            .frame(width: 40, height: 40)
        }
      }
      .frame(minWidth: 44, minHeight: 44)
      .contentShape(Rectangle())
  }

  private func dayCircleLabel(_ day: JourneyWeekDay) -> String {
    var parts = [journeyDayLabel(day.date)]
    if day.hasWorkout {
      parts.append(String(localized: "workout", bundle: L10n.bundle))
    }
    if day.isToday {
      parts.append(String(localized: "today", bundle: L10n.bundle))
    }
    return parts.joined(separator: ", ")
  }

  // MARK: Controls — add note, overflow

  private var controls: some View {
    HStack(spacing: 8) {
      Button(action: composeNote) {
        HStack(spacing: 6) {
          Image(systemName: "square.and.pencil")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.accent)
          Text(String(localized: "Add note", bundle: L10n.bundle))
            .forge(15, .semibold)
            .lineLimit(1)
        }
        .foregroundStyle(Theme.text)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .frame(height: 36)
        .background(Capsule().fill(Theme.innerSurface))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityLabel("Add note")
      .accessibilityIdentifier("journey.addNote")

      Spacer(minLength: 0)

      Menu {
        if let page, !page.events.isEmpty {
          Menu {
            ForEach(page.events) { event in
              Button(role: .destructive) {
                hide(event)
              } label: {
                  // Several events in a month share a title; the date tells them apart.
                  let dateText = event.day.formatted(
                    .dateTime.month().day().locale(L10n.locale))
                  Label("\(event.title) · \(dateText)", systemImage: "eye.slash")
                    .accessibilityLabel(
                      String(localized: "Hide \(event.title) · \(dateText)", bundle: L10n.bundle))
              }
            }
          } label: {
            Label("Hide an item", systemImage: "eye.slash")
          }
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
        Menu {
          Toggle(isOn: $photoDetailsEnabled) {
            Label("Show pose labels", systemImage: "tag")
          }
          Text("Shows pose labels only — photos are never revealed or loaded.")
        } label: {
          Label("Photo details", systemImage: "photo")
        }
        Button {
          showProfile = true
        } label: {
          Label("Private profile", systemImage: "person.crop.circle")
        }
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Theme.text)
          .frame(width: 36, height: 36)
          .background(Circle().fill(Theme.innerSurface))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("More timeline options")
      .accessibilityIdentifier("journey.menu")
    }
  }

  // MARK: Content states

  private var loadingCard: some View {
    VStack(spacing: 10) {
      ProgressView()
      Text("Loading this month").forgeLabel()
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 28)
    .card()
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
    .card()
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
    VStack(spacing: 10) {
      Image(systemName: "calendar")
        .font(.system(size: 34, weight: .semibold))
        .foregroundStyle(Theme.metricTime)
        .frame(width: 72, height: 72)
        .background(Circle().fill(Theme.metricTime.opacity(0.12)))
      Text(
        filter.isAll
          ? "Nothing recorded in \(monthTitle)"
          : "No \(filterTitle) entries in \(monthTitle)"
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
    .card()
    .accessibilityIdentifier("journey.empty")
  }

  // MARK: Day sections

  /// Whether the rail gives way to a full-width heading. The app caps Dynamic Type at
  /// `.xxLarge`; at and beyond that the narrow rail would crowd the cards, so the section
  /// collapses to a heading above the cards instead of clipping content.
  private var useCollapsedRail: Bool {
    dynamicTypeSize.isAccessibilitySize || dynamicTypeSize == .xxLarge
      || dynamicTypeSize == .xxxLarge
  }

  private func dayAnchor(_ day: Date) -> String {
    "day-\(day.timeIntervalSince1970)"
  }

  @ViewBuilder
  private func daySection(_ section: JourneySection) -> some View {
    dayHeading(section.day)
      .id(dayAnchor(section.day))
    if useCollapsedRail {
      ForEach(section.items) { item in
        itemCard(item).id(item.id)
      }
    } else {
      railSection(section)
    }
  }

  /// The timeline rail: a 2 pt track at the leading edge, one semantic node per item, and the
  /// cards to its right. The line and the nodes are decorative and hidden from VoiceOver.
  private func railSection(_ section: JourneySection) -> some View {
    ZStack(alignment: .topLeading) {
      Rectangle()
        .fill(Theme.track)
        .frame(width: 2)
        .frame(maxHeight: .infinity)
        .offset(x: 13)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 12) {
        ForEach(section.items) { item in
          HStack(alignment: .top, spacing: 12) {
            railNode(item)
            itemCard(item).id(item.id)
          }
        }
      }
    }
  }

  private func railNode(_ item: JourneyDayItem) -> some View {
    let symbol: String
    let tint: Color
    switch item {
    case .event(let event):
      switch event.kind {
      case .workout: symbol = "dumbbell.fill"
      case .programChange: symbol = "slider.horizontal.3"
      case .reflection: symbol = "note.text"
      case .progressPhoto: symbol = "camera.fill"
      case .bodyMeasurement: symbol = "scalemass.fill"
      }
      tint = journeyTint(event.kind)
    case .programChanges:
      symbol = "slider.horizontal.3"
      tint = journeyTint(.programChange)
    }
    return Image(systemName: symbol)
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(tint)
      .frame(width: 28, height: 28)
      .background(Circle().fill(tint.opacity(0.14)))
      .accessibilityHidden(true)
  }

  private func dayHeading(_ day: Date) -> some View {
    Text(dayTitle(day))
      .forge(15, .semibold)
      .foregroundStyle(Theme.text)
      .monospacedDigit()
      .padding(.top, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
  }

  private func dayTitle(_ day: Date) -> String {
    let calendar = Calendar.current
    let short = day.formatted(
      .dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(L10n.locale))
    if calendar.isDateInToday(day) {
      return String(localized: "Today · \(short)", bundle: L10n.bundle)
    }
    if calendar.isDateInYesterday(day) {
      return String(localized: "Yesterday · \(short)", bundle: L10n.bundle)
    }
    return short
  }

  private func loadMore(_ page: JourneyPage) -> some View {
    VStack(spacing: 8) {
      Button {
        limit += JourneyRepository.pageSize
      } label: {
        Label("Load more", systemImage: "arrow.down.circle")
      }
      .buttonStyle(PillButtonStyle(minHeight: 44))
      .accessibilityIdentifier("journey.loadMore")
      Text(
        String(
          localized: "Showing \(page.events.count) of \(page.visibleCount) entries",
          bundle: L10n.bundle)
      )
      .forgeCaption()
      .monospacedDigit()
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 6)
  }

  private var footer: some View {
    HStack(spacing: 6) {
      Image(systemName: "lock.fill")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
      Text("Notes and photos stay on this device. Private items stay out of shares.")
        .forge(12, .medium)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 6)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("journey.offlineNote")
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

  // MARK: Cards

  @ViewBuilder
  private func itemCard(_ item: JourneyDayItem) -> some View {
    switch item {
    case .event(let event):
      card(for: event)
    case .programChanges(let group):
      JourneyProgramChangesCard(group: group, profile: profiles.first) { row, group in
        openChange(row, in: group)
      }
    }
  }

  @ViewBuilder private func card(for event: JourneyEvent) -> some View {
    switch event.kind {
    case .workout:
      Button {
        selectedEvent = event
      } label: {
        if let session = sessions.first(where: { $0.remoteID == event.sourceID }),
          let repository
        {
          JourneyWorkoutCard(
            event: event, session: session, repository: repository, onHide: { hide(event) })
        } else {
          JourneyGenericCard(event: event, onHide: { hide(event) })
        }
      }
      .buttonStyle(RowPressStyle())
      .journeyCardAccessibility(for: event, revealsDetail: true, isRevealed: false)
    case .reflection:
      Button {
        editor = ReflectionEditorTarget(
          reflectionID: UUID(uuidString: event.sourceID), day: event.day)
      } label: {
        JourneyNoteCard(event: event, onHide: { hide(event) })
      }
      .buttonStyle(RowPressStyle())
      .journeyCardAccessibility(for: event, revealsDetail: true, isRevealed: false)
    case .progressPhoto:
      if revealedPhotos.contains(event.id.rawValue) {
        NavigationLink {
          ProgressPhotosView()
        } label: {
          JourneyPhotoCard(
            event: event, isRevealed: true, showsPose: true, onHide: { hide(event) })
        }
        .journeyCardAccessibility(for: event, revealsDetail: true, isRevealed: true)
      } else {
        Button {
          revealedPhotos.insert(event.id.rawValue)
          acknowledge(String(localized: "Photo revealed on this device", bundle: L10n.bundle))
        } label: {
          JourneyPhotoCard(
            event: event, isRevealed: false, showsPose: photoDetailsEnabled,
            onHide: { hide(event) })
        }
        .buttonStyle(RowPressStyle())
        .journeyCardAccessibility(
          for: event, revealsDetail: photoDetailsEnabled, isRevealed: false)
      }
    default:
      Button {
        selectedEvent = event
      } label: {
        JourneyGenericCard(event: event, onHide: { hide(event) })
      }
      .buttonStyle(RowPressStyle())
      .journeyCardAccessibility(for: event, revealsDetail: true, isRevealed: false)
    }
  }

  /// Builds the detail only at the tap, over the ascending session history it reads.
  private func openChange(_ row: ProgramChangeRow, in group: ProgramChangeGroup) {
    let ascending = sessions.sorted { $0.date < $1.date }
    changeTarget = ProgramChangeTarget(
      detail: ProgramChanges.detail(
        for: row, in: group, sessions: ascending, entries: decisions,
        profile: profiles.first))
  }

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

  private func hide(_ event: JourneyEvent) {
    guard let repository else { return }
    do {
      try repository.hide(event.id)
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
    page = JourneyPage(
      month: current.month,
      filter: current.filter,
      events: Array(sorted.prefix(current.limit)),
      visibleCount: max(current.visibleCount, sorted.count),
      limit: current.limit)
    rebuildSections()
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
    scrollTarget = nil
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
    scrollTarget = nil
    hasLoaded = false
    limit = JourneyRepository.pageSize
    editor = nil
    showHidden = false
    sections = []
    appliedGroups = []
    scheduledGroups = []
    shownWeekStart = nil
    changeTarget = nil
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

  /// Reads the observable override store during body evaluation, so a change anywhere (Today,
  /// the logger) invalidates this view and fires `onChange(of: overridesStamp)` — the one
  /// moment the scheduled groups are rebuilt.
  private var overridesStamp: String {
    scheduledGroups
      .flatMap { $0.rows.compactMap(\.exerciseID) }
      .sorted()
      .map { "\($0)=\(DecisionOverrides.get($0)?.rawValue ?? "")" }
      .joined(separator: "|")
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
      page = result
      coverage = repository.coveredMonths()
      hiddenCount = repository.hiddenItems().count
      state = .ready
      hasLoaded = true
      failure = nil
      rebuildProgramChangeGroups()
      if !anchorRaw.isEmpty, result.events.contains(where: { $0.id.rawValue == anchorRaw }) {
        scrollTarget = anchorRaw
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
      page = try repository.page(month: month, filter: filter, limit: limit)
      coverage = repository.coveredMonths()
      hiddenCount = repository.hiddenItems().count
      state = .ready
      hasLoaded = true
      failure = nil
      rebuildProgramChangeGroups()
    } catch {
      // Keep the last good page on screen; surface the read failure instead of an empty month.
      failure = message(for: error)
    }
  }

  // MARK: Program-change groups and section model

  /// Rebuilds the applied and scheduled groups and the section model. Both group walks cross
  /// the whole history, so this runs on projection, reload and override changes — never
  /// inside `body`.
  private func rebuildProgramChangeGroups() {
    guard let page else {
      appliedGroups = []
      scheduledGroups = []
      sections = []
      return
    }
    let pageChangeIDs = Set(page.events.filter { $0.kind == .programChange }.map(\.sourceID))
    let ledger = decisions.filter { pageChangeIDs.contains($0.journeyID) }
    appliedGroups = ProgramChanges.applied(
      entries: ledger, sessions: sessions, profile: profiles.first)
    scheduledGroups = profiles.first.map {
      ProgramChanges.scheduled(sessions: sessions, profile: $0)
    } ?? []
    rebuildSections()
  }

  private func rebuildSections() {
    guard let page else {
      sections = []
      return
    }
    var appliedBySourceID: [String: ProgramChangeGroup] = [:]
    for group in appliedGroups {
      for row in group.rows {
        if let sourceID = row.sourceID { appliedBySourceID[sourceID] = group }
      }
    }
    var shownApplied = Set<String>()
    let showsChanges = filter.matches(JourneyCategory.programChange)
    let calendar = Calendar.current
    var built: [JourneySection] = []
    for section in page.daySections {
      var items: [JourneyDayItem] = []
      for event in section.events {
        // One group card at its first event; the group's other events disappear.
        if let group = appliedBySourceID[event.sourceID] {
          if shownApplied.insert(group.id).inserted {
            items.append(.programChanges(group))
          }
          continue
        }
        items.append(.event(event))
      }
      if showsChanges {
        for group in scheduledGroups
        where calendar.isDate(group.anchorDate, inSameDayAs: section.day) {
          insertScheduled(group, into: &items)
        }
      }
      built.append(JourneySection(day: section.day, items: items))
    }
    sections = built
  }

  /// A scheduled group is not an event: it slots in right after its anchor session's workout
  /// card when that card is on the page, otherwise at the end of the day.
  private func insertScheduled(_ group: ProgramChangeGroup, into items: inout [JourneyDayItem]) {
    let index = items.lastIndex { item in
      guard case .event(let event) = item, event.kind == .workout,
        let session = sessions.first(where: { $0.remoteID == event.sourceID })
      else { return false }
      return session.dayName == group.dayName && session.date == group.anchorDate
    }
    if let index {
      items.insert(.programChanges(group), at: index + 1)
    } else {
      items.append(.programChanges(group))
    }
  }
}

// MARK: - Section model

/// One day's items: projected events plus grouped program-change cards.
private struct JourneySection: Identifiable {
  let day: Date
  let items: [JourneyDayItem]
  var id: Date { day }
}

private enum JourneyDayItem: Identifiable {
  case event(JourneyEvent)
  case programChanges(ProgramChangeGroup)

  var id: String {
    switch self {
    case .event(let event): return event.id.rawValue
    case .programChanges(let group): return "changes-\(group.id)"
    }
  }
}

/// One column of the week card.
private struct JourneyWeekDay: Identifiable {
  let date: Date
  let hasWorkout: Bool
  let isToday: Bool
  let isFuture: Bool
  var id: Date { date }
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

  /// The timeline's one destructive action on an event card. The source record is untouched.
  fileprivate func journeyHideMenu(_ onHide: @escaping () -> Void) -> some View {
    contextMenu {
      Button(role: .destructive, action: onHide) {
        Label("Hide from timeline", systemImage: "eye.slash")
      }
    }
  }
}

// MARK: - Cards

/// A workout card: the day's name and clock time, its exercises in first-logged order, the
/// featured lift from the repository's own pick, and the recorded minutes and working sets.
private struct JourneyWorkoutCard: View {
  let event: JourneyEvent
  let session: WorkoutSession
  let repository: JourneyRepository
  let onHide: () -> Void

  /// Exercises in the order they were logged, mirroring the session detail's ordering.
  private var orderedExercises: [Exercise] {
    var seen: [String] = []
    for set in session.sets.sorted(by: { $0.setIndex < $1.setIndex })
    where !seen.contains(set.exerciseID) {
      seen.append(set.exerciseID)
    }
    return seen.compactMap { ExerciseDB.find($0) }
  }

  var body: some View {
    let minutes = repository.recordedMinutes(for: session)
    let setCount = repository.workingSetCount(for: session)
    let lift = repository.featuredLiftParts(for: session)
    return HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(event.title)
            .forge(17, .semibold)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 8)
          if let time = journeyEventTime(event) {
            Text(time)
              .forge(12, .medium)
              .monospacedDigit()
              .foregroundStyle(Theme.textSecondary)
          }
        }
        let exercises = orderedExercises
        if !exercises.isEmpty {
          HStack(spacing: 6) {
            ForEach(exercises.prefix(3)) { exercise in
              ExerciseArt(exercise: exercise, size: 52)
            }
            if exercises.count > 3 {
              Text(String(localized: "+\(exercises.count - 3)", bundle: L10n.bundle))
                .forge(13, .semibold)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 52, height: 52)
                .background(
                  RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
                    .fill(Theme.innerSurface))
            }
          }
          .accessibilityHidden(true)
        }
        if let lift {
          (
            Text("Top set · ")
              .forge(15, .regular)
              .foregroundStyle(Theme.textSecondary)
              + Text(String(localized: "\(lift.name) \(lift.value)", bundle: L10n.bundle))
                .forge(15, .semibold)
                .foregroundStyle(Theme.text)
          )
          .fixedSize(horizontal: false, vertical: true)
        }
        if minutes > 0 || setCount > 0 {
          HStack(spacing: 6) {
            if minutes > 0 {
              InfoPill(
                symbol: "timer",
                text: String(localized: "\(minutes) min", bundle: L10n.bundle))
            }
            if setCount > 0 {
              InfoPill(
                symbol: "checkmark.circle",
                text: String(
                  localized: "\(setCount) set\(L10n.pluralSuffix(setCount))",
                  bundle: L10n.bundle))
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
        .accessibilityHidden(true)
    }
    .card(padding: 14)
    .contentShape(Rectangle())
    .journeyHideMenu(onHide)
  }
}

/// A note card: "Note" with its Private tag, the text itself, no invented time.
private struct JourneyNoteCard: View {
  let event: JourneyEvent
  let onHide: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
          Text("Note")
            .forge(13, .semibold)
            .foregroundStyle(Theme.textSecondary)
          PrivateTag()
        }
        if let text = event.detail, !text.isEmpty {
          Text(text)
            .forgeBody()
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
        .accessibilityHidden(true)
    }
    .card(padding: 14)
    .contentShape(Rectangle())
    .journeyHideMenu(onHide)
  }
}

/// A progress-photo card. Image bytes are read only after this device revealed the photo;
/// before that the surface shows a tap-to-reveal capsule and nothing else.
private struct JourneyPhotoCard: View {
  let event: JourneyEvent
  let isRevealed: Bool
  let showsPose: Bool
  let onHide: () -> Void

  /// Loaded only when revealed — never before the lifter's own tap on this device.
  @State private var image: UIImage?

  /// About twice the card's photo surface, so the downscale stays sharp at 2× screens.
  private static let thumbnailSize = CGSize(width: 640, height: 480)

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 6) {
          Text("Progress photo")
            .forge(13, .semibold)
            .foregroundStyle(Theme.textSecondary)
          PrivateTag()
          Spacer(minLength: 8)
          if let time = journeyEventTime(event) {
            Text(time)
              .forge(12, .medium)
              .monospacedDigit()
              .foregroundStyle(Theme.textSecondary)
          }
        }
        if showsPose, let pose = event.detail, !pose.isEmpty {
          Text(pose)
            .forge(13, .medium)
            .foregroundStyle(Theme.textSecondary)
        }
        photoSurface
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
        .accessibilityHidden(true)
    }
    .card(padding: 14)
    .contentShape(Rectangle())
    .journeyHideMenu(onHide)
    .task(id: isRevealed) { await loadIfRevealed() }
  }

  /// One decode per reveal, off the main thread, downscaled to about twice the card.
  private func loadIfRevealed() async {
    guard isRevealed else { return }
    let url = ProgressPhoto.directory.appendingPathComponent(event.sourceID)
    let size = Self.thumbnailSize
    image = await Task.detached(priority: .userInitiated) {
      UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: size)
    }.value
  }

  private var photoSurface: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Theme.metricTime.opacity(0.10)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: 120)
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
    .overlay {
      if image == nil {
        revealCapsule(
          isRevealed
            ? String(localized: "Revealed on this device", bundle: L10n.bundle)
            : String(localized: "Tap to reveal", bundle: L10n.bundle))
      }
    }
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
        .strokeBorder(Theme.imageOutline, lineWidth: 1)
    )
    .accessibilityHidden(true)
  }

  private func revealCapsule(_ text: String) -> some View {
    HStack(spacing: 5) {
      Image(systemName: "eye")
        .font(.system(size: 13, weight: .medium))
        .accessibilityHidden(true)
      Text(text)
        .forge(12, .medium)
    }
    .foregroundStyle(Theme.textSecondary)
    .padding(.horizontal, 12)
    .frame(height: 30)
    .background(Capsule().fill(Theme.card))
  }
}

/// The generic card every remaining kind falls back to: title, time, detail, chevron.
private struct JourneyGenericCard: View {
  let event: JourneyEvent
  let onHide: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(event.title)
            .forge(17, .semibold)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 8)
          if let time = journeyEventTime(event) {
            Text(time)
              .forge(12, .medium)
              .monospacedDigit()
              .foregroundStyle(Theme.textSecondary)
          }
        }
        if let detail = event.detail {
          Text(detail)
            .forgeLabel()
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Image(systemName: "chevron.right")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
        .accessibilityHidden(true)
    }
    .card(padding: 14)
    .contentShape(Rectangle())
    .journeyHideMenu(onHide)
  }
}

/// One program-changes card: its state chip and one row per change, each opening the sheet.
private struct JourneyProgramChangesCard: View {
  let group: ProgramChangeGroup
  let profile: UserProfile?
  let onRowTap: (ProgramChangeRow, ProgramChangeGroup) -> Void

  private var dayText: String {
    group.dayName.isEmpty ? "" : localizedDayName(group.dayName)
  }

  private var headerTitle: String {
    switch group.state {
    case .scheduled:
      return dayText.isEmpty
        ? String(localized: "Program changes", bundle: L10n.bundle)
        : String(localized: "Program changes after \(dayText)", bundle: L10n.bundle)
    case .applied:
      return dayText.isEmpty
        ? String(localized: "Program changes", bundle: L10n.bundle)
        : String(localized: "Program changes for \(dayText)", bundle: L10n.bundle)
    }
  }

  private var timeText: String? {
    group.anchorDate.formatted(.dateTime.hour().minute().locale(L10n.locale))
  }

  private var stateLine: String? {
    switch group.state {
    case .scheduled:
      guard !dayText.isEmpty else { return nil }
      if let date = group.effectiveDate {
        return String(
          localized: "From next \(dayText) · \(shortDate(date))", bundle: L10n.bundle)
      }
      return String(localized: "From your next \(dayText)", bundle: L10n.bundle)
    case .applied:
      let date = shortDate(group.effectiveDate ?? group.anchorDate)
      return dayText.isEmpty
        ? String(localized: "Applied · \(date)", bundle: L10n.bundle)
        : String(localized: "Applied when \(dayText) started · \(date)", bundle: L10n.bundle)
    }
  }

  private func shortDate(_ date: Date) -> String {
    date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(L10n.locale))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(headerTitle)
          .forge(13, .semibold)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        if let timeText {
          Text(timeText)
            .forge(12, .medium)
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
        }
      }
      if let stateLine {
        HStack(spacing: 8) {
          StateChip(
            text: group.state == .scheduled
              ? String(localized: "Scheduled", bundle: L10n.bundle)
              : String(localized: "Applied", bundle: L10n.bundle),
            tint: group.state == .scheduled ? Theme.metricTime : Theme.positive)
          Text(stateLine)
            .forge(13, .medium)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
        if index > 0 {
          Rectangle()
            .fill(Theme.ring)
            .frame(height: 1)
        }
        JourneyProgramChangeRow(row: row, state: group.state, profile: profile) {
          onRowTap(row, group)
        }
      }
    }
    .card(padding: 14)
  }
}

/// One change row: art tile, name, change line with the new value emphasized, reason, chevron.
private struct JourneyProgramChangeRow: View {
  let row: ProgramChangeRow
  let state: ProgramChangeState
  let profile: UserProfile?
  let onTap: () -> Void

  private func load(_ kg: Double) -> String {
    ProgramChanges.loadText(kg, exerciseID: row.exerciseID, profile: profile)
  }

  private func value(_ text: String, accent: Bool = false) -> Text {
    Text(text)
      .forge(15, .semibold)
      .foregroundStyle(accent ? Theme.accent : Theme.text)
  }

  private func secondary(_ text: Text) -> Text {
    text
      .forge(15, .regular)
      .foregroundStyle(Theme.textSecondary)
  }

  private var changeLine: Text {
    if row.kept, case .unchanged(let kg) = row.change {
      return secondary(Text("Kept ")) + value(load(kg))
    }
    switch row.change {
    case .increase(let fromKg, let toKg):
      return secondary(Text("New target "))
        + value(load(toKg), accent: true)
        + secondary(Text(String(localized: " was \(load(fromKg))", bundle: L10n.bundle)))
    case .decrease(let fromKg, let toKg):
      return secondary(Text("Lighter target "))
        + value(load(toKg))
        + secondary(Text(String(localized: " was \(load(fromKg))", bundle: L10n.bundle)))
    case .unchanged(let kg):
      return secondary(Text("Unchanged ")) + value(load(kg))
    case .starting(let kg):
      return secondary(Text("Starting target "))
        + value(load(kg))
    case .addReps(let kg):
      return secondary(Text("Same load ")) + value(load(kg))
        + secondary(Text(", add a rep"))
    case .other(let summary):
      return secondary(Text(summary))
    }
  }

  /// The same sentence as plain text, for the row's combined VoiceOver label.
  private var changePlainText: String {
    if row.kept, case .unchanged(let kg) = row.change {
      return String(localized: "Kept \(load(kg))", bundle: L10n.bundle)
    }
    switch row.change {
    case .increase(let fromKg, let toKg):
      return String(
        localized: "New target \(load(toKg)) was \(load(fromKg))", bundle: L10n.bundle)
    case .decrease(let fromKg, let toKg):
      return String(
        localized: "Lighter target \(load(toKg)) was \(load(fromKg))", bundle: L10n.bundle)
    case .unchanged(let kg):
      return String(localized: "Unchanged \(load(kg))", bundle: L10n.bundle)
    case .starting(let kg):
      return String(localized: "Starting target \(load(kg))", bundle: L10n.bundle)
    case .addReps(let kg):
      return String(localized: "Same load \(load(kg)), add a rep", bundle: L10n.bundle)
    case .other(let summary):
      return summary
    }
  }

  private var accessibilityText: String {
    var parts = [row.name, changePlainText]
    if !row.reason.isEmpty { parts.append(row.reason) }
    parts.append(
      state == .scheduled
        ? String(localized: "Scheduled", bundle: L10n.bundle)
        : String(localized: "Applied", bundle: L10n.bundle))
    return parts.joined(separator: ", ")
  }

  @ViewBuilder private var art: some View {
    if let exerciseID = row.exerciseID, let exercise = ExerciseDB.find(exerciseID) {
      ExerciseArt(exercise: exercise, size: 52)
    } else {
      IconBadge(symbol: "slider.horizontal.3", size: 52)
    }
  }

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 12) {
        art
        VStack(alignment: .leading, spacing: 2) {
          Text(row.name)
            .forge(15, .semibold)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
          changeLine
            .fixedSize(horizontal: false, vertical: true)
          if !row.reason.isEmpty {
            Text(row.reason)
              .forge(13, .regular)
              .foregroundStyle(Theme.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.textTertiary)
          .accessibilityHidden(true)
      }
      .padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(JourneyRowHighlightStyle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
  }
}

/// Pressed change rows light up instead of scaling — a scale would fight the card surface.
private struct JourneyRowHighlightStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background {
        if configuration.isPressed {
          RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
            .fill(Theme.innerSurface)
            .padding(.horizontal, -8)
            .padding(.vertical, -6)
        }
      }
  }
}

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
