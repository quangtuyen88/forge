import Foundation
import SwiftData
import ForgeCore

@Model
final class NutritionProfile {
  var sex: String
  var age: Int
  var heightCm: Double
  var activity: String
  var phase: String
  var kcal: Int
  var proteinG: Int
  var carbsG: Int
  var fatG: Int
  var updated: Date

  init(sex: Sex, age: Int, heightCm: Double, activity: ActivityLevel, phase: Phase) {
    self.sex = sex.rawValue
    self.age = age
    self.heightCm = heightCm
    self.activity = activity.rawValue
    self.phase = phase.rawValue
    self.kcal = 0
    self.proteinG = 0
    self.carbsG = 0
    self.fatG = 0
    self.updated = .now
  }
}

@Model
final class FoodItem {
  var id: String
  var name: String
  var brand: String
  var kcalPer100: Double
  var proteinPer100: Double
  var carbsPer100: Double
  var fatPer100: Double
  var servingG: Double
  var uses: Int
  var lastUsed: Date

  init(id: String, name: String, brand: String, kcalPer100: Double, proteinPer100: Double, carbsPer100: Double, fatPer100: Double, servingG: Double, uses: Int = 0, lastUsed: Date = .now) {
    self.id = id
    self.name = name
    self.brand = brand
    self.kcalPer100 = kcalPer100
    self.proteinPer100 = proteinPer100
    self.carbsPer100 = carbsPer100
    self.fatPer100 = fatPer100
    self.servingG = servingG
    self.uses = uses
    self.lastUsed = lastUsed
  }

  convenience init(draft: FoodItemDraft) {
    self.init(
      id: draft.barcode ?? "custom-\(UUID().uuidString)",
      name: draft.name,
      brand: draft.brand,
      kcalPer100: draft.kcalPer100,
      proteinPer100: draft.proteinPer100,
      carbsPer100: draft.carbsPer100,
      fatPer100: draft.fatPer100,
      servingG: draft.servingG > 0 ? draft.servingG : 100)
  }
}

@Model
final class FoodEntry {
  var date: Date
  var meal: String
  var itemID: String
  var name: String
  var grams: Double
  var kcal: Double
  var proteinG: Double
  var carbsG: Double
  var fatG: Double

  init(date: Date, meal: Meal, itemID: String, name: String, grams: Double, kcal: Double, proteinG: Double, carbsG: Double, fatG: Double) {
    self.date = date
    self.meal = meal.rawValue
    self.itemID = itemID
    self.name = name
    self.grams = grams
    self.kcal = kcal
    self.proteinG = proteinG
    self.carbsG = carbsG
    self.fatG = fatG
  }
}

enum Meal: String, CaseIterable, Identifiable {
  case breakfast, lunch, dinner, snack

  var id: String { rawValue }
  var name: String { rawValue.capitalized }

  var symbol: String {
    switch self {
    case .breakfast: return "sunrise.fill"
    case .lunch: return "sun.max.fill"
    case .dinner: return "moon.stars.fill"
    case .snack: return "carrot.fill"
    }
  }
}

enum Macros {
  static func recompute(profile: NutritionProfile, weightKg: Double, weeklySets: Int) {
    let targets = Nutrition.targets(
      sex: Sex(rawValue: profile.sex) ?? .male,
      age: profile.age,
      heightCm: profile.heightCm,
      weightKg: weightKg,
      activity: ActivityLevel(rawValue: profile.activity) ?? .moderate,
      phase: Phase(rawValue: profile.phase) ?? .recomp,
      weeklySets: weeklySets)
    profile.kcal = targets.kcal
    profile.proteinG = targets.proteinG
    profile.carbsG = targets.carbsG
    profile.fatG = targets.fatG
    profile.updated = .now
  }
}
