import Foundation

// MARK: - Stable identifiers
//
// Both are thin `RawRepresentable` wrappers so a recommendation id can never be
// passed where a program-version id is expected, and so every dictionary the
// ledger keeps has a total, deterministic ordering.

public struct RecommendationID: RawRepresentable, Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public var description: String { rawValue }
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct ProgramVersionID: RawRepresentable, Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public var description: String { rawValue }
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Evidence coverage

/// Which decision signals were required to justify a recommendation, and which
/// were actually observed. `fraction` is what the eligibility policy gates on,
/// so "we only saw half the evidence" is representable rather than implied.
public struct EvidenceCoverage: Codable, Sendable, Equatable {
  public let requiredSignals: [String]
  public let presentSignals: [String]

  public init(requiredSignals: [String], presentSignals: [String]) {
    self.requiredSignals = Array(Set(requiredSignals)).sorted()
    self.presentSignals = Array(Set(presentSignals)).sorted()
  }

  public init(required: [DecisionSignal], present: [DecisionSignal]) {
    self.init(requiredSignals: required.map(\.code), presentSignals: present.map(\.code))
  }

  /// Weighted coverage in 0…1. An empty requirement list is fully covered by definition.
  public var fraction: Double {
    guard !requiredSignals.isEmpty else { return 1 }
    let present = Set(presentSignals)
    let matched = requiredSignals.filter { present.contains($0) }.count
    return Double(matched) / Double(requiredSignals.count)
  }

  public var missingSignals: [String] {
    let present = Set(presentSignals)
    return requiredSignals.filter { !present.contains($0) }
  }

  /// True only when every required signal was observed.
  public var isComplete: Bool { missingSignals.isEmpty }
}

// MARK: - User authorization

public enum UserAuthorization: String, Codable, Sendable, CaseIterable {
  case notRequested, granted, denied, revoked

  public var allowsApplication: Bool { self == .granted }
}

// MARK: - Eligibility policy

public enum RecommendationIneligibility: String, Codable, Sendable, CaseIterable {
  case insufficientEvidence
  case authorizationMissing
  case authorizationDenied
  case authorizationRevoked
}

public struct RecommendationEligibility: Codable, Sendable, Equatable {
  public let isEligible: Bool
  public let requiresConfirmation: Bool
  public let coverage: Double
  public let reasons: [RecommendationIneligibility]

  public init(isEligible: Bool, requiresConfirmation: Bool, coverage: Double, reasons: [RecommendationIneligibility]) {
    self.isEligible = isEligible
    self.requiresConfirmation = requiresConfirmation
    self.coverage = coverage
    self.reasons = reasons
  }
}

public struct RecommendationEligibilityPolicy: Codable, Sendable, Equatable {
  /// Minimum `EvidenceCoverage.fraction` before the recommendation may be applied.
  public let minimumCoverage: Double
  /// When true the user must have explicitly granted authorization.
  public let requiresExplicitAuthorization: Bool
  /// When true the app must show a confirmation card before applying.
  public let requiresConfirmation: Bool
  /// Optional hard age limit; `nil` means expiry is driven by the snapshot itself.
  public let maxAge: TimeInterval?

  public init(
    minimumCoverage: Double = 1.0,
    requiresExplicitAuthorization: Bool = true,
    requiresConfirmation: Bool = true,
    maxAge: TimeInterval? = nil
  ) {
    self.minimumCoverage = minimumCoverage
    self.requiresExplicitAuthorization = requiresExplicitAuthorization
    self.requiresConfirmation = requiresConfirmation
    self.maxAge = maxAge
  }

  /// Changes the program and must be acknowledged: full evidence, a granted
  /// authorization, and a confirmation card.
  public static let consequential = RecommendationEligibilityPolicy()

  /// Read-only explanation the user asked for; nothing is applied.
  public static let informational = RecommendationEligibilityPolicy(
    minimumCoverage: 0, requiresExplicitAuthorization: false, requiresConfirmation: false)

  public func evaluate(coverage: EvidenceCoverage, authorization: UserAuthorization) -> RecommendationEligibility {
    var reasons: [RecommendationIneligibility] = []
    if coverage.fraction < minimumCoverage { reasons.append(.insufficientEvidence) }
    if requiresExplicitAuthorization {
      switch authorization {
      case .granted: break
      case .notRequested: reasons.append(.authorizationMissing)
      case .denied: reasons.append(.authorizationDenied)
      case .revoked: reasons.append(.authorizationRevoked)
      }
    } else {
      switch authorization {
      case .denied: reasons.append(.authorizationDenied)
      case .revoked: reasons.append(.authorizationRevoked)
      case .granted, .notRequested: break
      }
    }
    return RecommendationEligibility(
      isEligible: reasons.isEmpty,
      requiresConfirmation: requiresConfirmation,
      coverage: coverage.fraction,
      reasons: reasons)
  }
}

// MARK: - Snapshot validation

public enum RecommendationValidationIssue: String, Codable, Sendable, CaseIterable {
  case emptyRecommendationID
  case missingEvidence
  case missingSummary
  case expiryBeforeCreation
  case nonPositiveTargetLoad
  case unsupportedActionType
}

public enum RecommendationValidationPolicy {
  /// The action types `DecisionRecord` is allowed to carry. Anything else means
  /// the snapshot was built by something that does not understand the ledger.
  public static let knownActionTypes: Set<String> = ["load_change", "volume_change", "swap", "session", "plateau"]

  public static func validate(_ snapshot: RecommendationSnapshot) -> [RecommendationValidationIssue] {
    var issues: [RecommendationValidationIssue] = []
    if snapshot.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.emptyRecommendationID)
    }
    if snapshot.record.evidence.isEmpty { issues.append(.missingEvidence) }
    if snapshot.record.humanSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append(.missingSummary)
    }
    if let expiresAt = snapshot.expiresAt, expiresAt < snapshot.createdAt {
      issues.append(.expiryBeforeCreation)
    }
    if !knownActionTypes.contains(snapshot.record.type) {
      issues.append(.unsupportedActionType)
    } else if snapshot.record.type == "load_change",
              let toValue = snapshot.record.toValue, toValue <= 0 {
      issues.append(.nonPositiveTargetLoad)
    }
    return issues
  }
}

// MARK: - Immutable snapshot

/// A frozen description of one recommendation. It is never mutated after being
/// recorded; outcomes live in the ledger, not here.
public struct RecommendationSnapshot: Codable, Sendable, Equatable, Identifiable {
  public let id: RecommendationID
  public let programVersion: ProgramVersionID
  public let createdAt: Date
  public let expiresAt: Date?
  public let record: DecisionRecord
  public let coverage: EvidenceCoverage
  public let policy: RecommendationEligibilityPolicy
  public let authorization: UserAuthorization

  public init(
    id: RecommendationID,
    programVersion: ProgramVersionID,
    createdAt: Date,
    expiresAt: Date? = nil,
    record: DecisionRecord,
    coverage: EvidenceCoverage,
    policy: RecommendationEligibilityPolicy = .consequential,
    authorization: UserAuthorization = .notRequested
  ) {
    self.id = id
    self.programVersion = programVersion
    self.createdAt = createdAt
    self.expiresAt = expiresAt
    self.record = record
    self.coverage = coverage
    self.policy = policy
    self.authorization = authorization
  }

  /// What the recommendation is *about*, independent of which suggestion it is.
  public var subjectKey: String {
    if let exerciseID = record.exerciseID { return "exercise:\(exerciseID)" }
    if let muscle = record.muscle { return "muscle:\(muscle)" }
    return "type:\(record.type)"
  }

  public func eligibility() -> RecommendationEligibility {
    policy.evaluate(coverage: coverage, authorization: authorization)
  }

  public func isExpired(at now: Date) -> Bool {
    guard let expiresAt else { return false }
    return now >= expiresAt
  }

  /// Stale when the program moved on, or when the snapshot aged out.
  public func isStale(against currentProgramVersion: ProgramVersionID, at now: Date) -> Bool {
    programVersion != currentProgramVersion || isExpired(at: now)
  }
}

// MARK: - Exposure

/// A record that the recommendation was actually shown. Kept so "we never told
/// them" and "they ignored it" stay distinguishable.
public struct RecommendationExposure: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let recommendationID: RecommendationID
  public let programVersion: ProgramVersionID
  public let exposedAt: Date
  public let surface: String
  public let wasConsequential: Bool

  public init(
    recommendationID: RecommendationID,
    programVersion: ProgramVersionID,
    exposedAt: Date,
    surface: String,
    wasConsequential: Bool
  ) {
    self.id = "\(recommendationID.rawValue)#\(surface)"
    self.recommendationID = recommendationID
    self.programVersion = programVersion
    self.exposedAt = exposedAt
    self.surface = surface
    self.wasConsequential = wasConsequential
  }
}

// MARK: - Outcome

public enum RecommendationLedgerState: String, Codable, Sendable, CaseIterable {
  case proposed, applied, stale, conflict, failed
}

public struct RecommendationOutcome: Codable, Sendable, Equatable, Identifiable {
  public let id: RecommendationID
  public let programVersion: ProgramVersionID
  public let subjectKey: String
  public private(set) var state: RecommendationLedgerState
  public private(set) var appliedProgramVersion: ProgramVersionID?
  public private(set) var appliedAt: Date?
  public private(set) var resolvedAt: Date?
  public private(set) var reason: String?
  public private(set) var conflictingRecommendationID: RecommendationID?
  public private(set) var appliedCount: Int

  public init(id: RecommendationID, programVersion: ProgramVersionID, subjectKey: String) {
    self.id = id
    self.programVersion = programVersion
    self.subjectKey = subjectKey
    self.state = .proposed
    self.appliedProgramVersion = nil
    self.appliedAt = nil
    self.resolvedAt = nil
    self.reason = nil
    self.conflictingRecommendationID = nil
    self.appliedCount = 0
  }

  public var isApplied: Bool { state == .applied }
}

extension RecommendationOutcome {
  mutating func resolve(
    _ newState: RecommendationLedgerState,
    at date: Date,
    reason: String? = nil,
    conflicting: RecommendationID? = nil
  ) {
    state = newState
    resolvedAt = date
    self.reason = reason
    conflictingRecommendationID = conflicting
  }

  mutating func markApplied(version: ProgramVersionID, at date: Date) {
    state = .applied
    appliedProgramVersion = version
    appliedAt = date
    resolvedAt = date
    reason = nil
    conflictingRecommendationID = nil
    appliedCount = 1
  }
}

public enum RecommendationApplyOutcome: Sendable, Equatable {
  case applied
  case alreadyApplied
  case stale
  case conflict(RecommendationID)
  case ineligible([RecommendationIneligibility])
  case failed([RecommendationValidationIssue])
  case unknownRecommendation
}

// MARK: - Ledger

/// Holds immutable snapshots plus their mutable outcomes. Everything is gated
/// on the caller's injected `now` and on an explicit `currentProgramVersion`, so
/// the same inputs always produce the same idempotency/staleness decisions.
public struct RecommendationLedger: Codable, Sendable, Equatable {
  public private(set) var currentProgramVersion: ProgramVersionID
  public private(set) var snapshots: [RecommendationID: RecommendationSnapshot]
  public private(set) var outcomes: [RecommendationID: RecommendationOutcome]
  public private(set) var exposures: [RecommendationExposure]

  public init(currentProgramVersion: ProgramVersionID) {
    self.currentProgramVersion = currentProgramVersion
    self.snapshots = [:]
    self.outcomes = [:]
    self.exposures = []
  }

  /// Called by the app when a new program revision is generated. Makes every
  /// snapshot stamped with an older version stale without touching them.
  public mutating func advanceProgramVersion(to version: ProgramVersionID) {
    currentProgramVersion = version
  }

  /// Records a snapshot once. Re-recording the same id is a no-op so a stored
  /// snapshot can never be rewritten after the fact.
  @discardableResult
  public mutating func record(_ snapshot: RecommendationSnapshot) -> Bool {
    guard snapshots[snapshot.id] == nil else { return false }
    snapshots[snapshot.id] = snapshot
    outcomes[snapshot.id] = RecommendationOutcome(
      id: snapshot.id, programVersion: snapshot.programVersion, subjectKey: snapshot.subjectKey)
    return true
  }

  @discardableResult
  public mutating func expose(_ exposure: RecommendationExposure) -> Bool {
    guard snapshots[exposure.recommendationID] != nil else { return false }
    guard !exposures.contains(where: { $0.id == exposure.id }) else { return false }
    exposures.append(exposure)
    return true
  }

  public func snapshot(for id: RecommendationID) -> RecommendationSnapshot? { snapshots[id] }
  public func outcome(for id: RecommendationID) -> RecommendationOutcome? { outcomes[id] }

  public func exposures(for id: RecommendationID) -> [RecommendationExposure] {
    exposures.filter { $0.recommendationID == id }.sorted { $0.exposedAt < $1.exposedAt }
  }

  public func eligibility(for id: RecommendationID) -> RecommendationEligibility? {
    snapshots[id]?.eligibility()
  }

  public var orderedIDs: [RecommendationID] { snapshots.keys.sorted() }

  /// The one entry point that can move a recommendation to an outcome. The order
  /// of checks is the contract: idempotency, then validation, then staleness,
  /// then eligibility, then conflict, then — finally — apply.
  public mutating func apply(
    _ id: RecommendationID,
    authorization: UserAuthorization? = nil,
    at now: Date
  ) -> RecommendationApplyOutcome {
    guard let snapshot = snapshots[id], var outcome = outcomes[id] else {
      return .unknownRecommendation
    }

    // 1. Idempotency: already applied to this exact program version → no-op.
    if outcome.state == .applied, outcome.appliedProgramVersion == snapshot.programVersion {
      return .alreadyApplied
    }

    // 2. The snapshot must describe something we understand.
    let issues = RecommendationValidationPolicy.validate(snapshot)
    if !issues.isEmpty {
      outcome.resolve(.failed, at: now, reason: issues.map(\.rawValue).joined(separator: ","))
      outcomes[id] = outcome
      return .failed(issues)
    }

    // 3. Staleness: the program moved on, or the snapshot aged out.
    if snapshot.isStale(against: currentProgramVersion, at: now) {
      outcome.resolve(.stale, at: now, reason: snapshot.isExpired(at: now) ? "expired" : "version_drift")
      outcomes[id] = outcome
      return .stale
    }

    // 4. Eligibility: evidence coverage plus explicit authorization.
    let effectiveAuthorization = authorization ?? snapshot.authorization
    let eligibility = snapshot.policy.evaluate(coverage: snapshot.coverage, authorization: effectiveAuthorization)
    if !eligibility.isEligible {
      outcome.resolve(.failed, at: now, reason: eligibility.reasons.map(\.rawValue).joined(separator: ","))
      outcomes[id] = outcome
      return .ineligible(eligibility.reasons)
    }

    // 5. Conflict: a different recommendation already applied to this subject.
    if let conflict = conflictingAppliedID(for: snapshot, excluding: id) {
      outcome.resolve(.conflict, at: now, reason: "subject_conflict", conflicting: conflict)
      outcomes[id] = outcome
      return .conflict(conflict)
    }

    // 6. Apply.
    outcome.markApplied(version: snapshot.programVersion, at: now)
    outcomes[id] = outcome
    return .applied
  }

  /// Marks an outcome failed for a reason the policy could not express.
  public mutating func markFailed(_ id: RecommendationID, reason: String, at now: Date) {
    guard var outcome = outcomes[id] else { return }
    outcome.resolve(.failed, at: now, reason: reason)
    outcomes[id] = outcome
  }

  private func conflictingAppliedID(
    for snapshot: RecommendationSnapshot,
    excluding id: RecommendationID
  ) -> RecommendationID? {
    outcomes.values
      .filter {
        $0.state == .applied
          && $0.id != id
          && $0.subjectKey == snapshot.subjectKey
          && $0.appliedProgramVersion == snapshot.programVersion
      }
      .map(\.id)
      .sorted()
      .first
  }
}

// MARK: - Voice conversation coordination
//
// The voice surface is a turn-based reducer, not an async actor: the caller feeds
// one event per turn and reads back a state plus the single effect it must run.
// Consequential and ambiguous commands can never reach `.apply` without either an
// explicit confirmation or a clarification.

public enum VoiceTurnState: String, Codable, Sendable, CaseIterable {
  case idle, listening, clarifying, proposed, confirming, applied, cancelled, failed
}

public enum VoiceTurnEvent: Sendable, Equatable {
  case beginListening
  /// A finished utterance.
  case heard(VoiceCommand)
  /// A partial utterance that still looks unfinished ("eight reps at").
  case heardIncomplete(VoiceCommand)
  /// A parsed but not yet committed command.
  case propose(VoiceCommand)
  /// The user answered a clarification question.
  case clarify(VoiceCommand)
  /// The app has put the confirmation card on screen.
  case requestConfirmation
  case confirm
  case cancel
  /// The effect finished successfully.
  case applied
  case failed(String)
  case reset
}

public enum VoiceEffect: Sendable, Equatable {
  case none
  case apply(VoiceCommand)
  case requestConfirmation(VoiceCommand)
  case requestClarification(VoiceCommand, String)
  /// The same command was already applied this session; nothing was run.
  case ignoreDuplicate(VoiceCommand)
  case reject(String)
}

extension VoiceCommand {
  /// Commands that cannot be executed until the user says more.
  public var isAmbiguous: Bool {
    switch self {
    case .unrecognised:
      return true
    case .changeReps(let to, let delta):
      return to == nil && delta == nil
    case .swapExercise:
      // A swap must show options before it can change anything.
      return true
    default:
      return false
    }
  }

  /// Commands that change the prescription or the log in a way the user must see first.
  public var isConsequential: Bool { consequence == .confirm }
}

public struct VoiceConversationCoordinator: Sendable, Equatable {
  public private(set) var state: VoiceTurnState
  public private(set) var pendingCommand: VoiceCommand?
  public private(set) var clarificationPrompt: String?
  public private(set) var failureReason: String?
  /// Keys of everything already applied. A second identical apply is refused.
  public private(set) var appliedCommandKeys: [String]
  public private(set) var appliedCount: Int

  public init(state: VoiceTurnState = .idle) {
    self.state = state
    self.pendingCommand = nil
    self.clarificationPrompt = nil
    self.failureReason = nil
    self.appliedCommandKeys = []
    self.appliedCount = 0
  }

  public var isTerminal: Bool {
    state == .applied || state == .cancelled || state == .failed
  }

  public var isAwaitingConfirmation: Bool {
    state == .proposed || state == .confirming
  }

  /// Whether the pending command still needs an explicit yes.
  public var requiresConfirmation: Bool {
    isAwaitingConfirmation && (pendingCommand?.isConsequential ?? false)
  }

  @discardableResult
  public mutating func reduce(_ event: VoiceTurnEvent) -> VoiceEffect {
    switch event {
    case .reset:
      reset()
      return .none

    case .beginListening:
      reset()
      state = .listening
      return .none

    case .failed(let reason):
      failureReason = reason
      state = .failed
      return .none

    case .cancel:
      guard !isTerminal else { return .none }
      pendingCommand = nil
      clarificationPrompt = nil
      state = .cancelled
      return .none

    case .applied:
      state = .applied
      return .none

    case .heardIncomplete(let command):
      guard acceptsNewInput else { return .none }
      return clarify(command)

    case .heard(let command), .clarify(let command), .propose(let command):
      guard acceptsNewInput else { return .none }
      return route(command)

    case .requestConfirmation:
      guard let pending = pendingCommand, isAwaitingConfirmation else {
        return .reject("nothing_awaiting_confirmation")
      }
      state = .confirming
      return .requestConfirmation(pending)

    case .confirm:
      // Re-confirming something already applied must never apply it a second time.
      if state == .applied, let pending = pendingCommand {
        return .ignoreDuplicate(pending)
      }
      guard isAwaitingConfirmation, let pending = pendingCommand else {
        return .reject("nothing_to_confirm")
      }
      return applyIfFresh(pending)
    }
  }

  /// `.applied` still accepts a follow-up utterance; only a cancelled or failed
  /// turn is closed until the caller resets.
  private var acceptsNewInput: Bool {
    switch state {
    case .idle, .listening, .clarifying, .proposed, .confirming, .applied: return true
    case .cancelled, .failed: return false
    }
  }

  private mutating func reset() {
    state = .idle
    pendingCommand = nil
    clarificationPrompt = nil
    failureReason = nil
  }

  private mutating func route(_ command: VoiceCommand) -> VoiceEffect {
    pendingCommand = command
    clarificationPrompt = nil
    if command.isAmbiguous { return clarify(command) }
    if command.isConsequential {
      state = .proposed
      return .requestConfirmation(command)
    }
    return applyIfFresh(command)
  }

  private mutating func clarify(_ command: VoiceCommand) -> VoiceEffect {
    pendingCommand = command
    let prompt = VoiceConversationCoordinator.prompt(for: command)
    clarificationPrompt = prompt
    state = .clarifying
    return .requestClarification(command, prompt)
  }

  private mutating func applyIfFresh(_ command: VoiceCommand) -> VoiceEffect {
    let key = command.fingerprint
    guard !appliedCommandKeys.contains(key) else {
      state = .applied
      return .ignoreDuplicate(command)
    }
    appliedCommandKeys.append(key)
    appliedCount += 1
    pendingCommand = command
    clarificationPrompt = nil
    state = .applied
    return .apply(command)
  }

  public static func prompt(for command: VoiceCommand) -> String {
    switch command {
    case .unrecognised:
      return String(localized: "Didn't catch that — say the exercise, weight and reps.", bundle: ForgeCoreResources.bundle)
    case .changeReps(let to, let delta) where to == nil && delta == nil:
      return String(localized: "How many reps?", bundle: ForgeCoreResources.bundle)
    case .swapExercise:
      return String(localized: "Which exercise should replace it?", bundle: ForgeCoreResources.bundle)
    default:
      return String(localized: "Can you be more specific?", bundle: ForgeCoreResources.bundle)
    }
  }
}

// MARK: - Imported / shared program contracts
//
// These types deliberately carry *no* user history and *no* coach memory. The
// only user-shaped thing a program file may contain is the profile snapshot the
// author chose to publish, and even that is optional.

public struct ProgramExerciseEntry: Codable, Sendable, Equatable, Hashable {
  public let exerciseID: String
  public let exerciseName: String?
  public let sets: Int
  public let repRangeLower: Int
  public let repRangeUpper: Int
  public let targetRPE: Double?

  public init(
    exerciseID: String,
    exerciseName: String? = nil,
    sets: Int,
    repRangeLower: Int,
    repRangeUpper: Int,
    targetRPE: Double? = nil
  ) {
    self.exerciseID = exerciseID
    self.exerciseName = exerciseName
    self.sets = sets
    self.repRangeLower = repRangeLower
    self.repRangeUpper = repRangeUpper
    self.targetRPE = targetRPE
  }

  public var repRange: ClosedRange<Int>? {
    repRangeLower <= repRangeUpper ? repRangeLower...repRangeUpper : nil
  }
}

public struct ProgramDay: Codable, Sendable, Equatable, Identifiable {
  public let name: String
  public let exercises: [ProgramExerciseEntry]

  public init(name: String, exercises: [ProgramExerciseEntry]) {
    self.name = name
    self.exercises = exercises
  }

  public var id: String { name }
  public var exerciseIDs: [String] { exercises.map(\.exerciseID) }
  public var totalSets: Int { exercises.reduce(0) { $0 + max(0, $1.sets) } }
}

public struct ProgramSource: Codable, Sendable, Equatable {
  public enum Kind: String, Codable, Sendable, CaseIterable {
    case coach, file, link, share
  }

  public let kind: Kind
  public let name: String?
  /// Set for `.link`/`.share`: the token that authorised the import.
  public let tokenID: String?

  public init(kind: Kind, name: String? = nil, tokenID: String? = nil) {
    self.kind = kind
    self.name = name
    self.tokenID = tokenID
  }
}

public struct ProgramVersion: Codable, Sendable, Equatable, Identifiable {
  public let number: Int
  public let createdAt: Date
  public let note: String?
  public let days: [ProgramDay]

  public init(number: Int, createdAt: Date, note: String? = nil, days: [ProgramDay]) {
    self.number = number
    self.createdAt = createdAt
    self.note = note
    self.days = days
  }

  public var id: Int { number }
  public var exerciseCount: Int { days.reduce(0) { $0 + $1.exercises.count } }
  public var allExerciseIDs: [String] { Array(Set(days.flatMap(\.exerciseIDs))).sorted() }
}

public struct ImportedProgram: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let formatVersion: Int
  public let title: String
  public let source: ProgramSource
  public let importedAt: Date
  public let versions: [ProgramVersion]
  /// Which version is live. Explicit activation sets this; importing does not.
  public let activeVersionNumber: Int?

  public init(
    id: String,
    formatVersion: Int,
    title: String,
    source: ProgramSource,
    importedAt: Date,
    versions: [ProgramVersion],
    activeVersionNumber: Int? = nil
  ) {
    self.id = id
    self.formatVersion = formatVersion
    self.title = title
    self.source = source
    self.importedAt = importedAt
    self.versions = versions
    self.activeVersionNumber = activeVersionNumber
  }

  public var activeVersion: ProgramVersion? {
    if let activeVersionNumber, let match = versions.first(where: { $0.number == activeVersionNumber }) {
      return match
    }
    return versions.last
  }

  /// Returns a copy with an explicit active version, or nil if that version is absent.
  public func activating(version number: Int, at date: Date) -> ImportedProgram? {
    guard versions.contains(where: { $0.number == number }) else { return nil }
    return ImportedProgram(
      id: id, formatVersion: formatVersion, title: title, source: source,
      importedAt: date, versions: versions, activeVersionNumber: number)
  }
}

// MARK: - Structured warnings

public enum ImportWarningCode: String, Codable, Sendable, CaseIterable {
  case unsupportedFormatVersion
  case emptyProgram
  case emptyDay
  case unknownExercise
  case invalidSetCount
  case invalidRepRange
  case outOfRangeRPE
  case duplicateDay
  case duplicateVersion
  case noActiveVersion
  case missingTitle
  case unrecognizedContent
}

public struct ImportWarningContext: Codable, Sendable, Equatable, Hashable {
  public let day: String?
  public let exerciseID: String?
  public let index: Int?

  public init(day: String? = nil, exerciseID: String? = nil, index: Int? = nil) {
    self.day = day
    self.exerciseID = exerciseID
    self.index = index
  }
}

public struct ImportWarning: Codable, Sendable, Equatable, Hashable, Identifiable {
  public enum Severity: String, Codable, Sendable, CaseIterable, Comparable {
    case warning, error

    private var rank: Int { self == .error ? 1 : 0 }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
  }

  public let code: ImportWarningCode
  public let severity: Severity
  public let message: String
  public let context: ImportWarningContext?

  public var id: String {
    [code.rawValue, context?.day ?? "", context?.exerciseID ?? "", context?.index.map(String.init) ?? ""]
      .joined(separator: "|")
  }

  public init(code: ImportWarningCode, severity: Severity, message: String, context: ImportWarningContext? = nil) {
    self.code = code
    self.severity = severity
    self.message = message
    self.context = context
  }
}

// MARK: - Validation

public enum ProgramImportValidator {
  public static let supportedFormatVersion = 1
  public static let allowedSetRange = 1...20
  public static let allowedRPERange = 1.0...10.0

  public static func validate(
    _ program: ImportedProgram,
    knownExercise: (String) -> Bool = { ExerciseDB.find($0) != nil },
    supportedFormatVersion: Int = ProgramImportValidator.supportedFormatVersion
  ) -> [ImportWarning] {
    var warnings: [ImportWarning] = []

    func warn(_ code: ImportWarningCode, _ severity: ImportWarning.Severity, _ message: String,
              day: String? = nil, exerciseID: String? = nil, index: Int? = nil) {
      warnings.append(ImportWarning(
        code: code, severity: severity, message: message,
        context: ImportWarningContext(day: day, exerciseID: exerciseID, index: index)))
    }

    if program.formatVersion != supportedFormatVersion {
      warn(.unsupportedFormatVersion, .error,
           "Unsupported format version \(program.formatVersion).")
    }
    if program.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      warn(.missingTitle, .warning, "This program has no title.")
    }
    if program.versions.isEmpty {
      warn(.emptyProgram, .error, "This program contains no versions.")
    }

    var seenVersions = Set<Int>()
    for version in program.versions {
      if !seenVersions.insert(version.number).inserted {
        warn(.duplicateVersion, .error, "Duplicate version \(version.number).", index: version.number)
      }
      if version.days.isEmpty {
        warn(.emptyProgram, .error, "Version \(version.number) has no training days.", index: version.number)
      }
      var seenDays = Set<String>()
      for day in version.days {
        if !seenDays.insert(day.name).inserted {
          warn(.duplicateDay, .warning, "Duplicate day “\(day.name)” in version \(version.number).",
               day: day.name, index: version.number)
        }
        if day.exercises.isEmpty {
          warn(.emptyDay, .warning, "Day “\(day.name)” has no exercises.", day: day.name)
        }
        for entry in day.exercises {
          if !knownExercise(entry.exerciseID) {
            warn(.unknownExercise, .warning, "Unknown exercise “\(entry.exerciseID)”.",
                 day: day.name, exerciseID: entry.exerciseID)
          }
          if !allowedSetRange.contains(entry.sets) {
            warn(.invalidSetCount, .error, "\(entry.sets) sets is outside \(allowedSetRange.lowerBound)–\(allowedSetRange.upperBound).",
                 day: day.name, exerciseID: entry.exerciseID)
          }
          if entry.repRangeLower < 1 || entry.repRangeLower > entry.repRangeUpper {
            warn(.invalidRepRange, .error, "Invalid rep range \(entry.repRangeLower)–\(entry.repRangeUpper).",
                 day: day.name, exerciseID: entry.exerciseID)
          }
          if let rpe = entry.targetRPE, !allowedRPERange.contains(rpe) {
            warn(.outOfRangeRPE, .warning, "RPE \(rpe) is outside \(allowedRPERange.lowerBound)–\(allowedRPERange.upperBound).",
                 day: day.name, exerciseID: entry.exerciseID)
          }
        }
      }
    }

    if let active = program.activeVersionNumber, !program.versions.contains(where: { $0.number == active }) {
      warn(.noActiveVersion, .warning, "Active version \(active) is not in this program.")
    }

    return warnings.sorted {
      ($0.code.rawValue, $0.context?.day ?? "", $0.context?.exerciseID ?? "", $0.context?.index ?? 0)
        < ($1.code.rawValue, $1.context?.day ?? "", $1.context?.exerciseID ?? "", $1.context?.index ?? 0)
    }
  }
}

// MARK: - Preview / diff

public struct ProgramSetChange: Codable, Sendable, Equatable, Hashable {
  public let day: String
  public let exerciseID: String
  public let fromSets: Int
  public let toSets: Int

  public init(day: String, exerciseID: String, fromSets: Int, toSets: Int) {
    self.day = day
    self.exerciseID = exerciseID
    self.fromSets = fromSets
    self.toSets = toSets
  }
}

public struct ProgramVersionDiff: Codable, Sendable, Equatable {
  public let fromVersion: Int?
  public let toVersion: Int?
  public let addedExerciseIDs: [String]
  public let removedExerciseIDs: [String]
  public let setCountChanges: [ProgramSetChange]
  public let changedDays: [String]

  public init(
    fromVersion: Int?,
    toVersion: Int?,
    addedExerciseIDs: [String],
    removedExerciseIDs: [String],
    setCountChanges: [ProgramSetChange],
    changedDays: [String]
  ) {
    self.fromVersion = fromVersion
    self.toVersion = toVersion
    self.addedExerciseIDs = addedExerciseIDs
    self.removedExerciseIDs = removedExerciseIDs
    self.setCountChanges = setCountChanges
    self.changedDays = changedDays
  }

  public var isEmpty: Bool {
    addedExerciseIDs.isEmpty && removedExerciseIDs.isEmpty
      && setCountChanges.isEmpty && changedDays.isEmpty
  }

  public static func between(_ from: ProgramVersion?, _ to: ProgramVersion?) -> ProgramVersionDiff {
    let fromByDay = ProgramVersionDiff.flatSetCounts(from)
    let toByDay = ProgramVersionDiff.flatSetCounts(to)

    let fromIDs = Set(fromByDay.values.flatMap { $0.keys })
    let toIDs = Set(toByDay.values.flatMap { $0.keys })
    let added = toIDs.subtracting(fromIDs).sorted()
    let removed = fromIDs.subtracting(toIDs).sorted()

    var changes: [ProgramSetChange] = []
    for day in toByDay.keys.sorted() {
      for exerciseID in (toByDay[day] ?? [:]).keys.sorted() {
        guard let newSets = toByDay[day]?[exerciseID] else { continue }
        if let oldSets = fromByDay[day]?[exerciseID], oldSets != newSets {
          changes.append(ProgramSetChange(day: day, exerciseID: exerciseID, fromSets: oldSets, toSets: newSets))
        }
      }
    }

    // Only days whose exercise breakdown actually differs, so identical versions
    // report an empty diff.
    let allDays = Set(fromByDay.keys).union(toByDay.keys)
    let changedDays = allDays
      .filter { (fromByDay[$0] ?? [:]) != (toByDay[$0] ?? [:]) }
      .sorted()

    return ProgramVersionDiff(
      fromVersion: from?.number,
      toVersion: to?.number,
      addedExerciseIDs: added,
      removedExerciseIDs: removed,
      setCountChanges: changes,
      changedDays: changedDays)
  }

  private static func flatSetCounts(_ version: ProgramVersion?) -> [String: [String: Int]] {
    guard let version else { return [:] }
    var out: [String: [String: Int]] = [:]
    for day in version.days {
      var perExercise: [String: Int] = [:]
      for entry in day.exercises {
        perExercise[entry.exerciseID, default: 0] += entry.sets
      }
      out[day.name] = perExercise
    }
    return out
  }
}

public struct ProgramImportPreview: Codable, Sendable, Equatable {
  public let programID: String
  public let title: String
  public let formatVersion: Int
  public let versionCount: Int
  public let activeVersionNumber: Int?
  public let dayCount: Int
  public let exerciseCount: Int
  public let warnings: [ImportWarning]
  public let diff: ProgramVersionDiff

  public init(
    programID: String,
    title: String,
    formatVersion: Int,
    versionCount: Int,
    activeVersionNumber: Int?,
    dayCount: Int,
    exerciseCount: Int,
    warnings: [ImportWarning],
    diff: ProgramVersionDiff
  ) {
    self.programID = programID
    self.title = title
    self.formatVersion = formatVersion
    self.versionCount = versionCount
    self.activeVersionNumber = activeVersionNumber
    self.dayCount = dayCount
    self.exerciseCount = exerciseCount
    self.warnings = warnings
    self.diff = diff
  }

  public var hasBlockingErrors: Bool { warnings.contains { $0.severity == .error } }
  public var errorCount: Int { warnings.filter { $0.severity == .error }.count }
  public var warningCount: Int { warnings.filter { $0.severity == .warning }.count }
  /// A preview never activates anything; it only reports whether activation would be allowed.
  public var isActivatable: Bool { !hasBlockingErrors && versionCount > 0 }

  public static func make(
    imported: ImportedProgram,
    previous: ProgramVersion? = nil,
    knownExercise: (String) -> Bool = { ExerciseDB.find($0) != nil },
    supportedFormatVersion: Int = ProgramImportValidator.supportedFormatVersion
  ) -> ProgramImportPreview {
    let active = imported.activeVersion
    return ProgramImportPreview(
      programID: imported.id,
      title: imported.title,
      formatVersion: imported.formatVersion,
      versionCount: imported.versions.count,
      activeVersionNumber: imported.activeVersionNumber,
      dayCount: active?.days.count ?? 0,
      exerciseCount: active?.exerciseCount ?? 0,
      warnings: ProgramImportValidator.validate(
        imported, knownExercise: knownExercise, supportedFormatVersion: supportedFormatVersion),
      diff: ProgramVersionDiff.between(previous, active))
  }
}

// MARK: - Explicit activation

public enum ProgramActivationResult: Sendable, Equatable {
  /// The program with its active version stamped.
  case activated(ImportedProgram)
  /// Nothing changed: blocking validation errors.
  case rejected([ImportWarning])
  case versionNotFound(Int)
}

public enum ProgramActivationPolicy {
  /// Importing never activates. This is the only path that flips the active version,
  /// and it always names the version explicitly.
  public static func activate(
    _ program: ImportedProgram,
    version number: Int,
    at date: Date,
    knownExercise: (String) -> Bool = { ExerciseDB.find($0) != nil }
  ) -> ProgramActivationResult {
    guard program.versions.contains(where: { $0.number == number }) else {
      return .versionNotFound(number)
    }
    let blockers = ProgramImportValidator.validate(program, knownExercise: knownExercise)
      .filter { $0.severity == .error }
    guard blockers.isEmpty else { return .rejected(blockers) }
    guard let activated = program.activating(version: number, at: date) else {
      return .versionNotFound(number)
    }
    return .activated(activated)
  }
}

// MARK: - Redaction / sharing

/// A program stripped of anything that could identify the author or leak their
/// training. It has no history, no coach memory, no source token and no version
/// bookkeeping — only the plan.
public struct ShareableProgram: Codable, Sendable, Equatable {
  public let formatVersion: Int
  public let title: String
  public let note: String?
  public let createdAt: Date
  public let days: [ProgramDay]

  public init(formatVersion: Int, title: String, note: String? = nil, createdAt: Date, days: [ProgramDay]) {
    self.formatVersion = formatVersion
    self.title = title
    self.note = note
    self.createdAt = createdAt
    self.days = days
  }

  public var exerciseIDs: [String] { Array(Set(days.flatMap(\.exerciseIDs))).sorted() }

  public func json() -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(self), let string = String(data: data, encoding: .utf8) else {
      return "{}"
    }
    return string
  }
}

public enum ProgramRedactor {
  /// Keys that must never appear in a shared payload. Used both to redact and to
  /// reject an inbound file that tried to smuggle them through.
  public static let sensitiveKeys: Set<String> = [
    "rawHistory", "history", "coachMemory", "coachNotes", "loggedSets",
    "sessionLog", "workoutHistory", "userName", "userEmail", "bodyweightKg",
    "hrv", "sleepHours", "apiToken", "sessionToken", "token",
  ]

  public static func redact(
    _ program: ImportedProgram,
    title: String? = nil,
    note: String? = nil,
    version number: Int? = nil,
    at date: Date
  ) -> ShareableProgram {
    let source: ProgramVersion?
    if let number {
      source = program.versions.first { $0.number == number }
    } else {
      source = program.activeVersion
    }
    return ShareableProgram(
      formatVersion: program.formatVersion,
      title: title ?? program.title,
      note: note,
      createdAt: date,
      days: source?.days ?? [])
  }
}

// MARK: - Revocable share tokens

public enum ShareScope: String, Codable, Sendable, CaseIterable {
  case readOnly, remixable
}

public enum ShareTokenStatus: String, Codable, Sendable, CaseIterable {
  case active, expired, revoked
}

public struct ShareTokenMetadata: Codable, Sendable, Equatable, Identifiable {
  public let id: String
  public let programID: String
  public let scope: ShareScope
  public let createdAt: Date
  public let expiresAt: Date
  public let revokedAt: Date?

  public init(
    id: String,
    programID: String,
    scope: ShareScope,
    createdAt: Date,
    expiresAt: Date,
    revokedAt: Date? = nil
  ) {
    self.id = id
    self.programID = programID
    self.scope = scope
    self.createdAt = createdAt
    self.expiresAt = expiresAt
    self.revokedAt = revokedAt
  }

  public var isRevoked: Bool { revokedAt != nil }

  /// Expiry is inclusive: at exactly `expiresAt` the token is already dead.
  public func status(at now: Date) -> ShareTokenStatus {
    if isRevoked { return .revoked }
    return now >= expiresAt ? .expired : .active
  }

  public func isValid(at now: Date) -> Bool { status(at: now) == .active }

  public func revoking(at now: Date) -> ShareTokenMetadata {
    ShareTokenMetadata(
      id: id, programID: programID, scope: scope,
      createdAt: createdAt, expiresAt: expiresAt, revokedAt: now)
  }
}

public enum ShareTokenPolicy {
  public static func status(_ token: ShareTokenMetadata, at now: Date) -> ShareTokenStatus {
    token.status(at: now)
  }

  public static func accepts(_ token: ShareTokenMetadata, at now: Date) -> Bool {
    token.isValid(at: now)
  }
}

// MARK: - Import decoding

public enum ProgramImportError: Error, Sendable, Equatable {
  case malformedJSON
  case containsSensitiveContent([String])
}

public enum ProgramImportDecoder {
  /// Local program files may contain versions, but must stay bounded before parsing.
  public static let maximumBytes = 1_048_576

  /// Decodes an inbound program, refusing any payload that carries user history
  /// or coach memory keys — even if the current model has nowhere to put them.
  public static func decode(_ data: Data) throws -> ImportedProgram {
    guard data.count <= maximumBytes,
      let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
      throw ProgramImportError.malformedJSON
    }
    let offending = sensitiveKeys(in: object)
    if !offending.isEmpty {
      throw ProgramImportError.containsSensitiveContent(offending)
    }
    do {
      let decoder = JSONDecoder()
      if let program = try? decoder.decode(ImportedProgram.self, from: data) {
        return program
      }
      // Offline exports use the redacted shape, not the private import bookkeeping.
      // A deterministic content identity makes reopening the same file duplicate-safe.
      let shared = try decoder.decode(ShareableProgram.self, from: data)
      return ImportedProgram(
        id: "shared-file." + SetRevision.fingerprint(of: shared.json()).rawValue,
        formatVersion: shared.formatVersion, title: shared.title,
        source: ProgramSource(kind: .file), importedAt: .now,
        versions: [ProgramVersion(
          number: 1, createdAt: shared.createdAt, note: shared.note, days: shared.days)],
        activeVersionNumber: nil)
    } catch {
      throw ProgramImportError.malformedJSON
    }
  }

  public static func sensitiveKeys(in value: Any) -> [String] {
    var found = Set<String>()
    func walk(_ node: Any) {
      if let dict = node as? [String: Any] {
        for (key, child) in dict {
          if ProgramRedactor.sensitiveKeys.contains(key) { found.insert(key) }
          walk(child)
        }
      } else if let array = node as? [Any] {
        array.forEach(walk)
      }
    }
    walk(value)
    return found.sorted()
  }
}
