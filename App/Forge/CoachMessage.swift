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

@Model
final class CoachNote {
  var date: Date
  var text: String

  init(text: String, date: Date = .now) {
    self.text = text
    self.date = date
  }
}
