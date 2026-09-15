import XCTest
@testable import ForgeCore

final class NutritionTests: XCTestCase {
  func testBMR() {
    XCTAssertEqual(Nutrition.bmr(sex: .male, age: 30, heightCm: 180, weightKg: 80), 1780, accuracy: 0.5)
  }

  func testRecompTargets() {
    let t = Nutrition.targets(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, phase: .recomp, weeklySets: 0)
    XCTAssertEqual(t.kcal, 2759)
    XCTAssertEqual(t.proteinG, 160)
  }

  func testCutLowersKcalRaisesProtein() {
    let recomp = Nutrition.targets(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, phase: .recomp, weeklySets: 0)
    let cut = Nutrition.targets(sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, phase: .cut, weeklySets: 0)
    XCTAssertEqual(Double(cut.kcal), Double(recomp.kcal) * 0.8, accuracy: 1.5)
    XCTAssertEqual(cut.proteinG, 176)
  }

  func testCarbsNeverNegative() {
    let t = Nutrition.targets(sex: .female, age: 45, heightCm: 150, weightKg: 45, activity: .sedentary, phase: .cut, weeklySets: 0)
    XCTAssertGreaterThanOrEqual(t.carbsG, 0)
    XCTAssertGreaterThanOrEqual(t.proteinG * 4 + t.fatG * 9 + t.carbsG * 4, t.kcal - 10)
  }
}
