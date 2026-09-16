import Foundation

public struct WeeklyReview: Equatable {
  public var week: Int
  public var sessionsDone: Int
  public var sessionsPlanned: Int
  public var tonnageKg: Double
  public var priorTonnageKg: Double?
  public var prs: [String]
  public var nextWeekNote: String

  public init(week: Int, sessionsDone: Int, sessionsPlanned: Int, tonnageKg: Double, priorTonnageKg: Double?, prs: [String], nextWeekNote: String) {
    self.week = week
    self.sessionsDone = sessionsDone
    self.sessionsPlanned = sessionsPlanned
    self.tonnageKg = tonnageKg
    self.priorTonnageKg = priorTonnageKg
    self.prs = prs
    self.nextWeekNote = nextWeekNote
  }
}

public enum WeeklyReviewBuilder {
  private static func tonnageText(_ kg: Double, usesLb: Bool) -> String {
    let v = usesLb ? Plates.kgToLb(kg) : kg
    return v.rounded().formatted(.number.precision(.fractionLength(0...0)).grouping(.automatic))
  }

  private static func unit(_ usesLb: Bool) -> String { usesLb ? "lb" : "kg" }

  public static func headline(_ r: WeeklyReview, usesLb: Bool) -> String {
    String(localized: "Week \(r.week) done: \(r.sessionsDone)/\(r.sessionsPlanned) sessions.", bundle: .module)
  }

  public static func lines(_ r: WeeklyReview, usesLb: Bool) -> [String] {
    let u = unit(usesLb)
    if let prior = r.priorTonnageKg {
      let pct = String(format: "%+.0f %%", (r.tonnageKg - prior) / prior * 100)
      return [
        String(localized: "Tonnage \(tonnageText(r.tonnageKg, usesLb: usesLb)) \(u), \(pct) vs week \(r.week - 1).", bundle: .module),
        r.prs.isEmpty
          ? String(localized: "No PRs this week — normal in an accumulation week.", bundle: .module)
          : String(localized: "PRs: \(r.prs.joined(separator: ", ")).", bundle: .module),
        r.nextWeekNote,
      ]
    }
    return [
      String(localized: "Tonnage \(tonnageText(r.tonnageKg, usesLb: usesLb)) \(u).", bundle: .module),
      r.prs.isEmpty
        ? String(localized: "No PRs this week — normal in an accumulation week.", bundle: .module)
        : String(localized: "PRs: \(r.prs.joined(separator: ", ")).", bundle: .module),
      r.nextWeekNote,
    ]
  }
}
