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
  public let decisions: [DecisionRecord]
  /// Fields the builder dropped because they came from Apple Health.
  public let withheld: [String]

  public init(fields: [ContextField], decisions: [DecisionRecord], withheld: [String]) {
    self.fields = fields
    self.decisions = decisions
    self.withheld = withheld
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
  public static func packet(fields: [ContextField], decisions: [DecisionRecord]) -> CoachContextPacket {
    let withheld = fields.filter { $0.source == .healthKit }.map { $0.key }
    let kept = fields.filter { $0.source != .healthKit }
    return CoachContextPacket(fields: kept, decisions: decisions, withheld: withheld)
  }
}
