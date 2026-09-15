import Foundation
import SwiftData

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
