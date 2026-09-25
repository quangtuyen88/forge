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
    if input.recoveryReduced { lines.append(String(localized: "Recovery-limited: weekly sets lowered about 15 %", bundle: L10n.bundle)) }
    lines.append(String(localized: "\(input.sessionLength.rawValue)-min sessions: up to \(input.sessionLength.maxExercises) exercises a day", bundle: L10n.bundle))
    switch input.goal {
    case .hypertrophy: lines.append(String(localized: "Hypertrophy: compounds 8–12, isolation 12–15", bundle: L10n.bundle))
    case .strength: lines.append(String(localized: "Strength: compounds 4–6, isolation 8–12", bundle: L10n.bundle))
    case .both: lines.append(String(localized: "Size and strength: compounds 6–10, isolation 10–15", bundle: L10n.bundle))
    }
    return lines
  }

  /// Exercise changes between two setups over the same week: "Face Pull → Rear Delt Fly", "− X", "+ Y".
  static func exerciseSwaps(before: ProfileInput, after: ProfileInput) -> [String] {
    var swaps: [String] = []
    for (old, new) in zip(Program.week(1, profile: before), Program.week(1, profile: after)) {
      let oldIDs = Set(old.exercises.map(\.exercise.id))
      let newIDs = Set(new.exercises.map(\.exercise.id))
      let removed = old.exercises.map(\.exercise).filter { !newIDs.contains($0.id) }
      let added = new.exercises.map(\.exercise).filter { !oldIDs.contains($0.id) }
      for i in 0..<max(removed.count, added.count) {
        let from = i < removed.count ? removed[i] : nil
        let to = i < added.count ? added[i] : nil
        let swap: String
        if let from, let to {
          swap = "\(from.localizedName) → \(to.localizedName)"
        } else if let from {
          swap = "− \(from.localizedName)"
        } else if let to {
          swap = "+ \(to.localizedName)"
        } else {
          continue
        }
        if !swaps.contains(swap) { swaps.append(swap) }
      }
    }
    return swaps
  }
}
