public enum Mesocycle {
  public static let weeks = 6
  public static let maxSetsPerSlot = 8
  public static let deloadWeek = 6
  public static let deloadVolumeMultiplier = 0.5
  public static let deloadIntensityMultiplier = 0.65
  public static let deloadRPECap = 6.0

  public static func targetSets(muscle: Muscle, week: Int, recoveryReduced: Bool) -> Int? {
    guard let l = VolumeLandmarks.landmarks(for: muscle, recoveryReduced: recoveryReduced),
          (1...weeks).contains(week) else { return nil }
    let step = min(max((l.mavLow - l.mev + 3) / 4, 1), 2)
    let week5 = min(l.mev + 4 * step, l.mrv)
    if week == deloadWeek { return Int((Double(week5) * deloadVolumeMultiplier).rounded()) }
    return min(l.mev + (week - 1) * step, l.mrv)
  }
}
