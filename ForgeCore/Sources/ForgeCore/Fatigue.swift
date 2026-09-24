public struct FatigueInputs: Sendable {
  public var acuteVolume7d: Double
  public var avgWeeklyVolume28d: Double
  public var soreness: Int
  public var sleepHoursLastNight: Double
  public var sleepBaseline7d: Double
  public var sessionsLast7d: Int
  public var missedRPESessionsLast7d: Int
  public var hrvLastNight: Double?        // ms, SDNN
  public var hrvBaseline7d: Double?
  public var restingHRLastNight: Double?  // bpm
  public var restingHRBaseline7d: Double?

  public init(acuteVolume7d: Double, avgWeeklyVolume28d: Double, soreness: Int, sleepHoursLastNight: Double, sleepBaseline7d: Double, sessionsLast7d: Int, missedRPESessionsLast7d: Int, hrvLastNight: Double? = nil, hrvBaseline7d: Double? = nil, restingHRLastNight: Double? = nil, restingHRBaseline7d: Double? = nil) {
    self.acuteVolume7d = acuteVolume7d
    self.avgWeeklyVolume28d = avgWeeklyVolume28d
    self.soreness = soreness
    self.sleepHoursLastNight = sleepHoursLastNight
    self.sleepBaseline7d = sleepBaseline7d
    self.sessionsLast7d = sessionsLast7d
    self.missedRPESessionsLast7d = missedRPESessionsLast7d
    self.hrvLastNight = hrvLastNight
    self.hrvBaseline7d = hrvBaseline7d
    self.restingHRLastNight = restingHRLastNight
    self.restingHRBaseline7d = restingHRBaseline7d
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

  /// 0 when hrv >= 95% of baseline, 50 when 85–95%, 100 below 85%. nil inputs → nil.
  public static func hrvScore(lastNight: Double?, baseline: Double?) -> Double? {
    guard let lastNight, let baseline, baseline > 0 else { return nil }
    let ratio = lastNight / baseline
    if ratio >= 0.95 { return 0 }
    if ratio >= 0.85 { return 50 }
    return 100
  }

  /// 0 when rhr <= baseline+3 bpm, 50 when +3..+7, 100 above +7. nil inputs → nil.
  public static func restingHRScore(lastNight: Double?, baseline: Double?) -> Double? {
    guard let lastNight, let baseline else { return nil }
    let delta = lastNight - baseline
    if delta <= 3 { return 0 }
    if delta <= 7 { return 50 }
    return 100
  }

  /// max of the two when at least one exists.
  public static func cardioScore(_ i: FatigueInputs) -> Double? {
    let h = hrvScore(lastNight: i.hrvLastNight, baseline: i.hrvBaseline7d)
    let r = restingHRScore(lastNight: i.restingHRLastNight, baseline: i.restingHRBaseline7d)
    if let h, let r { return max(h, r) }
    return h ?? r
  }

  public static func score(_ i: FatigueInputs) -> Int {
    if let cardio = cardioScore(i) {
      // ponytail: cardio weight 0.20 is a guess; recalibrate against beta HRV data
      let s = 0.30 * acvrScore(acvr(i))
        + 0.20 * sorenessScore(i.soreness)
        + 0.15 * sleepDeficitScore(lastNight: i.sleepHoursLastNight, baseline: i.sleepBaseline7d)
        + 0.15 * missedRPEPenalty(missed: i.missedRPESessionsLast7d, sessions: i.sessionsLast7d)
        + 0.20 * cardio
      return Int(min(max(s, 0), 100).rounded())
    }
    let s = 0.35 * acvrScore(acvr(i))
      + 0.25 * sorenessScore(i.soreness)
      + 0.20 * sleepDeficitScore(lastNight: i.sleepHoursLastNight, baseline: i.sleepBaseline7d)
      + 0.20 * missedRPEPenalty(missed: i.missedRPESessionsLast7d, sessions: i.sessionsLast7d)
    return Int(min(max(s, 0), 100).rounded())
  }

  public static func shouldDeloadEarly(recentScores: [Int]) -> Bool {
    recentScores.count >= 2 && recentScores.suffix(2).allSatisfy { $0 >= 80 }
  }

  public static func action(forScore s: Int) -> FatigueAction {
    switch s {
    case ..<40: return .proceed
    case ..<60: return .reduceOptionalSets(by: 1)
    case ..<80: return .lightSession(volumeMultiplier: 0.7, rpeCap: 7)
    default: return .forceRest
    }
  }

  /// A night under 6 h trims optional sets even when the score alone says proceed.
  public static func action(forScore s: Int, sleepHoursLastNight: Double) -> FatigueAction {
    let scored = action(forScore: s)
    guard scored == .proceed, sleepHoursLastNight > 0, sleepHoursLastNight < 6 else { return scored }
    return .reduceOptionalSets(by: 1)
  }
}
