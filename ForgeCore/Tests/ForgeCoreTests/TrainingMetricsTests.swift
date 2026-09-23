import XCTest

@testable import ForgeCore

final class TrainingMetricsTests: XCTestCase {
  private let tokyo = TimeZone(identifier: "Asia/Tokyo")!
  private var cal: Calendar { TrainingMetrics.reportingCalendar(timeZone: tokyo) }
  private var now: Date { date(2026, 9, 22, 22, 0, 0) }

  private func date(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int = 0,
    _ minute: Int = 0,
    _ second: Int = 0,
    in zone: TimeZone? = nil
  ) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return TrainingMetrics.reportingCalendar(timeZone: zone ?? tokyo).date(from: components)!
  }

  /// F01: one Monday session, five sets, all eligible, one bench set without reported effort.
  private func f01() -> [MetricSet] {
    let session = date(2026, 9, 21, 18, 0, 0)
    return [
      MetricSet(exerciseID: "bench", date: session, weightKg: 60, reps: 8, storedRPE: 8, effortReported: true, eligible: true),
      MetricSet(exerciseID: "bench", date: session, weightKg: 60, reps: 8, storedRPE: 8, effortReported: true, eligible: true),
      MetricSet(exerciseID: "bench", date: session, weightKg: 60, reps: 8, storedRPE: 8, effortReported: false, eligible: true),
      MetricSet(exerciseID: "row", date: session, weightKg: 40, reps: 10, storedRPE: 7, effortReported: true, eligible: true),
      MetricSet(exerciseID: "row", date: session, weightKg: 40, reps: 10, storedRPE: 8, effortReported: true, eligible: true),
    ]
  }

  /// Five August sessions with a few sets each; deadlift 80x8 on Aug 10; nothing after Aug 17.
  private func augustHistory() -> [MetricSet] {
    var sets: [MetricSet] = []
    for session in [date(2026, 8, 3, 18), date(2026, 8, 6, 18), date(2026, 8, 10, 18), date(2026, 8, 13, 18), date(2026, 8, 17, 18)] {
      sets.append(MetricSet(exerciseID: "squat", date: session, weightKg: 70, reps: 5, storedRPE: 7, effortReported: true, eligible: true))
      sets.append(MetricSet(exerciseID: "press", date: session, weightKg: 35, reps: 6, storedRPE: 6.5, effortReported: true, eligible: true))
    }
    sets.append(MetricSet(exerciseID: "deadlift", date: date(2026, 8, 10, 18), weightKg: 80, reps: 8, storedRPE: 8.5, effortReported: true, eligible: true))
    return sets
  }

  private var currentWeek: DateInterval {
    TrainingMetrics.reportingWeek(containing: now, calendar: cal)
  }

  func testReportingWeekOfNowIsMondayBasedHalfOpen() {
    let week = currentWeek
    XCTAssertEqual(week.start, date(2026, 9, 21))
    XCTAssertEqual(week.end, date(2026, 9, 28))
  }

  func testThisWeekRecordedSetsVolumeAndEffortCoverage() {
    let thisWeek = TrainingMetrics.sets(f01() + augustHistory(), in: currentWeek, scope: .allRecorded)
    XCTAssertEqual(thisWeek.count, 5)
    XCTAssertEqual(TrainingMetrics.volume(thisWeek), 2240, accuracy: 0.001)
    let coverage = TrainingMetrics.effortCoverage(thisWeek)
    XCTAssertEqual(coverage.reported, 4)
    XCTAssertEqual(coverage.total, 5)
    XCTAssertEqual(coverage.mean!, 7.75, accuracy: 0.001)
  }

  func testBenchEstimateInWindowAndAllTimeBestAnyLift() {
    let window = DateInterval(start: date(2026, 8, 31), end: date(2026, 9, 28))
    let bench = TrainingMetrics.bestEstimate(f01() + augustHistory(), scope: .allRecorded, in: window, exerciseID: "bench")
    XCTAssertEqual(bench!.e1RM, 76, accuracy: 0.001)
    let allTime = TrainingMetrics.bestEstimate(f01() + augustHistory(), scope: .allRecorded, in: nil, exerciseID: nil)
    XCTAssertEqual(allTime!.exerciseID, "deadlift")
    XCTAssertEqual(allTime!.e1RM, 80 * (1 + 8.0 / 30), accuracy: 0.01)
  }

  func testWeeklyBinsFourWeeksWithAugustCoverageStart() {
    let bins = TrainingMetrics.weeklyBins(
      f01() + augustHistory(), weeks: 4, now: now, calendar: cal, scope: .allRecorded,
      hardSetsOnly: false, coverageStart: date(2026, 8, 3))
    XCTAssertEqual(bins.map(\.start), [date(2026, 8, 31), date(2026, 9, 7), date(2026, 9, 14), date(2026, 9, 21)])
    XCTAssertEqual(bins.map(\.count), [0, 0, 0, 5])
    XCTAssertTrue(bins.allSatisfy(\.covered))
    let average = TrainingMetrics.averageCount(bins)!
    XCTAssertEqual(average.mean, 1.25, accuracy: 0.001)
    XCTAssertEqual(average.weeks, 4)
  }

  func testNewUserEarlierWeeksUncovered() {
    let bins = TrainingMetrics.weeklyBins(
      f01(), weeks: 4, now: now, calendar: cal, scope: .allRecorded,
      hardSetsOnly: false, coverageStart: date(2026, 9, 21, 18, 0, 0))
    XCTAssertFalse(bins[0].covered)
    XCTAssertFalse(bins[1].covered)
    XCTAssertFalse(bins[2].covered)
    XCTAssertTrue(bins[3].covered)
    let average = TrainingMetrics.averageCount(bins)!
    XCTAssertEqual(average.mean, 5, accuracy: 0.001)
    XCTAssertEqual(average.weeks, 1)
  }

  func testUnverifiedF04SetsCountOnlyInAllRecordedScope() {
    let f04 = [
      MetricSet(exerciseID: "bench", date: date(2026, 9, 22, 12), weightKg: 100, reps: 10, storedRPE: 9, effortReported: true, eligible: false),
      MetricSet(exerciseID: "bench", date: date(2026, 9, 22, 12), weightKg: 100, reps: 10, storedRPE: 9, effortReported: true, eligible: false),
    ]
    let all = f01() + f04
    let recorded = TrainingMetrics.sets(all, in: currentWeek, scope: .allRecorded)
    XCTAssertEqual(recorded.count, 7)
    XCTAssertEqual(TrainingMetrics.volume(recorded), 4240, accuracy: 0.001)
    let eligible = TrainingMetrics.sets(all, in: currentWeek, scope: .analysisEligible)
    XCTAssertEqual(eligible.count, 5)
    XCTAssertEqual(TrainingMetrics.volume(eligible), 2240, accuracy: 0.001)
  }

  func testCorrectionRaisesVolumeAndBenchEstimate() {
    var corrected = f01()
    corrected[0].reps = 9
    let thisWeek = TrainingMetrics.sets(corrected + augustHistory(), in: currentWeek, scope: .allRecorded)
    XCTAssertEqual(TrainingMetrics.volume(thisWeek), 2300, accuracy: 0.001)
    let window = DateInterval(start: date(2026, 8, 31), end: date(2026, 9, 28))
    let bench = TrainingMetrics.bestEstimate(corrected + augustHistory(), scope: .allRecorded, in: window, exerciseID: "bench")
    XCTAssertEqual(bench!.e1RM, 78, accuracy: 0.001)
  }

  func testDeletingOneBenchSetLowersCountAndVolume() {
    var remaining = f01()
    remaining.removeFirst()
    let thisWeek = TrainingMetrics.sets(remaining + augustHistory(), in: currentWeek, scope: .allRecorded)
    XCTAssertEqual(thisWeek.count, 4)
    XCTAssertEqual(TrainingMetrics.volume(thisWeek), 1760, accuracy: 0.001)
  }

  func testHalfOpenWeekBoundaries() {
    let week = currentWeek
    XCTAssertTrue(TrainingMetrics.contains(week, date(2026, 9, 27, 23, 59, 59)))
    XCTAssertFalse(TrainingMetrics.contains(week, date(2026, 9, 28)))
    let newYearWeek = TrainingMetrics.reportingWeek(containing: date(2026, 12, 31), calendar: cal)
    XCTAssertEqual(newYearWeek.start, date(2026, 12, 28))
    XCTAssertEqual(newYearWeek.end, date(2027, 1, 4))
  }

  func testDSTWeeksUseCalendarDaysNotFixedSeconds() {
    let newYork = TimeZone(identifier: "America/New_York")!
    let calendar = TrainingMetrics.reportingCalendar(timeZone: newYork)
    func nyDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
      date(year, month, day, in: newYork)
    }
    let mondayWeek = TrainingMetrics.reportingWeek(containing: nyDate(2026, 11, 2), calendar: calendar)
    XCTAssertEqual(mondayWeek.start, nyDate(2026, 11, 2))
    XCTAssertEqual(mondayWeek.end, nyDate(2026, 11, 9))
    let fallBackWeek = TrainingMetrics.reportingWeek(containing: nyDate(2026, 11, 1), calendar: calendar)
    XCTAssertEqual(fallBackWeek.end.timeIntervalSince(fallBackWeek.start), 7 * 86400 + 3600, accuracy: 0.001)
  }
}
