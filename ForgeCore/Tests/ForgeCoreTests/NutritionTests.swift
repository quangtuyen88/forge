import XCTest

@testable import ForgeCore

final class NutritionTests: XCTestCase {
  func testRecompTargets() {
    let t = Nutrition.targets(
      sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, phase: .recomp,
      weeklySets: 0)
    XCTAssertEqual(t.kcal, 2759)
    XCTAssertEqual(t.proteinG, 160)
  }

  func testCutLowersKcalRaisesProtein() {
    let recomp = Nutrition.targets(
      sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, phase: .recomp,
      weeklySets: 0)
    let cut = Nutrition.targets(
      sex: .male, age: 30, heightCm: 180, weightKg: 80, activity: .moderate, phase: .cut,
      weeklySets: 0)
    XCTAssertEqual(Double(cut.kcal), Double(recomp.kcal) * 0.8, accuracy: 1.5)
    XCTAssertEqual(cut.proteinG, 176)
  }

  func testDailyTrainingRecommendationAddsOnlyCarbs() {
    let base = MacroTargets(kcal: 2_500, proteinG: 160, carbsG: 300, fatG: 70)
    let result = NutritionTargetAdvisor.recommend(base: base, dayType: .training)
    XCTAssertEqual(result.carbAdjustmentG, 45)
    XCTAssertEqual(result.recommended.kcal, 2_680)
    XCTAssertEqual(result.recommended.proteinG, base.proteinG)
    XCTAssertEqual(result.recommended.fatG, base.fatG)
  }

  func testRestAndDeloadRecommendationsKeepProteinStable() {
    let base = MacroTargets(kcal: 2_500, proteinG: 160, carbsG: 300, fatG: 70)
    let rest = NutritionTargetAdvisor.recommend(base: base, dayType: .rest)
    let deload = NutritionTargetAdvisor.recommend(base: base, dayType: .deload)
    XCTAssertLessThan(rest.recommended.carbsG, base.carbsG)
    XCTAssertLessThan(deload.recommended.carbsG, base.carbsG)
    XCTAssertEqual(rest.recommended.proteinG, base.proteinG)
    XCTAssertEqual(deload.recommended.fatG, base.fatG)
  }
}
