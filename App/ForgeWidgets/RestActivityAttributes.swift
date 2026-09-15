import ActivityKit
import Foundation

struct RestActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var endDate: Date
    var exerciseName: String
    var nextSet: Int
    var totalSets: Int
  }
  var dayName: String
}
