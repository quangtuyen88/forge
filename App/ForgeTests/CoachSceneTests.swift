import XCTest
import SwiftUI
@testable import Forge
import ForgeCore

final class CoachSceneTests: XCTestCase {
  /// Failure mode 1: every exercise in the DB must have a scene image for both coaches.
  func testEveryExerciseHasASceneForBothCoaches() {
    for e in ExerciseDB.all {
      let scene = CoachScene.forExercise(e)
      for coach in Coach.allCases {
        XCTAssertNotNil(UIImage(named: coach.scene(scene)),
                        "missing \(coach.rawValue)-scene-\(scene.rawValue) for exercise \(e.id)")
      }
    }
  }

  /// Every scene and both flat faces must exist as assets.
  func testAllSceneAndFaceAssetsExist() {
    for scene in CoachScene.allCases {
      for coach in Coach.allCases {
        XCTAssertNotNil(UIImage(named: coach.scene(scene)),
                        "missing \(coach.rawValue)-scene-\(scene.rawValue)")
      }
    }
    XCTAssertNotNil(UIImage(named: Coach.nova.face), "missing nova face")
    XCTAssertNotNil(UIImage(named: Coach.kai.face), "missing kai face")
  }

  /// Failure mode 2: family mapping.
  func testFamilyMapping() {
    XCTAssertEqual(CoachScene.forExercise(ExerciseDB.find("deadlift")!), .deadlift, "hinge must not map to a push scene")
    XCTAssertEqual(CoachScene.forExercise(ExerciseDB.find("lat_pulldown")!), .pullup, "vertical pull maps to pullup")
    XCTAssertEqual(CoachScene.forExercise(ExerciseDB.find("landmine_press")!), .ohp, "vertical push maps to ohp")
    XCTAssertEqual(CoachScene.forExercise(ExerciseDB.find("barbell_curl")!), .curl, "biceps isolation maps to curl")
    XCTAssertEqual(CoachScene.forExercise(ExerciseDB.find("db_calf_raise")!), .calf, "calf raises map to calf")
    XCTAssertEqual(CoachScene.forExercise(ExerciseDB.find("lateral_raise")!), .lateral, "lateral raise maps to lateral")
    XCTAssertEqual(CoachScene.forExercise(ExerciseDB.find("hanging_leg_raise")!), .legraise, "core maps to legraise")
    XCTAssertEqual(CoachScene.forExercise(ExerciseDB.find("back_squat")!), .squat, "squat maps to squat")
    XCTAssertEqual(CoachScene.forExercise(ExerciseDB.find("barbell_bench")!), .bench, "horizontal push maps to bench")
    XCTAssertEqual(CoachScene.forExercise(ExerciseDB.find("bent_row")!), .row, "horizontal pull maps to row")
  }

  /// Failure mode 3: the face is its own asset (a crop of the avatar photo), not the avatar itself.
  func testFaceIsItsOwnAsset() {
    XCTAssertEqual(Coach.nova.face, "nova-face")
    XCTAssertEqual(Coach.kai.face, "kai-face")
    XCTAssertNotEqual(Coach.nova.face, Coach.nova.avatar)
    XCTAssertNotEqual(Coach.kai.face, Coach.kai.avatar)
  }
}
