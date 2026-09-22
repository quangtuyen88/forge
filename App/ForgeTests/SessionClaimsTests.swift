import ForgeCore
import XCTest

@testable import Forge

/// What the screens are allowed to claim about a session. Each case here is a sentence the
/// app used to say that the log could not support.
@MainActor
final class SessionClaimsTests: XCTestCase {

  // MARK: - F05: one duration, one way of writing it

  func testASessionShorterThanAMinuteSaysSoInsteadOfRoundingToZero() {
    XCTAssertEqual(SessionSummaryView.durationText(28), "Under 1 min")
  }

  func testNoElapsedTimeIsAbsentRatherThanZeroMinutes() {
    XCTAssertEqual(SessionSummaryView.durationText(0), "—")
  }

  func testAWholeMinuteReadsAsMinutes() {
    XCTAssertEqual(SessionSummaryView.durationText(600), "10 min")
  }

  /// The summary and History used to round the same short session to 0 and 1. One rule now.
  func testTheSummaryAndHistoryAgreeOnTheSameShortSession() {
    let container = try? JourneyTestStore.inMemory()
    guard let context = container?.mainContext else { return XCTFail("no store") }
    let session = WorkoutSession(
      date: Date(timeIntervalSince1970: 1_700_000_000), dayName: "Full A", week: 1,
      completed: true)
    context.insert(session)
    let first = LoggedSet(
      exerciseID: "bench_press", setIndex: 0, weightKg: 64, reps: 8, rpe: 8, targetRPE: 8,
      loggedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let second = LoggedSet(
      exerciseID: "bench_press", setIndex: 1, weightKg: 64, reps: 8, rpe: 8, targetRPE: 8,
      loggedAt: Date(timeIntervalSince1970: 1_700_000_028))
    first.session = session
    second.session = session
    context.insert(first)
    context.insert(second)

    XCTAssertEqual(SessionMath.durationText([session]), "Under 1 min")
    XCTAssertEqual(SessionSummaryView.durationText(28), SessionMath.durationText([session]))
  }

  // MARK: - F01: effort is an observation

  func testASetLoggedWithoutTouchingRPEReportsNoEffort() {
    let set = LoggedSet(
      exerciseID: "bench_press", setIndex: 0, weightKg: 64, reps: 8, rpe: 8, targetRPE: 8,
      loggedAt: Date(timeIntervalSince1970: 1_700_000_000))
    XCTAssertFalse(set.effortReported)
    XCTAssertNil(set.reportedRPE, "the plan target must not read back as a report")
  }

  func testAnExplicitlyTypedEffortIsARealReport() {
    let set = LoggedSet(
      exerciseID: "bench_press", setIndex: 0, weightKg: 64, reps: 8, rpe: 8.5, targetRPE: 8,
      loggedAt: Date(timeIntervalSince1970: 1_700_000_000), effortReported: true)
    XCTAssertEqual(set.reportedRPE, 8.5)
  }

  // MARK: - QA R01: a plan target is never rendered as a reported effort

  private func loggedSet(rpe: Double, reported: Bool, kg: Double = 62.5) -> LoggedSet {
    LoggedSet(
      exerciseID: "bench", setIndex: 0, weightKg: kg, reps: 8, rpe: rpe, targetRPE: 8,
      loggedAt: Date(timeIntervalSince1970: 1_700_000_000), effortReported: reported)
  }

  func testAnUnratedSetRowCarriesNoEffortSuffix() {
    let row = SessionDetailView.setRowText(loggedSet(rpe: 8, reported: false), lb: false)
    XCTAssertFalse(row.contains("@"), row)
    XCTAssertTrue(row.contains("8"), row)
  }

  func testARatedSetRowShowsTheReportedEffort() {
    let row = SessionDetailView.setRowText(loggedSet(rpe: 8.5, reported: true), lb: false)
    XCTAssertTrue(row.contains("@"), row)
  }

  /// A saved 62.5 that reads back as 63 is a different set.
  func testASetRowKeepsTheSavedLoadPrecision() {
    let row = SessionDetailView.setRowText(loggedSet(rpe: 8, reported: false), lb: false)
    XCTAssertTrue(row.contains(Fmt.num(62.5)), row)
  }

  func testVoiceOverSaysEffortIsNotRecordedRatherThanReadingTheTarget() {
    let spoken = SessionDetailView.setRowAccessibilityLabel(
      loggedSet(rpe: 8, reported: false), lb: false)
    XCTAssertTrue(spoken.localizedCaseInsensitiveContains("not recorded"), spoken)
  }

  // MARK: - QA R02: an edit is a draft until Save

  func testADraftSeedsFromTheSetWithoutWritingBackToIt() {
    let set = loggedSet(rpe: 8, reported: false)
    var draft = LoggedSetDraft(set, lb: false)
    draft.weightText = "664"
    draft.reps = 30
    XCTAssertEqual(set.weightKg, 62.5, accuracy: 0.001)
    XCTAssertEqual(set.reps, 8)
    XCTAssertFalse(set.effortReported)
  }

  func testADraftAcceptsEitherDecimalSeparator() {
    XCTAssertEqual(LoggedSetDraft.parse("62,5"), 62.5)
    XCTAssertEqual(LoggedSetDraft.parse("62.5"), 62.5)
    // A trailing separator is still a usable number; empty and non-numeric text are not, and
    // that is what keeps Save disabled mid-typing.
    XCTAssertEqual(LoggedSetDraft.parse("62,"), 62)
    XCTAssertNil(LoggedSetDraft.parse(""))
    XCTAssertNil(LoggedSetDraft.parse("6a4"))
  }

  func testChoosingAnRPEInTheEditorMarksItAsReported() {
    var draft = LoggedSetDraft(loggedSet(rpe: 8, reported: false), lb: false)
    XCTAssertFalse(draft.effortReported)
    draft.rpe = 8.5
    draft.effortReported = true
    XCTAssertTrue(draft.effortReported)
  }

  // MARK: - QA: an initial prescription is not a change

  func testAFirstPrescriptionIsNotLabelledAsAChange() {
    XCTAssertEqual(
      JourneyProgramChangePolicy.title(for: "load_change", from: nil, to: 60), "Starting load")
    XCTAssertEqual(
      JourneyProgramChangePolicy.title(for: "volume_change", from: nil, to: 12), "Starting volume")
  }

  func testARealAdjustmentStillReadsAsAChange() {
    XCTAssertEqual(
      JourneyProgramChangePolicy.title(for: "load_change", from: 60, to: 62.5), "Load changed")
    XCTAssertEqual(JourneyProgramChangePolicy.title(for: "load_change"), "Load changed")
  }
}
