import ForgeCore
import XCTest

@testable import Forge

/// The share source reads the log; it never re-derives it. These pin what the composer is
/// allowed to say about a session.
@MainActor
final class ShareCardSourceTests: XCTestCase {

  private func set(
    _ exerciseID: String, kg: Double, reps: Int, rpe: Double = 8, reported: Bool = false
  ) -> LoggedSet {
    let logged = LoggedSet(
      exerciseID: exerciseID, setIndex: 0, weightKg: kg, reps: reps, rpe: rpe, targetRPE: 8,
      loggedAt: Date(timeIntervalSince1970: 1_700_000_000))
    logged.effortReported = reported
    return logged
  }

  func testTheTopSetPerExerciseIsTheHeaviestLoggedOne() {
    let top = SessionTopSet.best(in: [
      set("bench_press", kg: 70, reps: 10),
      set("bench_press", kg: 82.5, reps: 8),
      set("bench_press", kg: 75, reps: 9),
    ])
    XCTAssertEqual(top.count, 1)
    XCTAssertEqual(top.first?.weightKg, 82.5)
    XCTAssertEqual(top.first?.reps, 8)
  }

  func testAtTheSameLoadMoreRepsWins() {
    let top = SessionTopSet.best(in: [
      set("row", kg: 70, reps: 8),
      set("row", kg: 70, reps: 11),
    ])
    XCTAssertEqual(top.first?.reps, 11)
  }

  func testExercisesKeepTheOrderTheyWereTrainedIn() {
    let top = SessionTopSet.best(in: [
      set("squat", kg: 100, reps: 5),
      set("bench_press", kg: 80, reps: 8),
      set("squat", kg: 110, reps: 3),
    ])
    XCTAssertEqual(top.map(\.exerciseID), ["squat", "bench_press"])
  }

  func testUnreportedEffortIsNotTheTargetInDisguise() {
    let top = SessionTopSet.best(in: [set("bench_press", kg: 80, reps: 8, rpe: 8, reported: false)])
    XCTAssertFalse(top.first?.effortReported ?? true)
  }

  func testAnEmptySessionYieldsNoHighlightsRatherThanAPlaceholder() {
    XCTAssertTrue(SessionTopSet.best(in: []).isEmpty)
  }

  func testAnEmptySourceRendersAnEmptyDocumentNotInventedContent() {
    let source = ShareCardSource(
      title: "Upper A", date: Date(timeIntervalSince1970: 1_700_000_000), highlights: [],
      totalExerciseCount: 0, aggregates: [], nextTarget: nil)
    let document = source.document(format: .square, disclosure: .safeDefaults)
    XCTAssertTrue(document.highlights.isEmpty)
    XCTAssertTrue(document.aggregates.isEmpty)
    XCTAssertNil(document.nextTarget)
  }

  /// The exported canvas is fixed. A long name, a wrapped Vietnamese label or an unbreakable
  /// token must not widen the PNG — whatever receives it would crop or letterbox the result.
  func testEveryFormatAndLocaleExportsTheExactCanvas() throws {
    let previous = UserDefaults.standard.string(forKey: L10n.key)
    defer {
      UserDefaults.standard.set(previous, forKey: L10n.key)
      L10n.apply(previous ?? "en")
    }
    let highlights = [
      ShareHighlight(
        exerciseID: "bench_press",
        exerciseName: "Neutral-Grip Dumbbell Bench Press (Chest-Supported)",
        load: LoadValue(milliUnits: 82_500, unit: .kg), reps: 8, rpeTenths: 85,
        qualifier: ShareCardQualifier.unverified)
    ]
    for language in L10n.supported {
      UserDefaults.standard.set(language, forKey: L10n.key)
      L10n.apply(language)
      for format in ShareCardFormat.allCases {
        let source = ShareCardSource(
          title: "Upper A", date: Date(timeIntervalSince1970: 1_700_000_000),
          highlights: highlights, totalExerciseCount: 6,
          aggregates: [ShareAggregate(key: "sets", value: "14 working sets")],
          nextTarget: nil)
        let document = source.document(
          format: format, disclosure: ShareDisclosure(showsRPE: true, showsDate: true))
        let image = try XCTUnwrap(ShareCardRenderer.uiImage(document))
        let pixels = image.cgImage.map { ($0.width, $0.height) }
        XCTAssertEqual(
          pixels?.0, document.format.pixelSize.width, "\(language) \(format.rawValue) width")
        XCTAssertEqual(
          pixels?.1, document.format.pixelSize.height, "\(language) \(format.rawValue) height")
      }
    }
  }

  func testTheAccessibilityTextCarriesTheSameQualifiersAsTheImage() {
    let source = ShareCardSource(
      title: "Upper A", date: Date(timeIntervalSince1970: 1_700_000_000),
      highlights: [
        ShareHighlight(
          exerciseID: "bench_press", exerciseName: "Bench Press",
          load: LoadValue(milliUnits: 82_500, unit: .kg), reps: 8, rpeTenths: 85,
          qualifier: nil)
      ],
      totalExerciseCount: 4, aggregates: [], nextTarget: nil)
    let document = source.document(format: .square, disclosure: .safeDefaults)
    let text = ShareCardComposer.accessibilityText(document)
    XCTAssertTrue(
      text.contains(ShareCardComposer.qualifierText(ShareCardQualifier.selectedSubset)),
      "a partial card says so in its text alternative too")
    XCTAssertFalse(text.contains("RPE"), "an unselected detail stays out of the text")
  }
}
