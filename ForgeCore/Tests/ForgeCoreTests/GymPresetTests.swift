import XCTest
@testable import ForgeCore

final class GymPresetTests: XCTestCase {
  func testMatchingRoundTripsEveryCase() {
    for preset in GymPreset.allCases {
      XCTAssertEqual(GymPreset.matching(preset.equipment), preset, preset.rawValue)
    }
  }
}
