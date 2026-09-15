import Foundation
import SwiftData

@Model
final class BodyMeasurement {
  var date: Date
  var weightKg: Double?
  var bodyFatPercent: Double?
  var tape: [String: Double]
  var remoteID: String = ""
  var updatedAt: Date = Date.now
  var deleted: Bool = false

  init(date: Date, weightKg: Double? = nil, bodyFatPercent: Double? = nil, tape: [String: Double] = [:]) {
    self.date = date
    self.weightKg = weightKg
    self.bodyFatPercent = bodyFatPercent
    self.tape = tape
  }

  static let tapeKeys = ["chest", "waist", "hips", "arm", "thigh"]
}
