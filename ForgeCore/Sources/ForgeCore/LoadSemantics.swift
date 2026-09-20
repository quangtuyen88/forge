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
