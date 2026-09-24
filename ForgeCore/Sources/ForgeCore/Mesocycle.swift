public enum Mesocycle {
  public static let weeks = 6
  public static let maxSetsPerSlot = 8
  public static let deloadWeek = 6
  public static let deloadVolumeMultiplier = 0.5
  public static let deloadIntensityMultiplier = 0.65
  public static let deloadRPECap = 6.0

  /// The block offset that keeps the program week when days per week changes; an edit never advances or rewinds the week.
  public static func rebasedOffset(sessionsDone: Int, offset: Int, fromDays: Int, toDays: Int) -> Int {
    let from = max(fromDays, 1)
    let to = max(toDays, 1)
    if from == to { return offset }
    let counted = max(0, sessionsDone + offset)
    let week = counted / from
    let within = counted % from
    let newCounted = week * to + min(within, to - 1)
    return newCounted - sessionsDone
  }

  public static func targetSets(muscle: Muscle, week: Int, recoveryReduced: Bool) -> Int? {
    guard let l = VolumeLandmarks.landmarks(for: muscle, recoveryReduced: recoveryReduced),
          (1...weeks).contains(week) else { return nil }
    let step = min(max((l.mavLow - l.mev + 3) / 4, 1), 2)
    let week5 = min(l.mev + 4 * step, l.mrv)
    if week == deloadWeek { return Int((Double(week5) * deloadVolumeMultiplier).rounded()) }
    let target = min(l.mev + (week - 1) * step, l.mrv)
    // Recovery-limited: about 15 % fewer weekly sets, never below maintenance volume.
    return recoveryReduced ? max(l.mv, Int((Double(target) * 0.85).rounded())) : target
  }
}
