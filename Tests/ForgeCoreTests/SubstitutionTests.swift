import XCTest
@testable import ForgeCore

final class SubstitutionTests: XCTestCase {
  func testAllMapEntries() {
    let cases: [(String, InjuryFlag, String)] = [
      ("barbell_bench", .shoulder, "db_bench_neutral"),
      ("overhead_press", .shoulder, "landmine_press"),
      ("dips", .shoulder, "cable_fly"),
      ("back_squat", .knee, "leg_press"),
      ("lunge", .knee, "leg_extension"),
      ("deadlift", .back, "hip_thrust"),
      ("bent_row", .back, "chest_supported_row"),
    ]
    for (id, flag, expected) in cases {
      XCTAssertEqual(Substitution.replacement(for: id, flags: [flag]), expected, "\(id) + \(flag)")
    }
  }

  func testUnknownIDAndEmptyFlags() {
    XCTAssertNil(Substitution.replacement(for: "snatch", flags: [.shoulder]))
    XCTAssertNil(Substitution.replacement(for: "barbell_bench", flags: []))
    XCTAssertNil(Substitution.replacement(for: "lat_pulldown", flags: [.shoulder, .knee, .back]))
  }

  func testShoulderWinsOverBack() {
    XCTAssertEqual(Substitution.replacement(for: "barbell_bench", flags: [.back, .shoulder]), "db_bench_neutral")
  }

  func testResolveReturnsOriginalWhenNoMatch() {
    let lat = ExerciseDB.find("lat_pulldown")!
    XCTAssertEqual(Substitution.resolve(lat, flags: [.knee]), lat)
  }

  func testResolveReturnsReplacement() {
    let ohp = ExerciseDB.find("overhead_press")!
    XCTAssertEqual(Substitution.resolve(ohp, flags: [.shoulder]).id, "landmine_press")
  }

  func testEveryReplacementIDExistsInDB() {
    for flag in InjuryFlag.allCases {
      for exercise in ExerciseDB.all {
        if let sub = Substitution.replacement(for: exercise.id, flags: [flag]) {
          XCTAssertNotNil(ExerciseDB.find(sub), "\(exercise.id) -> \(sub)")
        }
      }
    }
  }
}
