import Foundation

public enum LoadDomain: String, Codable, Sendable {
  case externalMass, assistance, machineScale, bodyweight
}

public enum LoadingConvention: String, Codable, Sendable {
  case perHand, combined, totalIncludingBar, platesOnly, perSide
  case assistanceDisplayed, notApplicable, unknown
}

public enum LoadSide: String, Codable, Sendable {
  case left, right, bilateral, unspecified
}

public enum LoadNormalizationStatus: String, Codable, Sendable {
  case verified, ambiguous, unsupported
}

public struct LoadDescriptor: Codable, Equatable, Sendable {
  public var originalValue: String
  public var originalUnit: String
  public var domain: LoadDomain
  public var convention: LoadingConvention
  public var equipmentInstanceID: String?
  public var loadModelRevision: Int?
  public var side: LoadSide
  public var normalizationStatus: LoadNormalizationStatus

  public init(
    originalValue: String,
    originalUnit: String,
    domain: LoadDomain,
    convention: LoadingConvention,
    equipmentInstanceID: String? = nil,
    loadModelRevision: Int? = nil,
    side: LoadSide = .unspecified,
    normalizationStatus: LoadNormalizationStatus
  ) {
    self.originalValue = originalValue
    self.originalUnit = originalUnit
    self.domain = domain
    self.convention = convention
    self.equipmentInstanceID = equipmentInstanceID
    self.loadModelRevision = loadModelRevision
    self.side = side
    self.normalizationStatus = normalizationStatus
  }

  public static func legacy(weightKg: Double) -> LoadDescriptor {
    LoadDescriptor(
      originalValue: String(weightKg),
      originalUnit: "kg",
      domain: .externalMass,
      convention: .unknown,
      normalizationStatus: .ambiguous)
  }
}

/// Parses a typed load in the display unit. Nil for blank, non-numeric, negative, non-finite,
/// above 2000, more than two decimals, or zero where the movement carries external load.
public enum LoadEntry {
  public static let maximum = 2000.0

  public static func parse(_ text: String, allowsZero: Bool) -> Double? {
    let trimmed = text.replacingOccurrences(of: ",", with: ".")
      .trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    // Fraction digits are counted in the text, not the value: "62.560" was never typed on a plate stack.
    let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2, parts.count == 1 || parts[1].count <= 2 else { return nil }
    guard let value = Double(trimmed), value.isFinite else { return nil }
    guard value >= 0, value <= maximum else { return nil }
    if value == 0 && !allowsZero { return nil }
    return value
  }
}

public struct ComparisonContext: Codable, Equatable, Sendable {
  public var exerciseID: String
  public var variantID: String?
  public var equipmentInstanceID: String?
  public var loadModelRevision: Int?
  public var convention: LoadingConvention
  public var side: LoadSide
  public var normalizationStatus: LoadNormalizationStatus

  public init(
    exerciseID: String,
    variantID: String? = nil,
    equipmentInstanceID: String? = nil,
    loadModelRevision: Int? = nil,
    convention: LoadingConvention,
    side: LoadSide = .unspecified,
    normalizationStatus: LoadNormalizationStatus
  ) {
    self.exerciseID = exerciseID
    self.variantID = variantID
    self.equipmentInstanceID = equipmentInstanceID
    self.loadModelRevision = loadModelRevision
    self.convention = convention
    self.side = side
    self.normalizationStatus = normalizationStatus
  }

  public func incompatibility(with other: ComparisonContext) -> String? {
    guard normalizationStatus == .verified, other.normalizationStatus == .verified else {
      return "Load meaning is not verified"
    }
    guard exerciseID == other.exerciseID else { return "Different exercises" }
    guard variantID == other.variantID else { return "Different exercise variants" }
    guard equipmentInstanceID == other.equipmentInstanceID else {
      return "Different equipment instances"
    }
    guard loadModelRevision == other.loadModelRevision else { return "Different load models" }
    guard convention == other.convention else { return "Different loading conventions" }
    guard side == other.side else { return "Different sides" }
    return nil
  }

  public func isComparable(to other: ComparisonContext) -> Bool {
    incompatibility(with: other) == nil
  }
}
