import Foundation

// MARK: - Units and prescriptions
//
// Integration contracts for the existing training engine. Nothing here computes a training
// rule: these types carry what an existing `Decision` already decided, with the provenance
// needed to keep private inputs off the network. See docs/FORGECORE_INTEGRATION.md.

public enum MassUnit: String, Codable, Sendable, Equatable {
  case kg, lb
}

/// A load in whole milli-units of its own unit: 82.5 kg is `82_500` with `.kg`.
/// Integer storage keeps a round-trip exact, so an exported prescription can never drift
/// by a floating-point step away from the plates the lifter actually loads.
public struct LoadValue: Codable, Sendable, Equatable, Hashable {
  public let milliUnits: Int64
  public let unit: MassUnit

  public init(milliUnits: Int64, unit: MassUnit) {
    self.milliUnits = milliUnits
    self.unit = unit
  }

  /// Rounds to the nearest milli-unit; `kg` values come from the engine, which works in kg.
  public init(kg: Double) {
    self.milliUnits = Int64((kg * 1000).rounded())
    self.unit = .kg
  }

  public var value: Double { Double(milliUnits) / 1000 }
}

/// One prescription line. `load == nil` means uncalibrated or not applicable — never zero weight.
public struct SetPrescription: Codable, Sendable, Equatable {
  public let exerciseID: String
  public let load: LoadValue?
  public let workingSets: Int
  public let minimumReps: Int
  public let maximumReps: Int
  public let targetRPETenths: Int?

  public init(
    exerciseID: String, load: LoadValue?, workingSets: Int, minimumReps: Int, maximumReps: Int,
    targetRPETenths: Int?
  ) {
    self.exerciseID = exerciseID
    self.load = load
    self.workingSets = workingSets
    self.minimumReps = minimumReps
    self.maximumReps = maximumReps
    self.targetRPETenths = targetRPETenths
  }
}

// MARK: - Provenance

/// Where a fact that a decision depended on came from. This is lineage, not display data:
/// one `derivedHealth` origin anywhere in a decision's dependencies blocks its cloud export.
public enum EvidenceOrigin: String, Sendable, Equatable, Hashable, CaseIterable {
  case workoutLog
  case programConfiguration
  case userPreference
  case manualCheckIn
  case healthKit
  case derivedHealth
  case unknown
}

public struct EvidenceFact: Sendable, Equatable {
  public let key: String
  public let displayValue: String
  public let sourceID: String?
  public let sourceRevision: Int64?
  public let observedAt: Date?
  public let origin: EvidenceOrigin

  public init(
    key: String, displayValue: String, sourceID: String? = nil, sourceRevision: Int64? = nil,
    observedAt: Date? = nil, origin: EvidenceOrigin
  ) {
    self.key = key
    self.displayValue = displayValue
    self.sourceID = sourceID
    self.sourceRevision = sourceRevision
    self.observedAt = observedAt
    self.origin = origin
  }
}

public enum DecisionScope: String, Codable, Sendable, Equatable {
  case nextSet, futureSession, futureWeek
}

// MARK: - Reason codes

/// The stable machine namespace for a committed change. A code is emitted by the rule branch
/// that made the change; unknown codes are preserved verbatim, never decoded away.
public enum TrainingReasonCode {
  public static let progressionRepRangePassed = "load.progression.rep_range_passed"
  public static let progressionEffortBelowTarget = "load.progression.effort_below_target"
  public static let holdTargetMet = "load.hold.target_met"
  public static let holdEffortUnreported = "load.hold.effort_unreported"
  public static let reductionEffortAboveTarget = "load.reduction.effort_above_target"
  public static let volumeReductionRecoveryPolicy = "volume.reduction.recovery_policy"
  public static let volumeIncreaseRamp = "volume.increase.ramp"
  public static let substitutionEquipment = "exercise.substitution.equipment"
  public static let substitutionPlateau = "exercise.substitution.plateau"
  public static let firstExposureCalibration = "load.first_exposure.calibration"
  public static let scheduleUserRequest = "schedule.change.user_request"
  public static let scheduleMissedSession = "schedule.change.missed_session"
  public static let deloadScheduled = "plan.deload.scheduled"
  public static let deloadEarlyPolicy = "plan.deload.early_policy"
  public static let userOverride = "load.override.user_request"

  /// Every code this build knows. A code outside this set is still stored and displayed
  /// through a generic fallback; it is never silently dropped and never cloud-exported.
  public static let known: Set<String> = [
    progressionRepRangePassed, progressionEffortBelowTarget, holdTargetMet, holdEffortUnreported,
    reductionEffortAboveTarget, volumeReductionRecoveryPolicy, volumeIncreaseRamp,
    substitutionEquipment, substitutionPlateau, firstExposureCalibration, scheduleUserRequest,
    scheduleMissedSession, deloadScheduled, deloadEarlyPolicy, userOverride,
  ]
}

extension DecisionSignal {
  /// The provenance of the input behind this signal. Readiness, sleep and soreness are
  /// Health-derived or self-reported recovery context: they stay local.
  public var origin: EvidenceOrigin {
    switch self {
    case .rpeBelowTarget, .rpeAboveTarget, .repsAtTopOfRange, .repsBelowRange, .completedAllSets,
      .e1rmUp, .e1rmFlat, .e1rmDown, .plateau, .missedSessions, .firstExposure:
      return .workoutLog
    case .volumeBelowMEV, .volumeAboveMRV, .timeBudget, .equipmentMissing, .deloadWeek:
      return .programConfiguration
    case .userOverride:
      return .userPreference
    case .sorenessHigh:
      return .manualCheckIn
    case .readinessLow, .readinessNormal, .readinessHigh, .sleepShort:
      return .derivedHealth
    }
  }
}

// MARK: - Decision

/// One committed change with the evidence that produced it.
///
/// Intentionally **not** `Codable`: only `CloudExportPolicy` may turn a decision into something
/// that crosses the network, and only after checking every dependency origin.
public struct ProgramDecision: Sendable, Equatable {
  public let id: String
  public let requestID: UUID
  public let planID: String
  public let planRevisionBefore: Int64
  public let planRevisionAfter: Int64
  public let sessionID: String?
  public let scope: DecisionScope
  public let engineVersion: String
  public let rulesVersion: String
  public let reasonCode: String
  public let before: SetPrescription
  public let after: SetPrescription
  public let evidence: [EvidenceFact]
  /// Every causal dependency, including control-flow inputs that left no visible evidence line.
  public let dependencyOrigins: Set<EvidenceOrigin>
  public let createdAt: Date
  public let supersedesDecisionID: String?

  public init(
    id: String, requestID: UUID, planID: String, planRevisionBefore: Int64,
    planRevisionAfter: Int64, sessionID: String?, scope: DecisionScope, engineVersion: String,
    rulesVersion: String, reasonCode: String, before: SetPrescription, after: SetPrescription,
    evidence: [EvidenceFact], dependencyOrigins: Set<EvidenceOrigin>, createdAt: Date,
    supersedesDecisionID: String? = nil
  ) {
    self.id = id
    self.requestID = requestID
    self.planID = planID
    self.planRevisionBefore = planRevisionBefore
    self.planRevisionAfter = planRevisionAfter
    self.sessionID = sessionID
    self.scope = scope
    self.engineVersion = engineVersion
    self.rulesVersion = rulesVersion
    self.reasonCode = reasonCode
    self.before = before
    self.after = after
    self.evidence = evidence
    self.dependencyOrigins = dependencyOrigins
    self.createdAt = createdAt
    self.supersedesDecisionID = supersedesDecisionID
  }

  /// Origins from the declared dependencies plus every evidence line actually attached.
  public var allOrigins: Set<EvidenceOrigin> {
    dependencyOrigins.union(evidence.map(\.origin))
  }
}

public struct CloudDecisionProjection: Codable, Sendable, Equatable {
  public let schemaVersion: Int
  public let id: String
  public let planID: String
  public let planRevisionAfter: Int64
  public let scope: DecisionScope
  public let reasonCode: String
  public let before: SetPrescription
  public let after: SetPrescription

  public init(
    schemaVersion: Int, id: String, planID: String, planRevisionAfter: Int64, scope: DecisionScope,
    reasonCode: String, before: SetPrescription, after: SetPrescription
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.planID = planID
    self.planRevisionAfter = planRevisionAfter
    self.scope = scope
    self.reasonCode = reasonCode
    self.before = before
    self.after = after
  }
}

/// Allowlist, not blacklist: a decision leaves the device only when every origin it depended on
/// is workout/program data **and** its reason code has been reviewed for export.
public struct CloudExportPolicy: Sendable {
  public static let schemaVersion = 1

  public static let allowedOrigins: Set<EvidenceOrigin> = [.workoutLog, .programConfiguration]

  /// Reviewed codes only. Adding one is a policy decision with a test, not a convenience.
  public static let reviewedReasonCodes: Set<String> = [
    TrainingReasonCode.progressionRepRangePassed,
    TrainingReasonCode.progressionEffortBelowTarget,
    TrainingReasonCode.holdTargetMet,
    TrainingReasonCode.holdEffortUnreported,
    TrainingReasonCode.reductionEffortAboveTarget,
    TrainingReasonCode.firstExposureCalibration,
  ]

  public init() {}

  public func project(_ decision: ProgramDecision) -> CloudDecisionProjection? {
    let origins = decision.allOrigins
    guard !origins.isEmpty,
      origins.isSubset(of: Self.allowedOrigins),
      Self.reviewedReasonCodes.contains(decision.reasonCode)
    else { return nil }

    return CloudDecisionProjection(
      schemaVersion: Self.schemaVersion,
      id: decision.id,
      planID: decision.planID,
      planRevisionAfter: decision.planRevisionAfter,
      scope: decision.scope,
      reasonCode: decision.reasonCode,
      before: decision.before,
      after: decision.after)
  }

  /// Decisions that may cross the network, in input order. Everything else is withheld.
  public func exportable(_ decisions: [ProgramDecision]) -> [CloudDecisionProjection] {
    decisions.compactMap(project)
  }
}

// MARK: - Legacy ledger bridge

/// Provenance for the ledger records the app already writes.
///
/// `DecisionRecord` carries formatted evidence strings ("readiness 82"), so the signal codes are
/// the only reliable lineage. A record whose codes are unknown is treated as `unknown` origin and
/// therefore never exported — missing lineage is not permission.
public enum DecisionProvenance {
  public static func origins(reasonCodes: [String]) -> Set<EvidenceOrigin> {
    guard !reasonCodes.isEmpty else { return [.unknown] }
    var out: Set<EvidenceOrigin> = []
    for code in reasonCodes {
      guard let signal = DecisionSignal.allCases.first(where: { $0.code == code }) else {
        out.insert(.unknown)
        continue
      }
      out.insert(signal.origin)
    }
    return out
  }

  public static func origins(_ record: DecisionRecord) -> Set<EvidenceOrigin> {
    origins(reasonCodes: record.reasonCodes)
  }

  /// True when every code behind the record is workout or program data.
  public static func isCloudExportable(_ record: DecisionRecord) -> Bool {
    let origins = origins(record)
    return !origins.isEmpty && origins.isSubset(of: CloudExportPolicy.allowedOrigins)
  }

  /// The records that may be sent to the cloud coach, newest-first order preserved.
  ///
  /// This is the lineage gate the coach payload must pass through: a decision that read
  /// readiness, sleep or soreness keeps its full explanation on device.
  public static func cloudExportable(_ records: [DecisionRecord]) -> [DecisionRecord] {
    records.filter(isCloudExportable)
  }

  /// The reason codes withheld from a payload, for the local "what was not sent" note.
  public static func withheldCodes(_ records: [DecisionRecord]) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for record in records where !isCloudExportable(record) {
      for code in record.reasonCodes where seen.insert(code).inserted {
        out.append(code)
      }
    }
    return out
  }
}

// MARK: - Requests, receipts and errors

public enum TrainingIntentKind: String, Codable, Sendable, Equatable {
  case reconcileCompletedSession, shortenSession, swapExercise, applyDecisionLedger
}

/// A canonical request identity. The fingerprint covers intent, resource and content — never a
/// retry timestamp — so a repeated delivery of the same work is recognisable as a replay.
public struct TrainingRequest: Sendable, Equatable {
  public let id: UUID
  public let kind: TrainingIntentKind
  public let resourceID: String
  public let contentKey: String
  public let requestedAt: Date

  public init(
    id: UUID, kind: TrainingIntentKind, resourceID: String, contentKey: String, requestedAt: Date
  ) {
    self.id = id
    self.kind = kind
    self.resourceID = resourceID
    self.contentKey = contentKey
    self.requestedAt = requestedAt
  }

  public var fingerprint: String {
    TrainingFingerprint.make(kind: kind, resourceID: resourceID, contentKey: contentKey)
  }
}

public enum TrainingFingerprint {
  /// Deterministic, order-stable and independent of wall-clock time.
  public static func make(kind: TrainingIntentKind, resourceID: String, contentKey: String)
    -> String
  {
    "\(kind.rawValue)|\(resourceID)|\(contentKey)"
  }

  /// Content key for a ledger write: the decision identities being committed, sorted.
  public static func ledgerContentKey(decisionIDs: [String]) -> String {
    decisionIDs.sorted().joined(separator: ",")
  }
}

public struct CommitReceipt: Sendable, Equatable {
  public let requestID: UUID
  public let fingerprint: String
  public let planRevisionAfter: Int64
  public let decisionIDs: [String]

  public init(
    requestID: UUID, fingerprint: String, planRevisionAfter: Int64, decisionIDs: [String]
  ) {
    self.requestID = requestID
    self.fingerprint = fingerprint
    self.planRevisionAfter = planRevisionAfter
    self.decisionIDs = decisionIDs
  }
}

public enum IntegrationError: Error, Equatable {
  case staleSnapshot
  case expiredProposal
  case invalidApproval
  case idempotencyConflict
  case unsupportedAction
  case invalidInput
}
