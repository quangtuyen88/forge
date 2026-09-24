import XCTest
@testable import ForgeCore

final class LandmarksTests: XCTestCase {
  let table: [Muscle: (Int, Int, Int, Int, Int)] = [
    .chest: (6, 8, 12, 16, 20),
    .back: (8, 10, 14, 18, 22),
    .quads: (6, 8, 12, 14, 18),
    .hamstrings: (4, 6, 10, 12, 16),
    .glutes: (4, 6, 10, 14, 16),
    .sideDelts: (6, 8, 14, 18, 22),
    .rearDelts: (4, 6, 10, 14, 18),
    .triceps: (4, 6, 10, 12, 16),
    .biceps: (4, 6, 10, 14, 18),
    .calves: (6, 8, 12, 14, 18),
    .abs: (4, 6, 10, 12, 16),
  ]

  func testChestBase() {
    let l = VolumeLandmarks.base(for: .chest)!
    XCTAssertEqual(l.mv, 6)
    XCTAssertEqual(l.mev, 8)
    XCTAssertEqual(l.mavLow, 12)
    XCTAssertEqual(l.mavHigh, 16)
    XCTAssertEqual(l.mrv, 20)
  }

  func testFullTable() {
    for muscle in Muscle.allCases {
      if let t = table[muscle] {
        let l = VolumeLandmarks.base(for: muscle)
        XCTAssertNotNil(l, "\(muscle)")
        XCTAssertEqual(l?.mv, t.0, "\(muscle) mv")
        XCTAssertEqual(l?.mev, t.1, "\(muscle) mev")
        XCTAssertEqual(l?.mavLow, t.2, "\(muscle) mavLow")
        XCTAssertEqual(l?.mavHigh, t.3, "\(muscle) mavHigh")
        XCTAssertEqual(l?.mrv, t.4, "\(muscle) mrv")
      } else {
        XCTAssertNil(VolumeLandmarks.base(for: muscle), "\(muscle) should have no row")
      }
    }
  }

  func testRecoveryReduced() {
    let l = VolumeLandmarks.landmarks(for: .chest, recoveryReduced: true)!
    XCTAssertEqual(l.mrv, 17)
    XCTAssertEqual(l.mv, 6)
    XCTAssertEqual(l.mev, 8)
    XCTAssertEqual(l.mavLow, 12)
    XCTAssertEqual(l.mavHigh, 16)
  }

  func testRecoveryReducedBackMRV() {
    let l = VolumeLandmarks.landmarks(for: .back, recoveryReduced: true)!
    XCTAssertEqual(l.mrv, 19)
  }

  func testFloor() {
    let l = VolumeLandmarks.base(for: .chest)!
    XCTAssertEqual(l.floor(recoveryReduced: false), 8)
    XCTAssertEqual(l.floor(recoveryReduced: true), 6)
  }

  func testNilMuscles() {
    XCTAssertNil(VolumeLandmarks.base(for: .frontDelts))
    XCTAssertNil(VolumeLandmarks.base(for: .forearms))
    XCTAssertNil(VolumeLandmarks.landmarks(for: .frontDelts, recoveryReduced: true))
  }
}
