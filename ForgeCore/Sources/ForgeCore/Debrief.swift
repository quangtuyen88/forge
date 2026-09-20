import Foundation

public struct DebriefSet {
  public var exercise: String
  public var weightKg: Double
  public var reps: Int
  /// The effort value stored on the set. When `effortReported` is false this is the plan's
  /// target sitting in the field, not something the lifter told us.
  public var rpe: Double
  public var targetRPE: Double
  /// True only when the lifter actually reported effort — a tap on the RPE stepper, a typed
  /// `@8`, a Watch payload that carried one. A prescribed target must never be read back as
  /// an observation: "RPE on target" about sets nobody rated is a claim the log cannot make.
  public var effortReported: Bool

  public init(
    exercise: String, weightKg: Double, reps: Int, rpe: Double, targetRPE: Double,
    effortReported: Bool = false
  ) {
    self.exercise = exercise
    self.weightKg = weightKg
    self.reps = reps
    self.rpe = rpe
    self.targetRPE = targetRPE
    self.effortReported = effortReported
  }

  /// The effort the lifter reported, or nothing.
  public var reportedRPE: Double? { effortReported ? rpe : nil }
}

public struct DebriefPR {
  public var exercise: String
  public var e1RM: Double
  public var priorE1RM: Double?

  public init(exercise: String, e1RM: Double, priorE1RM: Double?) {
    self.exercise = exercise
    self.e1RM = e1RM
    self.priorE1RM = priorE1RM
  }
}

public struct DebriefNext {
  public var exercise: String
  public var kg: Double
  public var deltaKg: Double

  public init(exercise: String, kg: Double, deltaKg: Double) {
    self.exercise = exercise
    self.kg = kg
    self.deltaKg = deltaKg
  }
}

public struct DebriefLine: Equatable {
  public enum Kind: Equatable { case result, effort, next }
  public var kind: Kind
  public var text: String

  public init(kind: Kind, text: String) {
    self.kind = kind
    self.text = text
  }
}

public enum Debrief {
  private static func weightText(_ kg: Double, usesLb: Bool) -> String {
    let v = usesLb ? Plates.kgToLb(kg) : kg
    return v.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
  }

  private static func tonnageText(_ kg: Double, usesLb: Bool) -> String {
    let v = usesLb ? Plates.kgToLb(kg) : kg
    return v.rounded().formatted(.number.precision(.fractionLength(0...0)).grouping(.automatic))
  }

  private static func unit(_ usesLb: Bool) -> String { usesLb ? "lb" : "kg" }

  private static func deltaMarker(_ deltaKg: Double, usesLb: Bool) -> String {
    let d = usesLb ? Plates.kgToLb(deltaKg) : deltaKg
    if abs(d) < 0.05 { return "(=)" }
    let v = abs(d).formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    return d > 0 ? "(+\(v))" : "(−\(v))"
  }

  public static func lines(sets: [DebriefSet], prs: [DebriefPR], tonnageKg: Double, priorTonnageKg: Double?, dayName: String, next: [DebriefNext], usesLb: Bool) -> [DebriefLine] {
    var out: [DebriefLine] = []

    if let pr = prs.first {
      if let prior = pr.priorE1RM {
        out.append(DebriefLine(
          kind: .result,
          text: String(localized: "PR: \(pr.exercise) e1RM \(weightText(prior, usesLb: usesLb)) → \(weightText(pr.e1RM, usesLb: usesLb)) \(unit(usesLb)).", bundle: ForgeCoreResources.bundle)))
      } else {
        out.append(DebriefLine(
          kind: .result,
          text: String(localized: "First e1RM on record for \(pr.exercise): \(weightText(pr.e1RM, usesLb: usesLb)) \(unit(usesLb)).", bundle: ForgeCoreResources.bundle)))
      }
    } else if let prior = priorTonnageKg {
      let pct = String(format: "(%+.0f %%)", (tonnageKg - prior) / prior * 100)
      out.append(DebriefLine(
        kind: .result,
        text: String(localized: "Tonnage \(tonnageText(tonnageKg, usesLb: usesLb)) \(unit(usesLb)) vs \(tonnageText(prior, usesLb: usesLb)) \(unit(usesLb)) last \(dayName) \(pct).", bundle: ForgeCoreResources.bundle)))
    } else {
      out.append(DebriefLine(
        kind: .result,
        text: String(localized: "First \(dayName) on record: \(tonnageText(tonnageKg, usesLb: usesLb)) \(unit(usesLb)).", bundle: ForgeCoreResources.bundle)))
    }

    // Only reported effort can support a statement about effort. Sets the lifter never
    // rated are counted as coverage, not folded into an average that reads like a report.
    let rated = sets.filter(\.effortReported)
    if rated.isEmpty {
      out.append(DebriefLine(
        kind: .effort,
        text: sets.isEmpty
          ? String(localized: "No sets recorded.", bundle: ForgeCoreResources.bundle)
          : String(localized: "Effort not recorded for these \(sets.count) sets.", bundle: ForgeCoreResources.bundle)))
    } else {
      let drift = rated.reduce(0.0) { $0 + ($1.rpe - $1.targetRPE) } / Double(rated.count)
      let over = rated.filter { $0.rpe - $0.targetRPE >= 0.5 }.count
      let coverage = rated.count == sets.count
        ? ""
        : " " + String(localized: "RPE recorded for \(rated.count) of \(sets.count) sets.", bundle: ForgeCoreResources.bundle)
      if drift >= 0.5 {
        out.append(DebriefLine(
          kind: .effort,
          text: String(localized: "RPE ran \(String(format: "%.1f", drift)) over target on \(over) of \(rated.count) sets — loads were heavy.", bundle: ForgeCoreResources.bundle) + coverage))
      } else if drift <= -0.5 {
        out.append(DebriefLine(
          kind: .effort,
          text: String(localized: "RPE \(String(format: "%.1f", abs(drift))) under target — room to add load.", bundle: ForgeCoreResources.bundle) + coverage))
      } else {
        out.append(DebriefLine(
          kind: .effort,
          text: String(localized: "RPE on target across \(rated.count) sets.", bundle: ForgeCoreResources.bundle) + coverage))
      }
    }

    if next.isEmpty {
      out.append(DebriefLine(
        kind: .next,
        text: String(localized: "Next \(dayName): loads adapt from these sets.", bundle: ForgeCoreResources.bundle)))
    } else {
      let entries = next.prefix(3).map { n in
        "\(n.exercise) \(weightText(n.kg, usesLb: usesLb)) \(unit(usesLb)) \(deltaMarker(n.deltaKg, usesLb: usesLb))"
      }.joined(separator: ", ")
      out.append(DebriefLine(
        kind: .next,
        text: String(localized: "Next \(dayName): \(entries).", bundle: ForgeCoreResources.bundle)))
    }

    return out
  }
}
