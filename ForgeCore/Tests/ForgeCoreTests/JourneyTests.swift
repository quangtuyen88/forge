import XCTest

@testable import ForgeCore

// MARK: - deterministic fixtures

/// Fixed zone with DST, so month boundaries and local days are reproducible.
private let ny: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/New_York")!
  calendar.locale = Locale(identifier: "en_US_POSIX")
  return calendar
}()

/// Fixed zone without DST, for the control case.
private let nairobi: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "Africa/Nairobi")!
  calendar.locale = Locale(identifier: "en_US_POSIX")
  return calendar
}()

private let utc: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  calendar.locale = Locale(identifier: "en_US_POSIX")
  return calendar
}()

private func day(
  _ year: Int, _ month: Int, _ dayOfMonth: Int, _ hour: Int = 0, _ minute: Int = 0,
  _ calendar: Calendar = ny
) -> Date {
  calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: hour, minute: minute))
    ?? Date(timeIntervalSince1970: 0)
}

/// A UUID-shaped owner, deliberately lowercase so canonicalisation is exercised.
private let lowercaseOwner = "3f2504e0-4f89-11d3-9a0c-0305e82c3301"
private let canonicalOwner = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"

private func key(
  _ dayValue: Date,
  _ precision: JourneyDatePrecision,
  _ id: String,
  instant: Date? = nil
) -> JourneySortKey {
  JourneySortKey(day: dayValue, precision: precision, instant: instant, eventID: JourneyEventID(id))
}

private func order(_ keys: [JourneySortKey]) -> [String] {
  JourneySortKey.sorted(keys).map(\.eventID.rawValue)
}

private func draft(
  _ text: String,
  _ dayValue: Date,
  source: JourneySourceReference? = nil
) -> JourneyReflectionDraft {
  JourneyReflectionDraft(text: text, day: dayValue, source: source)
}

final class JourneyTests: XCTestCase {

  // MARK: - Identity: stability

  func testEventIDIsAPureFunctionOfOwnerKindSourceAndFacet() {
    let first = JourneyEventID.make(owner: lowercaseOwner, kind: .workout, sourceID: "a1b2c3", facet: .record)
    let second = JourneyEventID.make(owner: lowercaseOwner, kind: .workout, sourceID: "a1b2c3", facet: .record)
    XCTAssertEqual(first, second)
    XCTAssertEqual(first.rawValue, second.rawValue)
  }

  func testEventIDGoldenValueLocksTheEncoding() {
    // Any change to the encoding — including a version bump — must be deliberate.
    let id = JourneyEventID.make(owner: lowercaseOwner, kind: .workout, sourceID: "a1b2c3", facet: .record)
    XCTAssertEqual(
      id.rawValue,
      "journey.v1|36:3F2504E0-4F89-11D3-9A0C-0305E82C3301|7:workout|6:a1b2c3|6:record")
  }

  /// The identity must not move when the *presentation* of the same source moves.
  func testIdentityIgnoresTitlesDatesAndRevisions() {
    let dateA = day(2025, 3, 1, 6, 0)
    let dateB = day(2026, 11, 30, 21, 45)

    let eventA = JourneyEvent(
      owner: lowercaseOwner, kind: .workout, sourceID: "s-1", title: "Leg day",
      date: dateA, precision: .timestamp, calendar: ny)
    let eventB = JourneyEvent(
      owner: lowercaseOwner, kind: .workout, sourceID: "s-1", title: "Quads & hams (edited)",
      date: dateB, precision: .timestamp, calendar: ny)

    XCTAssertEqual(eventA.id, eventB.id)
    XCTAssertEqual(eventA.id, JourneyEventID.workout(owner: lowercaseOwner, sessionID: "s-1"))
  }

  func testOwnerCaseVariantsCollapseToTheCanonicalSpelling() {
    XCTAssertEqual(JourneyEventID.canonicalOwner(lowercaseOwner), canonicalOwner)
    XCTAssertEqual(JourneyEventID.canonicalOwner("  \(canonicalOwner)  "), canonicalOwner)

    let lower = JourneyEventID.make(owner: lowercaseOwner, kind: .workout, sourceID: "s", facet: .record)
    let upper = JourneyEventID.make(owner: canonicalOwner, kind: .workout, sourceID: "s", facet: .record)
    XCTAssertEqual(lower, upper)
  }

  func testNonUUIDOwnerIsOnlyTrimmed() {
    XCTAssertEqual(JourneyEventID.canonicalOwner("  lifter-7  "), "lifter-7")
    XCTAssertEqual(JourneyEventID.canonicalOwner("lifter-7"), "lifter-7")
    XCTAssertNotEqual(
      JourneyEventID.make(owner: "lifter-7", kind: .workout, sourceID: "s"),
      JourneyEventID.make(owner: "LIFTER-7", kind: .workout, sourceID: "s"))
  }

  func testSourceIDIsTrimmedBeforeEncoding() {
    XCTAssertEqual(
      JourneyEventID.make(owner: lowercaseOwner, kind: .reflection, sourceID: "  abc  ", facet: .record),
      JourneyEventID.make(owner: lowercaseOwner, kind: .reflection, sourceID: "abc", facet: .record))
  }

  // MARK: - Identity: collision resistance

  func testSeparatorInsideComponentsCannotCollide() {
    // The naive `kind:source:facet` join collides on exactly this pair.
    let split = JourneyEventID.make(
      owner: lowercaseOwner, kind: .workout, sourceID: "a:b", facet: nil)
    let merged = JourneyEventID.make(
      owner: lowercaseOwner, kind: .workout, sourceID: "a", facet: JourneyFacet("b"))
    XCTAssertNotEqual(split, merged)
    XCTAssertEqual(split.components?.sourceID, "a:b")
    XCTAssertNil(split.components?.facet)
    XCTAssertEqual(merged.components?.sourceID, "a")
    XCTAssertEqual(merged.components?.facet, JourneyFacet("b"))
  }

  func testPipeAndLengthPrefixInsideComponentsCannotCollide() {
    let tricky = JourneyEventID.make(
      owner: lowercaseOwner, kind: .progressPhoto, sourceID: "3:a|7:record", facet: nil)
    let plain = JourneyEventID.make(
      owner: lowercaseOwner, kind: .progressPhoto, sourceID: "3", facet: JourneyFacet("a"))
    XCTAssertNotEqual(tricky, plain)
    XCTAssertEqual(tricky.components?.sourceID, "3:a|7:record")
    XCTAssertNil(tricky.components?.facet)
  }

  func testMultiScalarGraphemeInSourceIDSurvivesRoundTrip() {
    let fileName = "🇻🇳-e\u{0301}-👨‍👩‍👧‍👦.jpg"
    let id = JourneyEventID.progressPhoto(owner: lowercaseOwner, fileName: fileName)
    XCTAssertEqual(id.components?.sourceID, fileName)
    XCTAssertTrue(id.isWellFormed)
  }

  func testEveryKindProducesADistinctIdentityForTheSameSource() {
    let ids = Set(JourneySourceKind.allCases.map {
      JourneyEventID.make(owner: lowercaseOwner, kind: $0, sourceID: "shared-1", facet: .record)
    })
    XCTAssertEqual(ids.count, JourneySourceKind.allCases.count)
  }

  func testOwnerKindSourceAndFacetEachChangeTheIdentity() {
    let base = JourneyEventID.make(owner: lowercaseOwner, kind: .workout, sourceID: "s", facet: .record)
    XCTAssertNotEqual(base, JourneyEventID.make(owner: "other", kind: .workout, sourceID: "s", facet: .record))
    XCTAssertNotEqual(base, JourneyEventID.make(owner: lowercaseOwner, kind: .reflection, sourceID: "s", facet: .record))
    XCTAssertNotEqual(base, JourneyEventID.make(owner: lowercaseOwner, kind: .workout, sourceID: "t", facet: .record))
    XCTAssertNotEqual(
      base, JourneyEventID.make(owner: lowercaseOwner, kind: .workout, sourceID: "s", facet: .milestone))
  }

  func testFacetNameInitializerTreatsBlankAsAbsent() {
    for name in [nil, "", "   "] as [String?] {
      XCTAssertEqual(
        JourneyEventID.make(owner: lowercaseOwner, kind: .workout, sourceID: "s", facetName: name),
        JourneyEventID.make(owner: lowercaseOwner, kind: .workout, sourceID: "s", facet: nil))
    }
    XCTAssertEqual(
      JourneyEventID.make(owner: lowercaseOwner, kind: .workout, sourceID: "s", facetName: " milestone "),
      JourneyEventID.make(owner: lowercaseOwner, kind: .workout, sourceID: "s", facet: .milestone))
  }

  func testWellFormedRejectsBlankOwnerOrSource() {
    XCTAssertFalse(JourneyEventID.make(owner: "", kind: .workout, sourceID: "s").isWellFormed)
    XCTAssertFalse(JourneyEventID.make(owner: lowercaseOwner, kind: .workout, sourceID: "  ").isWellFormed)
    XCTAssertFalse(JourneyEventID("not-a-journey-id").isWellFormed)
    XCTAssertTrue(JourneyEventID.workout(owner: lowercaseOwner, sessionID: "s").isWellFormed)
    XCTAssertNil(JourneyEventID("not-a-journey-id").components)
  }

  func testParseRejectsMalformedEncodings() {
    XCTAssertNil(JourneyEventID("").components)
    XCTAssertNil(JourneyEventID("journey.v1").components)
    XCTAssertNil(JourneyEventID("journey.v1|3:a").components)               // truncated
    XCTAssertNil(JourneyEventID("journey.v1|3:a|7:workout|1:s|6:record").components)  // non-numeric length
    XCTAssertNil(JourneyEventID("journey.v1|3:a|7:workout|1:s|6:recorded").components)  // overrun tail
    XCTAssertNil(JourneyEventID("journey.v1|3:a|7:unknown|1:s|0:").components)  // unknown kind
  }

  func testSchemaVersionIsRecordedAndDetectable() {
    let id = JourneyEventID.workout(owner: lowercaseOwner, sessionID: "s")
    XCTAssertEqual(JourneyEventID.version(of: id.rawValue), 1)
    XCTAssertEqual(JourneyEventID.version(of: "journey.v2|0:|7:workout|0:|0:"), 2)
    XCTAssertNil(JourneyEventID.version(of: "journey.vx|0:"))
    XCTAssertNil(JourneyEventID.version(of: "3F2504E0-4F89-11D3-9A0C-0305E82C3301"))

    // A future-version id is not silently reinterpreted at this version.
    XCTAssertNil(JourneyEventID("journey.v2|0:|7:workout|0:|0:").components)
  }

  func testEventIDCodableRoundTripUsesASingleString() throws {
    let id = JourneyEventID.programChange(owner: lowercaseOwner, decisionID: "decision-9")
    let data = try JSONEncoder().encode(id)
    XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"\(id.rawValue)\"")
    XCTAssertEqual(try JSONDecoder().decode(JourneyEventID.self, from: data), id)
  }

  // MARK: - Ordering

  func testResolvedLocalDaySortsDescending() {
    let keys = [
      key(day(2025, 3, 1), .dayOnly, "a"),
      key(day(2025, 3, 3), .dayOnly, "b"),
      key(day(2025, 3, 2), .dayOnly, "c"),
    ]
    XCTAssertEqual(order(keys), ["b", "c", "a"])
  }

  func testTimedEntrySortsBeforeDateOnlyEntryWithinTheSameDay() {
    let sameDay = day(2025, 3, 5)
    let timed = key(sameDay, .timestamp, "a-timed", instant: day(2025, 3, 5, 18, 30))
    let dateOnly = key(sameDay, .dayOnly, "z-date-only")
    XCTAssertEqual(order([dateOnly, timed]), ["a-timed", "z-date-only"])
  }

  func testInstantSortsDescendingWithinSameDayAndPrecision() {
    let sameDay = day(2025, 3, 5)
    let morning = key(sameDay, .timestamp, "morning", instant: day(2025, 3, 5, 6, 0))
    let evening = key(sameDay, .timestamp, "evening", instant: day(2025, 3, 5, 20, 0))
    let noon = key(sameDay, .timestamp, "noon", instant: day(2025, 3, 5, 12, 0))
    XCTAssertEqual(order([morning, evening, noon]), ["evening", "noon", "morning"])
  }

  func testEventIDSortsDescendingToBreakEveryRemainingTie() {
    let sameDay = day(2025, 3, 5)
    let instant = day(2025, 3, 5, 9, 0)
    let keys = [
      key(sameDay, .timestamp, "e1", instant: instant),
      key(sameDay, .timestamp, "e3", instant: instant),
      key(sameDay, .timestamp, "e2", instant: instant),
    ]
    XCTAssertEqual(order(keys), ["e3", "e2", "e1"])
  }

  func testDayOnlyKeysNeverCarryAnInstant() {
    let resolved = JourneySortKey(
      date: day(2025, 3, 5, 14, 20), precision: .dayOnly, eventID: JourneyEventID("x"), calendar: ny)
    XCTAssertNil(resolved.instant)
    XCTAssertEqual(resolved.day, day(2025, 3, 5))

    let timed = JourneySortKey(
      date: day(2025, 3, 5, 14, 20), precision: .timestamp, eventID: JourneyEventID("x"), calendar: ny)
    XCTAssertEqual(timed.day, day(2025, 3, 5))
    XCTAssertEqual(timed.instant, day(2025, 3, 5, 14, 20))
  }

  func testComparatorIsTotalDeterministicAndIndependentOfInputOrder() {
    let keys = (0..<12).map { index -> JourneySortKey in
      let precision: JourneyDatePrecision = index.isMultiple(of: 2) ? .timestamp : .dayOnly
      let instant = index.isMultiple(of: 2) ? day(2025, 3, 3, 6 + index, 0) : nil
      return key(day(2025, 3, 3), precision, "id-\(index)", instant: instant)
    }
    let ascending = order(keys)
    let descending = order(keys.reversed())
    let shuffled = order(keys.shuffled())
    XCTAssertEqual(ascending, descending)
    XCTAssertEqual(ascending, shuffled)
    XCTAssertEqual(Set(ascending).count, keys.count)
  }

  func testSortIsStableForIndistinguishableKeys() {
    let same = JourneySortKey(
      day: day(2025, 3, 5), precision: .dayOnly, instant: nil, eventID: JourneyEventID("same"))
    let stable = JourneySortKey.sorted([("first", same), ("second", same), ("third", same)]) { $0.1 }
    XCTAssertEqual(stable.map(\.0), ["first", "second", "third"])
  }

  func testMonthBoundaryUsesTheResolvedLocalDay() {
    let lateFebruary = JourneyEvent(
      owner: lowercaseOwner, kind: .workout, sourceID: "feb", title: "Late",
      date: day(2025, 2, 28, 23, 30), precision: .timestamp, calendar: ny)
    let earlyMarch = JourneyEvent(
      owner: lowercaseOwner, kind: .workout, sourceID: "mar", title: "Early",
      date: day(2025, 3, 1, 0, 30), precision: .timestamp, calendar: ny)

    XCTAssertEqual(lateFebruary.day, day(2025, 2, 28))
    XCTAssertEqual(earlyMarch.day, day(2025, 3, 1))
    XCTAssertEqual(JourneySortKey.sorted([lateFebruary, earlyMarch]).map(\.sourceID), ["mar", "feb"])

    let march = JourneyMonth(year: 2025, month: 3)
    XCTAssertTrue(march.contains(earlyMarch.day, calendar: ny))
    XCTAssertFalse(march.contains(lateFebruary.day, calendar: ny))
    XCTAssertEqual(JourneyDate.month(of: earlyMarch.instant ?? .now, calendar: ny), march)
    XCTAssertEqual(JourneyDate.month(of: lateFebruary.instant ?? .now, calendar: ny), JourneyMonth(year: 2025, month: 2))
  }

  // MARK: - Filters

  func testEmptySelectionMeansAll() {
    let filter = JourneyFilter.all
    XCTAssertTrue(filter.isAll)
    XCTAssertEqual(filter.selectionCount, 0)
    XCTAssertEqual(filter.resolvedCategories, Set(JourneyCategory.allCases))
    for category in JourneyCategory.allCases {
      XCTAssertTrue(filter.matches(category))
    }
    for kind in JourneySourceKind.allCases {
      XCTAssertTrue(filter.matches(kind: kind))
    }
  }

  func testFilterUsesOrSemantics() {
    let filter = JourneyFilter.any([.workout, .body])
    XCTAssertFalse(filter.isAll)
    XCTAssertEqual(filter.selectionCount, 2)
    XCTAssertTrue(filter.matches(.workout))
    XCTAssertTrue(filter.matches(.body))
    XCTAssertFalse(filter.matches(.note))
    XCTAssertFalse(filter.matches(.programChange))

    // Body admits both of its source kinds — OR, not AND.
    XCTAssertTrue(filter.matches(kind: .bodyMeasurement))
    XCTAssertTrue(filter.matches(kind: .progressPhoto))
    XCTAssertFalse(filter.matches(kind: .reflection))
  }

  func testTogglingRoundTripsBackToAll() {
    let one = JourneyFilter.all.toggling(.workout)
    XCTAssertEqual(one.categories, [.workout])
    let none = one.toggling(.workout)
    XCTAssertTrue(none.isAll)
    XCTAssertEqual(none, JourneyFilter.all)

    let unioned = JourneyFilter.all.toggling(.note).including(.body, .programChange)
    XCTAssertEqual(unioned.categories, [.note, .body, .programChange])
    XCTAssertEqual(unioned.excluding(.body).categories, [.note, .programChange])
    XCTAssertTrue(unioned.cleared().isAll)
  }

  func testFilterMatchesEventsAndGatesHidden() {
    let visible = JourneyEvent(
      owner: lowercaseOwner, kind: .reflection, sourceID: "n1", title: "Note",
      date: day(2025, 3, 5), precision: .dayOnly, calendar: ny)
    let hidden = visible.hidden()

    XCTAssertTrue(JourneyFilter.all.matches(visible))
    XCTAssertFalse(JourneyFilter.all.matches(hidden))
    XCTAssertTrue(JourneyFilter.all.withHidden(true).matches(hidden))
    XCTAssertFalse(JourneyFilter.any([.workout]).matches(visible))
    XCTAssertTrue(JourneyFilter.any([.note]).matches(visible))
    XCTAssertTrue(JourneyFilter.any([.note]).withHidden(true).matches(hidden))
  }

  func testFilterCodingIsDeterministicAndLenient() throws {
    let filter = JourneyFilter.any([.note, .workout]).withHidden(true)
    let data = try JSONEncoder().encode(filter)
    let json = String(decoding: data, as: UTF8.self)
    XCTAssertTrue(json.contains("[\"note\",\"workout\"]"), json)
    XCTAssertEqual(try JSONDecoder().decode(JourneyFilter.self, from: data), filter)

    let legacy = Data(#"{"categories":["workout","sunrise"],"includesHidden":false}"#.utf8)
    let decoded = try JSONDecoder().decode(JourneyFilter.self, from: legacy)
    XCTAssertEqual(decoded.categories, [.workout])

    let empty = try JSONDecoder().decode(JourneyFilter.self, from: Data("{}".utf8))
    XCTAssertEqual(empty, JourneyFilter.all)
  }

  // MARK: - Months

  func testMonthIntervalIsHalfOpenOnInjectedCalendarBoundaries() {
    let march = JourneyMonth(year: 2025, month: 3)
    let interval = march.interval(calendar: ny)
    XCTAssertEqual(march.startDate(calendar: ny), day(2025, 3, 1))
    XCTAssertEqual(march.endDate(calendar: ny), day(2025, 4, 1))
    XCTAssertEqual(interval.start, day(2025, 3, 1))
    XCTAssertEqual(interval.end, day(2025, 4, 1))

    XCTAssertTrue(march.contains(day(2025, 3, 1, 0, 0), calendar: ny))
    XCTAssertTrue(march.contains(day(2025, 3, 31, 23, 59), calendar: ny))
    XCTAssertFalse(day(2025, 4, 1) < interval.end)
    XCTAssertFalse(march.contains(day(2025, 2, 28, 23, 59), calendar: ny))
  }

  func testMonthDayCountAndDays() {
    XCTAssertEqual(JourneyMonth(year: 2025, month: 3).dayCount(calendar: ny), 31)
    XCTAssertEqual(JourneyMonth(year: 2025, month: 2).dayCount(calendar: ny), 28)
    XCTAssertEqual(JourneyMonth(year: 2024, month: 2).dayCount(calendar: ny), 29)

    let days = JourneyMonth(year: 2025, month: 3).days(calendar: ny)
    XCTAssertEqual(days.count, 31)
    XCTAssertEqual(days.first, day(2025, 3, 1))
    XCTAssertEqual(days.last, day(2025, 3, 31))
    XCTAssertEqual(days, days.sorted())
  }

  func testSpringForwardMonthIsAnHourShorter() {
    let marchNY = JourneyMonth(year: 2025, month: 3).interval(calendar: ny)
    XCTAssertEqual(marchNY.duration, 743 * 3600)  // 31 days minus the skipped hour
    let marchNairobi = JourneyMonth(year: 2025, month: 3).interval(calendar: nairobi)
    XCTAssertEqual(marchNairobi.duration, 744 * 3600)
    XCTAssertEqual(JourneyMonth(year: 2025, month: 3).dayCount(calendar: ny), 31)
  }

  func testMonthArithmeticWrapsTheYear() {
    XCTAssertEqual(JourneyMonth(year: 2025, month: 12).next, JourneyMonth(year: 2026, month: 1))
    XCTAssertEqual(JourneyMonth(year: 2025, month: 1).previous, JourneyMonth(year: 2024, month: 12))
    XCTAssertEqual(JourneyMonth(year: 2025, month: 3).advanced(by: -13), JourneyMonth(year: 2024, month: 2))
    XCTAssertEqual(JourneyMonth(year: 2025, month: 3).advanced(by: 0), JourneyMonth(year: 2025, month: 3))
    XCTAssertEqual(JourneyMonth(year: 2024, month: 2).advanced(by: 12), JourneyMonth(year: 2025, month: 2))
  }

  func testMonthFromDateAndIdentifierRoundTrip() throws {
    XCTAssertEqual(JourneyMonth(containing: day(2025, 3, 31, 23, 59), calendar: ny), JourneyMonth(year: 2025, month: 3))
    XCTAssertEqual(JourneyMonth(containing: day(2025, 4, 1, 0, 1), calendar: ny), JourneyMonth(year: 2025, month: 4))

    let march = JourneyMonth(year: 2025, month: 3)
    XCTAssertEqual(march.identifier, "2025-03")
    XCTAssertEqual(JourneyMonth(identifier: "2025-03"), march)
    XCTAssertEqual(JourneyMonth(identifier: march.identifier), march)

    XCTAssertNil(JourneyMonth(identifier: "2025-13"))
    XCTAssertNil(JourneyMonth(identifier: "2025-00"))
    XCTAssertNil(JourneyMonth(identifier: "2025-3"))
    XCTAssertNil(JourneyMonth(identifier: "25-03"))
    XCTAssertNil(JourneyMonth(identifier: "abc"))

    let data = try JSONEncoder().encode(march)
    XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"identifier":"2025-03"}"#)
    XCTAssertEqual(try JSONDecoder().decode(JourneyMonth.self, from: data), march)
  }

  func testMonthOrderingAndSequence() {
    XCTAssertLessThan(JourneyMonth(year: 2024, month: 12), JourneyMonth(year: 2025, month: 1))
    XCTAssertLessThan(JourneyMonth(year: 2025, month: 3), JourneyMonth(year: 2025, month: 4))
    XCTAssertEqual(
      JourneyMonth.months(from: JourneyMonth(year: 2025, month: 1), through: JourneyMonth(year: 2025, month: 4)),
      [
        JourneyMonth(year: 2025, month: 1), JourneyMonth(year: 2025, month: 2),
        JourneyMonth(year: 2025, month: 3), JourneyMonth(year: 2025, month: 4),
      ])
    XCTAssertEqual(
      JourneyMonth.months(from: JourneyMonth(year: 2025, month: 4), through: JourneyMonth(year: 2025, month: 1)),
      [])
    XCTAssertEqual(
      JourneyMonth.months(from: JourneyMonth(year: 2024, month: 11), through: JourneyMonth(year: 2025, month: 1)),
      [
        JourneyMonth(year: 2024, month: 11), JourneyMonth(year: 2024, month: 12),
        JourneyMonth(year: 2025, month: 1),
      ])
  }

  // MARK: - Reflection validation: blankness

  func testBlankReflectionsAreRejected() {
    let now = day(2025, 3, 10, 9, 0)
    for text in ["", "   ", "\n", "\t \r\n", "\u{00A0}"] {
      let failures = JourneyReflectionValidator.standard.validation(
        of: draft(text, now), owner: lowercaseOwner, now: now, calendar: ny)
      XCTAssertEqual(failures.map(\.code), [.emptyContent], "text: \(text.debugDescription)")
    }
  }

  func testWhitespacePaddedReflectionIsAccepted() {
    let now = day(2025, 3, 10, 9, 0)
    XCTAssertTrue(
      JourneyReflectionValidator.standard.isValid(
        draft("\n  felt strong today  \n", now), owner: lowercaseOwner, now: now, calendar: ny))
    XCTAssertEqual(draft("\n  felt strong today  \n", now).normalizedText, "felt strong today")
  }

  // MARK: - Reflection validation: grapheme clusters

  func testGraphemeCountingUsesClustersNotScalarsOrBytes() {
    let family = "👨‍👩‍👧‍👦"
    XCTAssertEqual(family.count, 1)
    XCTAssertEqual(family.unicodeScalars.count, 7)
    XCTAssertEqual(JourneyText.graphemeClusterCount(family), 1)

    XCTAssertEqual("🇻🇳".count, 1)
    XCTAssertEqual("🇻🇳".unicodeScalars.count, 2)

    let decomposed = "e\u{0301}"
    XCTAssertEqual(decomposed.count, 1)
    XCTAssertEqual(decomposed.unicodeScalars.count, 2)
    XCTAssertEqual(JourneyText.graphemeClusterCount(decomposed), 1)

    XCTAssertEqual(JourneyText.graphemeClusterCount(String(repeating: "a", count: 2_000)), 2_000)
  }

  func testExactlyTwoThousandGraphemesIsAcceptedAndTwoThousandOneIsNot() {
    let now = day(2025, 3, 10, 9, 0)
    let validator = JourneyReflectionValidator.standard

    let atLimit = String(repeating: "a", count: 2_000)
    XCTAssertTrue(validator.isValid(draft(atLimit, now), owner: lowercaseOwner, now: now, calendar: ny))

    let overLimit = String(repeating: "a", count: 2_001)
    let failures = validator.validation(of: draft(overLimit, now), owner: lowercaseOwner, now: now, calendar: ny)
    XCTAssertEqual(failures.map(\.code), [.contentTooLong])
    XCTAssertEqual(failures.first?.limit, 2_000)
    XCTAssertEqual(failures.first?.actual, 2_001)

    // 2,000 grapheme clusters, 50,000 UTF-8 bytes.
    let emoji = String(repeating: "👨‍👩‍👧‍👦", count: 2_000)
    XCTAssertEqual(emoji.utf8.count, 50_000)
    XCTAssertEqual(JourneyText.graphemeClusterCount(emoji), 2_000)
    XCTAssertTrue(validator.isValid(draft(emoji, now), owner: lowercaseOwner, now: now, calendar: ny))

    let emojiOver = String(repeating: "👨‍👩‍👧‍👦", count: 2_001)
    XCTAssertEqual(
      validator.validation(of: draft(emojiOver, now), owner: lowercaseOwner, now: now, calendar: ny).map(\.code),
      [.contentTooLong])
  }

  func testAtLimitTextWithTrailingNewlineStaysAtLimit() {
    let now = day(2025, 3, 10, 9, 0)
    let padded = String(repeating: "a", count: 2_000) + "\n\n "
    XCTAssertTrue(
      JourneyReflectionValidator.standard.isValid(
        draft(padded, now), owner: lowercaseOwner, now: now, calendar: ny))
    XCTAssertEqual(draft(padded, now).normalizedText.count, 2_000)
  }

  func testValidatorHonoursACustomLimit() {
    let now = day(2025, 3, 10, 9, 0)
    let short = JourneyReflectionValidator(maximumGraphemeClusters: 5)
    XCTAssertTrue(short.isValid(draft("12345", now), owner: lowercaseOwner, now: now, calendar: ny))
    XCTAssertEqual(
      short.validation(of: draft("123456", now), owner: lowercaseOwner, now: now, calendar: ny).map(\.code),
      [.contentTooLong])
    XCTAssertEqual(short.maximumGraphemeClusters, 5)
  }

  // MARK: - Reflection validation: dates

  func testFutureDayIsRejectedAndTodayIsNot() {
    let now = day(2025, 3, 10, 9, 0)
    let validator = JourneyReflectionValidator.standard

    XCTAssertEqual(
      validator.validation(of: draft("x", day(2025, 3, 11)), owner: lowercaseOwner, now: now, calendar: ny)
        .map(\.code),
      [.futureDay])
    XCTAssertTrue(validator.isValid(draft("x", day(2025, 3, 10)), owner: lowercaseOwner, now: now, calendar: ny))
    XCTAssertTrue(
      validator.isValid(draft("x", day(2025, 3, 10, 23, 59)), owner: lowercaseOwner, now: now, calendar: ny))
    XCTAssertTrue(
      validator.isValid(draft("x", day(2025, 3, 9, 23, 59)), owner: lowercaseOwner, now: now, calendar: ny))
  }

  func testFutureCheckIsLocalDayRelativeNotWallClockRelative() {
    // 00:30 local on the 10th; a note dated 23:00 *the same local day* is not future.
    let justAfterMidnight = day(2025, 3, 10, 0, 30)
    XCTAssertFalse(JourneyDate.isFutureDay(day(2025, 3, 10, 23, 0), now: justAfterMidnight, calendar: ny))
    XCTAssertTrue(JourneyDate.isFutureDay(day(2025, 3, 11, 0, 1), now: justAfterMidnight, calendar: ny))
  }

  func testFutureCheckFollowsTheInjectedCalendar() {
    // 23:00 New York on March 10 is 03:00 UTC on March 11.
    let nowNY = day(2025, 3, 10, 0, 30)
    let candidate = day(2025, 3, 10, 23, 0)

    XCTAssertTrue(
      JourneyReflectionValidator.standard.isValid(
        draft("x", candidate), owner: lowercaseOwner, now: nowNY, calendar: ny))
    XCTAssertEqual(
      JourneyReflectionValidator.standard.validation(
        of: draft("x", candidate), owner: lowercaseOwner, now: nowNY, calendar: utc).map(\.code),
      [.futureDay])
  }

  func testResolvedDayIsTheLocalStartOfDay() {
    let resolved = draft("x", day(2025, 3, 10, 22, 15)).resolvedDay(calendar: ny)
    XCTAssertEqual(resolved, day(2025, 3, 10))
    XCTAssertEqual(draft("  x  ", day(2025, 3, 10, 22, 15)).normalized(calendar: ny).day, day(2025, 3, 10))
    XCTAssertEqual(draft("  x  ", day(2025, 3, 10, 22, 15)).normalized(calendar: ny).text, "x")
  }

  // MARK: - Reflection validation: owner and aggregation

  func testMissingOwnerIsRejected() {
    let now = day(2025, 3, 10, 9, 0)
    for owner in ["", "   ", "\n"] {
      XCTAssertEqual(
        JourneyReflectionValidator.standard.validation(of: draft("hello", now), owner: owner, now: now, calendar: ny)
          .map(\.code),
        [.missingOwner])
    }
    XCTAssertTrue(
      JourneyReflectionValidator.standard.isValid(
        draft("hello", now), owner: "  \(canonicalOwner)  ", now: now, calendar: ny))
  }

  func testEveryFailureIsReportedInAFixedOrder() {
    let now = day(2025, 3, 10, 9, 0)
    let failures = JourneyReflectionValidator.standard.validation(
      of: draft("   ", day(2025, 3, 20)), owner: "", now: now, calendar: ny)
    XCTAssertEqual(failures.map(\.code), [.missingOwner, .emptyContent, .futureDay])
    XCTAssertEqual(failures.map(\.message), failures.compactMap { $0.message.isEmpty ? nil : $0.message })
  }

  func testValidateThrowsAllFailures() {
    let now = day(2025, 3, 10, 9, 0)
    XCTAssertThrowsError(
      try JourneyReflectionValidator.standard.validate(
        draft("   ", day(2025, 3, 20)), owner: "", now: now, calendar: ny)
    ) { error in
      guard let validation = error as? JourneyValidationError else {
        return XCTFail("expected JourneyValidationError, got \(error)")
      }
      XCTAssertEqual(validation.codes, [.missingOwner, .emptyContent, .futureDay])
      XCTAssertEqual(validation.first?.code, .missingOwner)
    }
    XCTAssertNoThrow(
      try JourneyReflectionValidator.standard.validate(
        draft("squats felt heavy", now), owner: lowercaseOwner, now: now, calendar: ny))
  }

  func testValidationErrorIsCodable() throws {
    let error = JourneyValidationError(failures: [
      JourneyValidationFailure(code: .contentTooLong, limit: 2_000, actual: 2_100)
    ])
    let data = try JSONEncoder().encode(error)
    XCTAssertEqual(try JSONDecoder().decode(JourneyValidationError.self, from: data), error)
    XCTAssertEqual(error.failures.first?.message, JourneyValidationCode.contentTooLong.message)
  }

  // MARK: - Events

  func testEventDerivesIdentityCategoryAndSortKey() {
    let event = JourneyEvent(
      owner: lowercaseOwner, kind: .progressPhoto, sourceID: "2025-03-05.jpg", title: "Front",
      date: day(2025, 3, 5, 7, 15), precision: .timestamp, calendar: ny)

    XCTAssertEqual(event.id, JourneyEventID.progressPhoto(owner: lowercaseOwner, fileName: "2025-03-05.jpg"))
    XCTAssertEqual(event.category, .body)
    XCTAssertEqual(event.sourceReference, JourneySourceReference(kind: .progressPhoto, sourceID: "2025-03-05.jpg"))
    XCTAssertEqual(event.sourceReference.category, .body)
    XCTAssertEqual(event.day, day(2025, 3, 5))
    XCTAssertEqual(event.instant, day(2025, 3, 5, 7, 15))
    XCTAssertEqual(
      event.sortKey,
      key(day(2025, 3, 5), .timestamp, event.id.rawValue, instant: day(2025, 3, 5, 7, 15)))
    XCTAssertFalse(event.isHidden)
    XCTAssertTrue(event.hidden().isHidden)
    XCTAssertFalse(event.hidden().hidden(false).isHidden)
  }

  func testDateOnlyEventDropsTheTime() {
    let event = JourneyEvent(
      owner: lowercaseOwner, kind: .bodyMeasurement, sourceID: "m1", title: "Weigh-in",
      date: day(2025, 3, 5, 7, 15), precision: .dayOnly, calendar: ny)
    XCTAssertNil(event.instant)
    XCTAssertEqual(event.day, day(2025, 3, 5))
    XCTAssertEqual(event.sortKey.precision, .dayOnly)
    XCTAssertNil(event.sortKey.instant)
  }

  func testSortingEventsUsesTheSingleComparator() {
    let events = [
      JourneyEvent(
        owner: lowercaseOwner, kind: .workout, sourceID: "b", title: "B",
        date: day(2025, 3, 5, 6, 0), precision: .timestamp, calendar: ny),
      JourneyEvent(
        owner: lowercaseOwner, kind: .reflection, sourceID: "a", title: "A",
        date: day(2025, 3, 5), precision: .dayOnly, calendar: ny),
      JourneyEvent(
        owner: lowercaseOwner, kind: .workout, sourceID: "c", title: "C",
        date: day(2025, 3, 6, 6, 0), precision: .timestamp, calendar: ny),
    ]
    XCTAssertEqual(JourneySortKey.sorted(events).map(\.sourceID), ["c", "b", "a"])
    XCTAssertEqual(JourneyFilter.all.withHidden(true).matches(events[0]), true)
  }

  func testEventAndSortKeyRoundTripThroughCodable() throws {
    let event = JourneyEvent(
      owner: lowercaseOwner, kind: .programChange, sourceID: "d-1", facet: .milestone, title: "Added a day",
      detail: "5 days", date: day(2025, 3, 5, 7, 15), precision: .timestamp, calendar: ny)
    let data = try JSONEncoder().encode(event)
    XCTAssertEqual(try JSONDecoder().decode(JourneyEvent.self, from: data), event)

    let sortKey = event.sortKey
    let keyData = try JSONEncoder().encode(sortKey)
    XCTAssertEqual(try JSONDecoder().decode(JourneySortKey.self, from: keyData), sortKey)
  }

  func testSourceKindCategoryMappingIsTotal() {
    XCTAssertEqual(JourneySourceKind.workout.category, .workout)
    XCTAssertEqual(JourneySourceKind.programChange.category, .programChange)
    XCTAssertEqual(JourneySourceKind.bodyMeasurement.category, .body)
    XCTAssertEqual(JourneySourceKind.progressPhoto.category, .body)
    XCTAssertEqual(JourneySourceKind.reflection.category, .note)

    let covered = Set(JourneySourceKind.allCases.map(\.category))
    XCTAssertEqual(covered, Set(JourneyCategory.allCases))
    XCTAssertEqual(JourneyCategory.body.sourceKinds, [.bodyMeasurement, .progressPhoto])
    XCTAssertTrue(JourneySourceKind.progressPhoto.isPrivateByDefault)
    XCTAssertFalse(JourneySourceKind.workout.isPrivateByDefault)
  }
}
