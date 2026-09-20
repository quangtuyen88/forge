import Foundation

// MARK: - Plan identity
//
// The store has no revision counters, and inventing one from a row count would be a number
// that looks like a version without behaving like one: counts fall when rows are deleted,
// and `max(updatedAt)` moves with the clock. What a commit actually needs is *equality* —
// "is the plan I am about to change still the plan the preview described?" — so identity
// here is a content digest, and ordering is deliberately not claimed.

/// A stable content digest over the values that define a plan, a log cursor or the local
/// context. Equality only: two digests are the same state or different state, never newer
/// or older.
public enum PlanRevision {
  /// FNV-1a 64-bit over the canonical joined components. Integers and identifiers only —
  /// a `Double` in the input makes the digest drift across platforms and formatters.
  public static func digest(_ components: [String]) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in components.joined(separator: "\u{1f}").utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01B3
    }
    return String(hash, radix: 16)
  }

  /// The empty state has an identity too, so "no plan yet" cannot silently match "a plan I
  /// have not read".
  public static let none = PlanRevision.digest([])
}

// MARK: - Read envelope
//
// Every local read the coach is given carries what it is, where it came from and how fresh
// it is. A bare value would let an answer from a plan two revisions old read as current.

/// Why a read produced no value. Missing evidence is not evidence of no progress, so each
/// reason stays distinct instead of collapsing into an empty result.
public enum CoachReadStatus: String, Sendable, Codable, Equatable {
  case ok
  /// The resource does not exist.
  case notFound = "not_found"
  /// It exists, but policy withholds it from this surface — Health-derived reasoning, for one.
  case notShared = "not_shared"
  /// It exists and is readable, but describes a plan revision that is no longer current.
  case stale
  /// The request names something ambiguous: two exercises answer to "bench".
  case needsClarification = "needs_clarification"
  /// A local read failed for a reason the lifter cannot act on.
  case unavailable
}

/// One local read, stamped. `source` is always a projection name rather than a model claim,
/// so an answer can say where a fact came from.
public struct CoachEnvelope<Value: Sendable & Equatable>: Sendable, Equatable {
  public static var currentSchemaVersion: Int { 1 }

  public let schemaVersion: Int
  public let status: CoachReadStatus
  public let source: String
  public let asOf: Date
  public let planRevision: String
  public let data: Value?

  public init(
    schemaVersion: Int = CoachEnvelope.currentSchemaVersion,
    status: CoachReadStatus,
    source: String = "local_engine_projection",
    asOf: Date,
    planRevision: String,
    data: Value?
  ) {
    self.schemaVersion = schemaVersion
    self.status = status
    self.source = source
    self.asOf = asOf
    self.planRevision = planRevision
    self.data = data
  }

  public static func ok(_ value: Value, asOf: Date, planRevision: String) -> CoachEnvelope {
    CoachEnvelope(status: .ok, asOf: asOf, planRevision: planRevision, data: value)
  }

  public static func failure(_ status: CoachReadStatus, asOf: Date, planRevision: String) -> CoachEnvelope {
    CoachEnvelope(status: status, asOf: asOf, planRevision: planRevision, data: nil)
  }

  /// A read is usable only when it succeeded *and* still describes the current plan.
  public func isFresh(against current: String) -> Bool {
    status == .ok && planRevision == current
  }
}

// MARK: - Read payloads
//
// Deliberately small, typed and free of evidence prose: these cross into a model turn, and
// a free-text reason is exactly where a Health-derived fact leaks.

public struct CurrentWorkoutProjection: Sendable, Equatable {
  public let sessionID: String
  public let dayName: String
  public let prescriptions: [SetPrescription]

  public init(sessionID: String, dayName: String, prescriptions: [SetPrescription]) {
    self.sessionID = sessionID
    self.dayName = dayName
    self.prescriptions = prescriptions
  }
}

public struct DecisionProjection: Sendable, Equatable {
  public let decisionID: String
  public let reasonCode: String
  public let scope: DecisionScope
  public let before: SetPrescription?
  public let after: SetPrescription?

  public init(decisionID: String, reasonCode: String, scope: DecisionScope, before: SetPrescription?, after: SetPrescription?) {
    self.decisionID = decisionID
    self.reasonCode = reasonCode
    self.scope = scope
    self.before = before
    self.after = after
  }
}

public struct RecentSetProjection: Sendable, Equatable {
  public let exerciseID: String
  public let performedAt: Date
  public let load: LoadValue?
  public let reps: Int
  public let rpeTenths: Int?

  public init(exerciseID: String, performedAt: Date, load: LoadValue?, reps: Int, rpeTenths: Int?) {
    self.exerciseID = exerciseID
    self.performedAt = performedAt
    self.load = load
    self.reps = reps
    self.rpeTenths = rpeTenths
  }
}

public struct ConstraintsProjection: Sendable, Equatable {
  public let equipmentIDs: [String]
  public let excludedExerciseIDs: [String]
  public let minutesPerSession: Int?
  public let daysPerWeek: Int?

  public init(equipmentIDs: [String], excludedExerciseIDs: [String], minutesPerSession: Int?, daysPerWeek: Int?) {
    self.equipmentIDs = equipmentIDs
    self.excludedExerciseIDs = excludedExerciseIDs
    self.minutesPerSession = minutesPerSession
    self.daysPerWeek = daysPerWeek
  }
}

/// The read side of the coach contract. Four reads, each policy-filtered, each stamped.
/// Nothing here writes, and nothing here returns a Health-derived value.
public enum CoachReadContracts {
  public static let toolNames = [
    "get_current_workout", "get_program_decision", "get_recent_sessions", "get_program_constraints",
  ]

  /// A decision may be read only when the export policy already allows it to leave the
  /// device. The same lineage rule that filters the context packet filters a tool read, so
  /// a private recovery branch cannot be laundered through a per-decision lookup.
  public static func decision(
    _ record: DecisionRecord?,
    scope: DecisionScope = .futureSession,
    asOf: Date,
    planRevision: String
  ) -> CoachEnvelope<DecisionProjection> {
    guard let record else {
      return .failure(.notFound, asOf: asOf, planRevision: planRevision)
    }
    guard DecisionProvenance.isCloudExportable(record) else {
      return .failure(.notShared, asOf: asOf, planRevision: planRevision)
    }
    let projection = DecisionProjection(
      decisionID: record.id,
      reasonCode: record.reasonCodes.first ?? "",
      scope: scope,
      before: nil,
      after: nil)
    return .ok(projection, asOf: asOf, planRevision: planRevision)
  }

  /// "Bench" is two exercises in most catalogues. An ambiguous name is answered with a
  /// clarification, never with a silently chosen lift.
  public static func resolveExercise(
    _ name: String,
    candidates: [(id: String, name: String)],
    asOf: Date,
    planRevision: String
  ) -> CoachEnvelope<String> {
    let needle = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else {
      return .failure(.needsClarification, asOf: asOf, planRevision: planRevision)
    }
    let exact = candidates.filter { $0.name.lowercased() == needle }
    if exact.count == 1 { return .ok(exact[0].id, asOf: asOf, planRevision: planRevision) }
    let partial = candidates.filter { $0.name.lowercased().contains(needle) }
    if partial.count == 1 { return .ok(partial[0].id, asOf: asOf, planRevision: planRevision) }
    if partial.isEmpty { return .failure(.notFound, asOf: asOf, planRevision: planRevision) }
    return .failure(.needsClarification, asOf: asOf, planRevision: planRevision)
  }
}
