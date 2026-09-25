import ForgeCore
import SwiftData
import XCTest

@testable import Forge

/// The share export's contract: the switches decide what leaves the device, and the PDF/CSV
/// payloads carry real data without private prose or photo files.
@MainActor
final class ProgressExportTests: XCTestCase {

  // MARK: fixtures

  private func session(
    _ date: Date, dayName: String, completed: Bool = true, tombstoned: Bool = false
  ) -> WorkoutSession {
    let session = WorkoutSession(date: date, dayName: dayName, week: 1, completed: completed)
    session.tombstoned = tombstoned
    return session
  }

  private func loggedSet(
    _ exerciseID: String, kg: Double, reps: Int, index: Int, at loggedAt: Date
  ) -> LoggedSet {
    LoggedSet(
      exerciseID: exerciseID, setIndex: index, weightKg: kg, reps: reps, rpe: 8, targetRPE: 8,
      loggedAt: loggedAt)
  }

  /// Pins the app language so names, dates and units stay byte-stable in the assertions.
  private func inEnglish<T>(_ body: () throws -> T) rethrows -> T {
    let previous = UserDefaults.standard.string(forKey: L10n.key)
    UserDefaults.standard.set("en", forKey: L10n.key)
    L10n.apply("en")
    defer {
      UserDefaults.standard.set(previous, forKey: L10n.key)
      L10n.apply(previous ?? "en")
    }
    return try body()
  }

  /// A minimal RFC 4180 reader, so quoted commas, quotes and newlines are checked as fields
  /// rather than as raw substrings.
  private func rows(_ csv: String) -> [[String]] {
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var quoted = false
    var index = csv.startIndex
    while index < csv.endIndex {
      let character = csv[index]
      if quoted {
        if character == "\"" {
          let next = csv.index(after: index)
          if next < csv.endIndex, csv[next] == "\"" {
            field.append("\"")
            index = csv.index(after: next)
          } else {
            quoted = false
            index = next
          }
        } else {
          field.append(character)
          index = csv.index(after: index)
        }
      } else {
        switch character {
        case "\"":
          quoted = true
          index = csv.index(after: index)
        case ",":
          row.append(field)
          field = ""
          index = csv.index(after: index)
        case "\n":
          row.append(field)
          field = ""
          rows.append(row)
          row = []
          index = csv.index(after: index)
        case "\r":
          index = csv.index(after: index)
        default:
          field.append(character)
          index = csv.index(after: index)
        }
      }
    }
    if !field.isEmpty || !row.isEmpty {
      row.append(field)
      rows.append(row)
    }
    return rows
  }

  // MARK: CSV

  func testDefaultOptionsExportOnlyTheSwitchedOnCategories() throws {
    try inEnglish {
      let container = try JourneyTestStore.inMemory()
      let context = container.mainContext
      let profile = try JourneyTestStore.profile(in: context)

      let day = JourneyTestStore.date(2026, 9, 19)
      let push = session(day, dayName: "Push A")
      let bench = loggedSet("barbell_bench", kg: 80, reps: 8, index: 0, at: day)
      let deadlift = loggedSet("deadlift", kg: 150, reps: 5, index: 1, at: day)
      bench.session = push
      deadlift.session = push
      deadlift.effortReported = true
      let deleted = session(JourneyTestStore.date(2026, 9, 20), dayName: "Pull A", tombstoned: true)
      let deletedSet = loggedSet("romanian_deadlift", kg: 60, reps: 10, index: 0, at: day)
      deletedSet.session = deleted
      let change = DecisionLogEntry(
        DecisionRecord(
          id: "load_change-barbell_bench-1", date: day, type: "load_change",
          exerciseID: "barbell_bench", muscle: nil, fromValue: 80, toValue: 82.5,
          reasonCodes: [], evidence: [], humanSummary: "Barbell Bench Press: 80 kg → 82.5 kg"))
      let measurement = BodyMeasurement(date: day, weightKg: 80.2, bodyFatPercent: 18.5)
      let note = JourneyReflection(ownerID: "owner", text: "private prose", day: day)
      let photo = ProgressPhoto(date: day, fileName: "IMG_0001.jpg", pose: "front")
      let models: [any PersistentModel] = [
        push, deleted, bench, deadlift, deletedSet, change, measurement, note, photo,
      ]
      models.forEach { context.insert($0) }
      try context.save()

      let source = ProgressExportSource(
        sessions: [push, deleted], decisions: [change], measurements: [measurement],
        notes: [note], photos: [photo], profile: profile)
      let csv = ProgressExport.csv(ProgressExportOptions(), source: source)

      let table = rows(csv)
      XCTAssertEqual(
        table.first,
        ["record_type", "date", "exercise_id", "exercise", "set", "weight_kg", "reps", "rpe", "value", "unit", "detail"])
      XCTAssertEqual(
        Set(table.dropFirst().map { $0[0] }), ["workout_set", "program_change", "record"])
      XCTAssertTrue(
        table.contains {
          $0 == ["workout_set", ISO8601DateFormatter().string(from: day), "barbell_bench", "Barbell Bench Press", "1", "80", "8", "", "", "", "Push A"]
        },
        "a raw set keeps its instant, index and day name, and an unreported effort stays empty")
      XCTAssertTrue(
        table.contains { $0[0] == "workout_set" && $0[2] == "deadlift" && $0[7] == "8" },
        "a reported effort is the set's own RPE, never the plan's target")
      XCTAssertTrue(
        table.contains { $0[0] == "program_change" && $0[2] == "barbell_bench" && $0[8] == "82.5" && $0[9] == "kg" },
        "a program change carries its new load")
      XCTAssertFalse(csv.contains("romanian_deadlift"), "a deleted session never exports")
      XCTAssertFalse(csv.contains("private prose"), "private prose stays off unless asked for")
      XCTAssertFalse(csv.contains("IMG_0001"), "photo files never leave")
    }
  }

  func testNoteTextIsQuotedAndEscapedExactlyAsRFC4180Requires() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let day = JourneyTestStore.date(2026, 9, 19)
    let note = JourneyReflection(ownerID: "owner", text: "a, \"b\"\nc", day: day)
    context.insert(note)
    try context.save()

    var options = ProgressExportOptions()
    options.notes = true
    let csv = ProgressExport.csv(
      options,
      source: ProgressExportSource(
        sessions: [], decisions: [], measurements: [], notes: [note], photos: [], profile: nil))

    let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
    let table = rows(csv)
    XCTAssertEqual(table.count, 2)
    XCTAssertEqual(
      table[1],
      ["note", String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!),
        "", "", "", "", "", "", "", "", "a, \"b\"\nc"])
  }

  func testPhotoRowsCarryThePoseAndNeverTheFileName() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let day = JourneyTestStore.date(2026, 9, 19)
    let photo = ProgressPhoto(date: day, fileName: "IMG_0001.jpg", pose: "front")
    context.insert(photo)
    try context.save()

    var options = ProgressExportOptions()
    options.photos = true
    let csv = ProgressExport.csv(
      options,
      source: ProgressExportSource(
        sessions: [], decisions: [], measurements: [], notes: [], photos: [photo], profile: nil))

    let table = rows(csv)
    XCTAssertEqual(table.count, 2)
    XCTAssertEqual(table[1].count, 11)
    XCTAssertEqual(table[1][0], "photo")
    XCTAssertEqual(table[1][1], ISO8601DateFormatter().string(from: day))
    XCTAssertEqual(table[1][10], "front")
    XCTAssertFalse(csv.contains("IMG_0001"), "the file name is never a column")
  }

  func testTheRecordRowIsTheBestEligibleSetByEpley() throws {
    try inEnglish {
      let container = try JourneyTestStore.inMemory()
      let context = container.mainContext
      let day = JourneyTestStore.date(2026, 9, 19)
      let trusted = session(day, dayName: "Lower A")
      let heavy = loggedSet("deadlift", kg: 150, reps: 5, index: 0, at: day)
      let lighter = loggedSet("deadlift", kg: 140, reps: 3, index: 1, at: day)
      let bench = loggedSet("barbell_bench", kg: 80, reps: 8, index: 2, at: day)
      heavy.session = trusted
      lighter.session = trusted
      bench.session = trusted
      // Four sets inside 150 seconds: too short to be a real session, so nothing in it may
      // become a record — not even its heavier deadlift.
      let rushed = session(day, dayName: "Rushed")
      let fabricated = loggedSet("deadlift", kg: 220, reps: 1, index: 0, at: day)
      fabricated.session = rushed
      for index in 1...3 {
        let filler = loggedSet(
          "romanian_deadlift", kg: 60, reps: 10, index: index,
          at: day.addingTimeInterval(Double(index) * 50))
        filler.session = rushed
        context.insert(filler)
      }
      let models: [any PersistentModel] = [
        trusted, rushed, heavy, lighter, bench, fabricated,
      ]
      models.forEach { context.insert($0) }
      try context.save()

      let csv = ProgressExport.csv(
        ProgressExportOptions(),
        source: ProgressExportSource(
          sessions: [trusted, rushed], decisions: [], measurements: [], notes: [], photos: [],
          profile: nil))
      let table = rows(csv)
      let record = try XCTUnwrap(table.first { $0[0] == "record" && $0[2] == "deadlift" })
      XCTAssertEqual(record[5], "150")
      XCTAssertEqual(record[6], "5")
      XCTAssertEqual(record[8], String(format: "%.1f", Strength.epley(weightKg: 150, reps: 5)))
      XCTAssertFalse(
        table.contains { $0[0] == "record" && $0[5] == "220" },
        "an ineligible heavier set is never a record")
    }
  }

  func testWithheldFlagsNameExactlyWhatStayedPrivate() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let day = JourneyTestStore.date(2026, 9, 19)
    let note = JourneyReflection(ownerID: "owner", text: "Felt strong", day: day)
    context.insert(note)
    try context.save()

    var options = ProgressExportOptions()
    options.notes = true
    options.photos = false
    let content = ProgressExport.content(
      options,
      source: ProgressExportSource(
        sessions: [], decisions: [], measurements: [], notes: [note], photos: [], profile: nil),
      now: day)
    XCTAssertNotNil(content.notes)
    XCTAssertFalse(content.withheldNotes)
    XCTAssertTrue(content.withheldPhotos)
  }

  func testOnlyRealProgramChangesExportAndOnlyLoadsSayKg() throws {
    try inEnglish {
      let container = try JourneyTestStore.inMemory()
      let context = container.mainContext
      let day = JourneyTestStore.date(2026, 9, 19)
      func entry(
        _ type: String, id: String, to: Double?, summary: String, exerciseID: String? = nil
      ) -> DecisionLogEntry {
        DecisionLogEntry(
          DecisionRecord(
            id: id, date: day, type: type, exerciseID: exerciseID, muscle: nil,
            fromValue: nil, toValue: to, reasonCodes: [], evidence: [], humanSummary: summary))
      }
      let load = entry(
        "load_change", id: "load_change-barbell_bench-1", to: 82.5,
        summary: "Barbell Bench Press: 80 kg → 82.5 kg", exerciseID: "barbell_bench")
      let week = entry(
        "weekplan", id: "weekplan-1", to: 4, summary: "Week planned: 4 sessions")
      let config = entry(
        "constraints", id: "constraints-1", to: 3, summary: "Equipment constraints set")
      let models: [any PersistentModel] = [load, week, config]
      models.forEach { context.insert($0) }
      try context.save()

      let source = ProgressExportSource(
        sessions: [], decisions: [load, week, config], measurements: [], notes: [], photos: [],
        profile: nil)

      let changes = try XCTUnwrap(
        ProgressExport.content(ProgressExportOptions(), source: source, now: day).changes)
      XCTAssertEqual(changes.count, 2, "only applied program change types reach the page")
      XCTAssertFalse(
        changes.contains { $0.text.contains("Equipment constraints") })

      let changeRows = rows(ProgressExport.csv(ProgressExportOptions(), source: source))
        .filter { $0[0] == "program_change" }
      XCTAssertEqual(changeRows.count, 2, "an excluded decision type never exports")
      XCTAssertTrue(
        changeRows.contains { $0[2] == "barbell_bench" && $0[8] == "82.5" && $0[9] == "kg" },
        "a load change carries its unit")
      XCTAssertTrue(
        changeRows.contains { $0[9] == "" },
        "a non-load change with a value never says kg")
    }
  }

  // MARK: content

  func testContentRespectsTheSwitchesAndAlwaysShowsFourReportingWeeks() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let profile = try JourneyTestStore.profile(in: context)
    let now = JourneyTestStore.date(2026, 9, 24)

    let currentWeek = session(JourneyTestStore.date(2026, 9, 22), dayName: "Lower A")
    let deadlift = loggedSet("deadlift", kg: 100, reps: 5, index: 0, at: JourneyTestStore.date(2026, 9, 22))
    deadlift.session = currentWeek
    let note = JourneyReflection(ownerID: "owner", text: "Felt strong", day: JourneyTestStore.date(2026, 9, 22))
    let photo = ProgressPhoto(date: JourneyTestStore.date(2026, 9, 22), fileName: "u.jpg", pose: "side")
    let models: [any PersistentModel] = [currentWeek, deadlift, note, photo]
    models.forEach { context.insert($0) }
    try context.save()

    let source = ProgressExportSource(
      sessions: [currentWeek], decisions: [], measurements: [], notes: [note], photos: [photo],
      profile: profile)

    let defaults = ProgressExport.content(ProgressExportOptions(), source: source, now: now)
    XCTAssertNotNil(defaults.workouts)
    XCTAssertNil(defaults.notes)
    XCTAssertNil(defaults.photos)
    XCTAssertTrue(defaults.withheldNotes)
    XCTAssertTrue(defaults.withheldPhotos)

    var open = ProgressExportOptions()
    open.notes = true
    open.photos = true
    let shared = ProgressExport.content(open, source: source, now: now)
    XCTAssertFalse(shared.withheldNotes)
    XCTAssertFalse(shared.withheldPhotos)
    XCTAssertNotNil(shared.notes)
    XCTAssertNotNil(shared.photos)

    var closed = ProgressExportOptions()
    closed.workouts = false
    XCTAssertNil(ProgressExport.content(closed, source: source, now: now).workouts)

    let weeks = try XCTUnwrap(shared.workouts?.weeks)
    XCTAssertEqual(weeks.count, 4)
    XCTAssertEqual(weeks.map(\.isCurrent), [false, false, false, true])
    let calendar = TrainingMetrics.reportingCalendar()
    XCTAssertEqual(
      weeks.last?.start, TrainingMetrics.reportingWeek(containing: now, calendar: calendar).start)
    XCTAssertEqual(weeks.last?.volumeKg ?? 0, 500, accuracy: 0.001)
  }

  func testRangeTextSpansTheFirstToTheLastCompletedSession() throws {
    try inEnglish {
      let container = try JourneyTestStore.inMemory()
      let context = container.mainContext
      let profile = try JourneyTestStore.profile(in: context)
      let first = session(JourneyTestStore.date(2026, 9, 1), dayName: "Upper A")
      let last = session(JourneyTestStore.date(2026, 9, 24), dayName: "Lower A")
      let open = session(JourneyTestStore.date(2026, 9, 30), dayName: "Upper B", completed: false)
      let models: [any PersistentModel] = [first, last, open]
      models.forEach { context.insert($0) }
      try context.save()

      let content = ProgressExport.content(
        ProgressExportOptions(),
        source: ProgressExportSource(
          sessions: [first, last, open], decisions: [], measurements: [], notes: [], photos: [],
          profile: profile),
        now: JourneyTestStore.date(2026, 9, 24))
      let range = DateIntervalFormatter()
      range.locale = L10n.locale
      range.dateTemplate = "dMMMyyyy"
      XCTAssertEqual(content.title, "Regulift · Training summary")
      XCTAssertEqual(
        content.rangeText, "\(range.string(from: first.date, to: last.date)) · Hypertrophy")
    }
  }
}
