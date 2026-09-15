import Foundation

/// Locale-aware number formatting for every user-facing numeric string.
enum Fmt {
  /// Locale decimal separator, no grouping, ≤ max fraction digits, trailing zeros dropped: 80 → "80", 47.5 → "47,5" (de).
  static func num(_ v: Double, max: Int = 1) -> String {
    v.formatted(.number.precision(.fractionLength(0...max)).grouping(.never))
  }

  /// Rounded, no grouping.
  static func int(_ v: Double) -> String {
    v.rounded().formatted(.number.precision(.fractionLength(0...0)).grouping(.never))
  }

  /// Rounded with locale grouping: 2800 → "2.800" (de) / "2,800" (en).
  static func grouped(_ v: Double) -> String {
    v.rounded().formatted(.number.precision(.fractionLength(0...0)).grouping(.automatic))
  }

  /// num(v) + unit suffix.
  static func kg(_ v: Double, lb: Bool) -> String {
    num(v) + (lb ? " lb" : " kg")
  }
}
