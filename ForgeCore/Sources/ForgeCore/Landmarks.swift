public struct VolumeLandmarks: Equatable, Sendable {
  public let mv, mev, mavLow, mavHigh, mrv: Int

  public static func base(for muscle: Muscle) -> VolumeLandmarks? {
    landmarks(for: muscle, recoveryReduced: false)
  }

  public static func landmarks(for muscle: Muscle, recoveryReduced: Bool) -> VolumeLandmarks? {
    let l: VolumeLandmarks
    switch muscle {
    case .chest: l = VolumeLandmarks(mv: 6, mev: 8, mavLow: 12, mavHigh: 16, mrv: 20)
    case .back: l = VolumeLandmarks(mv: 8, mev: 10, mavLow: 14, mavHigh: 18, mrv: 22)
    case .quads: l = VolumeLandmarks(mv: 6, mev: 8, mavLow: 12, mavHigh: 14, mrv: 18)
    case .hamstrings: l = VolumeLandmarks(mv: 4, mev: 6, mavLow: 10, mavHigh: 12, mrv: 16)
    case .glutes: l = VolumeLandmarks(mv: 4, mev: 6, mavLow: 10, mavHigh: 14, mrv: 16)
    case .sideDelts: l = VolumeLandmarks(mv: 6, mev: 8, mavLow: 14, mavHigh: 18, mrv: 22)
    case .rearDelts: l = VolumeLandmarks(mv: 4, mev: 6, mavLow: 10, mavHigh: 14, mrv: 18)
    case .triceps: l = VolumeLandmarks(mv: 4, mev: 6, mavLow: 10, mavHigh: 12, mrv: 16)
    case .biceps: l = VolumeLandmarks(mv: 4, mev: 6, mavLow: 10, mavHigh: 14, mrv: 18)
    case .calves: l = VolumeLandmarks(mv: 6, mev: 8, mavLow: 12, mavHigh: 14, mrv: 18)
    case .abs: l = VolumeLandmarks(mv: 4, mev: 6, mavLow: 10, mavHigh: 12, mrv: 16)
    case .frontDelts, .forearms: return nil
    }
    guard recoveryReduced else { return l }
    return VolumeLandmarks(mv: l.mv, mev: l.mev, mavLow: l.mavLow, mavHigh: l.mavHigh, mrv: Int((Double(l.mrv) * 0.85).rounded()))
  }

  /// Weekly sets the plan never goes below: MV when recovery-limited, else MEV.
  public func floor(recoveryReduced: Bool) -> Int { recoveryReduced ? mv : mev }
}
