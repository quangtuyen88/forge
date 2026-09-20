import Foundation

// MARK: - Units

/// The unit a load value is expressed in on a given equipment instance.
///
/// `unspecified` exists so imported / legacy data whose unit could not be trusted keeps
/// its original string verbatim instead of being silently coerced to kilograms.
public enum LoadUnit: String, Codable, CaseIterable, Sendable {
  case kilograms
  case pounds
  case unspecified

  public static let poundsToKilograms = 0.45359237

  public var symbol: String {
    switch self {
    case .kilograms: return "kg"
    case .pounds: return "lb"
    case .unspecified: return ""
    }
  }

  /// Lenient parse used by migration. Anything unrecognized becomes `.unspecified`, never kg.
  public static func parse(_ raw: String?) -> LoadUnit {
    guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      !trimmed.isEmpty
    else { return .unspecified }
    switch trimmed {
    case "kg", "kgs", "kilo", "kilos", "kilogram", "kilograms":
      return .kilograms
    case "lb", "lbs", "pound", "pounds":
      return .pounds
    default:
      return .unspecified
    }
  }

  public func toKilograms(_ value: Double) -> Double? {
    switch self {
    case .kilograms: return value
    case .pounds: return value * LoadUnit.poundsToKilograms
    case .unspecified: return nil
    }
  }

  public func fromKilograms(_ kilograms: Double) -> Double? {
    switch self {
    case .kilograms: return kilograms
    case .pounds: return kilograms / LoadUnit.poundsToKilograms
    case .unspecified: return nil
    }
  }
}

// MARK: - Equipment kind

/// Physical apparatus behind an equipment instance.
public enum EquipmentKind: String, Codable, CaseIterable, Sendable {
  case barbell
  case dumbbell
  case machine
  case cable
  case plateLoaded
  case bodyweight
  case bands
  case unknown

  public init(equipment: Equipment?) {
    switch equipment {
    case .barbell: self = .barbell
    case .dumbbell: self = .dumbbell
    case .machine: self = .machine
    case .cable: self = .cable
    case .bodyweight: self = .bodyweight
    case .bands: self = .bands
    case .none: self = .unknown
    }
  }

  /// Best-effort mapping back to the coarse `Equipment` enum. Machine-like kinds all map to
  /// `.machine`; `unknown` deliberately maps to `nil` so callers cannot assume apparatus.
  public var equipment: Equipment? {
    switch self {
    case .barbell: return .barbell
    case .dumbbell: return .dumbbell
    case .machine, .plateLoaded: return .machine
    case .cable: return .cable
    case .bodyweight: return .bodyweight
    case .bands: return .bands
    case .unknown: return nil
    }
  }

  /// Apparatus whose load meaning does not depend on the specific gym/unit — a bodyweight or
  /// band load means the same thing anywhere. Barbells and dumbbells are NOT included because
  /// inventories differ per gym.
  public var isGymIndependent: Bool {
    switch self {
    case .bodyweight, .bands: return true
    default: return false
    }
  }

  /// Machine-like apparatus whose mechanics/lever arms differ per unit. Instances must never be
  /// treated as interchangeable, and unknown kinds are treated conservatively as machine-like.
  public var requiresExactInstance: Bool {
    switch self {
    case .machine, .cable, .plateLoaded, .unknown: return true
    default: return false
    }
  }
}

// MARK: - Load model

/// A versioned description of how a number printed on an equipment instance should be read.
///
/// `revision` bumps whenever the physical or logical meaning changes (a machine gets re-plated,
/// a stack is relabelled, a barbell convention is corrected). Two loads are only comparable when
/// their `revision`s match, so silently edited equipment cannot corrupt history.
public struct LoadModel: Codable, Equatable, Hashable, Identifiable, Sendable {
  public var id: String
  public var revision: Int
  public var domain: LoadDomain
  public var convention: LoadingConvention
  public var unit: LoadUnit
  /// Smallest change the equipment can actually make, expressed in `unit`.
  public var increment: Double
  /// Bar weight in `unit`, when the bar is part of a barbell total or anchors a plates-only reading.
  public var barWeight: Double?
  /// Weight of the first selectable step on a machine/cable stack, in `unit`.
  public var stackBaseWeight: Double?
  /// Weight added per stack step, in `unit`.
  public var stackIncrement: Double?
  public var normalizationStatus: LoadNormalizationStatus
  public var createdAt: Date
  public var updatedAt: Date

  public init(
    id: String,
    revision: Int = 1,
    domain: LoadDomain,
    convention: LoadingConvention,
    unit: LoadUnit,
    increment: Double,
    barWeight: Double? = nil,
    stackBaseWeight: Double? = nil,
    stackIncrement: Double? = nil,
    normalizationStatus: LoadNormalizationStatus,
    createdAt: Date = .now,
    updatedAt: Date = .now
  ) {
    self.id = id
    self.revision = revision
    self.domain = domain
    self.convention = convention
    self.unit = unit
    self.increment = increment
    self.barWeight = barWeight
    self.stackBaseWeight = stackBaseWeight
    self.stackIncrement = stackIncrement
    self.normalizationStatus = normalizationStatus
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  /// Increment normalized to kilograms, or `nil` when the unit is not trustworthy.
  public var incrementKg: Double? { unit.toKilograms(increment) }

  /// Whether the bar is numerically part of the displayed value.
  public var includesBar: Bool {
    switch convention {
    case .totalIncludingBar, .combined: return barWeight != nil
    default: return false
    }
  }

  /// Legacy/imported passport: unknown convention, unverified semantics. Never invents a unit.
  public static func legacyUnknown(id: String, revision: Int = 0, now: Date = .now) -> LoadModel {
    LoadModel(
      id: id,
      revision: revision,
      domain: .externalMass,
      convention: .unknown,
      unit: .unspecified,
      increment: 0,
      normalizationStatus: .ambiguous,
      createdAt: now,
      updatedAt: now)
  }

  /// Total barbell load from a value that excludes the bar (plates only).
  public func total(fromPlatesOutsideBar plates: Double) -> Double? {
    guard let barWeight else { return nil }
    return barWeight + plates
  }

  /// Load for a selectorized stack expressed as a number of steps above the base.
  public func stackLoad(steps: Int) -> Double? {
    guard let stackBaseWeight, let stackIncrement else { return nil }
    return stackBaseWeight + stackIncrement * Double(steps)
  }

  // MARK: Factories

  public static func barbellTotalKG(
    id: String, revision: Int = 1, barWeight: Double = 20, increment: Double = 2.5,
    now: Date = .now
  ) -> LoadModel {
    LoadModel(
      id: id, revision: revision, domain: .externalMass, convention: .totalIncludingBar,
      unit: .kilograms, increment: increment, barWeight: barWeight,
      normalizationStatus: .verified, createdAt: now, updatedAt: now)
  }

  public static func barbellTotalLB(
    id: String, revision: Int = 1, barWeight: Double = 45, increment: Double = 5,
    now: Date = .now
  ) -> LoadModel {
    LoadModel(
      id: id, revision: revision, domain: .externalMass, convention: .totalIncludingBar,
      unit: .pounds, increment: increment, barWeight: barWeight,
      normalizationStatus: .verified, createdAt: now, updatedAt: now)
  }

  public static func platesOnlyKG(
    id: String, revision: Int = 1, barWeight: Double = 20, increment: Double = 2.5,
    now: Date = .now
  ) -> LoadModel {
    LoadModel(
      id: id, revision: revision, domain: .externalMass, convention: .platesOnly,
      unit: .kilograms, increment: increment, barWeight: barWeight,
      normalizationStatus: .verified, createdAt: now, updatedAt: now)
  }

  public static func perHandKG(
    id: String, revision: Int = 1, increment: Double = 2, barWeight: Double? = nil,
    now: Date = .now
  ) -> LoadModel {
    LoadModel(
      id: id, revision: revision, domain: .externalMass, convention: .perHand,
      unit: .kilograms, increment: increment, barWeight: barWeight,
      normalizationStatus: .verified, createdAt: now, updatedAt: now)
  }

  public static func assistanceKG(
    id: String, revision: Int = 1, increment: Double = 5, now: Date = .now
  ) -> LoadModel {
    LoadModel(
      id: id, revision: revision, domain: .assistance, convention: .assistanceDisplayed,
      unit: .kilograms, increment: increment,
      normalizationStatus: .verified, createdAt: now, updatedAt: now)
  }

  public static func machineStackKG(
    id: String, revision: Int = 1, stackBaseWeight: Double = 5, stackIncrement: Double = 5,
    now: Date = .now
  ) -> LoadModel {
    LoadModel(
      id: id, revision: revision, domain: .machineScale, convention: .combined,
      unit: .kilograms, increment: stackIncrement, stackBaseWeight: stackBaseWeight,
      stackIncrement: stackIncrement,
      normalizationStatus: .verified, createdAt: now, updatedAt: now)
  }
}

// MARK: - Equipment instance

/// A concrete, identified piece of equipment at a location. Stable `id` plus the
/// `loadModel.revision` form the passport that makes recorded loads comparable over time.
public struct EquipmentInstance: Codable, Equatable, Hashable, Identifiable, Sendable {
  public var id: String
  public var name: String
  public var kind: EquipmentKind
  /// The gym/location this instance belongs to, or `nil` when it travels with the lifter.
  public var gymProfileID: String?
  public var loadModel: LoadModel
  public var createdAt: Date
  public var updatedAt: Date
  public var isRetired: Bool

  public init(
    id: String,
    name: String,
    kind: EquipmentKind,
    gymProfileID: String? = nil,
    loadModel: LoadModel,
    createdAt: Date = .now,
    updatedAt: Date = .now,
    isRetired: Bool = false
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.gymProfileID = gymProfileID
    self.loadModel = loadModel
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.isRetired = isRetired
  }

  /// Deterministic, human-debuggable ID from a name and location.
  public static func stableID(name: String?, gymProfileID: String?) -> String {
    let nameSlug = EquipmentPassport.slug(name ?? "unknown")
    guard let gymProfileID, !gymProfileID.isEmpty else { return "legacy.\(nameSlug)" }
    return "legacy.\(nameSlug).\(EquipmentPassport.slug(gymProfileID))"
  }

  /// Comparison context for a load recorded on this instance for a given exercise.
  public func comparisonContext(
    exerciseID: String,
    variantID: String? = nil,
    side: LoadSide = .unspecified
  ) -> ComparisonContext {
    ComparisonContext(
      exerciseID: exerciseID,
      variantID: variantID,
      equipmentInstanceID: id,
      loadModelRevision: loadModel.revision,
      convention: loadModel.convention,
      side: side,
      normalizationStatus: loadModel.normalizationStatus)
  }

  /// `nil` when the two loads may be compared, otherwise a human-readable reason.
  public func incompatibility(
    with other: EquipmentInstance,
    exerciseID: String,
    variantID: String? = nil,
    side: LoadSide = .unspecified
  ) -> String? {
    comparisonContext(exerciseID: exerciseID, variantID: variantID, side: side)
      .incompatibility(
        with: other.comparisonContext(exerciseID: exerciseID, variantID: variantID, side: side))
  }

  public func isComparable(
    to other: EquipmentInstance,
    exerciseID: String,
    variantID: String? = nil,
    side: LoadSide = .unspecified
  ) -> Bool {
    incompatibility(with: other, exerciseID: exerciseID, variantID: variantID, side: side) == nil
  }
}

// MARK: - Resolution

public enum EquipmentResolution: Equatable, Sendable {
  case resolved(EquipmentInstance)
  case ambiguous(candidateIDs: [String])
  case unavailable

  public var instance: EquipmentInstance? {
    if case .resolved(let instance) = self { return instance }
    return nil
  }

  public var explanation: String {
    switch self {
    case .resolved(let instance):
      return "Resolved to \(instance.name) (\(instance.id)) revision \(instance.loadModel.revision)"
    case .ambiguous(let ids):
      return "Ambiguous: \(ids.count) candidate instances (\(ids.joined(separator: ", ")))"
    case .unavailable:
      return "Unavailable: no equipment instance for this kind at the requested gym profile"
    }
  }
}

/// A passport catalogue: the set of equipment instances a lifter has recorded.
public struct EquipmentPassport: Codable, Equatable, Sendable {
  public var instances: [EquipmentInstance]

  public init(instances: [EquipmentInstance] = []) {
    self.instances = instances
  }

  public func instance(id: String) -> EquipmentInstance? {
    instances.first { $0.id == id }
  }

  /// Live (non-retired) instances of a kind at a location, ordered by stable ID.
  public func instances(kind: EquipmentKind, gymProfileID: String?) -> [EquipmentInstance] {
    instances
      .filter { !$0.isRetired && $0.kind == kind && $0.gymProfileID == gymProfileID }
      .sorted { $0.id < $1.id }
  }

  /// Deterministically pick the equipment instance for a gym profile.
  ///
  /// Rules, in order:
  /// 1. Only live instances of the requested kind are considered.
  /// 2. An exact `gymProfileID` match wins; exactly one match resolves, several are ambiguous.
  /// 3. With no exact match, only genuinely gym-independent kinds (bodyweight, bands) may fall
  ///    back to a location-less instance. Machine-like apparatus never falls back — that would
  ///    imply unsafe equivalence between two different machines.
  /// 4. Everything else is `unavailable`.
  public func resolve(kind: EquipmentKind, forGymProfile gymProfileID: String) -> EquipmentResolution {
    let live = instances
      .filter { !$0.isRetired && $0.kind == kind }
      .sorted { $0.id < $1.id }
    guard !live.isEmpty else { return .unavailable }

    let exact = live.filter { $0.gymProfileID == gymProfileID }
    if exact.count == 1 { return .resolved(exact[0]) }
    if exact.count > 1 { return .ambiguous(candidateIDs: exact.map(\.id)) }

    guard kind.isGymIndependent else { return .unavailable }

    let global = live.filter { $0.gymProfileID == nil }
    if global.count == 1 { return .resolved(global[0]) }
    if global.count > 1 { return .ambiguous(candidateIDs: global.map(\.id)) }
    return .unavailable
  }

  /// Human-readable explanation of whether two loads can be compared.
  public static func explainIncompatibility(
    _ a: ComparisonContext,
    _ b: ComparisonContext
  ) -> String {
    a.incompatibility(with: b) ?? "Comparable: identical exercise, variant, equipment, revision and convention"
  }

  static func slug(_ value: String) -> String {
    var out = ""
    var pendingDash = false
    for character in value.lowercased() {
      if character.isLetter || character.isNumber {
        if pendingDash && !out.isEmpty { out.append("-") }
        pendingDash = false
        out.append(character)
      } else {
        pendingDash = true
      }
    }
    return out.isEmpty ? "unknown" : out
  }
}

// MARK: - Legacy import / migration

/// A permissive, all-optional record describing equipment as it may appear in imported or
/// pre-passport data. Every missing field is preserved as unknown rather than guessed.
public struct LegacyEquipmentRecord: Codable, Equatable, Sendable {
  public var id: String?
  public var name: String?
  public var kind: String?
  public var gymProfileID: String?
  public var unit: String?
  public var increment: Double?
  public var barWeight: Double?
  public var revision: Int?
  public var lastWeight: Double?

  public init(
    id: String? = nil,
    name: String? = nil,
    kind: String? = nil,
    gymProfileID: String? = nil,
    unit: String? = nil,
    increment: Double? = nil,
    barWeight: Double? = nil,
    revision: Int? = nil,
    lastWeight: Double? = nil
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.gymProfileID = gymProfileID
    self.unit = unit
    self.increment = increment
    self.barWeight = barWeight
    self.revision = revision
    self.lastWeight = lastWeight
  }
}

public struct EquipmentMigrationResult: Codable, Equatable, Sendable {
  public var instance: EquipmentInstance
  public var descriptor: LoadDescriptor
  public var warnings: [String]

  public init(instance: EquipmentInstance, descriptor: LoadDescriptor, warnings: [String]) {
    self.instance = instance
    self.descriptor = descriptor
    self.warnings = warnings
  }
}

/// Migration helpers that preserve unknown / ambiguous legacy semantics.
///
/// The guiding rule: never infer a loading convention, never coerce an unknown unit, and never
/// claim machine equivalence. Migrated loads therefore carry `normalizationStatus == .ambiguous`
/// until a human confirms the passport, which blocks comparison through `ComparisonContext`.
public enum EquipmentPassportMigration {
  public static func migrate(_ record: LegacyEquipmentRecord, now: Date = .now)
    -> EquipmentMigrationResult
  {
    var warnings: [String] = []

    let kind = record.kind.flatMap { EquipmentKind(rawValue: $0.lowercased()) } ?? .unknown
    if record.kind == nil {
      warnings.append("Equipment kind missing; recorded as unknown.")
    } else if kind == .unknown && record.kind?.lowercased() != "unknown" {
      warnings.append("Unrecognized equipment kind '\(record.kind!)'; recorded as unknown.")
    }

    let unit = LoadUnit.parse(record.unit)
    if unit == .unspecified {
      warnings.append("Load unit unknown; original value preserved without conversion.")
    }

    // A legacy barbell/plates reading is never assumed to include the bar — convention stays
    // unknown so a plates-only value and a total can never be compared by accident.
    warnings.append("Loading convention unknown; requires confirmation before comparison.")

    let id = record.id ?? EquipmentInstance.stableID(
      name: record.name, gymProfileID: record.gymProfileID)

    let model = LoadModel(
      id: "\(id).model",
      revision: record.revision ?? 0,
      domain: kind == .bodyweight ? .bodyweight : .externalMass,
      convention: .unknown,
      unit: unit,
      increment: record.increment ?? 0,
      barWeight: record.barWeight,
      normalizationStatus: .ambiguous,
      createdAt: now,
      updatedAt: now)

    let instance = EquipmentInstance(
      id: id,
      name: record.name ?? "Unknown equipment",
      kind: kind,
      gymProfileID: record.gymProfileID,
      loadModel: model,
      createdAt: now,
      updatedAt: now)

    let descriptor = LoadDescriptor(
      originalValue: valueString(record.lastWeight),
      originalUnit: record.unit ?? "",
      domain: model.domain,
      convention: .unknown,
      equipmentInstanceID: id,
      loadModelRevision: model.revision,
      side: .unspecified,
      normalizationStatus: .ambiguous)

    return EquipmentMigrationResult(instance: instance, descriptor: descriptor, warnings: warnings)
  }

  /// Renders a legacy numeric value without a spurious `.0` for whole numbers, while still
  /// preserving the raw magnitude for non-integral values.
  static func valueString(_ value: Double?) -> String {
    guard let value else { return "" }
    if value == value.rounded() && abs(value) < 1e15 { return String(Int64(value)) }
    return String(value)
  }

  /// Convenience for a raw JSON payload (already decoded into `Data`).
  public static func migrate(json: Data, now: Date = .now) throws -> EquipmentMigrationResult {
    let record = try JSONDecoder().decode(LegacyEquipmentRecord.self, from: json)
    return migrate(record, now: now)
  }
}
