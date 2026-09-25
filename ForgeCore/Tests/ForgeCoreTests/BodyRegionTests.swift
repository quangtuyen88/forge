import XCTest

@testable import ForgeCore

final class BodyRegionTests: XCTestCase {
  func testEveryMuscleHasARegion() {
    for muscle in Muscle.allCases {
      XCTAssertNotNil(muscle.region)
    }
  }

  func testSummedAndOrderedByVolume() {
    let volume: [Muscle: Double] = [
      .back: 6, .quads: 4, .glutes: 3, .chest: 5,
    ]
    XCTAssertEqual(BodyRegions.worked(volume), [.legs, .back, .chest])
  }

  func testZeroAndMissingMusclesExcluded() {
    let volume: [Muscle: Double] = [
      .chest: 5, .back: 0, .quads: 0,
    ]
    XCTAssertEqual(BodyRegions.worked(volume), [.chest])
  }

  func testTiesKeepEnumOrder() {
    let volume: [Muscle: Double] = [
      .back: 4, .chest: 4, .abs: 2,
    ]
    XCTAssertEqual(BodyRegions.worked(volume), [.back, .chest, .core])
  }

  func testEmptyInput() {
    XCTAssertEqual(BodyRegions.worked([:]), [])
  }
}
