public enum WarmUp {
  /// Percentage-of-working-load ramp, empty when the working load is too close to the empty bar.
  public static func ramp(workingKg: Double, barKg: Double, incrementKg: Double) -> [(kg: Double, reps: Int)] {
    guard workingKg > barKg * 1.5 else { return [] }
    var out: [(kg: Double, reps: Int)] = []
    for (fraction, reps) in zip([0.4, 0.6, 0.8], [8, 5, 3]) {
      let kg = Progression.round(workingKg * fraction, toIncrement: incrementKg)
      guard kg > barKg, kg < workingKg, kg != out.last?.kg else { continue }
      out.append((kg, reps))
    }
    return out
  }
}
