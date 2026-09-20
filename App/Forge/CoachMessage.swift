import Foundation
import SwiftData
import ForgeCore

@Model
final class CoachMessage {
  var date: Date
  var role: String
  var text: String
  var citations: [String]

  init(date: Date = .now, role: String, text: String, citations: [String] = []) {
    self.date = date
    self.role = role
    self.text = text
    self.citations = citations
  }
}

@Model
final class CoachNote {
  var date: Date
  var text: String
  var kind: String = CoachMemoryKind.other.rawValue
  var source: String = "coach"
  var confirmedAt: Date = Date.now
  var expiresAt: Date? = nil
  var supersededAt: Date? = nil

  init(
    text: String,
    kind: CoachMemoryKind? = nil,
    source: String = "coach",
    date: Date = .now,
    expiresAt: Date? = nil
  ) {
    self.text = text
    self.kind = (kind ?? CoachMemoryKind.infer(from: text)).rawValue
    self.source = source
    self.date = date
    self.confirmedAt = date
    self.expiresAt = expiresAt
  }

  var memoryKind: CoachMemoryKind { CoachMemoryKind(rawValue: kind) ?? .other }
  var isActive: Bool { supersededAt == nil && (expiresAt == nil || expiresAt! > .now) }
}
