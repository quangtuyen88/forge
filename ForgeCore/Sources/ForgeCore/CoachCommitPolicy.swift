import Foundation

// MARK: - Bound consent
//
// A coach action is approved against a *preview*: an exact diff, shown at an exact plan
// state, for an exact recommendation. Anything that arrives later claiming that approval
// has to match all three. This does not replace `RecommendationLedger` — it produces the
// checked input to it, and every rejection maps onto an outcome the ledger already has.

/// The preview the lifter saw, and the identity of the state it described.
public struct CommitPreview: Sendable, Equatable {
  public let recommendationID: RecommendationID
  public let programVersion: ProgramVersionID
  /// `PlanRevision.digest` of the plan at the moment the preview was built.
  public let planRevision: String
  /// A digest of the change itself — identifiers, integers and enum raw values, never
  /// rendered text.
  ///
  /// Binding consent to the *displayed strings* looks tempting and is wrong here: the app
  /// switches language in place and formats numbers by region, so "82,5 kg" becomes
  /// "82.5 kg" with no plan change at all and a legitimate apply would be refused as a
  /// mismatch. The strings the lifter actually read are captured in `displayedLines` for
  /// the receipt; the authorization compares meaning.
  public let previewDigest: String
  /// What was on the card, verbatim, at preview time. Captured — never re-rendered.
  public let displayedLines: [String]
  public let expiresAt: Date

  public init(
    recommendationID: RecommendationID,
    programVersion: ProgramVersionID,
    planRevision: String,
    previewDigest: String,
    displayedLines: [String] = [],
    expiresAt: Date
  ) {
    self.recommendationID = recommendationID
    self.programVersion = programVersion
    self.planRevision = planRevision
    self.previewDigest = previewDigest
    self.displayedLines = displayedLines
    self.expiresAt = expiresAt
  }

  /// The digest of a proposed change. `components` must be locale-independent: ids, enum
  /// raw values and integers (`LoadValue.milliUnits`, set counts), never formatted numbers
  /// and never localized labels.
  public static func digest(
    ownerKey: String, recommendationID: RecommendationID, components: [String]
  ) -> String {
    PlanRevision.digest([ownerKey, recommendationID.rawValue] + components)
  }
}

/// Proof that a trusted interaction approved one exact preview.
///
/// A model tool call cannot forge one usefully: the digest and revisions are checked
/// against the proposal the app persisted, so a fabricated approval fails the same way a
/// stale one does. `confirmed: true` is never an argument the model supplies.
public struct CommitApproval: Sendable, Equatable {
  public let preview: CommitPreview
  public let approvedAt: Date

  public init(preview: CommitPreview, approvedAt: Date) {
    self.preview = preview
    self.approvedAt = approvedAt
  }
}

/// Why a commit was refused. Each case maps onto an existing ledger outcome so there is
/// still exactly one vocabulary for "what happened to this recommendation".
public enum CommitRejection: String, Sendable, Equatable {
  case unknownProposal
  case expired
  case staleRevision
  case digestMismatch
  case wrongOwner
  case replayedWithDifferentContent

  /// The ledger state this rejection means. Nothing here invents a new terminal state.
  public var ledgerState: RecommendationLedgerState {
    switch self {
    case .unknownProposal, .wrongOwner: return .failed
    case .expired, .staleRevision: return .stale
    case .digestMismatch, .replayedWithDifferentContent: return .conflict
    }
  }
}

/// The single gate every consequential change passes before `RecommendationLedger.apply`.
/// Pure: no clock read, no storage, no UUIDs — the caller supplies `now` and the stored
/// proposal, so the same inputs always produce the same verdict.
public enum CoachCommitPolicy {
  /// Returns nil when the approval may proceed to the ledger.
  public static func check(
    approval: CommitApproval,
    storedProposal: CommitPreview?,
    ownerKey: String,
    expectedOwnerKey: String,
    currentPlanRevision: String,
    currentProgramVersion: ProgramVersionID,
    existingReceiptDigest: String?,
    now: Date
  ) -> CommitRejection? {
    guard ownerKey == expectedOwnerKey else { return .wrongOwner }
    // The saved proposal is the truth, never the fields echoed back by the caller.
    guard let stored = storedProposal else { return .unknownProposal }
    guard stored.recommendationID == approval.preview.recommendationID else { return .unknownProposal }

    // A replay of the same operation is fine and returns the original receipt; the same
    // identity with different content is a conflict, not a second application.
    if let existingReceiptDigest {
      return existingReceiptDigest == stored.previewDigest ? nil : .replayedWithDifferentContent
    }

    guard now < stored.expiresAt else { return .expired }
    guard approval.preview.previewDigest == stored.previewDigest else { return .digestMismatch }
    guard approval.preview.planRevision == stored.planRevision else { return .staleRevision }
    guard stored.planRevision == currentPlanRevision else { return .staleRevision }
    guard stored.programVersion == currentProgramVersion else { return .staleRevision }
    return nil
  }
}
