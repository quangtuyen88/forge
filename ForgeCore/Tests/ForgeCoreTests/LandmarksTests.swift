import XCTest
@testable import ForgeCore

final class LandmarksTests: XCTestCase {
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
}
