import Foundation

// MARK: - Stable identity
//
// Feedback binds to the *identity* of one logged set — which set, in which session, at which
// revision — so it can never drift onto another set, and so a set can be recognised as changed
// since the lifter wrote the feedback.

public struct SetLimiterEventID: RawRepresentable, Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public var description: String { rawValue }
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A revision of one logged set, derived from the set's recorded content rather than from a
/// stored counter, so *any* edit to the load, reps, index or variant produces a new revision
/// without every edit site having to remember to bump one.
public struct SetRevision: RawRepresentable, Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ rawValue: String) { self.rawValue = rawValue }
  public var description: String { rawValue }
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

  /// Deterministic FNV-1a fingerprint. Stable across launches and processes; it identifies a
  /// revision, it is not a security primitive.
  public static func fingerprint(of canonical: String) -> SetRevision {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in canonical.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01b3
    }
    return SetRevision("r" + String(hash, radix: 16))
  }
}

public enum SetRevisionBuilder {
  /// Canonical string for one set's recorded content. Parts are joined with a unit separator so
  /// no part can impersonate a boundary of another part.
  public static func canonical(
    setID: String, loadValue: String, loadUnit: String, reps: Int, setIndex: Int, variant: String
  ) -> String {
    [
      setID, loadUnit, loadValue, String(reps), String(setIndex),
      variant.isEmpty ? "straight" : variant,
    ].joined(separator: "\u{1F}")
  }

  public static func revision(
    setID: String, loadValue: String, loadUnit: String, reps: Int, setIndex: Int, variant: String
  ) -> SetRevision {
    .fingerprint(
      of: canonical(
        setID: setID, loadValue: loadValue, loadUnit: loadUnit, reps: reps, setIndex: setIndex,
        variant: variant))
  }
}

/// Immutable pointer to the set a feedback event was written against.
public struct SetIdentity: Codable, Hashable, Sendable {
  public let setID: String
  public let sessionID: String
  public let exerciseID: String
  public let setIndex: Int
  public let revision: SetRevision
  public let loggedAt: Date

  public init(
    setID: String, sessionID: String, exerciseID: String, setIndex: Int, revision: SetRevision,
    loggedAt: Date
  ) {
    self.setID = setID
    self.sessionID = sessionID
    self.exerciseID = exerciseID
    self.setIndex = setIndex
    self.revision = revision
    self.loggedAt = loggedAt
  }

  /// True when the set has been recorded differently since the feedback was written.
  public func isStale(against currentRevision: SetRevision) -> Bool { revision != currentRevision }
}

// MARK: - Closed reason codes

/// The ordinary, closed set of limiters a set can be reported to have ended on. Pain and
/// discomfort are deliberately *not* in this list: they take the separate safety route below.
public enum SetLimiterReason: String, Codable, CaseIterable, Sendable, Hashable {
  case targetMuscles
  case grip
  case breathing
  case setup
  case techniqueUncertainty
  case interrupted
  case other
  case unsure

  public var label: String {
    switch self {
    case .targetMuscles: return "Target muscles"
    case .grip: return "Grip"
    case .breathing: return "Breathing"
    case .setup: return "Setup problem"
    case .techniqueUncertainty: return "Technique unsure"
    case .interrupted: return "Set cut short"
    case .other: return "Something else"
    case .unsure: return "Not sure"
    }
  }

  /// Detail line for the picker. Descriptive, never a diagnosis and never a push-through nudge.
  public var detail: String {
    switch self {
    case .targetMuscles: return "The muscle doing the work was what stopped the set"
    case .grip: return "The set ended because of your grip, not the target muscle"
    case .breathing: return "Breathing, not the muscle, ended the set"
    case .setup: return "Equipment or position setup was wrong for this set"
    case .techniqueUncertainty: return "You are unsure the reps were technically sound"
    case .interrupted: return "Something interrupted the set before it finished"
    case .other: return "A reason that is not on this list"
    case .unsure: return "You would rather not classify it"
    }
  }

  public var symbol: String {
    switch self {
    case .targetMuscles: return "figure.strengthtraining.traditional"
    case .grip: return "hand.raised.fill"
    case .breathing: return "wind"
    case .setup: return "wrench.and.screwdriver.fill"
    case .techniqueUncertainty: return "questionmark.circle"
    case .interrupted: return "pause.circle"
    case .other: return "ellipsis.circle"
    case .unsure: return "questionmark.circle"
    }
  }

  /// What the app may offer in response. Bounded by design: a limiter never rewrites a program,
  /// never adds volume and never swaps an exercise.
  public var allowedResponse: SetLimiterResponse {
    switch self {
    case .targetMuscles: return .recordOnly
    case .grip: return .recordOnly
    case .breathing: return .offerSupportedRestAdjustment
    case .setup: return .offerSetupReview
    case .techniqueUncertainty: return .showCuratedGuidance
    case .interrupted: return .offerScopeExclusion
    case .other: return .recordOnly
    case .unsure: return .recordOnly
    }
  }

  /// Grip is recorded, but a review may only be offered once the versioned evidence rule is met
  /// (several sessions, not one set). The policy holds the gate; nothing here counts sessions.
  public var requiresVersionedEvidenceBeforeReview: Bool { self == .grip }

  /// True when the reason is a statement about the set that still needs an exclusion decision.
  public var withholdsAnalysis: Bool { !SetFeedbackAnalysisPolicy.excludedScopes(forReason: self).isEmpty }
}

/// The bounded set of responses a limiter may produce.
public enum SetLimiterResponse: String, Codable, CaseIterable, Sendable {
  case recordOnly
  case offerScopeExclusion
  case offerSetupReview
  case offerSupportedRestAdjustment
  case showCuratedGuidance
  case safetyGuidance

  /// No response in this list is ever a program mutation.
  public var mutatesProgram: Bool { false }
}

// MARK: - Discomfort safety branch

/// Separate, safety-oriented route. This is not a performance-optimisation reason.
public enum DiscomfortSignal: String, Codable, CaseIterable, Sendable, Hashable {
  case noticed
  case changedTheSet
  case stoppedTheSet

  public var label: String {
    switch self {
    case .noticed: return "Noticed some discomfort"
    case .changedTheSet: return "Adjusted the set because of it"
    case .stoppedTheSet: return "Stopped the set because of it"
    }
  }

  /// Stopping is treated as a valid, completed decision — never as a missed set.
  public var isUnfinished: Bool { false }
}

public struct DiscomfortFeedback: Codable, Hashable, Sendable {
  public var signal: DiscomfortSignal
  public var note: String?

  public init(signal: DiscomfortSignal, note: String? = nil) {
    self.signal = signal
    self.note = SetLimiterEvent.sanitizedNote(note)
  }
}

/// Reviewed, non-diagnostic safety copy. Plain statements only: nothing here names a condition,
/// prescribes rehabilitation, or turns discomfort into a reason to continue training.
public enum DiscomfortSafetyCopy {
  public static let headline = "Stopping or changing a set for discomfort is a valid choice"
  public static let guidance =
    "Regulift is not a doctor and this is not a diagnosis. Nothing here is medical advice and nothing will tell you to train through discomfort. If pain is sharp or sudden, or keeps coming back, have a clinician look at it."
  public static let nextSteps =
    "Your logged set is kept as recorded. Ordinary load progression for this lift is paused for this set, and you can remove this note at any time."
  /// A discomfort report never becomes a reason to continue or intensify.
  public static let neverEncouragesContinuation = true
  public static let neverPrescribesRehabilitation = true

  public static func response(for signal: DiscomfortSignal) -> SetLimiterResponse { .safetyGuidance }
}

// MARK: - Event

public struct SetFeedbackProvenance: Codable, Hashable, Sendable {
  public enum Source: String, Codable, CaseIterable, Sendable {
    case lifter
    case watch
    case voice
    case review
  }

  public let source: Source
  public let actorID: String?
  public let appVersion: String?
  public let capturedAt: Date

  public init(source: Source, actorID: String? = nil, appVersion: String? = nil, capturedAt: Date) {
    self.source = source
    self.actorID = actorID
    self.appVersion = appVersion
    self.capturedAt = capturedAt
  }
}

public enum SetLimiterKind: Codable, Hashable, Sendable {
  case limiter(SetLimiterReason)
  case discomfort(DiscomfortFeedback)

  public var limiterReason: SetLimiterReason? {
    if case .limiter(let reason) = self { return reason }
    return nil
  }

  public var discomfort: DiscomfortFeedback? {
    if case .discomfort(let feedback) = self { return feedback }
    return nil
  }

  public var isDiscomfort: Bool { discomfort != nil }

  /// Short, non-diagnostic description for a row or chip.
  public var label: String {
    if let reason = limiterReason { return reason.label }
    if let discomfort { return discomfort.signal.label }
    return ""
  }

  public var symbol: String {
    if let reason = limiterReason { return reason.symbol }
    return "exclamationmark.triangle"
  }

  public var allowedResponse: SetLimiterResponse {
    if let reason = limiterReason { return reason.allowedResponse }
    if let discomfort { return DiscomfortSafetyCopy.response(for: discomfort.signal) }
    return .recordOnly
  }
}

/// One optional statement about one set. Editable and deletable; deletion is a tombstone so a
/// derived summary can be invalidated instead of silently changing meaning.
public struct SetLimiterEvent: Codable, Hashable, Sendable, Identifiable {
  public static let maxNoteLength = 280

  public let id: SetLimiterEventID
  public let identity: SetIdentity
  public var kind: SetLimiterKind
  /// Optional free text. Trimmed; empty reads as `nil` so "no note" cannot be mistaken for one.
  public var note: String?
  public let provenance: SetFeedbackProvenance
  public let createdAt: Date
  public var updatedAt: Date
  public var deletedAt: Date?

  public init(
    id: SetLimiterEventID, identity: SetIdentity, kind: SetLimiterKind, note: String?,
    provenance: SetFeedbackProvenance, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil
  ) {
    self.id = id
    self.identity = identity
    self.kind = kind
    self.note = Self.sanitizedNote(note)
    self.provenance = provenance
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.deletedAt = deletedAt
  }

  /// Whitespace-only text is not a note, and no note grows without bound.
  public static func sanitizedNote(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return String(trimmed.prefix(maxNoteLength))
  }

  /// At most one feedback per set: the id is derived from the set, so re-recording replaces the
  /// previous statement (keeping `createdAt`) rather than accumulating a second one.
  public static func id(forSet setID: String) -> SetLimiterEventID {
    SetLimiterEventID("setfeedback." + setID)
  }

  public static func record(
    identity: SetIdentity, kind: SetLimiterKind, note: String? = nil,
    provenance: SetFeedbackProvenance, at now: Date
  ) -> SetLimiterEvent {
    SetLimiterEvent(
      id: id(forSet: identity.setID), identity: identity, kind: kind, note: note,
      provenance: provenance, createdAt: now, updatedAt: now, deletedAt: nil)
  }

  /// Edit in place: same set, same identity, new statement. `createdAt` is history and stays.
  public mutating func edit(kind: SetLimiterKind, note: String?, at now: Date) {
    self.kind = kind
    self.note = Self.sanitizedNote(note)
    self.updatedAt = now
    self.deletedAt = nil
  }

  /// Rebinding after the set itself changed: the identity (and therefore the revision) is
  /// refreshed while the statement and its creation time survive.
  public func rebinding(to identity: SetIdentity, at now: Date) -> SetLimiterEvent {
    SetLimiterEvent(
      id: id, identity: identity, kind: kind, note: note, provenance: provenance,
      createdAt: createdAt, updatedAt: now, deletedAt: deletedAt)
  }

  /// Soft deletion. The recorded set is untouched and nothing else is rewritten.
  public mutating func delete(at now: Date) {
    deletedAt = now
    updatedAt = now
  }

  public mutating func restore(at now: Date) {
    deletedAt = nil
    updatedAt = now
  }

  public var isDeleted: Bool { deletedAt != nil }

  /// The recorded set was edited after this statement was written.
  public func isStale(against currentRevision: SetRevision) -> Bool {
    identity.isStale(against: currentRevision)
  }

  /// A durable Coach memory is a separate, confirmed decision; one set statement never becomes
  /// one by itself.
  public var isDurableMemory: Bool { false }
}

// MARK: - Named analysis scopes

/// The named analyses a set's feedback can be withheld from. Every scope is checked through
/// `SetFeedbackAnalysisPolicy`, so a surface can never invent its own exclusion rule.
public enum SetAnalysisScope: String, Codable, CaseIterable, Sendable, Hashable {
  case progression
  case trends
  case achievements
  case crew

  public var label: String {
    switch self {
    case .progression: return "load progression"
    case .trends: return "Progress trends"
    case .achievements: return "records and awards"
    case .crew: return "Crew"
    }
  }

  public var shortExplanation: String {
    switch self {
    case .progression: return "next load suggestions for this lift"
    case .trends: return "charts and weekly totals"
    case .achievements: return "PRs, badges and awards"
    case .crew: return "Crew rings and posts"
    }
  }
}

/// Pure eligibility policy. Two rules that always hold: exclusion never deletes recorded work,
/// and it never penalises adherence, readiness, or the program.
public enum SetFeedbackAnalysisPolicy {
  /// Which named analyses a reason withholds the set from. Documented per reason so the UI can
  /// state it plainly, and so a test can pin it.
  ///
  /// - `targetMuscles`: nothing withheld. The target muscle ended the set — the recorded work is
  ///   exactly what progression wants to read.
  /// - `grip`, `breathing`, `other`: load progression only. The reps happened at the recorded
  ///   load, so trends, records and Crew keep them, but the load read is withheld because
  ///   something other than the target muscle ended the set.
  /// - `techniqueUncertainty`, `setup`: progression and records. A record cannot stand on reps
  ///   whose execution or setup is in question.
  /// - `interrupted`: progression, trends and records. The set did not complete as planned, so
  ///   its volume distorts trend maths.
  /// - `unsure`: every scope. The lifter could not vouch for the set, so nothing analytic is
  ///   built on it.
  /// - discomfort: every scope. A set that hurt is not a performance datum to celebrate or to
  ///   rank against a crew.
  public static func excludedScopes(forReason reason: SetLimiterReason) -> Set<SetAnalysisScope> {
    switch reason {
    case .targetMuscles:
      return []
    case .grip, .breathing, .other:
      return [.progression]
    case .techniqueUncertainty, .setup:
      return [.progression, .achievements]
    case .interrupted:
      return [.progression, .trends, .achievements]
    case .unsure:
      return Set(SetAnalysisScope.allCases)
    }
  }

  public static func excludedScopes(forKind kind: SetLimiterKind) -> Set<SetAnalysisScope> {
    if let reason = kind.limiterReason { return excludedScopes(forReason: reason) }
    if kind.discomfort != nil { return Set(SetAnalysisScope.allCases) }
    return []
  }

  /// Exclusions for an event. A deleted event excludes nothing: removing feedback restores the
  /// set to every analysis without touching the recorded work.
  public static func excludedScopes(_ event: SetLimiterEvent?) -> Set<SetAnalysisScope> {
    guard let event, !event.isDeleted else { return [] }
    return excludedScopes(forKind: event.kind)
  }

  public static func isEligible(_ event: SetLimiterEvent?, for scope: SetAnalysisScope) -> Bool {
    !excludedScopes(event).contains(scope)
  }

  /// True when no named analysis was affected — the set stays eligible everywhere.
  public static func isEligibleEverywhere(_ event: SetLimiterEvent?) -> Bool {
    excludedScopes(event).isEmpty
  }

  /// One clear sentence naming the scopes that were withheld, for the sheet and for the row.
  public static func scopeExplanation(_ scopes: Set<SetAnalysisScope>) -> String? {
    guard !scopes.isEmpty else { return nil }
    let ordered = SetAnalysisScope.allCases.filter { scopes.contains($0) }
    let names = ordered.map(\.label)
    let joined: String
    switch names.count {
    case 1: joined = names[0]
    case 2: joined = "\(names[0]) and \(names[1])"
    default: joined = names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    }
    return "Left out of \(joined). Your logged set stays in History exactly as recorded."
  }

  /// Explanation for a stored event, or `nil` when the set is used everywhere.
  public static func scopeExplanation(for event: SetLimiterEvent?) -> String? {
    scopeExplanation(excludedScopes(event))
  }

  /// The one line History shows next to a set that is excluded somewhere.
  public static func historyNote(for event: SetLimiterEvent?) -> String? {
    guard let event, !event.isDeleted else { return nil }
    guard let explanation = scopeExplanation(for: event) else { return nil }
    let reason = event.kind.isDiscomfort ? "you reported discomfort" : "you marked it “\(event.kind.label)”"
    return "\(explanation) Because \(reason)."
  }

  /// True when the surface reading this set is a named analysis scope it was excluded from.
  public static func excludes(_ event: SetLimiterEvent?, from scope: SetAnalysisScope) -> Bool {
    excludedScopes(event).contains(scope)
  }

  // Fixed properties of the policy, asserted in tests and never configurable at a call site.
  public static let affectsAdherence = false
  public static let affectsReadiness = false
  public static let mutatesProgram = false
  public static let createsCoachMemory = false
  public static let deletesRecordedWork = false
}

// MARK: - Prompt discipline

/// Prompts are optional and rate-limited: at most one unsolicited prompt per workout, and zero
/// is always within the rule. A skipped prompt changes nothing downstream.
public enum SetFeedbackPromptRule {
  public static let maximumUnsolicitedPromptsPerWorkout = 1
  public static let promptsAreRequired = false
  public static let skippedPromptAffectsAdherence = false
  public static let skippedPromptAffectsReadiness = false
  public static let skippedPromptAffectsAwards = false

  public enum Verdict: String, Equatable, Sendable {
    case notAllowed
    case allowed
  }

  /// `unsolicitedPromptsAlreadyShown` counts prompts the app started, never ones the lifter
  /// opened. Zero is allowed; two in one workout never is.
  public static func verdict(reason: SetLimiterReason?, unsolicitedPromptsAlreadyShown: Int) -> Verdict {
    guard reason != nil else { return .notAllowed }
    guard unsolicitedPromptsAlreadyShown >= 0 else { return .notAllowed }
    return unsolicitedPromptsAlreadyShown < maximumUnsolicitedPromptsPerWorkout ? .allowed : .notAllowed
  }

  /// A rule-defined unusual result is the only thing that may make clarification useful. It is an
  /// interaction rule, not a physiological threshold, and it never blocks finishing a workout.
  public struct UnusualResult: Equatable, Sendable {
    public let repsBelowRange: Bool
    public let effortNotReported: Bool
    public let loadJumped: Bool

    public init(repsBelowRange: Bool, effortNotReported: Bool, loadJumped: Bool) {
      self.repsBelowRange = repsBelowRange
      self.effortNotReported = effortNotReported
      self.loadJumped = loadJumped
    }

    public var suggestsReason: SetLimiterReason? {
      if repsBelowRange { return .interrupted }
      if loadJumped { return .setup }
      if effortNotReported { return .unsure }
      return nil
    }
  }
}

// MARK: - Contextual summaries

/// A conservative, derived view of repeated feedback for one exercise. It references the events
/// it was built from and is stale the moment one of them is edited or deleted, so nothing keeps
/// reporting a statement the lifter has retracted.
public struct SetLimiterContextSummary: Codable, Equatable, Sendable {
  public let exerciseID: String
  public let reasonCounts: [String: Int]
  public let discomfortCount: Int
  public let sourceEventIDs: [String]
  public let revisionToken: String
  public let latestAt: Date

  public init(
    exerciseID: String, reasonCounts: [String: Int], discomfortCount: Int, sourceEventIDs: [String],
    revisionToken: String, latestAt: Date
  ) {
    self.exerciseID = exerciseID
    self.reasonCounts = reasonCounts
    self.discomfortCount = discomfortCount
    self.sourceEventIDs = sourceEventIDs
    self.revisionToken = revisionToken
    self.latestAt = latestAt
  }

  public var describesARepeatPattern: Bool { sourceEventIDs.count >= 2 }

  /// True when the events on hand no longer produce this token. A summary is never repaired in
  /// place; it is rebuilt from its sources or dropped.
  public func isStale(against events: [SetLimiterEvent]) -> Bool {
    SetLimiterSummaryBuilder.token(for: events) != revisionToken
  }
}

public enum SetLimiterSummaryBuilder {
  public static func token(for events: [SetLimiterEvent]) -> String {
    events
      .sorted { $0.id < $1.id }
      .map { "\($0.id.rawValue)@\(Int($0.updatedAt.timeIntervalSince1970)):\($0.deletedAt != nil ? "d" : "a")" }
      .joined(separator: ",")
  }

  /// Live events only: a deleted statement leaves the summary the moment it is deleted.
  public static func summary(exerciseID: String, events: [SetLimiterEvent]) -> SetLimiterContextSummary? {
    let live = events.filter { $0.identity.exerciseID == exerciseID && !$0.isDeleted }
      .sorted { $0.id < $1.id }
    guard let latest = live.map(\.updatedAt).max(), !live.isEmpty else { return nil }
    var counts: [String: Int] = [:]
    var discomfort = 0
    for event in live {
      if event.kind.isDiscomfort { discomfort += 1 } else if let reason = event.kind.limiterReason {
        counts[reason.rawValue, default: 0] += 1
      }
    }
    return SetLimiterContextSummary(
      exerciseID: exerciseID,
      reasonCounts: counts,
      discomfortCount: discomfort,
      sourceEventIDs: live.map(\.id.rawValue),
      revisionToken: token(for: live),
      latestAt: latest)
  }

  /// One sentence for a repeated signal — and nothing at all for a single set, which is not a
  /// pattern. No cause is inferred from it.
  public static func headline(_ summary: SetLimiterContextSummary) -> String? {
    guard summary.describesARepeatPattern else { return nil }
    if summary.discomfortCount >= 2 {
      return "Discomfort reported on \(summary.discomfortCount) sets of this exercise. Progression for those sets stays paused."
    }
    guard let top = summary.reasonCounts.max(by: { ($0.value, $0.key) < ($1.value, $1.key) }),
      let reason = SetLimiterReason(rawValue: top.key), top.value >= 2
    else { return nil }
    return "\(reason.label) reported on \(top.value) sets of this exercise. This is context, not a cause."
  }
}

// MARK: - Codec

/// JSON persistence for one event. Decoding is lenient about absence and strict about meaning:
/// an unreadable payload or an unknown reason code reads as `nil`, which leaves the set eligible
/// and never guesses a reason. The raw payload is the caller's to keep.
public enum SetLimiterEventCodec {
  public static func encode(_ event: SetLimiterEvent) -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(event) else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
  }

  public static func decode(_ json: String) -> SetLimiterEvent? {
    let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(SetLimiterEvent.self, from: data)
  }
}
