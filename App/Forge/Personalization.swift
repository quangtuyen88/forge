import ForgeCore

enum Personalization {
  /// Lines explaining why week 1 looks the way it does: real diffs against an unconstrained plan, then recovery, session length, goal.
  static func lines(for input: ProfileInput) -> [String] {
    var lines: [String] = []
    var baseline = input
    baseline.equipment = Set(Equipment.allCases)
    baseline.injuryFlags = []
    baseline.recoveryReduced = false
    let mine = Program.week(1, profile: input)
    let base = Program.week(1, profile: baseline)
    for (a, b) in zip(mine, base) where a.exercises.count == b.exercises.count {
      for (pa, pb) in zip(a.exercises, b.exercises) where pa.exercise.id != pb.exercise.id {
        let flag = InjuryFlag.allCases.first {
          input.injuryFlags.contains($0) && Substitution.replacement(for: pb.exercise.id, flags: [$0]) == pa.exercise.id
        }
        let line = flag.map { String(localized: "\($0.rawValue.capitalized) flag: \(pa.exercise.localizedName) replaces \(pb.exercise.localizedName)", bundle: L10n.bundle) }
          ?? String(localized: "Your gym: \(pa.exercise.localizedName) instead of \(pb.exercise.localizedName)", bundle: L10n.bundle)
        if !lines.contains(line) { lines.append(line) }
      }
    }
    if input.recoveryReduced { lines.append(String(localized: "Recovery-limited: weekly max sets lowered 15 %", bundle: L10n.bundle)) }
    lines.append(String(localized: "\(input.sessionLength.rawValue)-min sessions: up to \(input.sessionLength.maxExercises) exercises a day", bundle: L10n.bundle))
    switch input.goal {
    case .hypertrophy: lines.append(String(localized: "Hypertrophy: compounds 8–12, isolation 12–15", bundle: L10n.bundle))
    case .strength: lines.append(String(localized: "Strength: compounds 4–6, isolation 8–12", bundle: L10n.bundle))
    case .both: lines.append(String(localized: "Size and strength: compounds 6–10, isolation 10–15", bundle: L10n.bundle))
    }
    return lines
  }
}
