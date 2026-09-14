public struct FatigueInputs: Sendable {
  public var acuteVolume7d: Double
  public var avgWeeklyVolume28d: Double
  public var soreness: Int
  public var sleepHoursLastNight: Double
  public var sleepBaseline7d: Double
  public var sessionsLast7d: Int
  public var missedRPESessionsLast7d: Int

  public init(acuteVolume7d: Double, avgWeeklyVolume28d: Double, soreness: Int, sleepHoursLastNight: Double, sleepBaseline7d: Double, sessionsLast7d: Int, missedRPESessionsLast7d: Int) {
    self.acuteVolume7d = acuteVolume7d
    self.avgWeeklyVolume28d = avgWeeklyVolume28d
    self.soreness = soreness
    self.sleepHoursLastNight = sleepHoursLastNight
    self.sleepBaseline7d = sleepBaseline7d
    self.sessionsLast7d = sessionsLast7d
    self.missedRPESessionsLast7d = missedRPESessionsLast7d
  }
}

public enum FatigueAction: Equatable, Sendable {
  case proceed
  case reduceOptionalSets(by: Int)
  case lightSession(volumeMultiplier: Double, rpeCap: Double)
  case forceRest
}

public enum Fatigue {
  public static func acvr(_ i: FatigueInputs) -> Double {
    i.avgWeeklyVolume28d == 0 ? 1.0 : i.acuteVolume7d / i.avgWeeklyVolume28d
  }

  public static func acvrScore(_ ratio: Double) -> Double {
    if ratio <= 1.3 { return 0 }
    if ratio <= 1.5 { return 50 }
    return 100
  }

  public static func sorenessScore(_ soreness: Int) -> Double {
    Double(min(max(soreness, 1), 5) - 1) / 4 * 100
  }

  // ponytail: 2h deficit saturates; tune against beta data
  public static func sleepDeficitScore(lastNight: Double, baseline: Double) -> Double {
    let deficit = max(0, baseline - lastNight)
    return min(100, deficit / 2 * 100)
  }

  public static func missedRPEPenalty(missed: Int, sessions: Int) -> Double {
    sessions == 0 ? 0 : min(100, Double(missed) / Double(sessions) * 100)
  }

  public static func score(_ i: FatigueInputs) -> Int {
    let s = 0.35 * acvrScore(acvr(i))
      + 0.25 * sorenessScore(i.soreness)
      + 0.20 * sleepDeficitScore(lastNight: i.sleepHoursLastNight, baseline: i.sleepBaseline7d)
      + 0.20 * missedRPEPenalty(missed: i.missedRPESessionsLast7d, sessions: i.sessionsLast7d)
    return Int(min(max(s, 0), 100).rounded())
  }

  public static func action(forScore s: Int) -> FatigueAction {
    switch s {
    case ..<40: return .proceed
    case ..<60: return .reduceOptionalSets(by: 1)
    case ..<80: return .lightSession(volumeMultiplier: 0.7, rpeCap: 7)
    default: return .forceRest
    }
  }
}
