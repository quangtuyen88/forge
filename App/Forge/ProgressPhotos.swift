import Foundation
import SwiftData
import UIKit

@Model
final class ProgressPhoto {
  var date: Date
  var fileName: String
  var pose: String

  init(date: Date, fileName: String, pose: String) {
    self.date = date
    self.fileName = fileName
    self.pose = pose
  }

  static let poses = ["front", "side", "back"]

  static var directory: URL {
    let dir = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("ProgressPhotos", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  var fileURL: URL { Self.directory.appendingPathComponent(fileName) }

  static func insert(_ data: Data, date: Date, pose: String, context: ModelContext) {
    let fileName = "\(UUID().uuidString).jpg"
    do {
      try data.write(to: directory.appendingPathComponent(fileName), options: [.atomic, .completeFileProtection])
      context.insert(ProgressPhoto(date: date, fileName: fileName, pose: pose))
    } catch {
      // ponytail: silent skip on write failure; surface an alert if users hit disk errors
    }
  }

  func deleteFile() {
    try? FileManager.default.removeItem(at: fileURL)
  }
}
