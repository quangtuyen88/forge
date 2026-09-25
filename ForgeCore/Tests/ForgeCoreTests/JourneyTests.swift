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

  func testEventIDGoldenValueLocksTheEncoding() {
    // Any change to the encoding — including a version bump — must be deliberate.
    let id = JourneyEventID.make(owner: lowercaseOwner, kind: .workout, sourceID: "a1b2c3", facet: .record)
    XCTAssertEqual(
      id.rawValue,
      "journey.v1|36:3F2504E0-4F89-11D3-9A0C-0305E82C3301|7:workout|6:a1b2c3|6:record")
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

  func testParseRejectsMalformedEncodings() {
    XCTAssertNil(JourneyEventID("").components)
    XCTAssertNil(JourneyEventID("journey.v1").components)
    XCTAssertNil(JourneyEventID("journey.v1|3:a").components)               // truncated
    XCTAssertNil(JourneyEventID("journey.v1|3:a|7:workout|1:s|6:record").components)  // non-numeric length
    XCTAssertNil(JourneyEventID("journey.v1|3:a|7:workout|1:s|6:recorded").components)  // overrun tail
    XCTAssertNil(JourneyEventID("journey.v1|3:a|7:unknown|1:s|0:").components)  // unknown kind
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

  // MARK: - Filters

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

  // MARK: - Reflection validation: grapheme clusters

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
}
