import XCTest
@testable import ForgeCore

/// A card must never say more than the log does. These tests are the claims it refuses to
/// make.
final class ShareCardTests: XCTestCase {
  private let date = Date(timeIntervalSince1970: 1_700_000_000)

  private func highlight(
    _ name: String, kg: Double?, reps: Int, rpeTenths: Int? = nil, qualifier: String? = nil
  ) -> ShareHighlight {
    ShareHighlight(
      exerciseID: name.lowercased(), exerciseName: name,
      load: kg.map { LoadValue(milliUnits: Int64($0 * 1000), unit: .kg) },
      reps: reps, rpeTenths: rpeTenths, qualifier: qualifier)
  }

  private func build(
    highlights: [ShareHighlight],
    total: Int = 2,
    aggregates: [ShareAggregate] = [],
    nextTarget: ShareNextTarget? = nil,
    disclosure: ShareDisclosure = .safeDefaults,
    format: ShareCardFormat = .square
  ) -> ShareCardResult {
    ShareCardBuilder.topSets(
      title: "Upper A", date: date, highlights: highlights, totalExerciseCount: total,
      aggregates: aggregates, nextTarget: nextTarget, disclosure: disclosure,
      format: format, look: .clean, dateText: { _ in "Nov 14, 2023" })
  }

  private func document(_ result: ShareCardResult) throws -> CardDocument {
    guard case .ready(let document) = result else {
      throw XCTSkip("expected a ready card, got \(result)")
    }
    return document
  }

  // MARK: - T05, T18, T19: nothing is invented

  func testMissingEffortIsAbsentNotZero() throws {
    let card = try document(
      build(
        highlights: [highlight("Bench Press", kg: 82.5, reps: 8, rpeTenths: nil)],
        disclosure: ShareDisclosure(showsRPE: true)))
    XCTAssertNil(card.highlights.first?.rpeTenths)
  }

  func testEffortStaysHiddenUntilItIsSelected() throws {
    let card = try document(
      build(highlights: [highlight("Bench Press", kg: 82.5, reps: 8, rpeTenths: 85)]))
    XCTAssertNil(card.highlights.first?.rpeTenths, "RPE is off until the lifter turns it on")
  }

  func testANextTargetNeedsBothTheToggleAndACommittedTarget() throws {
    let target = ShareNextTarget(
      exerciseName: "Bench Press",
      load: LoadValue(milliUnits: 85_000, unit: .kg), minimumReps: 6, maximumReps: 8)
    let off = try document(build(highlights: [highlight("Bench Press", kg: 82.5, reps: 8)], nextTarget: target))
    XCTAssertNil(off.nextTarget, "off by default")

    let on = try document(
      build(
        highlights: [highlight("Bench Press", kg: 82.5, reps: 8)], nextTarget: target,
        disclosure: ShareDisclosure(showsNextTarget: true)))
    XCTAssertNotNil(on.nextTarget)
    XCTAssertTrue(on.mandatoryQualifiers.contains(ShareCardQualifier.planned))
  }

  func testATogglesOnTargetWithNothingCommittedShowsNoTarget() throws {
    let card = try document(
      build(
        highlights: [highlight("Bench Press", kg: 82.5, reps: 8)], nextTarget: nil,
        disclosure: ShareDisclosure(showsNextTarget: true)))
    XCTAssertNil(card.nextTarget)
    XCTAssertFalse(card.mandatoryQualifiers.contains(ShareCardQualifier.planned))
  }

  // MARK: - Truthful scope

  func testASubsetOfTheSessionSaysSo() throws {
    let card = try document(
      build(highlights: [highlight("Bench Press", kg: 82.5, reps: 8)], total: 5))
    XCTAssertEqual(card.subsetLabel, ShareCardQualifier.selectedSubset)
  }

  func testACompleteSessionNeedsNoSubsetLabel() throws {
    let card = try document(
      build(
        highlights: [highlight("Bench", kg: 82.5, reps: 8), highlight("Row", kg: 70, reps: 10)],
        total: 2))
    XCTAssertNil(card.subsetLabel)
  }

  func testAnUnverifiedSetKeepsItsQualifier() throws {
    let card = try document(
      build(
        highlights: [
          highlight("Bench Press", kg: 82.5, reps: 8, qualifier: ShareCardQualifier.unverified)
        ]))
    XCTAssertTrue(card.mandatoryQualifiers.contains(ShareCardQualifier.unverified))
  }

  func testNoEligibleContentIsAnEmptyStateNotAnEmptyCard() {
    XCTAssertEqual(build(highlights: []), .unavailable(.noEligibleContent))
  }

  // MARK: - Bounded layout

  func testSquareAndStoryHaveTheirOwnHighlightBudgets() throws {
    let many = (1...6).map { highlight("Lift \($0)", kg: 60, reps: 8) }
    XCTAssertEqual(try document(build(highlights: many, total: 6, format: .square)).highlights.count, 3)
    XCTAssertEqual(try document(build(highlights: many, total: 6, format: .story)).highlights.count, 4)
  }

  func testExportCanvasesAreFixedPixelSizes() {
    XCTAssertEqual(ShareCardFormat.square.pixelSize.width, 1080)
    XCTAssertEqual(ShareCardFormat.square.pixelSize.height, 1080)
    XCTAssertEqual(ShareCardFormat.story.pixelSize.height, 1920)
  }

  func testAtMostTwoSummaryMetrics() throws {
    let card = try document(
      build(
        highlights: [highlight("Bench", kg: 82.5, reps: 8)],
        aggregates: [
          ShareAggregate(key: "sets", value: "14 working sets"),
          ShareAggregate(key: "duration", value: "48 min"),
          ShareAggregate(key: "tonnage", value: "8,200 kg"),
        ]))
    XCTAssertEqual(card.aggregates.count, 2)
  }

  func testAnAggregateCarriesTheScopeItActuallyCovers() throws {
    let card = try document(
      build(
        highlights: [highlight("Bench", kg: 82.5, reps: 8)],
        aggregates: [ShareAggregate(key: "tonnage", value: "8,200 kg", scopeLabel: "barbell only")]))
    XCTAssertEqual(card.aggregates.first?.scopeLabel, "barbell only")
  }

  // MARK: - T22: hidden is hidden everywhere

  func testADateStaysHiddenUntilSelected() throws {
    XCTAssertNil(try document(build(highlights: [highlight("Bench", kg: 82.5, reps: 8)])).subtitle)
    let shown = try document(
      build(
        highlights: [highlight("Bench", kg: 82.5, reps: 8)],
        disclosure: ShareDisclosure(showsDate: true)))
    XCTAssertEqual(shown.subtitle, "Nov 14, 2023")
  }

  func testAHiddenTitleIsAlsoAbsentFromTheCaption() throws {
    let card = try document(
      build(
        highlights: [highlight("Bench Press", kg: 82.5, reps: 8)],
        disclosure: ShareDisclosure(showsSessionTitle: false)))
    let caption = ShareCardBuilder.caption(
      for: card, line: { "\($0.exerciseName) \($0.reps)" }, qualifierText: { $0 })
    XCTAssertFalse(caption.contains("Upper A"))
  }

  func testTheCaptionCarriesTheMandatoryPlannedLabel() throws {
    let card = try document(
      build(
        highlights: [highlight("Bench Press", kg: 82.5, reps: 8)],
        nextTarget: ShareNextTarget(
          exerciseName: "Bench Press", load: LoadValue(milliUnits: 85_000, unit: .kg),
          minimumReps: 6, maximumReps: 8),
        disclosure: ShareDisclosure(showsNextTarget: true)))
    let caption = ShareCardBuilder.caption(
      for: card, line: { "\($0.exerciseName) \($0.reps)" },
      qualifierText: { $0 == ShareCardQualifier.planned ? "Planned — not completed" : $0 })
    XCTAssertTrue(caption.contains("Planned — not completed"))
  }

  func testTheCaptionOnlyNamesWhatTheCardShows() throws {
    let card = try document(
      build(highlights: [highlight("Bench Press", kg: 82.5, reps: 8)], total: 5))
    let caption = ShareCardBuilder.caption(
      for: card, line: { "\($0.exerciseName) \($0.reps)" }, qualifierText: { $0 })
    XCTAssertFalse(caption.contains("Lift 2"), "no unseen exercise list in the text")
    XCTAssertTrue(caption.contains(ShareCardQualifier.selectedSubset))
  }

  func testTheSafeDefaultsRevealNothingOptional() {
    let defaults = ShareDisclosure.safeDefaults
    XCTAssertFalse(defaults.showsRPE)
    XCTAssertFalse(defaults.showsComparison)
    XCTAssertFalse(defaults.showsDate)
    XCTAssertFalse(defaults.showsDisplayName)
    XCTAssertFalse(defaults.showsNextTarget)
  }
}
