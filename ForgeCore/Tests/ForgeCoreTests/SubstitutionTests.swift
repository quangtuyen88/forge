import XCTest
@testable import ForgeCore

final class SubstitutionTests: XCTestCase {
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
