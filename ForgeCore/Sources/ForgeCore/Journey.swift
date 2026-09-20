import Foundation

// MARK: - Source kind and category
//
// `JourneySourceKind` names the concrete record that produced a timeline entry.
// `JourneyCategory` is the coarse grouping the filter sheet exposes. The mapping
// is total and lives here so the UI and the repository can never disagree about
// which tab a progress photo belongs to.
//
// Everything in this file is pure: no SwiftData, no UIKit, no ambient clock. The
// calendar and "now" are injected at every call site that needs them.

/// The kind of record behind a timeline entry.
public enum JourneySourceKind: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
  case workout
  case bodyMeasurement
  case progressPhoto
  case programChange
  case reflection

  /// The filter-sheet grouping this kind belongs to. Total by construction.
  public var category: JourneyCategory {
    switch self {
    case .workout: return .workout
    case .programChange: return .programChange
    case .bodyMeasurement, .progressPhoto: return .body
    case .reflection: return .note
    }
  }

  /// Display name. Kept out of payloads: the raw value is the storage key.
  public var name: String {
    switch self {
    case .workout: return "Workout"
    case .bodyMeasurement: return "Body measurement"
    case .progressPhoto: return "Progress photo"
    case .programChange: return "Program change"
    case .reflection: return "Note"
    }
  }

  /// True for kinds that are private by default and never expose raw payloads.
  public var isPrivateByDefault: Bool {
    self == .progressPhoto || self == .bodyMeasurement
  }
}

/// The coarse grouping the filter sheet offers: All, Workouts, Program changes,
/// Body, Notes. "All" is not a case — it is the empty selection (see `JourneyFilter`).
public enum JourneyCategory: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
  case workout
  case programChange
  case body
  case note

  public var name: String {
    switch self {
    case .workout: return "Workouts"
    case .programChange: return "Program changes"
    case .body: return "Body"
    case .note: return "Notes"
    }
  }

  /// The source kinds that satisfy this category, in declaration order.
  public var sourceKinds: [JourneySourceKind] {
    JourneySourceKind.allCases.filter { $0.category == self }
  }
}

// MARK: - Facet

/// Which aspect of a source record an entry represents. Most sources contribute
/// exactly one `.record` entry; a source that can contribute several distinct
/// entries (a session's summary, a program's change events) uses other facets so
/// the entries stay collision-free against each other.
public struct JourneyFacet: RawRepresentable, Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public var description: String { rawValue }
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

  /// The source record itself.
  public static let record = JourneyFacet("record")
  /// A derived highlight attached to the source (never a separate source).
  public static let milestone = JourneyFacet("milestone")
  /// A rolled-up summary entry.
  public static let summary = JourneyFacet("summary")
}

// MARK: - Event identity

/// A stable, collision-safe, versioned identity for one timeline entry.
///
/// The identity is derived **only** from the owner, the source kind, the canonical
/// source id and the facet. It never reads a date, a title, a revision or a
/// `PersistentIdentifier`, so editing a title, re-syncing a record, or re-deriving
/// the timeline on another device all produce the same id — and therefore the same
/// hide/restore override, the same list position for ties, and the same idempotency
/// key on write.
///
/// Encoding is length-prefixed, so a source id containing the separator, the
/// prefix, another id, or a multi-scalar grapheme cannot collide with a different
/// (source, facet) pair:
///
///     journey.v1|36:3F2504E0-4F89-11D3-9A0C-0305E82C3301|7:workout|6:a1b2c3|6:record
///
/// Each field is `<utf8 byte count>:<payload>`; `JourneyEventID.components` parses
/// exactly those bytes back, which is what makes the encoding injective.
public struct JourneyEventID: RawRepresentable, Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public var description: String { rawValue }
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

  /// Bumped only if the encoding itself changes; old ids stay parseable by their
  /// own version, so a stored override is never orphaned by an upgrade.
  public static let schemaVersion = 1

  public static var prefix: String { "journey.v\(schemaVersion)" }

  private static let fieldSeparator: UInt8 = 124  // "|"
  private static let lengthSeparator: UInt8 = 58  // ":"

  /// Canonical owner form. A UUID owner (the app's `UserProfile.remoteID`) is
  /// folded to its uppercase canonical spelling so a lowercase id assigned by one
  /// code path cannot desynchronise from an uppercase one assigned by another.
  /// Non-UUID owners are only trimmed.
  public static func canonicalOwner(_ owner: String) -> String {
    let trimmed = owner.trimmingCharacters(in: .whitespacesAndNewlines)
    return UUID(uuidString: trimmed)?.uuidString ?? trimmed
  }

  /// The one constructor. Pure: same arguments ⇒ same value, forever.
  public static func make(
    owner: String,
    kind: JourneySourceKind,
    sourceID: String,
    facet: JourneyFacet? = nil
  ) -> JourneyEventID {
    let fields = [
      field(canonicalOwner(owner)),
      field(kind.rawValue),
      field(sourceID.trimmingCharacters(in: .whitespacesAndNewlines)),
      field(facet?.rawValue ?? ""),
    ]
    return JourneyEventID("\(prefix)|" + fields.joined(separator: "|"))
  }

  /// Convenience for callers holding a facet as free text (e.g. decoded from a
  /// payload). An empty or whitespace-only name means "no facet".
  public static func make(owner: String, kind: JourneySourceKind, sourceID: String, facetName: String?) -> JourneyEventID {
    let name = facetName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return make(owner: owner, kind: kind, sourceID: sourceID, facet: name.isEmpty ? nil : JourneyFacet(name))
  }

  /// Canonical-source-id constructors, one per kind. These mirror the ids the
  /// repository actually stores: `remoteID` for synced records, the photo file
  /// name for progress photos, the reflection's own UUID for notes.
  public static func workout(owner: String, sessionID: String) -> JourneyEventID {
    make(owner: owner, kind: .workout, sourceID: sessionID, facet: .record)
  }

  public static func bodyMeasurement(owner: String, measurementID: String) -> JourneyEventID {
    make(owner: owner, kind: .bodyMeasurement, sourceID: measurementID, facet: .record)
  }

  public static func progressPhoto(owner: String, fileName: String) -> JourneyEventID {
    make(owner: owner, kind: .progressPhoto, sourceID: fileName, facet: .record)
  }

  public static func programChange(owner: String, decisionID: String) -> JourneyEventID {
    make(owner: owner, kind: .programChange, sourceID: decisionID, facet: .record)
  }

  public static func reflection(owner: String, reflectionID: String) -> JourneyEventID {
    make(owner: owner, kind: .reflection, sourceID: reflectionID, facet: .record)
  }

  private static func field(_ value: String) -> String {
    "\(value.utf8.count):\(value)"
  }

  // MARK: Parsing

  public struct Components: Equatable, Hashable, Sendable {
    public let owner: String
    public let kind: JourneySourceKind
    public let sourceID: String
    public let facet: JourneyFacet?
  }

  /// The encoded version, or `nil` when the value is not a Journey id at all.
  public static func version(of rawValue: String) -> Int? {
    guard rawValue.hasPrefix("journey.v") else { return nil }
    let rest = rawValue.dropFirst("journey.v".count)
    let digits = rest.prefix { $0.isASCII && $0.isNumber }
    guard !digits.isEmpty, rest.dropFirst(digits.count).first == "|" else { return nil }
    return Int(digits)
  }

  /// Inverse of `make`. `nil` for anything not encoded at the current version.
  public var components: Components? {
    let bytes = Array(rawValue.utf8)
    let head = Array((Self.prefix + "|").utf8)
    guard bytes.count >= head.count, Array(bytes.prefix(head.count)) == head else { return nil }

    var index = head.count
    var values: [String] = []
    for position in 0..<4 {
      var length = 0
      var digits = 0
      while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
        length = length * 10 + Int(bytes[index] - 48)
        digits += 1
        index += 1
        guard digits <= 9 else { return nil }
      }
      guard digits > 0, index < bytes.count, bytes[index] == Self.lengthSeparator else { return nil }
      index += 1
      guard index + length <= bytes.count else { return nil }
      guard let value = String(bytes: bytes[index..<(index + length)], encoding: .utf8) else { return nil }
      values.append(value)
      index += length
      if position < 3 {
        guard index < bytes.count, bytes[index] == Self.fieldSeparator else { return nil }
        index += 1
      }
    }
    guard index == bytes.count else { return nil }
    guard let kind = JourneySourceKind(rawValue: values[1]) else { return nil }
    let facet = values[3].isEmpty ? nil : JourneyFacet(values[3])
    return Components(owner: values[0], kind: kind, sourceID: values[2], facet: facet)
  }

  /// True when the id names a concrete source: parseable, with a non-blank owner
  /// and a non-blank source id. An id built from a missing `remoteID` is not.
  public var isWellFormed: Bool {
    guard let components else { return false }
    return !components.owner.isEmpty && !components.sourceID.isEmpty
  }
}

// MARK: - Date precision

/// Whether an entry names an instant or only a calendar day. Date-only sources
/// (a weigh-in logged "today", a note attached to a day) must not invent a
/// midnight timestamp, and must not be ordered against a timed entry as though
/// they had one.
public enum JourneyDatePrecision: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
  /// A real instant is known.
  case timestamp
  /// Only the local calendar day is meaningful.
  case dayOnly

  public var isTimed: Bool { self == .timestamp }

  /// Lower rank sorts first within the same resolved day.
  public var sortRank: Int {
    switch self {
    case .timestamp: return 0
    case .dayOnly: return 1
    }
  }
}

// MARK: - Local-day helpers

public enum JourneyDate {
  /// Start of the local day containing `date`, in the injected calendar.
  public static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
    calendar.startOfDay(for: date)
  }

  public static func isSameDay(_ lhs: Date, _ rhs: Date, calendar: Calendar = .current) -> Bool {
    calendar.isDate(lhs, inSameDayAs: rhs)
  }

  public static func month(of date: Date, calendar: Calendar = .current) -> JourneyMonth {
    JourneyMonth(containing: date, calendar: calendar)
  }

  /// True when `date`'s local day is strictly after `now`'s local day. Same-day is
  /// never "future", even if the wall clock is later: 09:00 today is a valid day.
  public static func isFutureDay(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
    calendar.startOfDay(for: date) > calendar.startOfDay(for: now)
  }
}

// MARK: - Sort key

/// The single ordering rule for the whole timeline. Every consumer sorts with
/// these four clauses and nothing else, so two devices with the same data produce
/// the same order — including the order of entries that tie on day and instant.
///
/// 1. resolved local day, descending (newest day first)
/// 2. within a day, timed entries before date-only entries
/// 3. within the same day and precision, occurrence instant, descending
/// 4. remaining ties broken by event id, descending (total, stable, repeatable)
public struct JourneySortKey: Codable, Equatable, Hashable, Sendable, Comparable {
  /// Resolved start of the local day the entry belongs to.
  public let day: Date
  public let precision: JourneyDatePrecision
  /// The occurrence instant. Always `nil` for `.dayOnly`.
  public let instant: Date?
  public let eventID: JourneyEventID

  public init(day: Date, precision: JourneyDatePrecision, instant: Date? = nil, eventID: JourneyEventID) {
    self.day = day
    self.precision = precision
    // Normalise: a day-only key can never carry an instant, so two keys that mean
    // the same thing are never distinguishable.
    self.instant = precision == .timestamp ? instant : nil
    self.eventID = eventID
  }

  /// Resolves a raw occurrence date into a key.
  public init(
    date: Date,
    precision: JourneyDatePrecision,
    eventID: JourneyEventID,
    calendar: Calendar = .current
  ) {
    self.init(
      day: calendar.startOfDay(for: date),
      precision: precision,
      instant: precision == .timestamp ? date : nil,
      eventID: eventID)
  }

  /// The one comparator.
  public static func precedes(_ lhs: JourneySortKey, _ rhs: JourneySortKey) -> Bool {
    if lhs.day != rhs.day { return lhs.day > rhs.day }
    if lhs.precision != rhs.precision { return lhs.precision.sortRank < rhs.precision.sortRank }
    if lhs.instant != rhs.instant {
      return (lhs.instant ?? .distantPast) > (rhs.instant ?? .distantPast)
    }
    return lhs.eventID.rawValue > rhs.eventID.rawValue
  }

  public static func < (lhs: JourneySortKey, rhs: JourneySortKey) -> Bool { precedes(lhs, rhs) }

  /// Deterministic sort. Swift's `sorted(by:)` is not guaranteed stable, so entries
  /// whose keys compare equal keep their input order here instead of drifting.
  public static func sorted<T>(_ items: [T], by key: (T) -> JourneySortKey) -> [T] {
    items.enumerated()
      .sorted { lhs, rhs in
        let left = key(lhs.element)
        let right = key(rhs.element)
        if precedes(left, right) { return true }
        if precedes(right, left) { return false }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
  }

  public static func sorted(_ keys: [JourneySortKey]) -> [JourneySortKey] {
    sorted(keys) { $0 }
  }

  public static func sorted(_ events: [JourneyEvent]) -> [JourneyEvent] {
    sorted(events) { $0.sortKey }
  }
}

// MARK: - Event

/// One immutable timeline card. Holds no raw source payload: no sets, no body
/// measurements, no image bytes — only what the timeline draws and what the
/// repository needs to link back to the canonical detail screen.
public struct JourneyEvent: Codable, Equatable, Hashable, Sendable, Identifiable {
  public let id: JourneyEventID
  public let owner: String
  public let kind: JourneySourceKind
  public let sourceID: String
  public let facet: JourneyFacet
  public let title: String
  public let detail: String?
  /// Resolved start of the local day the entry sits under.
  public let day: Date
  public let precision: JourneyDatePrecision
  public let instant: Date?
  /// True when a visibility override hides this card. The source record is untouched.
  public let isHidden: Bool

  public var category: JourneyCategory { kind.category }

  public var sortKey: JourneySortKey {
    JourneySortKey(day: day, precision: precision, instant: instant, eventID: id)
  }

  /// The canonical source reference a card links back to.
  public var sourceReference: JourneySourceReference {
    JourneySourceReference(kind: kind, sourceID: sourceID)
  }

  public init(
    id: JourneyEventID,
    owner: String,
    kind: JourneySourceKind,
    sourceID: String,
    facet: JourneyFacet = .record,
    title: String,
    detail: String? = nil,
    day: Date,
    precision: JourneyDatePrecision,
    instant: Date? = nil,
    isHidden: Bool = false
  ) {
    self.id = id
    self.owner = owner
    self.kind = kind
    self.sourceID = sourceID
    self.facet = facet
    self.title = title
    self.detail = detail
    self.day = day
    self.precision = precision
    self.instant = precision == .timestamp ? instant : nil
    self.isHidden = isHidden
  }

  /// Builds an event and its identity from the canonical source id in one step, so
  /// no caller ever assembles an id by hand.
  public init(
    owner: String,
    kind: JourneySourceKind,
    sourceID: String,
    facet: JourneyFacet = .record,
    title: String,
    detail: String? = nil,
    date: Date,
    precision: JourneyDatePrecision,
    isHidden: Bool = false,
    calendar: Calendar = .current
  ) {
    self.init(
      id: JourneyEventID.make(owner: owner, kind: kind, sourceID: sourceID, facet: facet),
      owner: owner,
      kind: kind,
      sourceID: sourceID,
      facet: facet,
      title: title,
      detail: detail,
      day: calendar.startOfDay(for: date),
      precision: precision,
      instant: precision == .timestamp ? date : nil,
      isHidden: isHidden)
  }

  public func hidden(_ hidden: Bool = true) -> JourneyEvent {
    JourneyEvent(
      id: id, owner: owner, kind: kind, sourceID: sourceID, facet: facet, title: title, detail: detail,
      day: day, precision: precision, instant: instant, isHidden: hidden)
  }
}

/// A pointer back to the canonical record a card represents.
public struct JourneySourceReference: Codable, Equatable, Hashable, Sendable {
  public let kind: JourneySourceKind
  public let sourceID: String

  public init(kind: JourneySourceKind, sourceID: String) {
    self.kind = kind
    self.sourceID = sourceID
  }

  public var category: JourneyCategory { kind.category }
}

// MARK: - Filter

/// Category filter with OR semantics: a card matches when its category is in the
/// selection. An **empty** selection means All — not "nothing" — so the sheet's
/// default state is representable without a sentinel case.
public struct JourneyFilter: Codable, Equatable, Hashable, Sendable {
  public let categories: Set<JourneyCategory>
  /// Hidden cards are excluded unless the caller explicitly asks for them
  /// (the Hidden items sheet).
  public let includesHidden: Bool

  public init(categories: Set<JourneyCategory> = [], includesHidden: Bool = false) {
    self.categories = categories
    self.includesHidden = includesHidden
  }

  /// The empty selection: every category.
  public static let all = JourneyFilter()

  public static func any(_ categories: [JourneyCategory]) -> JourneyFilter {
    JourneyFilter(categories: Set(categories))
  }

  public var isAll: Bool { categories.isEmpty }

  /// How many chips are lit in the sheet.
  public var selectionCount: Int { categories.count }

  /// The categories this filter actually admits.
  public var resolvedCategories: Set<JourneyCategory> {
    categories.isEmpty ? Set(JourneyCategory.allCases) : categories
  }

  /// OR: membership, with empty meaning All.
  public func matches(_ category: JourneyCategory) -> Bool {
    categories.isEmpty || categories.contains(category)
  }

  /// Labelled so a leading-dot literal is never ambiguous against
  /// `matches(_: JourneyCategory)`.
  public func matches(kind: JourneySourceKind) -> Bool {
    matches(kind.category)
  }

  /// Category OR-membership plus the hidden-visibility gate.
  public func matches(_ event: JourneyEvent) -> Bool {
    matches(event.category) && (includesHidden || !event.isHidden)
  }

  /// Adds a category if absent, removes it if present. Toggling every category off
  /// returns to All, which is the semantic the sheet's "All" row relies on.
  public func toggling(_ category: JourneyCategory) -> JourneyFilter {
    var next = categories
    if next.contains(category) { next.remove(category) } else { next.insert(category) }
    return JourneyFilter(categories: next, includesHidden: includesHidden)
  }

  public func including(_ categories: JourneyCategory...) -> JourneyFilter {
    JourneyFilter(categories: self.categories.union(categories), includesHidden: includesHidden)
  }

  public func excluding(_ category: JourneyCategory) -> JourneyFilter {
    var next = categories
    next.remove(category)
    return JourneyFilter(categories: next, includesHidden: includesHidden)
  }

  public func withHidden(_ includesHidden: Bool) -> JourneyFilter {
    JourneyFilter(categories: categories, includesHidden: includesHidden)
  }

  public func cleared() -> JourneyFilter {
    JourneyFilter(categories: [], includesHidden: includesHidden)
  }

  /// Deterministic coding: the selection is stored as a sorted array of raw values,
  /// so the same filter always encodes to the same bytes. Unknown raw values decode
  /// to nothing rather than failing the whole payload.
  private enum CodingKeys: String, CodingKey {
    case categories
    case includesHidden
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let raw = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
    self.categories = Set(raw.compactMap(JourneyCategory.init(rawValue:)))
    self.includesHidden = try container.decodeIfPresent(Bool.self, forKey: .includesHidden) ?? false
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(categories.map(\.rawValue).sorted(), forKey: .categories)
    try container.encode(includesHidden, forKey: .includesHidden)
  }
}

// MARK: - Month

/// A calendar month, independent of time zone. Intervals are always built from the
/// injected calendar, so a month's bounds move with the viewer's zone exactly the
/// way the rest of the timeline does — a 23:30 session on the 31st never leaks into
/// the next month's page.
public struct JourneyMonth: Codable, Equatable, Hashable, Sendable, Comparable, CustomStringConvertible {
  public let year: Int
  public let month: Int  // 1...12

  /// Out-of-range components are clamped, which (together with the year clamp)
  /// guarantees the month always resolves to a real calendar date.
  public init(year: Int, month: Int) {
    self.year = min(max(year, 1), 9999)
    self.month = min(max(month, 1), 12)
  }

  public init(containing date: Date, calendar: Calendar = .current) {
    let parts = calendar.dateComponents([.year, .month], from: date)
    self.init(year: parts.year ?? 1970, month: parts.month ?? 1)
  }

  /// Strict `YYYY-MM`; `nil` when malformed or out of range.
  public init?(identifier: String) {
    let parts = identifier.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0].count == 4, parts[1].count == 2,
          parts[0].allSatisfy({ $0.isASCII && $0.isNumber }),
          parts[1].allSatisfy({ $0.isASCII && $0.isNumber }),
          let year = Int(parts[0]), let month = Int(parts[1]),
          year >= 1, year <= 9999, month >= 1, month <= 12
    else { return nil }
    self.init(year: year, month: month)
  }

  public var identifier: String { String(format: "%04d-%02d", year, month) }
  public var description: String { identifier }

  public static func < (lhs: JourneyMonth, rhs: JourneyMonth) -> Bool {
    (lhs.year, lhs.month) < (rhs.year, rhs.month)
  }

  /// Month arithmetic, wrapping the year. Months before year 1 clamp to year 1.
  public func advanced(by months: Int) -> JourneyMonth {
    let total = year * 12 + (month - 1) + months
    guard total >= 0 else { return JourneyMonth(year: 1, month: 1) }
    return JourneyMonth(year: total / 12, month: total % 12 + 1)
  }

  public var next: JourneyMonth { advanced(by: 1) }
  public var previous: JourneyMonth { advanced(by: -1) }

  /// First instant of the month in the injected calendar.
  public func startDate(calendar: Calendar = .current) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: 1))
      ?? Date(timeIntervalSince1970: 0)
  }

  /// First instant of the *next* month — the exclusive upper bound.
  public func endDate(calendar: Calendar = .current) -> Date {
    calendar.date(byAdding: .month, value: 1, to: startDate(calendar: calendar))
      ?? startDate(calendar: calendar)
  }

  /// Half-open `[start, end)`. Its duration is shorter than `dayCount` days in a
  /// month that contains a spring-forward transition.
  public func interval(calendar: Calendar = .current) -> DateInterval {
    DateInterval(start: startDate(calendar: calendar), end: endDate(calendar: calendar))
  }

  public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
    interval(calendar: calendar).contains(date)
  }

  public func dayCount(calendar: Calendar = .current) -> Int {
    calendar.dateComponents([.day], from: startDate(calendar: calendar), to: endDate(calendar: calendar)).day ?? 0
  }

  /// Every local start-of-day in the month, ascending.
  public func days(calendar: Calendar = .current) -> [Date] {
    let bounds = interval(calendar: calendar)
    var result: [Date] = []
    var cursor = bounds.start
    while cursor < bounds.end {
      result.append(cursor)
      guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
      cursor = next
    }
    return result
  }

  /// Inclusive month span, ascending. Empty when `end` precedes `start`.
  public static func months(from start: JourneyMonth, through end: JourneyMonth) -> [JourneyMonth] {
    guard start <= end else { return [] }
    var result: [JourneyMonth] = []
    var cursor = start
    while cursor <= end {
      result.append(cursor)
      cursor = cursor.next
    }
    return result
  }

  private enum CodingKeys: String, CodingKey { case identifier }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let raw = try container.decode(String.self, forKey: .identifier)
    guard let month = JourneyMonth(identifier: raw) else {
      throw DecodingError.dataCorruptedError(forKey: .identifier, in: container, debugDescription: "bad month \(raw)")
    }
    self = month
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(identifier, forKey: .identifier)
  }
}

// MARK: - Reflection text

/// Grapheme-cluster counting and blankness. Swift's `String.count` counts extended
/// grapheme clusters, which is the rule the product promises ("2,000 characters"
/// means what the user sees, not UTF-8 bytes or Unicode scalars).
public enum JourneyText {
  public static let maximumGraphemeClusterCount = 2_000

  public static func graphemeClusterCount(_ text: String) -> Int { text.count }

  public static func trimmed(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Whitespace and newlines only.
  public static func isBlank(_ text: String) -> Bool { trimmed(text).isEmpty }

  public static func fits(_ text: String, limit: Int = maximumGraphemeClusterCount) -> Bool {
    graphemeClusterCount(text) <= limit
  }
}

// MARK: - Reflection draft

/// What the editor hands the repository before a `JourneyReflection` record exists.
/// Pure data: the repository assigns the stable UUID and the revision.
public struct JourneyReflectionDraft: Codable, Equatable, Hashable, Sendable {
  public var text: String
  /// The chosen day. Stored as soon as it is validated, so the card keeps the day
  /// the user picked even if the record is saved after midnight.
  public var day: Date
  /// Optional typed link to the canonical record the note is about.
  public var source: JourneySourceReference?
  /// Idempotency key for a retried save; not part of the identity.
  public var clientRequestID: String?

  public init(
    text: String,
    day: Date,
    source: JourneySourceReference? = nil,
    clientRequestID: String? = nil
  ) {
    self.text = text
    self.day = day
    self.source = source
    self.clientRequestID = clientRequestID
  }

  /// The text that will be stored and measured: surrounding whitespace removed, so
  /// a pasted trailing newline cannot push a 2,000-character note over the limit.
  public var normalizedText: String { JourneyText.trimmed(text) }

  /// The stored day: the local start of the chosen day.
  public func resolvedDay(calendar: Calendar = .current) -> Date {
    calendar.startOfDay(for: day)
  }

  public func normalized(calendar: Calendar = .current) -> JourneyReflectionDraft {
    JourneyReflectionDraft(
      text: normalizedText, day: resolvedDay(calendar: calendar), source: source,
      clientRequestID: clientRequestID)
  }
}

// MARK: - Reflection validation

public enum JourneyValidationCode: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
  /// The reflection is empty or whitespace only.
  case emptyContent
  /// More grapheme clusters than the validator allows.
  case contentTooLong
  /// The chosen day is after the local day of `now`.
  case futureDay
  /// No stable owner, so no collision-safe identity can be derived.
  case missingOwner

  public var message: String {
    switch self {
    case .emptyContent: return String(localized: "Write something before saving the note.", bundle: ForgeCoreResources.bundle)
    case .contentTooLong: return String(localized: "Notes are limited to 2,000 characters.", bundle: ForgeCoreResources.bundle)
    case .futureDay: return String(localized: "A note cannot be dated in the future.", bundle: ForgeCoreResources.bundle)
    case .missingOwner: return String(localized: "This profile has no stable identifier yet.", bundle: ForgeCoreResources.bundle)
    }
  }
}

public struct JourneyValidationFailure: Error, Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
  public let code: JourneyValidationCode
  public let message: String
  /// The limit that was exceeded, when the failure has one.
  public let limit: Int?
  /// The observed value, when the failure has one.
  public let actual: Int?

  public init(code: JourneyValidationCode, message: String? = nil, limit: Int? = nil, actual: Int? = nil) {
    self.code = code
    self.message = message ?? code.message
    self.limit = limit
    self.actual = actual
  }

  public var description: String { message }
}

/// All failures for one draft, in a fixed order. Thrown by `validate(_:)`.
public struct JourneyValidationError: Error, Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
  public let failures: [JourneyValidationFailure]

  public init(failures: [JourneyValidationFailure]) {
    self.failures = failures
  }

  public var codes: [JourneyValidationCode] { failures.map(\.code) }
  public var description: String { failures.map(\.message).joined(separator: " ") }
  public var first: JourneyValidationFailure? { failures.first }
}

/// Validation for reflection drafts. Reports **every** problem at once rather than
/// the first, so the editor can show all of them in one pass.
public struct JourneyReflectionValidator: Codable, Equatable, Hashable, Sendable {
  /// Maximum extended grapheme clusters in the normalized text.
  public let maximumGraphemeClusters: Int

  public init(maximumGraphemeClusters: Int = JourneyText.maximumGraphemeClusterCount) {
    self.maximumGraphemeClusters = maximumGraphemeClusters
  }

  public static let standard = JourneyReflectionValidator()

  /// Non-empty after trimming, at most `maximumGraphemeClusters` clusters, no
  /// future local day, and a stable owner. Deterministic — `now` and `calendar`
  /// are injected.
  public func validation(
    of draft: JourneyReflectionDraft,
    owner: String,
    now: Date = .now,
    calendar: Calendar = .current
  ) -> [JourneyValidationFailure] {
    var failures: [JourneyValidationFailure] = []

    if JourneyEventID.canonicalOwner(owner).isEmpty {
      failures.append(JourneyValidationFailure(code: .missingOwner))
    }

    let text = draft.normalizedText
    if text.isEmpty {
      failures.append(JourneyValidationFailure(code: .emptyContent))
    } else {
      let count = JourneyText.graphemeClusterCount(text)
      if count > maximumGraphemeClusters {
        failures.append(
          JourneyValidationFailure(code: .contentTooLong, limit: maximumGraphemeClusters, actual: count))
      }
    }

    if JourneyDate.isFutureDay(draft.day, now: now, calendar: calendar) {
      failures.append(JourneyValidationFailure(code: .futureDay))
    }

    return failures
  }

  public func isValid(
    _ draft: JourneyReflectionDraft,
    owner: String,
    now: Date = .now,
    calendar: Calendar = .current
  ) -> Bool {
    validation(of: draft, owner: owner, now: now, calendar: calendar).isEmpty
  }

  /// Throws `JourneyValidationError` carrying every failure.
  public func validate(
    _ draft: JourneyReflectionDraft,
    owner: String,
    now: Date = .now,
    calendar: Calendar = .current
  ) throws {
    let failures = validation(of: draft, owner: owner, now: now, calendar: calendar)
    guard failures.isEmpty else { throw JourneyValidationError(failures: failures) }
  }
}
