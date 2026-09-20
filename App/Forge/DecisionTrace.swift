import ForgeCore
import Foundation
import SwiftData

/// The commit boundary for the decision trace.
///
/// The existing engine still decides every load: nothing here computes a prescription. This
/// type only takes the decisions a start already produced and writes them exactly once, so a
/// retried workout start — a crash, a second tap, a resumed session — cannot log the same
/// committed change twice or double-explain it later.
enum DecisionTrace {

  /// Identity for one ledger write: the session being started plus the decisions in it.
  /// Time is deliberately absent, so a retry of the same start matches the first attempt.
  static func fingerprint(sessionKey: String, records: [DecisionRecord]) -> String {
    TrainingFingerprint.make(
      kind: .applyDecisionLedger,
      resourceID: sessionKey,
      contentKey: TrainingFingerprint.ledgerContentKey(decisionIDs: records.map(\.id)))
  }

  /// Writes the records once for this fingerprint and returns the receipt.
  ///
  /// A second call with the same fingerprint is a replay: it returns the original receipt and
  /// writes nothing. A call with the same session but different decisions is new work with its
  /// own fingerprint, so a genuinely changed plan is still recorded.
  @discardableResult
  @MainActor
  static func commit(
    records: [DecisionRecord],
    sessionKey: String,
    context: ModelContext,
    requestID: UUID = UUID()
  ) -> CommitReceipt {
    let operation = fingerprint(sessionKey: sessionKey, records: records)
    let receipt = CommitReceipt(
      requestID: requestID,
      fingerprint: operation,
      planRevisionAfter: 0,
      decisionIDs: records.map(\.id))
    guard !records.isEmpty else { return receipt }

    // Filtered in memory rather than in a #Predicate: the ledger is small, and a predicate
    // over a captured string is the kind of thing that fails at runtime, not at compile time.
    let stored = (try? context.fetch(FetchDescriptor<DecisionLogEntry>())) ?? []
    guard !stored.contains(where: { $0.operationFingerprint == operation }) else { return receipt }

    for record in records {
      context.insert(DecisionLogEntry(record, operationFingerprint: operation))
    }
    try? context.save()
    return receipt
  }

  /// The reason codes kept on device for this conversation, for the local disclosure line.
  static func withheldCodes(_ records: [DecisionRecord]) -> [String] {
    DecisionProvenance.withheldCodes(records)
  }
}
