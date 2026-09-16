import SwiftUI
import ForgeCore

struct Adjustment: Identifiable {
  enum Kind { case newVariant, decrease, increase, addReps, firstTime, repeatLoad }
  let exercise: Exercise
  let kind: Kind
  let detail: String
  var id: String { exercise.id }

  var symbol: String {
    switch kind {
    case .newVariant: "sparkles"
    case .decrease: "arrow.down.right"
    case .increase: "arrow.up.right"
    case .addReps: "plus"
    case .firstTime: "flag.fill"
    case .repeatLoad: "equal"
    }
  }

  var tint: Color {
    switch kind {
    case .newVariant: Theme.accent
    case .decrease: Theme.negative
    case .increase: Theme.positive
    case .addReps: Theme.accent
    case .firstTime: Theme.textSecondary
    case .repeatLoad: Theme.textTertiary
    }
  }
}

private extension Adjustment.Kind {
  var priority: Int {
    switch self {
    case .newVariant: 0
    case .decrease: 1
    case .increase: 2
    case .addReps: 3
    case .firstTime: 4
    case .repeatLoad: 5
    }
  }
}

func lastSets(_ exerciseID: String, in sessions: [WorkoutSession]) -> [LoggedSet] {
  for s in sessions.filter(\.completed).sorted(by: { $0.date > $1.date }) {
    let sets = s.sets.filter { $0.exerciseID == exerciseID }.sorted { $0.setIndex < $1.setIndex }
    if !sets.isEmpty { return sets }
  }
  return []
}

func adjustments(for day: PlannedDay, base: PlannedDay?, sessions: [WorkoutSession], profile: UserProfile?, usesLb: Bool) -> [Adjustment] {
  let baseIDs = Set(base?.exercises.map(\.exercise.id) ?? [])
  let dayIDs = Set(day.exercises.map(\.exercise.id))
  var out: [Adjustment] = []
  for planned in day.exercises {
    let lb = profile?.isLb(for: planned.exercise.id) ?? usesLb
    let unit = lb ? "lb" : "kg"
    func display(_ kg: Double) -> String {
      (lb ? Plates.kgToLb(kg) : kg).formatted(.number.precision(.fractionLength(0...1)))
    }
    let last = lastSets(planned.exercise.id, in: sessions)
    if base != nil, !baseIDs.contains(planned.exercise.id) {
      if let swappedFrom = profile?.exerciseOverrides.first(where: { $0.value == planned.exercise.id })?.key,
         let oldName = ExerciseDB.find(swappedFrom)?.name {
        out.append(Adjustment(
          exercise: planned.exercise,
          kind: .newVariant,
          detail: String(localized: "Replaces \(oldName) · your swap")))
      } else {
        let replaced = base?.exercises.first { $0.exercise.primary == planned.exercise.primary && !dayIDs.contains($0.exercise.id) }
        out.append(Adjustment(
          exercise: planned.exercise,
          kind: .newVariant,
          detail: replaced.map { String(localized: "Replaces \($0.exercise.name) · e1RM flat 3 weeks") } ?? String(localized: "New variant · e1RM flat 3 weeks")))
      }
      continue
    }
    if last.isEmpty {
      let kg = suggestedStartKg(for: planned, last: [], profile: profile)
      out.append(Adjustment(exercise: planned.exercise, kind: .firstTime, detail: String(localized: "First time · start \(display(kg)) \(unit)")))
      continue
    }
    let lastSet = last.last!
    let newKg = suggestedStartKg(for: planned, last: last, profile: profile)
    let delta = (lb ? Plates.kgToLb(newKg - lastSet.weightKg) : newKg - lastSet.weightKg)
      .formatted(.number.precision(.fractionLength(0...1)))
    let rpe = String(format: "%g", lastSet.rpe)
    let target = String(format: "%g", lastSet.targetRPE)
    let logs = last.map { SetLog(weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe) }
    let lo = planned.repRange.lowerBound
    let hi = planned.repRange.upperBound
    let kind: Adjustment.Kind
    let detail: String
    if Progression.shouldIncreaseLoad(sets: logs, repRange: planned.repRange, targetRPE: planned.targetRPE) {
      kind = .increase
      detail = String(localized: "+\(delta) \(unit) · top of \(lo)–\(hi) on every set")
    } else {
      switch Progression.nextLoad(currentKg: lastSet.weightKg, targetRPE: lastSet.targetRPE, actualRPE: lastSet.rpe) {
      case .increase where newKg - lastSet.weightKg > 0:
        kind = .increase
        detail = String(localized: "+\(delta) \(unit) · last RPE \(rpe) vs target \(target)")
      case .increase:
        kind = .repeatLoad
        detail = String(localized: "Repeat \(display(newKg)) \(unit) · rounded to your plates")
      case .addReps:
        kind = .addReps
        detail = String(localized: "Same load · add a rep, RPE on target")
      case .repeatLoad:
        kind = .repeatLoad
        detail = String(localized: "Repeat \(display(newKg)) \(unit) · RPE \(rpe) a touch high")
      case .decrease:
        kind = .decrease
        detail = String(localized: "\(delta) \(unit) · RPE \(rpe), fatigue flagged")
      }
    }
    out.append(Adjustment(exercise: planned.exercise, kind: kind, detail: detail))
  }
  return out.sorted { $0.kind.priority < $1.kind.priority }
}

func weekLine(week: Int, earlyDeload: Bool = false) -> String {
  if earlyDeload { return String(localized: "Early deload · two red days in a row") }
  if week == Mesocycle.deloadWeek { return String(localized: "Deload · half the sets, RPE ≤ 6") }
  if week == 1 { return String(localized: "Week 1 · starting at minimum effective volume") }
  return String(localized: "Week \(week) of \(Mesocycle.weeks) · volume ramps toward MAV")
}

struct VolumeNote: Identifiable {
  let muscle: Muscle
  let delta: Int
  var id: Muscle { muscle }

  var title: String {
    String(localized: "\(muscle.a11yName) volume")
  }

  var detail: String {
    delta > 0
      ? String(localized: "+1 set this week · top of the range on every set last week")
      : String(localized: "−1 set this week · RPE ran over target last week")
  }
}

func volumeNotes(_ delta: [Muscle: Int], day: PlannedDay) -> [VolumeNote] {
  let primaries = Set(day.exercises.map(\.exercise.primary))
  return delta
    .filter { primaries.contains($0.key) }
    .map { VolumeNote(muscle: $0.key, delta: $0.value) }
    .sorted { $0.muscle.rawValue < $1.muscle.rawValue }
}
