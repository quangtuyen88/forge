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

/// A full, locale-aware day label for VoiceOver — the rail shows only the decorative `19`/`SEP`
/// digits, so this is what a screen reader announces for that day.
private /// The event's own clock time, locale-aware. `nil` when the record carries only a day, so the
/// rail shows a bare dot instead of inventing a precision the source never had.
enum JourneyRail {
  /// Width of the timeline's left gutter. Sized so a locale-aware "12:15 PM" fits under the
  /// dot at 10pt without scaling; the rail collapses to a heading above .xxLarge anyway.
  static let width: CGFloat = 52
  /// Centre of the gutter — where the vertical line and every dot sit.
  static let centre: CGFloat = width / 2
}

func journeyEventTime(_ event: JourneyEvent) -> String? {
  guard event.precision == .timestamp, let instant = event.instant else { return nil }
  return instant.formatted(.dateTime.hour().minute().locale(L10n.locale))
}

func journeyDayLabel(_ day: Date) -> String {
  day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(L10n.locale))
}

// MARK: - Timeline

/// The month timeline: the lifter's own records, projected one month at a time into immutable
/// cards. Nothing here is generated, scored or inferred — a card exists because a workout, a
/// measurement, a photo, an applied program change or a note exists.
///
/// The view owns its own scroll view so the page can remember the card it was scrolled to
/// (`.scrollPosition`), while the Progress header and the Overview/Timeline switch stay pinned
/// above it. Month, filter, anchor and the photo-detail preference are device-local
/// `@AppStorage`, so leaving the tab and coming back reopens the same month, the same filter and
/// the nearest card.
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

  // MARK: Body

  var body: some View {
    VStack(spacing: Theme.groupGap) {
      monthHeader
      controls
      if let failure {
        failureBanner(failure)
      }
      content
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
    .navigationDestination(item: $selectedEvent) { event in
      destination(for: event)
    }
    .accessibilityIdentifier("journey.timeline")
  }

  // MARK: Header — month, previous/next, coverage chooser

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
      Button {
        stepMonth(-1)
      } label: {
        Image(systemName: "chevron.left")
          .font(.system(size: 15, weight: .semibold))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .disabled(neighbourMonth(-1) == nil)
      .accessibilityLabel("Previous month")
      .accessibilityIdentifier("journey.month.previous")

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

      Button {
        stepMonth(1)
      } label: {
        Image(systemName: "chevron.right")
          .font(.system(size: 15, weight: .semibold))
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .disabled(neighbourMonth(1) == nil)
      .accessibilityLabel("Next month")
      .accessibilityIdentifier("journey.month.next")

      Spacer(minLength: 0)

      Button {
        showFilter = true
      } label: {
        chip(
          symbol: "line.3.horizontal.decrease",
          title: filterTitle,
          tint: filter.isAll ? Theme.textSecondary : Theme.accent)
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

  /// The nearest month with content in that direction, or `nil` when there is none, so
  /// previous/next never walk into an empty month.
  private func neighbourMonth(_ delta: Int) -> JourneyMonth? {
    let options = coverageOptions.filter { covered($0) }
    return delta < 0
      ? options.filter { $0 < month }.max()
      : options.filter { $0 > month }.min()
  }

  private func stepMonth(_ delta: Int) {
    guard let target = neighbourMonth(delta) else { return }
    selectMonth(target)
  }

  private func selectMonth(_ candidate: JourneyMonth) {
    monthRaw = candidate.identifier
    limit = JourneyRepository.pageSize
    anchorRaw = ""
    scrollTarget = nil
  }

  // MARK: Controls — one filter sheet, add note, overflow

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

  private var controls: some View {
    HStack(spacing: 8) {
      Button(action: composeNote) {
        chip(
          symbol: "square.and.pencil",
          title: String(localized: "Add note", bundle: L10n.bundle),
          tint: Theme.accent)
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
        Image(systemName: "ellipsis.circle")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Theme.textSecondary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("More timeline options")
      .accessibilityIdentifier("journey.menu")
    }
  }

  private func chip(symbol: String, title: String, tint: Color) -> some View {
    HStack(spacing: 6) {
      Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
      Text(title).forge(13, .semibold).lineLimit(1)
    }
    .foregroundStyle(tint)
    .padding(.horizontal, 12)
    .frame(minHeight: 44)
    .background(Capsule().fill(tint.opacity(0.12)))
    .contentShape(Capsule())
  }

  // MARK: Content

  @ViewBuilder private var content: some View {
    switch state {
    case .loading:
      loadingCard
    case .unavailable(let message):
      unavailableCard(message)
    case .ready:
      if let page, !page.isEmpty {
        list(page)
      } else {
        emptyCard
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

  private func list(_ page: JourneyPage) -> some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 12) {
        ForEach(page.daySections) { section in
          daySection(section)
        }
        if page.hasMore {
          loadMore(page)
        }
        footer
      }
      .scrollTargetLayout()
      .padding(.bottom, 24)
    }
    .scrollPosition(id: $scrollTarget, anchor: .top)
    // A new month or filter is a different list: open it at its top, not at the old offset.
    .id([AnyHashable(page.month), AnyHashable(page.filter)])
    .accessibilityIdentifier("journey.list")
  }

  /// Whether the fixed date column gives way to a full-width heading. The app caps Dynamic Type
  /// at `.xxLarge`; at and beyond that the narrow rail would crowd the cards, so the section
  /// collapses to a heading above the cards instead of clipping content.
  private var useCollapsedRail: Bool {
    dynamicTypeSize.isAccessibilitySize || dynamicTypeSize == .xxLarge
      || dynamicTypeSize == .xxxLarge
  }

  @ViewBuilder
  private func daySection(_ section: JourneyDaySection) -> some View {
    if useCollapsedRail {
      dayHeading(section.day)
        .id("day-\(section.day.timeIntervalSince1970)")
      ForEach(section.events) { event in
        card(for: event, showsTime: true).id(event.id)
      }
    } else {
      railDaySection(section)
    }
  }

  /// Apple Fitness-style day rail: a narrow `19` / `SEP` column with a vertical line and one
  /// semantic-color dot per event, and the cards to the right. Multiple events on one day share
  /// the single date column. The line and dots are decorative and hidden from VoiceOver.
  private func railDaySection(_ section: JourneyDaySection) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 12) {
        dateRailHeader(section.day)
          .frame(width: JourneyRail.width, alignment: .top)
        Spacer(minLength: 0)
      }
      ZStack(alignment: .topLeading) {
        Rectangle()
          .fill(Theme.track.opacity(0.5))
          .frame(width: 1)
          .frame(maxHeight: .infinity)
          .offset(x: JourneyRail.centre)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 8) {
          ForEach(section.events) { event in
            HStack(alignment: .top, spacing: 12) {
              railMarker(event)
                card(for: event, showsTime: false).id(event.id)
              }
            }
          }
        }
    }
  }

  /// One event's marker in the rail: the semantic dot on the line, its clock time directly
  /// beneath. The rail owns the timestamp so the card keeps its full width for the title, and
  /// the pair is decorative — VoiceOver reads the time from the card's combined label.
  private func railMarker(_ event: JourneyEvent) -> some View {
    VStack(spacing: 3) {
      Circle()
        .fill(journeyTint(event.kind))
        .frame(width: 8, height: 8)
      if let time = journeyEventTime(event) {
        Text(time)
          .forge(10, .semibold)
          .monospacedDigit()
          .foregroundStyle(Theme.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
          .allowsTightening(true)
      }
    }
    .padding(.top, 9)
    .frame(width: JourneyRail.width)
    .accessibilityHidden(true)
  }

  private func dateRailHeader(_ day: Date) -> some View {
    VStack(alignment: .center, spacing: 1) {
      Text("\(Calendar.current.component(.day, from: day))")
        .forge(20, .heavy)
        .monospacedDigit()
        .foregroundStyle(Theme.text)
      // ast-grep-ignore: design-no-uppercase-text
      Text(day.formatted(.dateTime.month(.abbreviated).locale(L10n.locale)).uppercased())
        .forge(10, .bold, tracking: 0.6)
        .foregroundStyle(Theme.textSecondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(journeyDayLabel(day))
  }

  private func dayHeading(_ day: Date) -> some View {
    Text(dayTitle(day))
      .forge(13, .semibold)
      .foregroundStyle(Theme.textSecondary)
      .monospacedDigit()
      .padding(.top, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityAddTraits(.isHeader)
  }

  private func dayTitle(_ day: Date) -> String {
    let calendar = Calendar.current
    let short = day.formatted(.dateTime.day().month(.abbreviated).locale(L10n.locale))
    if calendar.isDateInToday(day) {
      return String(localized: "Today · \(short)", bundle: L10n.bundle)
    }
    if calendar.isDateInYesterday(day) {
      return String(localized: "Yesterday · \(short)", bundle: L10n.bundle)
    }
    return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(L10n.locale))
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
    VStack(alignment: .leading, spacing: Theme.groupGap) {
      JourneyOfflineNote()
      JourneyDisabledCapabilitiesCard()
    }
    .padding(.top, 6)
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

  @ViewBuilder private func card(for event: JourneyEvent, showsTime: Bool) -> some View {
    switch event.kind {
    case .reflection:
      Button {
        editor = ReflectionEditorTarget(
          reflectionID: UUID(uuidString: event.sourceID), day: event.day)
      } label: {
        JourneyEventCard(
          event: event, isRevealed: false, revealsDetail: true, showsTime: showsTime,
          onHide: { hide(event) })
      }
      .buttonStyle(RowPressStyle())
      .journeyCardAccessibility(for: event, revealsDetail: true, isRevealed: false)
    case .progressPhoto:
      if revealedPhotos.contains(event.id.rawValue) {
        NavigationLink {
          ProgressPhotosView()
        } label: {
          JourneyEventCard(
            event: event, isRevealed: true, revealsDetail: true, showsTime: showsTime,
            onHide: { hide(event) })
        }
        .journeyCardAccessibility(for: event, revealsDetail: true, isRevealed: true)
      } else {
        Button {
          revealedPhotos.insert(event.id.rawValue)
          acknowledge(String(localized: "Photo revealed on this device", bundle: L10n.bundle))
        } label: {
          JourneyEventCard(
            event: event, isRevealed: false, revealsDetail: photoDetailsEnabled,
            showsTime: showsTime, onHide: { hide(event) })
        }
        .buttonStyle(RowPressStyle())
        .journeyCardAccessibility(
          for: event, revealsDetail: photoDetailsEnabled, isRevealed: false)
      }
    default:
      Button {
        selectedEvent = event
      } label: {
        JourneyEventCard(
          event: event, isRevealed: false, revealsDetail: true, showsTime: showsTime,
          onHide: { hide(event) })
      }
      .buttonStyle(RowPressStyle())
      .journeyCardAccessibility(for: event, revealsDetail: true, isRevealed: false)
    }
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
      page = result
      coverage = repository.coveredMonths()
      hiddenCount = repository.hiddenItems().count
      state = .ready
      hasLoaded = true
      failure = nil
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
    } catch {
      // Keep the last good page on screen; surface the read failure instead of an empty month.
      failure = message(for: error)
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

// MARK: - Card

/// One timeline card. Full-width, one per row: the layout wraps instead of depending on a
/// narrow side rail, so it survives the largest Dynamic Type sizes the app allows, and the whole
/// surface is a single 56pt-tall tap target.
private struct JourneyEventCard: View {
  let event: JourneyEvent
  let isRevealed: Bool
  /// Whether the secondary line may be shown. Photo entries keep it hidden until revealed.
  let revealsDetail: Bool
  /// Whether the card prints the timestamp itself. False in the rail layout, where the gutter
  /// carries it beside the dot; true in the collapsed layout, which has no gutter.
  let showsTime: Bool
  let onHide: () -> Void

  private var timeText: String? {
    guard showsTime else { return nil }
    return journeyEventTime(event)
  }

  private var secondary: String? {
    guard revealsDetail else { return nil }
    return event.detail
  }

  /// The trailing text action. Delegates to the shared assembler so the visible row and the
  /// VoiceOver label can never drift apart.
  private var actionText: String { journeyCardActionText(for: event) }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(event.title)
          .forgeBodyStrong()
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        if let timeText {
          Text(timeText).forgeCaption().monospacedDigit()
        }
      }
      if let secondary {
        Text(secondary)
          .forgeLabel()
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
      }
      if event.kind == .progressPhoto {
        HStack(spacing: 4) {
          Image(systemName: isRevealed ? "eye" : "lock.fill")
            .font(.system(size: 9, weight: .semibold))
          Text(
            isRevealed
              ? "Revealed on this device" : (revealsDetail ? "Private" : "Private · tap to reveal")
          )
          .forge(11, .semibold)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.track.opacity(0.35)))
      }
      HStack(spacing: 4) {
        Spacer(minLength: 0)
        Text(actionText)
          .forge(13, .semibold)
          .fixedSize(horizontal: false, vertical: true)
        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Theme.textTertiary)
      }
      .foregroundStyle(Theme.textSecondary)
    }
    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.card)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
        .stroke(Theme.ring, lineWidth: 0.7)
    )
    .contentShape(Rectangle())
    .contextMenu {
      Button(role: .destructive, action: onHide) {
        Label("Hide from timeline", systemImage: "eye.slash")
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

// MARK: - Truthful footnotes

/// The timeline is local: no network call draws it. Said once, plainly, so an offline lifter is
/// never left wondering whether the timeline is stale or incomplete.
private struct JourneyOfflineNote: View {
  var body: some View {
    Label(
      "Works offline. The timeline reads records already stored on this device; browsing it makes no network request.",
      systemImage: "wifi.slash"
    )
    .forgeCaption()
    .fixedSize(horizontal: false, vertical: true)
    .accessibilityIdentifier("journey.offlineNote")
  }
}

/// The capabilities this surface deliberately does not have. Stated in the UI rather than left
/// ambiguous, so an absent milestone or review reads as "not built" instead of "nothing found".
private struct JourneyDisabledCapabilitiesCard: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Not in this timeline").forgeSection()
      row("flag.checkered", "Milestones are not detected automatically")
      row("doc.text.magnifyingglass", "No monthly review is written for you")
      row("trophy", "Personal records stay on their own charts")
      row("lock.shield", "Notes and body entries are never shared or published")
      row("text.badge.xmark", "No generated advice about your results")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
    .accessibilityIdentifier("journey.capabilities")
  }

  private func row(_ symbol: String, _ text: String) -> some View {
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
