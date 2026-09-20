import Foundation

public enum ContextSource: String, Sendable {
  case app, healthKit = "HealthKit", user
}

public struct ContextField: Sendable, Equatable {
  public let key: String
  public let value: String
  public let source: ContextSource
  public var uploadAllowed: Bool { source != .healthKit }

  public init(key: String, value: String, source: ContextSource) {
    self.key = key
    self.value = value
    self.source = source
  }
}

public struct CoachContextPacket: Sendable {
  public let fields: [ContextField]
  /// Decisions cleared for upload: every reason behind them is workout or program data.
  public let decisions: [DecisionRecord]
  /// Fields the builder dropped because they came from Apple Health.
  public let withheld: [String]
  /// Reason codes of decisions the builder kept on device because they read recovery context.
  public let withheldDecisionCodes: [String]

  public init(
    fields: [ContextField], decisions: [DecisionRecord], withheld: [String],
    withheldDecisionCodes: [String] = []
  ) {
    self.fields = fields
    self.decisions = decisions
    self.withheld = withheld
    self.withheldDecisionCodes = withheldDecisionCodes
  }

  /// Lines for the request body, Health-sourced fields already removed.
  public func rendered() -> String {
    var lines: [String] = []
    for f in fields where f.source != .healthKit {
      lines.append("\(f.key): \(f.value)")
    }
    if !decisions.isEmpty {
      lines.append(DecisionLedger.payload(decisions))
    }
    return lines.joined(separator: "\n")
  }
}

public enum CoachContextBuilder {
  /// Builds the upload packet.
  ///
  /// Two filters run here, and both are allowlists. Health-sourced *fields* are dropped, and so
  /// is any *decision* whose reasoning read readiness, sleep or soreness — a decision's evidence
  /// text ("readiness 82") is Health-derived even when the change itself looks like a plain
  /// progression, so lineage, not wording, decides what may leave the device.
  public static func packet(fields: [ContextField], decisions: [DecisionRecord])
    -> CoachContextPacket
  {
    let withheld = fields.filter { $0.source == .healthKit }.map { $0.key }
    let kept = fields.filter { $0.source != .healthKit }
    let exportable = DecisionProvenance.cloudExportable(decisions)
    let withheldCodes = DecisionProvenance.withheldCodes(decisions)
    return CoachContextPacket(
      fields: kept, decisions: exportable, withheld: withheld,
      withheldDecisionCodes: withheldCodes)
  }
}
