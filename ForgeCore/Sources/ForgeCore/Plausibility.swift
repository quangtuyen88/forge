import Foundation

public enum Plausibility {
  /// A set whose e1RM beats the lifter's best by more than this ratio needs confirming.
  public static let jumpRatio = 1.2
  /// Two sets closer than this are not two real sets.
  public static let minSetGap: TimeInterval = 20
  /// A session with four or more sets shorter than this is not a real session.
  public static let minSessionSeconds: TimeInterval = 300

  public static func isJump(e1rm: Double, previousBest: Double?) -> Bool {
    guard let previousBest, previousBest > 0 else { return false }
    return e1rm > previousBest * jumpRatio
  }

  public static func isRapid(loggedAt: Date, previous: Date?) -> Bool {
    guard let previous else { return false }
    return loggedAt.timeIntervalSince(previous) < minSetGap
  }

  public static func isShortSession(setCount: Int, first: Date?, last: Date?) -> Bool {
    guard setCount >= 4, let first, let last else { return false }
    return last.timeIntervalSince(first) < minSessionSeconds
  }
}
