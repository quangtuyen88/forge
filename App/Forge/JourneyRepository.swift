import ForgeCore
import Foundation
import SwiftData

// MARK: - Page

/// A bounded slice of one month's timeline. Every field is derived from records that exist
/// right now; the page holds no reference to a source object, so a card can be drawn and
/// linked without faulting the source back in.
struct JourneyPage {
  let month: JourneyMonth
  let filter: JourneyFilter
  /// The visible cards, already filtered, hidden-resolved and sorted, cut to `limit`.
  let events: [JourneyEvent]
  /// How many cards matched in total, before the `limit` cut. `events.count == min(visibleCount, limit)`.
  let visibleCount: Int
  let limit: Int

  /// True when more cards for this month/filter exist beyond the current page.
  var hasMore: Bool { visibleCount > events.count }
  var isEmpty: Bool { events.isEmpty }

  /// The current page's cards grouped under their resolved local day, newest day first.
  var daySections: [JourneyDaySection] {
    var order: [Date] = []
    var buckets: [Date: [JourneyEvent]] = [:]
    for event in events {
      if buckets[event.day] == nil { order.append(event.day) }
      buckets[event.day, default: []].append(event)
    }
    return order.map { JourneyDaySection(day: $0, events: buckets[$0] ?? []) }
  }
}

/// One day heading plus the cards filed under it.
struct JourneyDaySection: Identifiable, Equatable {
  let day: Date
  let events: [JourneyEvent]
  var id: Date { day }
}

// MARK: - Errors

enum JourneyRepositoryError: Error, LocalizedError, Equatable {
  case validation(JourneyValidationError)
  case missingOwner
  case notFound
  case foreignOwner
  case requestAlreadyDeleted
  case revisionConflict(expected: Int, actual: Int)

  var errorDescription: String? {
    switch self {
    case .validation(let error): return error.description
    case .missingOwner: return "This profile has no stable identifier yet."
    case .notFound: return "That item no longer exists."
    case .foreignOwner: return "That item belongs to a different local account."
    case .requestAlreadyDeleted:
      return "That note was already deleted. Start a new note to save it again."
    case .revisionConflict: return "This was changed on another screen. Reopen it to continue."
    }
  }
}

// MARK: - Program-change policy

/// Which `DecisionLogEntry` types the timeline is willing to present as a **program change**.
///
/// Default-deny: only a type this build has seen and classified is accepted, so a decision
/// type added by a future build is silently absent rather than mis-labelled. The set is the
/// subset of decision types that describe an adjustment actually applied to the program —
/// load/volume/reps changes, swaps, deload and whole-session changes. Deliberately excluded:
/// `experiment` / `experiment_result` (a self-run A/B, not a program change), `constraints`
/// and `equipmentPassport` (configuration, not a training change), and every `goal*` type
/// (a goal is tracked on its own surface, not as a timeline program change).
enum JourneyProgramChangePolicy {
  static let meaningfulAppliedTypes: Set<String> = [
    "load_change",
    "volume_change",
    "swap",
    "session",
    "deload",
    "plateau",
    "import_plan",
    "weekplan",
  ]

  /// True when `type` is an applied program change this build understands.
  static func accepts(_ type: String) -> Bool {
    let normalized = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return !normalized.isEmpty && meaningfulAppliedTypes.contains(normalized)
  }

  /// A short, non-claiming label for a decision type. Unknown types fall back to a readable
  /// form of the raw value rather than a fabricated summary.
  /// A first prescription has no prior value. Labelling it "Load changed" made every initial
  /// target in the timeline read as an adjustment the coach made, and made the Hide menu a list
  /// of indistinguishable "Hide Load changed" rows.
  static func title(for type: String, from: Double? = nil, to: Double? = nil) -> String {
    if type == "load_change", from == nil, to != nil { return "Starting load" }
    if type == "volume_change", from == nil, to != nil { return "Starting volume" }
    return title(for: type)
  }

  static func title(for type: String) -> String {
    switch type {
    case "load_change": return "Load changed"
    case "volume_change": return "Volume changed"
    case "swap": return "Exercise swapped"
    case "session": return "Session changed"
    case "deload": return "Deload scheduled"
    case "plateau": return "Plateau response"
    case "import_plan": return "Program imported"
    case "weekplan": return "Week planned"
    default: return type.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }
}

// MARK: - Repository

/// Owner-scoped, bounded projection of the lifter's own records into immutable Journey cards.
///
/// Everything here runs on the main actor over the app's single `ModelContext`. The repository
/// never copies raw source payloads (no image bytes, no sets, no body values) and never deletes
/// a source record; hiding is a stored override, not a deletion.
@MainActor
final class JourneyRepository {
  /// One page is 30 cards. "Load more" asks for `limit + pageSize`.
  nonisolated static let pageSize = 30

  let context: ModelContext
  private let profile: UserProfile
  private let calendar: Calendar
  private let clock: () -> Date

  /// Canonical owner id. Never empty: the repository assigns a UUID to the profile once when
  /// `remoteID` is empty, so identity (and therefore every event id) is stable from first use.
  private(set) var ownerID: String

  init(
    context: ModelContext,
    profile: UserProfile,
    accountID: String? = nil,
    calendar: Calendar = .current,
    now: @escaping () -> Date = { .now }
  ) {
    self.context = context
    self.profile = profile
    self.calendar = calendar
    self.clock = now
    self.ownerID = Self.resolveOwner(profile, accountID: accountID, context: context)
  }

  // MARK: Owner

  private static func resolveOwner(
    _ profile: UserProfile, accountID: String?, context: ModelContext
  ) -> String {
    var local = JourneyEventID.canonicalOwner(profile.journeyLocalOwnerID)
    if local.isEmpty {
      local = UUID().uuidString
      profile.journeyLocalOwnerID = local
      profile.updatedAt = .now
    }

    let account = JourneyEventID.canonicalOwner(accountID ?? "")
    guard !account.isEmpty else {
      try? context.save()
      return local
    }

    let bound = JourneyEventID.canonicalOwner(profile.journeyBoundAccountID)
    if bound.isEmpty {
      if local != account { migrateLocalJourney(from: local, to: account, context: context) }
      profile.journeyBoundAccountID = account
      profile.updatedAt = .now
      try? context.save()
    }
    return account
  }

  private static func migrateLocalJourney(
    from oldOwner: String, to newOwner: String, context: ModelContext
  ) {
    let reflections =
      (try? context.fetch(
        FetchDescriptor<JourneyReflection>(predicate: #Predicate { $0.ownerID == oldOwner }))) ?? []
    reflections.forEach { $0.ownerID = newOwner }

    let overrides =
      (try? context.fetch(
        FetchDescriptor<JourneyVisibilityOverride>(predicate: #Predicate { $0.ownerID == oldOwner })
      )) ?? []
    for override in overrides {
      guard let components = JourneyEventID(rawValue: override.eventID).components else {
        override.ownerID = newOwner
        continue
      }
      let migratedID = JourneyEventID.make(
        owner: newOwner,
        kind: components.kind,
        sourceID: components.sourceID,
        facet: components.facet)
      let raw = migratedID.rawValue
      let existing = try? context.fetch(
        FetchDescriptor<JourneyVisibilityOverride>(predicate: #Predicate { $0.eventID == raw })
      ).first
      if let existing {
        existing.hidden = existing.hidden || override.hidden
        existing.revision = max(existing.revision, override.revision) + 1
        existing.updatedAt = max(existing.updatedAt, override.updatedAt)
        context.delete(override)
      } else {
        override.ownerID = newOwner
        override.eventID = raw
      }
    }

    let localProfile = try? context.fetch(
      FetchDescriptor<JourneyPrivateProfile>(predicate: #Predicate { $0.ownerID == oldOwner })
    ).first
    if let localProfile {
      let accountProfile = try? context.fetch(
        FetchDescriptor<JourneyPrivateProfile>(predicate: #Predicate { $0.ownerID == newOwner })
      ).first
      if let accountProfile {
        if accountProfile.displayName.isEmpty {
          accountProfile.displayName = localProfile.displayName
        }
        if accountProfile.trainingStartDate == nil {
          accountProfile.trainingStartDate = localProfile.trainingStartDate
        }
        accountProfile.revision = max(accountProfile.revision, localProfile.revision) + 1
        accountProfile.updatedAt = max(accountProfile.updatedAt, localProfile.updatedAt)
        context.delete(localProfile)
      } else {
        localProfile.ownerID = newOwner
      }
    }
    try? context.save()
  }

  // MARK: Month projection

  /// Projects one calendar month into a bounded, sorted page.
  ///
  /// Order of operations is fixed: collect the month's sources, resolve hidden overrides onto
  /// the cards, apply the OR filter, sort with the one deterministic `JourneySortKey`, and only
  /// then cut to `limit`. Hidden cards are therefore removed **before** the page fills, so a
  /// page of 30 really contains 30 visible cards whenever 30 exist.
  func page(
    month: JourneyMonth,
    filter: JourneyFilter = .all,
    limit: Int = JourneyRepository.pageSize
  ) throws -> JourneyPage {
    let interval = month.interval(calendar: calendar)
    let hidden = try hiddenEventIDs()
    let cards = try collect(in: interval).map { $0.hidden(hidden.contains($0.id.rawValue)) }
    let matching = cards.filter { filter.matches($0) }
    let sorted = JourneySortKey.sorted(matching)
    let slice = Array(sorted.prefix(max(0, limit)))
    return JourneyPage(
      month: month, filter: filter, events: slice, visibleCount: sorted.count, limit: limit)
  }

  /// Collects every candidate card in the month. `inout` dirty flag reports whether a missing
  /// canonical source id was assigned, so the caller saves once after the whole month is read.
  private func collect(in interval: DateInterval) throws -> [JourneyEvent] {
    var dirty = false
    var events: [JourneyEvent] = []
    events.append(contentsOf: try workoutEvents(interval, dirty: &dirty))
    events.append(contentsOf: try measurementEvents(interval, dirty: &dirty))
    events.append(contentsOf: try photoEvents(interval))
    events.append(contentsOf: try programChangeEvents(interval, dirty: &dirty))
    events.append(contentsOf: try reflectionEvents(interval))
    if dirty { try context.save() }
    return events
  }

  // MARK: Workouts

  private func workoutEvents(_ interval: DateInterval, dirty: inout Bool) throws -> [JourneyEvent] {
    let start = interval.start
    let end = interval.end
    let descriptor = FetchDescriptor<WorkoutSession>(
      predicate: #Predicate {
        $0.completed == true && $0.tombstoned == false && $0.date >= start && $0.date < end
      },
      sortBy: [SortDescriptor(\WorkoutSession.date, order: .reverse)])
    let sessions = try context.fetch(descriptor)
    return sessions.map { session in
      if ensureRemoteID(session) { dirty = true }
      return workoutEvent(session)
    }
  }

  private func workoutEvent(_ session: WorkoutSession) -> JourneyEvent {
    var parts: [String] = []
    let eligible = session.analysisSets(.achievements)
    if let featured = featuredLiftLine(eligible) {
      parts.append(featured)
    }
    if !eligible.isEmpty {
      parts.append("\(eligible.count) working set\(eligible.count == 1 ? "" : "s")")
    }
    let minutes = recordedMinutes(session)
    if minutes > 0 { parts.append("\(minutes) min") }
    if session.week > 0 { parts.append("Week \(session.week)") }
    return JourneyEvent(
      owner: ownerID,
      kind: .workout,
      sourceID: session.remoteID,
      title: session.dayName.isEmpty ? "Workout" : session.dayName,
      detail: parts.isEmpty ? nil : parts.joined(separator: " · "),
      date: session.date,
      precision: .timestamp,
      calendar: calendar)
  }

  /// The one featured lift for a session: the heaviest eligible working set, tie-broken by reps,
  /// then set order, then exercise id, so the card is deterministic. Uses the exercise's
  /// localized name and the real weight/reps/unit — never a guessed or parallel figure.
  private func featuredLiftLine(_ eligible: [LoggedSet]) -> String? {
    guard
      let set = eligible.sorted(by: { lhs, rhs in
        if lhs.weightKg != rhs.weightKg { return lhs.weightKg > rhs.weightKg }
        if lhs.reps != rhs.reps { return lhs.reps > rhs.reps }
        if lhs.setIndex != rhs.setIndex { return lhs.setIndex < rhs.setIndex }
        return lhs.exerciseID < rhs.exerciseID
      }).first,
      let exercise = ExerciseDB.find(set.exerciseID)
    else { return nil }
    let lb = profile.isLb(for: set.exerciseID)
    let display = profile.display(kg: set.weightKg, for: set.exerciseID)
    return "\(exercise.localizedName) \(Fmt.kg(display, lb: lb)) × \(set.reps)"
  }

  /// Recorded session duration from persisted set timestamps, mirroring the canonical
  /// `SessionMath.totalMinutes` ceiling to the next whole minute. Zero — and therefore omitted —
  /// when fewer than two distinct timestamps exist.
  private func recordedMinutes(_ session: WorkoutSession) -> Int {
    let times = session.sets.map(\.loggedAt)
    guard let lo = times.min(), let hi = times.max(), hi > lo else { return 0 }
    return (Int(hi.timeIntervalSince(lo)) + 59) / 60
  }

  // MARK: Body measurements

  private func measurementEvents(_ interval: DateInterval, dirty: inout Bool) throws
    -> [JourneyEvent]
  {
    let start = interval.start
    let end = interval.end
    let descriptor = FetchDescriptor<BodyMeasurement>(
      predicate: #Predicate { $0.tombstoned == false && $0.date >= start && $0.date < end },
      sortBy: [SortDescriptor(\BodyMeasurement.date, order: .reverse)])
    let items = try context.fetch(descriptor)
    return items.map { measurement in
      if ensureRemoteID(measurement) { dirty = true }
      return measurementEvent(measurement)
    }
  }

  /// A body card names which metrics were recorded — never their values. The timeline never
  /// copies body data; the canonical detail screen is where the numbers live.
  private func measurementEvent(_ measurement: BodyMeasurement) -> JourneyEvent {
    var metrics: [String] = []
    if measurement.weightKg != nil { metrics.append("Weight") }
    if measurement.bodyFatPercent != nil { metrics.append("Body fat") }
    if !measurement.tape.isEmpty { metrics.append("Tape") }
    return JourneyEvent(
      owner: ownerID,
      kind: .bodyMeasurement,
      sourceID: measurement.remoteID,
      title: "Body check-in",
      detail: metrics.isEmpty ? nil : metrics.joined(separator: " · "),
      date: measurement.date,
      precision: .dayOnly,
      calendar: calendar)
  }

  // MARK: Progress photos

  /// Photos are identified by their file name, never by a `PersistentIdentifier`. The card
  /// carries only the pose label — no image bytes are read or copied.
  private func photoEvents(_ interval: DateInterval) throws -> [JourneyEvent] {
    let start = interval.start
    let end = interval.end
    let descriptor = FetchDescriptor<ProgressPhoto>(
      predicate: #Predicate { $0.date >= start && $0.date < end },
      sortBy: [SortDescriptor(\ProgressPhoto.date, order: .reverse)])
    return try context.fetch(descriptor).compactMap(photoEvent)
  }

  private func photoEvent(_ photo: ProgressPhoto) -> JourneyEvent? {
    let fileName = photo.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !fileName.isEmpty else { return nil }
    return JourneyEvent(
      owner: ownerID,
      kind: .progressPhoto,
      sourceID: fileName,
      title: "Progress photo",
      detail: photo.pose.isEmpty ? nil : photo.pose,
      date: photo.date,
      precision: .dayOnly,
      calendar: calendar)
  }

  // MARK: Program changes

  private func programChangeEvents(_ interval: DateInterval, dirty: inout Bool) throws
    -> [JourneyEvent]
  {
    let start = interval.start
    let end = interval.end
    let descriptor = FetchDescriptor<DecisionLogEntry>(
      predicate: #Predicate { $0.date >= start && $0.date < end },
      sortBy: [SortDescriptor(\DecisionLogEntry.date, order: .reverse)])
    return try context.fetch(descriptor).compactMap { entry in
      if entry.journeyID.isEmpty {
        entry.journeyID = UUID().uuidString
        dirty = true
      }
      return programChangeEvent(entry)
    }
  }

  /// A decision becomes a card only when the conservative type policy accepts it. The canonical
  /// source id is the decision's own derived id (type + subject + instant), never a model id.
  private func programChangeEvent(_ entry: DecisionLogEntry) -> JourneyEvent? {
    guard JourneyProgramChangePolicy.accepts(entry.type) else { return nil }
    let sourceID = entry.journeyID
    guard !sourceID.isEmpty else { return nil }
    return JourneyEvent(
      owner: ownerID,
      kind: .programChange,
      sourceID: sourceID,
      title: JourneyProgramChangePolicy.title(
        for: entry.type, from: entry.fromValue, to: entry.toValue),
      detail: entry.humanSummary.isEmpty ? nil : entry.humanSummary,
      date: entry.date,
      precision: .timestamp,
      calendar: calendar)
  }

  // MARK: Reflections

  private func reflectionEvents(_ interval: DateInterval) throws -> [JourneyEvent] {
    let owner = ownerID
    let start = interval.start
    let end = interval.end
    let descriptor = FetchDescriptor<JourneyReflection>(
      predicate: #Predicate {
        $0.ownerID == owner && $0.tombstoned == false && $0.day >= start && $0.day < end
      },
      sortBy: [SortDescriptor(\JourneyReflection.day, order: .reverse)])
    return try context.fetch(descriptor).map(reflectionEvent)
  }

  private func reflectionEvent(_ reflection: JourneyReflection) -> JourneyEvent {
    JourneyEvent(
      owner: ownerID,
      kind: .reflection,
      sourceID: reflection.reflectionID.uuidString,
      title: "Note",
      detail: reflection.text.isEmpty ? nil : reflection.text,
      date: reflection.day,
      precision: .dayOnly,
      calendar: calendar)
  }

  // MARK: Source existence resolution

  /// True when the referenced record still exists in this store (and, where the source can be
  /// soft-deleted, is not deleted). Used to decide whether a note's typed link is still live.
  func sourceExists(_ reference: JourneySourceReference) -> Bool {
    resolveEvent(kind: reference.kind, sourceID: reference.sourceID) != nil
  }

  /// Rebuilds the one card for a canonical source id, or `nil` when the source is gone. This is
  /// how the Hidden-items sheet resolves a stored override back to a real record — a hidden
  /// card whose source was deleted simply disappears from the list.
  func resolveEvent(kind: JourneySourceKind, sourceID: String) -> JourneyEvent? {
    switch kind {
    case .workout:
      let descriptor = FetchDescriptor<WorkoutSession>(
        predicate: #Predicate {
          $0.remoteID == sourceID && $0.completed == true && $0.tombstoned == false
        })
      guard let session = (try? context.fetch(descriptor))?.first, !sourceID.isEmpty else {
        return nil
      }
      return workoutEvent(session)
    case .bodyMeasurement:
      let descriptor = FetchDescriptor<BodyMeasurement>(
        predicate: #Predicate { $0.remoteID == sourceID && $0.tombstoned == false })
      guard let measurement = (try? context.fetch(descriptor))?.first, !sourceID.isEmpty else {
        return nil
      }
      return measurementEvent(measurement)
    case .progressPhoto:
      let descriptor = FetchDescriptor<ProgressPhoto>(
        predicate: #Predicate { $0.fileName == sourceID })
      guard let photo = (try? context.fetch(descriptor))?.first else { return nil }
      return photoEvent(photo)
    case .programChange:
      let descriptor = FetchDescriptor<DecisionLogEntry>(
        predicate: #Predicate { $0.journeyID == sourceID })
      guard let entry = (try? context.fetch(descriptor))?.first,
        JourneyProgramChangePolicy.accepts(entry.type)
      else { return nil }
      return programChangeEvent(entry)
    case .reflection:
      guard let uuid = UUID(uuidString: sourceID) else { return nil }
      let owner = ownerID
      let descriptor = FetchDescriptor<JourneyReflection>(
        predicate: #Predicate {
          $0.ownerID == owner && $0.reflectionID == uuid && $0.tombstoned == false
        })
      guard let reflection = (try? context.fetch(descriptor))?.first else { return nil }
      return reflectionEvent(reflection)
    }
  }

  // MARK: Hidden overrides

  /// Returns the canonical event ids this owner has hidden. Loaded once per projection.
  private func hiddenEventIDs() throws -> Set<String> {
    let owner = ownerID
    let descriptor = FetchDescriptor<JourneyVisibilityOverride>(
      predicate: #Predicate<JourneyVisibilityOverride> { item in
        item.ownerID == owner && item.hidden == true
      })
    return Set(try context.fetch(descriptor).map(\.eventID))
  }

  /// Hides a card. The source record is untouched.
  func hide(_ eventID: JourneyEventID) throws {
    _ = try setHidden(eventID, hidden: true)
  }

  /// Restores a hidden card. Keeps a `hidden == false` tombstone so the action is auditable.
  func restore(_ eventID: JourneyEventID) throws {
    _ = try setHidden(eventID, hidden: false)
  }

  @discardableResult
  private func setHidden(_ eventID: JourneyEventID, hidden: Bool) throws
    -> JourneyVisibilityOverride
  {
    guard let components = eventID.components else { throw JourneyRepositoryError.notFound }
    guard components.owner == ownerID else { throw JourneyRepositoryError.foreignOwner }
    guard resolveEvent(kind: components.kind, sourceID: components.sourceID) != nil else {
      throw JourneyRepositoryError.notFound
    }
    let raw = eventID.rawValue
    let existing = try context.fetch(
      FetchDescriptor<JourneyVisibilityOverride>(
        predicate: #Predicate<JourneyVisibilityOverride> { item in item.eventID == raw })
    ).first
    let override: JourneyVisibilityOverride
    if let existing {
      guard existing.ownerID == ownerID else { throw JourneyRepositoryError.foreignOwner }
      existing.hidden = hidden
      existing.revision += 1
      existing.updatedAt = clock()
      override = existing
    } else {
      override = JourneyVisibilityOverride(
        eventID: raw, ownerID: ownerID, hidden: hidden, revision: 1, updatedAt: clock())
      context.insert(override)
    }
    try context.save()
    return override
  }

  /// The Hidden-items sheet: every currently hidden card, resolved back to a live source and
  /// sorted by the one comparator. A hidden card whose source was deleted is dropped.
  func hiddenItems(filter: JourneyFilter = .all) -> [JourneyEvent] {
    let owner = ownerID
    let descriptor = FetchDescriptor<JourneyVisibilityOverride>(
      predicate: #Predicate { $0.ownerID == owner && $0.hidden == true })
    let overrides = (try? context.fetch(descriptor)) ?? []
    var events: [JourneyEvent] = []
    for override in overrides {
      let id = JourneyEventID(rawValue: override.eventID)
      guard let components = id.components,
        let event = resolveEvent(kind: components.kind, sourceID: components.sourceID)
      else { continue }
      // Category OR only: an empty selection means All, and the hidden gate is intentionally
      // not applied here — this list exists precisely to show hidden cards.
      guard filter.matches(event.category) else { continue }
      events.append(event.hidden(true))
    }
    return JourneySortKey.sorted(events)
  }

  // MARK: Month coverage

  /// True when any source in this store has content inside `month`. Uses `fetchLimit = 1` per
  /// source type, so it never loads a month's worth of rows just to answer yes/no.
  func hasContent(in month: JourneyMonth) -> Bool {
    let interval = month.interval(calendar: calendar)
    let start = interval.start
    let end = interval.end

    var sessions = FetchDescriptor<WorkoutSession>(
      predicate: #Predicate {
        $0.completed == true && $0.tombstoned == false && $0.date >= start && $0.date < end
      })
    sessions.fetchLimit = 1
    if !((try? context.fetch(sessions)) ?? []).isEmpty { return true }

    var measurements = FetchDescriptor<BodyMeasurement>(
      predicate: #Predicate { $0.tombstoned == false && $0.date >= start && $0.date < end })
    measurements.fetchLimit = 1
    if !((try? context.fetch(measurements)) ?? []).isEmpty { return true }

    var photos = FetchDescriptor<ProgressPhoto>(
      predicate: #Predicate { $0.date >= start && $0.date < end })
    photos.fetchLimit = 1
    if !((try? context.fetch(photos)) ?? []).isEmpty { return true }

    var decisions = FetchDescriptor<DecisionLogEntry>(
      predicate: #Predicate { $0.date >= start && $0.date < end })
    decisions.fetchLimit = 1
    if !((try? context.fetch(decisions)) ?? []).isEmpty {
      // The month has decisions; confirm at least one is a type the timeline shows.
      let all =
        (try? context.fetch(
          FetchDescriptor<DecisionLogEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < end })
        )) ?? []
      if all.contains(where: { JourneyProgramChangePolicy.accepts($0.type) }) { return true }
    }

    let owner = ownerID
    var reflections = FetchDescriptor<JourneyReflection>(
      predicate: #Predicate {
        $0.ownerID == owner && $0.tombstoned == false && $0.day >= start && $0.day < end
      })
    reflections.fetchLimit = 1
    if !((try? context.fetch(reflections)) ?? []).isEmpty { return true }

    return false
  }

  /// The month of the earliest record, or `nil` when the store is empty for this feature.
  var earliestMonth: JourneyMonth? {
    guard let date = earliestDate() else { return nil }
    return JourneyMonth(containing: date, calendar: calendar)
  }

  /// The month of the most recent record, or `nil` when the store is empty for this feature.
  var latestMonth: JourneyMonth? {
    guard let date = latestDate() else { return nil }
    return JourneyMonth(containing: date, calendar: calendar)
  }

  /// Every month between the first and last record that actually holds content, ascending.
  /// The coverage chooser reads this to grey out empty months instead of guessing.
  func coveredMonths() -> [JourneyMonth] {
    guard let start = earliestMonth, let end = latestMonth, start <= end else { return [] }
    return JourneyMonth.months(from: start, through: end).filter { hasContent(in: $0) }
  }

  private func earliestDate() -> Date? {
    var dates: [Date] = []
    var sessions = FetchDescriptor<WorkoutSession>(
      predicate: #Predicate<WorkoutSession> { session in
        session.completed == true && session.tombstoned == false
      },
      sortBy: [SortDescriptor(\WorkoutSession.date, order: .forward)])
    sessions.fetchLimit = 1
    if let value = (try? context.fetch(sessions))?.first?.date { dates.append(value) }

    var measurements = FetchDescriptor<BodyMeasurement>(
      predicate: #Predicate<BodyMeasurement> { measurement in measurement.tombstoned == false },
      sortBy: [SortDescriptor(\BodyMeasurement.date, order: .forward)])
    measurements.fetchLimit = 1
    if let value = (try? context.fetch(measurements))?.first?.date { dates.append(value) }

    var photos = FetchDescriptor<ProgressPhoto>(sortBy: [
      SortDescriptor(\ProgressPhoto.date, order: .forward)
    ])
    photos.fetchLimit = 1
    if let value = (try? context.fetch(photos))?.first?.date { dates.append(value) }

    let decisions =
      (try? context.fetch(
        FetchDescriptor<DecisionLogEntry>(sortBy: [
          SortDescriptor(\DecisionLogEntry.date, order: .forward)
        ]))) ?? []
    if let value = decisions.first(where: { entry in JourneyProgramChangePolicy.accepts(entry.type)
    })?.date {
      dates.append(value)
    }

    let owner = ownerID
    var reflections = FetchDescriptor<JourneyReflection>(
      predicate: #Predicate<JourneyReflection> { reflection in
        reflection.ownerID == owner && reflection.tombstoned == false
      },
      sortBy: [SortDescriptor(\JourneyReflection.day, order: .forward)])
    reflections.fetchLimit = 1
    if let value = (try? context.fetch(reflections))?.first?.day { dates.append(value) }

    return dates.min()
  }

  private func latestDate() -> Date? {
    var dates: [Date] = []
    var sessions = FetchDescriptor<WorkoutSession>(
      predicate: #Predicate<WorkoutSession> { session in
        session.completed == true && session.tombstoned == false
      },
      sortBy: [SortDescriptor(\WorkoutSession.date, order: .reverse)])
    sessions.fetchLimit = 1
    if let value = (try? context.fetch(sessions))?.first?.date { dates.append(value) }

    var measurements = FetchDescriptor<BodyMeasurement>(
      predicate: #Predicate<BodyMeasurement> { measurement in measurement.tombstoned == false },
      sortBy: [SortDescriptor(\BodyMeasurement.date, order: .reverse)])
    measurements.fetchLimit = 1
    if let value = (try? context.fetch(measurements))?.first?.date { dates.append(value) }

    var photos = FetchDescriptor<ProgressPhoto>(sortBy: [
      SortDescriptor(\ProgressPhoto.date, order: .reverse)
    ])
    photos.fetchLimit = 1
    if let value = (try? context.fetch(photos))?.first?.date { dates.append(value) }

    let decisions =
      (try? context.fetch(
        FetchDescriptor<DecisionLogEntry>(sortBy: [
          SortDescriptor(\DecisionLogEntry.date, order: .reverse)
        ]))) ?? []
    if let value = decisions.first(where: { entry in JourneyProgramChangePolicy.accepts(entry.type)
    })?.date {
      dates.append(value)
    }

    let owner = ownerID
    var reflections = FetchDescriptor<JourneyReflection>(
      predicate: #Predicate<JourneyReflection> { reflection in
        reflection.ownerID == owner && reflection.tombstoned == false
      },
      sortBy: [SortDescriptor(\JourneyReflection.day, order: .reverse)])
    reflections.fetchLimit = 1
    if let value = (try? context.fetch(reflections))?.first?.day { dates.append(value) }

    return dates.max()
  }

  // MARK: Reflections — write path

  /// Creates a note. Validation runs first; a repeated save with the same `clientRequestID`
  /// returns the record the first attempt produced instead of inserting a duplicate.
  @discardableResult
  func createReflection(_ draft: JourneyReflectionDraft) throws -> JourneyEvent {
    let normalized = draft.normalized(calendar: calendar)
    try validate(normalized)
    if let key = normalized.clientRequestID?.trimmingCharacters(in: .whitespacesAndNewlines),
      !key.isEmpty
    {
      if let existing = activeReflection(clientRequestID: key) {
        return reflectionEvent(existing)
      }
      if hasDeletedReflection(clientRequestID: key) {
        throw JourneyRepositoryError.requestAlreadyDeleted
      }
    }
    let now = clock()
    let reflection = JourneyReflection(
      ownerID: ownerID,
      text: normalized.text,
      day: normalized.resolvedDay(calendar: calendar),
      source: normalized.source,
      clientRequestID: normalized.clientRequestID,
      createdAt: now,
      updatedAt: now,
      revision: 1,
      deleted: false)
    context.insert(reflection)
    try context.save()
    return reflectionEvent(reflection)
  }

  /// Edits a note. `expectedRevision` (when given) rejects a write based on a stale read.
  @discardableResult
  func updateReflection(
    id: UUID,
    draft: JourneyReflectionDraft,
    expectedRevision: Int? = nil
  ) throws -> JourneyEvent {
    guard let reflection = reflection(id: id) else { throw JourneyRepositoryError.notFound }
    if let expectedRevision, expectedRevision != reflection.revision {
      throw JourneyRepositoryError.revisionConflict(
        expected: expectedRevision, actual: reflection.revision)
    }
    let normalized = draft.normalized(calendar: calendar)
    try validate(normalized)
    reflection.text = normalized.text
    reflection.day = normalized.resolvedDay(calendar: calendar)
    reflection.sourceKind = normalized.source?.kind.rawValue
    reflection.sourceID = normalized.source?.sourceID
    if let key = normalized.clientRequestID { reflection.clientRequestID = key }
    reflection.revision += 1
    reflection.updatedAt = clock()
    try context.save()
    return reflectionEvent(reflection)
  }

  /// Soft-deletes a note. The row is kept (flagged) so a re-synchronised duplicate cannot
  /// resurrect content the lifter removed.
  func deleteReflection(id: UUID, expectedRevision: Int? = nil) throws {
    guard let reflection = reflection(id: id), !reflection.tombstoned else {
      throw JourneyRepositoryError.notFound
    }
    if let expectedRevision, expectedRevision != reflection.revision {
      throw JourneyRepositoryError.revisionConflict(
        expected: expectedRevision, actual: reflection.revision)
    }
    reflection.text = ""
    reflection.sourceKind = nil
    reflection.sourceID = nil
    reflection.tombstoned = true
    reflection.revision += 1
    reflection.updatedAt = clock()
    try context.save()
  }

  /// The stored reflection behind an event id, or `nil` when it is gone or not this owner's.
  func reflection(for eventID: JourneyEventID) -> JourneyReflection? {
    guard let components = eventID.components,
      components.kind == .reflection,
      components.owner == ownerID,
      let uuid = UUID(uuidString: components.sourceID)
    else { return nil }
    return reflection(id: uuid)
  }

  /// The active reflection with this id. Deleted rows remain as private tombstones but do not resolve.
  func reflection(id: UUID) -> JourneyReflection? {
    let owner = ownerID
    let descriptor = FetchDescriptor<JourneyReflection>(
      predicate: #Predicate<JourneyReflection> { reflection in
        reflection.ownerID == owner && reflection.reflectionID == id
          && reflection.tombstoned == false
      })
    return (try? context.fetch(descriptor))?.first
  }

  private func activeReflection(clientRequestID key: String) -> JourneyReflection? {
    let owner = ownerID
    let descriptor = FetchDescriptor<JourneyReflection>(
      predicate: #Predicate<JourneyReflection> { reflection in
        reflection.ownerID == owner && reflection.tombstoned == false
          && reflection.clientRequestID == key
      })
    return (try? context.fetch(descriptor))?.first
  }

  private func hasDeletedReflection(clientRequestID key: String) -> Bool {
    let owner = ownerID
    var descriptor = FetchDescriptor<JourneyReflection>(
      predicate: #Predicate<JourneyReflection> { reflection in
        reflection.ownerID == owner && reflection.tombstoned == true
          && reflection.clientRequestID == key
      })
    descriptor.fetchLimit = 1
    return ((try? context.fetchCount(descriptor)) ?? 0) > 0
  }

  private func validate(_ draft: JourneyReflectionDraft) throws {
    do {
      try JourneyReflectionValidator.standard.validate(
        draft, owner: ownerID, now: clock(), calendar: calendar)
    } catch let error as JourneyValidationError {
      throw JourneyRepositoryError.validation(error)
    }
  }

  // MARK: Private profile

  /// The local identity card, or `nil` when the lifter has never saved one.
  func privateProfile() -> JourneyPrivateProfile? {
    let owner = ownerID
    let descriptor = FetchDescriptor<JourneyPrivateProfile>(
      predicate: #Predicate { $0.ownerID == owner })
    return (try? context.fetch(descriptor))?.first
  }

  /// Saves the local identity card, bumping its revision. `expectedRevision` (when given) is
  /// the revision the editor read back; a mismatch throws instead of clobbering a newer write.
  @discardableResult
  func savePrivateProfile(
    displayName: String,
    trainingStartDate: Date?,
    expectedRevision: Int? = nil
  ) throws -> JourneyPrivateProfile {
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let day = trainingStartDate.map { calendar.startOfDay(for: $0) }
    let existing = privateProfile()
    if let expectedRevision {
      let actual = existing?.revision ?? 0
      if expectedRevision != actual {
        throw JourneyRepositoryError.revisionConflict(expected: expectedRevision, actual: actual)
      }
    }
    if let existing {
      existing.displayName = name
      existing.trainingStartDate = day
      existing.revision += 1
      existing.updatedAt = clock()
      try context.save()
      return existing
    }
    let profile = JourneyPrivateProfile(
      ownerID: ownerID,
      displayName: name,
      trainingStartDate: day,
      revision: 1,
      updatedAt: clock())
    context.insert(profile)
    try context.save()
    return profile
  }

  // MARK: Helpers

  /// Assigns a canonical source id once when missing, marking the caller dirty so it saves.
  /// Returns true when the model was changed.
  @discardableResult
  private func ensureRemoteID<M: SyncModel>(_ model: M) -> Bool {
    guard model.remoteID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    model.remoteID = UUID().uuidString
    model.updatedAt = .now
    return true
  }
}
