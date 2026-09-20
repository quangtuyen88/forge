public enum Sex: String, Codable, Sendable, CaseIterable {
  case male, female

  public var name: String {
    switch self {
    case .male: return String(localized: "Male", bundle: ForgeCoreResources.bundle)
    case .female: return String(localized: "Female", bundle: ForgeCoreResources.bundle)
    }
  }
}

public enum ActivityLevel: String, Codable, Sendable, CaseIterable {
  case sedentary, light, moderate, high

  public var name: String {
    switch self {
    case .sedentary: return String(localized: "Sedentary", bundle: ForgeCoreResources.bundle)
    case .light: return String(localized: "Light", bundle: ForgeCoreResources.bundle)
    case .moderate: return String(localized: "Moderate", bundle: ForgeCoreResources.bundle)
    case .high: return String(localized: "High", bundle: ForgeCoreResources.bundle)
    }
  }

  public var factor: Double {
    switch self {
    case .sedentary: return 1.2
    case .light: return 1.375
    case .moderate: return 1.55
    case .high: return 1.725
    }
  }
}

public enum Phase: String, Codable, Sendable, CaseIterable {
  case cut, recomp, bulk

  public var name: String {
    switch self {
    case .cut: return String(localized: "Cut", bundle: ForgeCoreResources.bundle)
    case .recomp: return String(localized: "Recomp", bundle: ForgeCoreResources.bundle)
    case .bulk: return String(localized: "Bulk", bundle: ForgeCoreResources.bundle)
    }
  }

  public var factor: Double {
    switch self {
    case .cut: return 0.8
    case .recomp: return 1.0
    case .bulk: return 1.1
    }
  }
}

public struct MacroTargets: Equatable, Sendable {
  public let kcal: Int
  public let proteinG: Int
  public let carbsG: Int
  public let fatG: Int

  public init(kcal: Int, proteinG: Int, carbsG: Int, fatG: Int) {
    self.kcal = kcal
    self.proteinG = proteinG
    self.carbsG = carbsG
    self.fatG = fatG
  }
}

public enum NutritionDayType: String, Codable, Sendable {
  case training, rest, deload

  public var name: String {
    switch self {
    case .training: return "Training day"
    case .rest: return "Rest day"
    case .deload: return "Deload day"
    }
  }
}

public struct NutritionDailyRecommendation: Equatable, Sendable {
  public let dayType: NutritionDayType
  public let base: MacroTargets
  public let recommended: MacroTargets
  public let carbAdjustmentG: Int
  public let explanation: String

  public init(
    dayType: NutritionDayType, base: MacroTargets, recommended: MacroTargets, carbAdjustmentG: Int,
    explanation: String
  ) {
    self.dayType = dayType
    self.base = base
    self.recommended = recommended
    self.carbAdjustmentG = carbAdjustmentG
    self.explanation = explanation
  }
}

public enum NutritionTargetAdvisor {
  public static func recommend(base: MacroTargets, dayType: NutritionDayType)
    -> NutritionDailyRecommendation
  {
    let adjustment: Int
    let explanation: String
    switch dayType {
    case .training:
      adjustment = min(60, max(25, Int((Double(base.carbsG) * 0.15).rounded())))
      explanation =
        "Extra carbohydrate supports today's planned training. Protein and fat stay unchanged."
    case .rest:
      adjustment = -min(30, max(15, Int((Double(base.carbsG) * 0.08).rounded())))
      explanation =
        "A small carbohydrate reduction keeps the weekly calorie average stable on a rest day."
    case .deload:
      adjustment = -min(20, max(10, Int((Double(base.carbsG) * 0.05).rounded())))
      explanation = "Deload training needs slightly less carbohydrate while protein stays stable."
    }
    let carbs = max(0, base.carbsG + adjustment)
    let kcal = max(0, base.kcal + adjustment * 4)
    return NutritionDailyRecommendation(
      dayType: dayType,
      base: base,
      recommended: MacroTargets(
        kcal: kcal, proteinG: base.proteinG, carbsG: carbs, fatG: base.fatG),
      carbAdjustmentG: adjustment,
      explanation: explanation)
  }
}

public enum Nutrition {
  /// Mifflin-St Jeor.
  public static func bmr(sex: Sex, age: Int, heightCm: Double, weightKg: Double) -> Double {
    let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
    return sex == .male ? base + 5 : base - 161
  }

  public static func targets(
    sex: Sex, age: Int, heightCm: Double, weightKg: Double, activity: ActivityLevel, phase: Phase,
    weeklySets: Int
  ) -> MacroTargets {
    let tdee =
      bmr(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg) * activity.factor + Double(
        weeklySets) * 6
    let kcal = Int((tdee * phase.factor).rounded())
    let protein = Int((weightKg * (phase == .cut ? 2.2 : 2.0)).rounded())
    let fat = Int((max(weightKg * 0.8, Double(kcal) * 0.2 / 9)).rounded())
    let carbs = Int(max(0, (Double(kcal) - Double(protein) * 4 - Double(fat) * 9) / 4).rounded())
    return MacroTargets(kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat)
  }
}
