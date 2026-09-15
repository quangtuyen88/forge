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
        let line = flag.map { "\($0.rawValue.capitalized) flag: \(pa.exercise.name) replaces \(pb.exercise.name)" }
          ?? "Your gym: \(pa.exercise.name) instead of \(pb.exercise.name)"
        if !lines.contains(line) { lines.append(line) }
      }
    }
    if input.recoveryReduced { lines.append("Recovery-limited: weekly max sets lowered 15 %") }
    lines.append("\(input.sessionLength.rawValue)-min sessions: up to \(input.sessionLength.maxExercises) exercises a day")
    switch input.goal {
    case .hypertrophy: lines.append("Hypertrophy: compounds 8–12, isolation 12–15")
    case .strength: lines.append("Strength: compounds 4–6, isolation 8–12")
    case .both: lines.append("Size and strength: compounds 6–10, isolation 10–15")
    }
    return lines
  }
}
