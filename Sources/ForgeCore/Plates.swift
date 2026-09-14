public enum Plates {
  public static let defaultKg: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
  public static let defaultLb: [Double] = [45, 35, 25, 10, 5, 2.5]

  public static func perSide(target: Double, bar: Double, available: [Double]) -> [Double]? {
    guard target >= bar else { return nil }
    var remaining = (target - bar) / 2
    var plates: [Double] = []
    for plate in available.sorted(by: >) {
      while remaining >= plate - 0.0001 {
        plates.append(plate)
        remaining -= plate
      }
    }
    return abs(remaining) < 0.0001 ? plates : nil
  }

  public static func kgToLb(_ kg: Double) -> Double { kg * 2.20462 }
  public static func lbToKg(_ lb: Double) -> Double { lb / 2.20462 }
}
