public enum Sex: String, Codable, Sendable, CaseIterable {
  case male, female

  public var name: String {
    switch self {
    case .male: return String(localized: "Male", bundle: .module)
    case .female: return String(localized: "Female", bundle: .module)
    }
  }
}

public enum ActivityLevel: String, Codable, Sendable, CaseIterable {
  case sedentary, light, moderate, high

  public var name: String {
    switch self {
    case .sedentary: return String(localized: "Sedentary", bundle: .module)
    case .light: return String(localized: "Light", bundle: .module)
    case .moderate: return String(localized: "Moderate", bundle: .module)
    case .high: return String(localized: "High", bundle: .module)
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
    case .cut: return String(localized: "Cut", bundle: .module)
    case .recomp: return String(localized: "Recomp", bundle: .module)
    case .bulk: return String(localized: "Bulk", bundle: .module)
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

public enum Nutrition {
  /// Mifflin-St Jeor.
  public static func bmr(sex: Sex, age: Int, heightCm: Double, weightKg: Double) -> Double {
    let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
    return sex == .male ? base + 5 : base - 161
  }

  public static func targets(sex: Sex, age: Int, heightCm: Double, weightKg: Double, activity: ActivityLevel, phase: Phase, weeklySets: Int) -> MacroTargets {
    let tdee = bmr(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg) * activity.factor + Double(weeklySets) * 6
    let kcal = Int((tdee * phase.factor).rounded())
    let protein = Int((weightKg * (phase == .cut ? 2.2 : 2.0)).rounded())
    let fat = Int((max(weightKg * 0.8, Double(kcal) * 0.2 / 9)).rounded())
    let carbs = Int(max(0, (Double(kcal) - Double(protein) * 4 - Double(fat) * 9) / 4).rounded())
    return MacroTargets(kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat)
  }
}
