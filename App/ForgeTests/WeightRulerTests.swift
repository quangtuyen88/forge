import XCTest
import ForgeCore
@testable import Forge

final class WeightRulerTests: XCTestCase {
  func testOffGridStartSnapsToGrid() {
    XCTAssertEqual(WeightRuler.snapped(from: 220.5, ticks: 1, step: 5), 225, accuracy: 1e-9)
    XCTAssertEqual(WeightRuler.snapped(from: 220.5, ticks: -1, step: 5), 220, accuracy: 1e-9)
    XCTAssertEqual(WeightRuler.snapped(from: 220.5, ticks: 2, step: 5), 230, accuracy: 1e-9)
  }

  func testOnGridStartUnchanged() {
    XCTAssertEqual(WeightRuler.snapped(from: 100, ticks: 1, step: 2.5), 102.5, accuracy: 1e-9)
    XCTAssertEqual(WeightRuler.snapped(from: 100, ticks: -2, step: 2.5), 95, accuracy: 1e-9)
  }

  func testZeroTicksReturnsStart() {
    XCTAssertEqual(WeightRuler.snapped(from: 101, ticks: 0, step: 2.5), 101, accuracy: 1e-9)
  }

  func testClampsAtZero() {
    XCTAssertEqual(WeightRuler.snapped(from: 2.5, ticks: -3, step: 2.5), 0, accuracy: 1e-9)
    XCTAssertEqual(WeightRuler.snapped(from: 0, ticks: -1, step: 2.5), 0, accuracy: 1e-9)
  }

  func testFloatNoiseRoundsToGrid() {
    XCTAssertEqual(WeightRuler.snapped(from: 102.49999999, ticks: 1, step: 2.5), 105, accuracy: 1e-9)
    XCTAssertEqual(WeightRuler.snapped(from: 102.50000001, ticks: -1, step: 2.5), 100, accuracy: 1e-9)
  }

  func testStepUsesLbPlateJumps() {
    let barbell = ExerciseDB.all.first { $0.equipment == .barbell }!
    let dumbbell = ExerciseDB.all.first { $0.equipment == .dumbbell }!
    XCTAssertEqual(WeightRuler.step(for: barbell, lb: true), 5, accuracy: 1e-9)
    XCTAssertEqual(WeightRuler.step(for: dumbbell, lb: true), 2.5, accuracy: 1e-9)
    XCTAssertEqual(WeightRuler.step(for: barbell, lb: false), barbell.smallestIncrementKg, accuracy: 1e-9)
    XCTAssertEqual(WeightRuler.step(for: dumbbell, lb: false), dumbbell.smallestIncrementKg, accuracy: 1e-9)
  }
}
