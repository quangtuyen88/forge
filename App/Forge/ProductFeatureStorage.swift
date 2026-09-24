import ForgeCore
import Foundation

// MARK: - Typed, migration-safe feature storage
//
// Every ForgeCore feature contract is persisted as a JSON *string* on `UserProfile`.
// Strings were chosen deliberately:
//
//   * each lives in its own column and adds no SwiftData relationship and no new entity,
//     so a *newer* build can read a payload an older one wrote, and a fixed build can still
//     read a payload this build cannot parse;
//   * the exchange is non-destructive in both directions — a getter returns an empty or
//     `nil` value and leaves the raw payload untouched, and a setter refuses to overwrite or
//     clear a non-empty payload it cannot decode (see `payloadIsRewritable`);
//   * `updatedAt` only advances when a write actually encoded, so a rejected write
//     cannot masquerade as a change.
//
// What this does *not* buy: a build whose `UserProfile` model predates a field does not
// round-trip it. SwiftData only carries the columns the running model declares, and sync
// only carries keys named in `UserProfile.syncData` — so the string encoding protects
// against schema drift *within a build that has the field*, never against an old build that
// never modelled it. Keeping a never-synced secret (share tokens) out of `syncData` is a
// deliberate instance of the same rule.

extension UserProfile {

  /// Version identity used while a profile has no activated program version yet.
  static let unversionedProgramVersionID = ProgramVersionID("program.unversioned")

  /// Stable, deterministic identity for a concrete program version. Two builds that
  /// see the same `number` must agree, so this is derived and never random.
  static func programVersionID(for version: ProgramVersion) -> ProgramVersionID {
    ProgramVersionID("program.v\(version.number)")
  }

  /// The identity a recommendation ledger is stamped with right now.
  var currentProgramVersionID: ProgramVersionID {
    guard let version = activeProgramVersion else {
      return UserProfile.unversionedProgramVersionID
    }
    return UserProfile.programVersionID(for: version)
  }

  // MARK: - JSON plumbing

  fileprivate func decodedJSON<T: Decodable>(_ type: T.Type, from raw: String) -> T? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }

  fileprivate func encodedJSON<T: Encodable>(_ value: T) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  /// Whether the stored payload may be replaced. A non-empty payload this build cannot
  /// decode was written by a build whose schema this one does not understand; overwriting or
  /// clearing it would destroy data that build — or a later, fixed build — can still read. An
  /// empty payload is always rewritable.
  fileprivate func payloadIsRewritable<T: Decodable>(_ type: T.Type, raw: String) -> Bool {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty || decodedJSON(type, from: trimmed) != nil
  }

  // MARK: - Equipment passport

  /// An empty passport when nothing is stored or the stored payload cannot be read.
  var equipmentPassport: EquipmentPassport {
    get { decodedJSON(EquipmentPassport.self, from: equipmentPassportJSON) ?? EquipmentPassport() }
    set {
      guard payloadIsRewritable(EquipmentPassport.self, raw: equipmentPassportJSON),
              let json = encodedJSON(newValue) else { return }
      equipmentPassportJSON = json
        updatedAt = .now
      }
  }

  // MARK: - Equipment bindings

  /// Typed exercise/variant → equipment-instance binding map. Keys come from
  /// `equipmentBindingKey`; an unreadable payload reads back as empty and is left intact.
  var equipmentBindings: [String: String] {
    get { decodedJSON([String: String].self, from: equipmentBindingsJSON) ?? [:] }
    set {
      guard payloadIsRewritable([String: String].self, raw: equipmentBindingsJSON),
              let json = encodedJSON(newValue) else { return }
      equipmentBindingsJSON = json
        updatedAt = .now
      }
  }

  /// Binding key. A variant-specific binding shadows the exercise-level binding, so a
  /// close-grip machine press can resolve differently from the plain machine press.
  static func equipmentBindingKey(exerciseID: String, variant: String?) -> String {
    guard let variant, !variant.isEmpty, variant != "straight" else { return exerciseID }
    return "\(exerciseID)#\(variant)"
  }

  /// The bound instance id, variant-specific first then exercise-level.
  func boundEquipmentInstanceID(exerciseID: String, variant: String?) -> String? {
    let bindings = equipmentBindings
    if let variant, !variant.isEmpty, variant != "straight",
      let id = bindings[Self.equipmentBindingKey(exerciseID: exerciseID, variant: variant)]
    {
      return id
    }
    return bindings[exerciseID]
  }

  /// Records or clears a binding. `nil` clears both the variant-specific and the
  /// exercise-level key so the lifter can fall back to auto-resolution.
  func bindEquipment(exerciseID: String, variant: String?, instanceID: String?) {
    var bindings = equipmentBindings
    let variantKey = Self.equipmentBindingKey(exerciseID: exerciseID, variant: variant)
    if let instanceID {
      bindings[variantKey] = instanceID
    } else {
      bindings.removeValue(forKey: variantKey)
      if variantKey != exerciseID { bindings.removeValue(forKey: exerciseID) }
    }
    equipmentBindings = bindings
  }

  // MARK: - Equipment resolution

  /// How a load's physical instance was chosen.
  enum EquipmentInstanceChoice: Equatable {
    /// The lifter (or a previous session) explicitly bound this instance.
    case bound(EquipmentInstance)
    /// Exactly one live instance of the right kind at the active gym resolved.
    case uniqueActiveGym(EquipmentInstance)
    /// Nothing resolved — ambiguous or unavailable; callers keep the inferred descriptor.
    case unresolved

    var instance: EquipmentInstance? {
      switch self {
      case .bound(let instance), .uniqueActiveGym(let instance): return instance
      case .unresolved: return nil
      }
    }

    var isBound: Bool {
      if case .bound = self { return true }
      return false
    }
  }

  /// Resolve the instance a load should be recorded against: an explicit binding wins,
  /// otherwise a single active-gym instance of the right kind resolves. Ambiguity and
  /// absence are both reported as `.unresolved` so the caller keeps conservative inference.
  func equipmentInstanceChoice(
    exerciseID: String,
    variant: String?,
    kind: EquipmentKind
  ) -> EquipmentInstanceChoice {
    let passport = equipmentPassport
    if let boundID = boundEquipmentInstanceID(exerciseID: exerciseID, variant: variant),
      let bound = passport.instances.first(where: { $0.id == boundID && !$0.isRetired })
    {
      return .bound(bound)
    }
    switch passport.resolve(kind: kind, forGymProfile: trainingConstraints.activeGymProfileID) {
    case .resolved(let instance): return .uniqueActiveGym(instance)
    case .ambiguous, .unavailable: return .unresolved
    }
  }

  /// Live instances of a kind the lifter could pick from at the active gym, plus
  /// location-independent instances (bodyweight, bands). Ordered by id for a stable menu.
  func equipmentCandidates(kind: EquipmentKind) -> [EquipmentInstance] {
    let gymID = trainingConstraints.activeGymProfileID
    var seen = Set<String>()
    return equipmentPassport.instances
      .filter { instance in
        guard !instance.isRetired, instance.kind == kind else { return false }
        return instance.gymProfileID == gymID || (kind.isGymIndependent && instance.gymProfileID == nil)
      }
      .filter { seen.insert($0.id).inserted }
      .sorted { $0.id < $1.id }
  }

  /// Build the descriptor a logged set should carry.
  ///
  /// The original display value/unit are preserved verbatim; the semantic fields (domain,
  /// convention, instance id, load-model revision, normalization) come from the resolved
  /// instance's load model. When nothing resolves — no binding and not exactly one live
  /// active-gym instance — `LoggedSet.inferredDescriptor` is used unchanged, so pre-passport
  /// behaviour is preserved.
  func equipmentLoadDescriptor(
    exerciseID: String,
    variant: String?,
    displayValue: String,
    displayUnit: String,
    weightKg: Double,
    side: LoadSide
  ) -> LoadDescriptor {
    guard let exercise = ExerciseDB.find(exerciseID) else { return .legacy(weightKg: weightKg) }
    let kind = EquipmentKind(equipment: exercise.equipment)
    guard let instance = equipmentInstanceChoice(exerciseID: exerciseID, variant: variant, kind: kind).instance
    else {
      return LoggedSet.inferredDescriptor(exerciseID: exerciseID, weightKg: weightKg)
    }
    return LoadDescriptor(
      originalValue: displayValue.isEmpty ? String(weightKg) : displayValue,
      originalUnit: displayUnit.isEmpty ? (isLb(for: exerciseID) ? "lb" : "kg") : displayUnit,
      domain: instance.loadModel.domain,
      convention: instance.loadModel.convention,
      equipmentInstanceID: instance.id,
      loadModelRevision: instance.loadModel.revision,
      side: side,
      normalizationStatus: instance.loadModel.normalizationStatus)
  }

  // MARK: - Week plan

  /// `nil` when absent or undecodable. A plan that fails to decode is never cleared:
  /// the raw payload stays so a newer build can still read it.
  var weekPlan: WeekPlan? {
    get { decodedJSON(WeekPlan.self, from: weekPlanJSON) }
    set {
      guard payloadIsRewritable(WeekPlan.self, raw: weekPlanJSON) else { return }
        guard let newValue else {
        weekPlanJSON = ""
        updatedAt = .now
          return
      }
      guard let json = encodedJSON(newValue) else { return }
      weekPlanJSON = json
        updatedAt = .now
      }
  }

  // MARK: - Goals

  var goalRecords: [GoalRecord] {
    get { decodedJSON([GoalRecord].self, from: goalRecordsJSON) ?? [] }
    set {
      guard payloadIsRewritable([GoalRecord].self, raw: goalRecordsJSON),
              let json = encodedJSON(newValue) else { return }
      goalRecordsJSON = json
        updatedAt = .now
      }
  }

  // MARK: - Recommendation ledger

  /// Falls back to an empty ledger bound to the profile's current program version, so
  /// decisions made before the first decode still evaluate against the live version
  /// instead of silently treating every snapshot as stale.
  var recommendationLedger: RecommendationLedger {
    get {
      decodedJSON(RecommendationLedger.self, from: recommendationLedgerJSON)
        ?? RecommendationLedger(currentProgramVersion: currentProgramVersionID)
    }
    set {
      guard payloadIsRewritable(RecommendationLedger.self, raw: recommendationLedgerJSON),
              let json = encodedJSON(newValue) else { return }
      recommendationLedgerJSON = json
        updatedAt = .now
    }
  }

  // MARK: - Program import / activation

  var importedProgram: ImportedProgram? {
    get { decodedJSON(ImportedProgram.self, from: importedProgramJSON) }
    set {
      guard payloadIsRewritable(ImportedProgram.self, raw: importedProgramJSON) else { return }
        guard let newValue else {
        importedProgramJSON = ""
        updatedAt = .now
          return
      }
      guard let json = encodedJSON(newValue) else { return }
      importedProgramJSON = json
        updatedAt = .now
      }
  }

  /// The version that is actually live. Importing never sets this; only explicit
  /// activation does (`ProgramActivationPolicy`).
  var activeProgramVersion: ProgramVersion? {
    get { decodedJSON(ProgramVersion.self, from: activeProgramVersionJSON) }
    set {
      guard payloadIsRewritable(ProgramVersion.self, raw: activeProgramVersionJSON) else { return }
        guard let newValue else {
        activeProgramVersionJSON = ""
        updatedAt = .now
          return
      }
      guard let json = encodedJSON(newValue) else { return }
      activeProgramVersionJSON = json
        updatedAt = .now
      }
  }

  // MARK: - Share tokens

  var shareTokens: [ShareTokenMetadata] {
    get { decodedJSON([ShareTokenMetadata].self, from: shareTokensJSON) ?? [] }
    set {
      guard payloadIsRewritable([ShareTokenMetadata].self, raw: shareTokensJSON),
              let json = encodedJSON(newValue) else { return }
      shareTokensJSON = json
        updatedAt = .now
      }
  }

  // MARK: - Routine library / applied routines

  /// A reusable, load-free routine day saved by “Copy routine” or from an import
  /// candidate. The day shape is the entire payload: no loads, no history, no notes.
  struct SavedRoutine: Codable, Sendable, Equatable, Identifiable {
    /// Where the routine came from. "history" (own session) or "import" (validated
    /// candidate day).
    enum SourceKind: String, Codable, Sendable {
      case history
      case importCandidate
    }

    let id: String
    var name: String
    let createdAt: Date
    let sourceKind: SourceKind
    /// Session label or program title, for the library row only.
    let sourceName: String?
    let day: ProgramDay
  }

  /// A confirmed prescription bound to one acceptance, day and training block.
  struct AppliedRoutine: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let planID: String
    let planDayID: String
    let sessionName: String
    let appliedAt: Date
    let routineID: String?
    let day: ProgramDay
    let acceptanceID: String?
    let blockStart: Date?
    let constraintRevision: String?
    let programWeek: Int?
    let volumeRevision: String?
  }

  var routineLibrary: [SavedRoutine] {
    get { decodedJSON([SavedRoutine].self, from: routineLibraryJSON) ?? [] }
    set {
      guard payloadIsRewritable([SavedRoutine].self, raw: routineLibraryJSON),
              let json = encodedJSON(newValue) else { return }
      routineLibraryJSON = json
    }
  }

  var appliedRoutines: [AppliedRoutine] {
    get { decodedJSON([AppliedRoutine].self, from: appliedRoutinesJSON) ?? [] }
    set {
      guard payloadIsRewritable([AppliedRoutine].self, raw: appliedRoutinesJSON),
              let json = encodedJSON(newValue) else { return }
      appliedRoutinesJSON = json
    }
  }

}

// MARK: - Equipment passport bootstrap
//
// The passport is the only feature payload that has a legacy source of truth:
// `TrainingConstraints.gymProfiles` already records *which apparatus* a gym has, but
// nothing about its load semantics. Seeding is therefore deliberately asymmetric:
//
//   * barbell, dumbbell, bodyweight and bands get `verified` load models built from
//     the profile's own bar weights and unit preference — these are claims we can
//     honestly defend;
//   * machine, cable and anything unrecognized get `LoadModel.legacyUnknown` —
//     ambiguous normalization, unspecified unit, unknown convention — so a load
//     recorded against one can never be compared with a different machine merely
//     because both are labelled "machine";
//   * every instance is tied to the gym profile that lists it; the two genuinely
//     location-independent kinds (bodyweight, bands) are seeded once, location-less.
//
// Output is a pure function of the input: profiles are visited in sorted `id` order,
// kinds in a fixed order, and every ID is derived from kind + profile rather than
// from a UUID.

extension UserProfile {

  /// Fixed emission order, so the seeded passport is byte-stable across launches.
  static let bootstrapKindOrder: [EquipmentKind] = [
    .barbell, .dumbbell, .bodyweight, .bands, .machine, .cable,
  ]

  /// Deterministic instance ID. Location-independent kinds carry no profile suffix.
  static func bootstrapInstanceID(kind: EquipmentKind, gymProfileID: String?) -> String {
    guard let gymProfileID, !gymProfileID.isEmpty else { return "bootstrap.\(kind.rawValue)" }
    return "bootstrap.\(kind.rawValue).\(gymProfileID)"
  }

  static func bootstrapEquipmentPassport(
    from constraints: TrainingConstraints,
    usesLb: Bool,
    barKg: Double,
    barLb: Double,
    now: Date = .now
  ) -> EquipmentPassport {
    var instances: [EquipmentInstance] = []
    var seededGlobalKinds: Set<EquipmentKind> = []

    for profile in constraints.gymProfiles.sorted(by: { $0.id < $1.id }) {
      for kind in bootstrapKindOrder {
        guard let apparatus = kind.equipment, profile.equipment.contains(apparatus) else { continue }

        if kind.isGymIndependent {
          // Seed once, with no location: a band or a bodyweight load means the same
          // thing everywhere, so duplicating it per gym would invent equivalence.
          guard seededGlobalKinds.insert(kind).inserted else { continue }
          instances.append(
            bootstrapInstance(kind: kind, gymProfileID: nil, usesLb: usesLb, barKg: barKg, barLb: barLb, now: now))
        } else {
          instances.append(
            bootstrapInstance(
              kind: kind, gymProfileID: profile.id, usesLb: usesLb, barKg: barKg, barLb: barLb, now: now))
        }
      }
    }

    return EquipmentPassport(instances: instances)
  }

  /// The bootstrap passport for this profile's current constraints and bar settings.
  func bootstrappedEquipmentPassport(now: Date = .now) -> EquipmentPassport {
    UserProfile.bootstrapEquipmentPassport(
      from: trainingConstraints, usesLb: usesLb, barKg: barKg, barLb: barLb, now: now)
  }

  /// Seeds the passport from legacy constraints, but only when no payload has ever
  /// been stored. A payload that exists but cannot be decoded is left alone — it may
  /// be readable by a later build. Returns whether a write happened, so the caller can
  /// attach `DecisionLogEntry` evidence.
  @discardableResult
  func seedEquipmentPassportIfEmpty(now: Date = .now) -> Bool {
    guard equipmentPassportJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    let seeded = bootstrappedEquipmentPassport(now: now)
    guard !seeded.instances.isEmpty else { return false }
    equipmentPassport = seeded
    return true
  }

  static func bootstrapInstance(
    kind: EquipmentKind,
    gymProfileID: String?,
    usesLb: Bool,
    barKg: Double,
    barLb: Double,
    now: Date
  ) -> EquipmentInstance {
    let id = bootstrapInstanceID(kind: kind, gymProfileID: gymProfileID)
    return EquipmentInstance(
      id: id,
      name: bootstrapName(kind),
      kind: kind,
      gymProfileID: gymProfileID,
      loadModel: bootstrapLoadModel(
        id: "\(id).model", kind: kind, usesLb: usesLb, barKg: barKg, barLb: barLb, now: now),
      createdAt: now,
      updatedAt: now)
  }

  /// Verified models for apparatus we can describe honestly; `legacyUnknown` for the
  /// rest. Never invents a stack base, increment, unit or convention.
  static func bootstrapLoadModel(
    id: String,
    kind: EquipmentKind,
    usesLb: Bool,
    barKg: Double,
    barLb: Double,
    now: Date
  ) -> LoadModel {
    switch kind {
    case .barbell:
      return usesLb
        ? LoadModel.barbellTotalLB(id: id, barWeight: barLb, now: now)
        : LoadModel.barbellTotalKG(id: id, barWeight: barKg, now: now)

    case .dumbbell:
      if usesLb {
        return LoadModel(
          id: id, revision: 1, domain: .externalMass, convention: .perHand,
          unit: .pounds, increment: 5, normalizationStatus: .verified,
          createdAt: now, updatedAt: now)
      }
      return LoadModel.perHandKG(id: id, increment: 2, now: now)

    case .bodyweight:
      return LoadModel(
        id: id, revision: 1, domain: .bodyweight, convention: .notApplicable,
        unit: usesLb ? .pounds : .kilograms, increment: usesLb ? 5 : 2.5,
        normalizationStatus: .verified, createdAt: now, updatedAt: now)

    case .bands:
      // Band tension is not a mass and has no numeric step, which is itself a
      // verified statement — hence `.notApplicable` with an unspecified unit.
      return LoadModel(
        id: id, revision: 1, domain: .externalMass, convention: .notApplicable,
        unit: .unspecified, increment: 0, normalizationStatus: .verified,
        createdAt: now, updatedAt: now)

    case .machine, .cable, .plateLoaded, .unknown:
      return LoadModel.legacyUnknown(id: id, now: now)
    }
  }

  static func bootstrapName(_ kind: EquipmentKind) -> String {
    switch kind {
    case .barbell: return "Barbell"
    case .dumbbell: return "Dumbbells"
    case .bodyweight: return "Bodyweight"
    case .bands: return "Bands"
    case .machine: return "Machines (unverified)"
    case .cable: return "Cable stack (unverified)"
    case .plateLoaded: return "Plate-loaded (unverified)"
    case .unknown: return "Equipment (unverified)"
    }
  }
}
