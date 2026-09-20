import Foundation
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
/// Mirrors the server's note sanitiser: trim, collapse whitespace, strip newlines,
/// cap at 140 chars, and reject notes that read like instructions rather than facts.
func sanitizeNote(_ raw: String) -> String? {
  let collapsed = raw
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .split(whereSeparator: { $0.isWhitespace })
    .joined(separator: " ")
  let capped = String(collapsed.prefix(140))
  guard !capped.isEmpty, !PromptSecurity.isAttack(capped) else { return nil }
  let lower = capped.lowercased()
  let blocked = ["ignore", "disregard", "system prompt", "instruction", "act as", "jailbreak", "developer mode"]
  if blocked.contains(where: { lower.contains($0) }) { return nil }
  return capped
}

/// Shared mutable state for one on-device coach request.
@MainActor
final class CoachToolBox {
  var proposed: CoachAction?
  var exercises: [Exercise]
  /// The read side. Nil in contexts that have no store to read — the tools then answer
  /// `unavailable` instead of inventing a value.
  var reads: CoachReadSource?

  init(exercises: [Exercise], reads: CoachReadSource? = nil) {
    self.exercises = exercises
    self.reads = reads
  }
}

/// What the read tools are allowed to see. Deliberately four bounded projections and a plan
/// identity — not the store. A tool cannot reach past this into check-ins, Health values or
/// another profile, because there is nothing here to reach with.
@MainActor
protocol CoachReadSource {
  var planRevision: String { get }
  func currentWorkout() -> CoachEnvelope<CurrentWorkoutProjection>
  func decision(id: String) -> CoachEnvelope<DecisionProjection>
  func recentSets(exerciseID: String, limit: Int) -> CoachEnvelope<[RecentSetProjection]>
  func constraints() -> CoachEnvelope<ConstraintsProjection>
}

/// One envelope rendered for a model turn: status first, then the facts, then the plan it
/// was true for. A model that reads "not_shared" cannot reconstruct what was withheld, and
/// a model that reads "stale" is told so rather than answering from an old plan.
func renderEnvelope(_ status: CoachReadStatus, asOf: Date, planRevision: String, lines: [String]) -> String {
  var out = [
    "schema_version: \(CoachEnvelope<String>.currentSchemaVersion)",
    "status: \(status.rawValue)",
    "source: local_engine_projection",
    "plan_revision: \(planRevision)",
  ]
  out.append("as_of: \(ISO8601DateFormatter().string(from: asOf))")
  out.append(contentsOf: lines)
  return out.joined(separator: "\n")
}

#if canImport(FoundationModels)

private func normalizedName(_ s: String) -> String {
  let lower = s.lowercased()
  var out = ""
  out.reserveCapacity(lower.count)
  for ch in lower {
    if ch.isLetter || ch.isNumber || ch == " " {
      out.append(ch)
    } else {
      out.append(" ")
    }
  }
  return out
}

/// Resolves an exercise name against the full database: normalized exact name, else prefix match on words.
private func resolveExercise(_ raw: String) -> Exercise? {
  let input = normalizedName(raw).trimmingCharacters(in: .whitespaces)
  guard !input.isEmpty else { return nil }
  let all = ExerciseDB.everything
  if let exact = all.first(where: { normalizedName($0.name) == input }) { return exact }
  let words = input.split(separator: " ").map(String.init)
  guard !words.isEmpty else { return nil }
  for candidate in all {
    let nameWords = normalizedName(candidate.name).split(separator: " ").map(String.init)
    var remaining = nameWords
    var matched = true
    for word in words {
      guard let index = remaining.firstIndex(where: { $0.hasPrefix(word) }) else { matched = false; break }
      remaining.remove(at: index)
    }
    if matched { return candidate }
  }
  return nil
}

@available(iOS 26, *)
struct SwapExerciseTool: Tool {
  let box: CoachToolBox

  @available(iOS 26, *)
  @Generable
  struct Arguments {
    @Guide(description: "Name of the exercise currently in the plan to replace") var from: String
    @Guide(description: "Name of the exercise to use instead") var to: String
  }

  typealias Output = String

  var description: String {
    "Swap one planned exercise for another."
  }

  func call(arguments: Arguments) async throws -> String {
    let fromName = arguments.from.trimmingCharacters(in: .whitespacesAndNewlines)
    let toName = arguments.to.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let from = resolveExercise(fromName) else {
      return "Unknown exercise: \(fromName). Ask the lifter to pick from the plan."
    }
    guard let to = resolveExercise(toName) else {
      return "Unknown exercise: \(toName). Ask the lifter to pick from the plan."
    }
    await MainActor.run { box.proposed = .swap(from: from, to: to) }
    return "Proposed: swap \(from.name) for \(to.name). The lifter confirms in the app."
  }
}

@available(iOS 26, *)
struct EarlyDeloadTool: Tool {
  let box: CoachToolBox

  @available(iOS 26, *)
  @Generable
  struct Arguments {
    @Guide(description: "Why the lifter wants to deload early") var reason: String
  }

  typealias Output = String

  var description: String {
    "Start the deload now instead of waiting."
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments.reason
    await MainActor.run { box.proposed = .earlyDeload }
    return "Proposed: start the deload now. The lifter confirms in the app."
  }
}

@available(iOS 26, *)
struct RestartBlockTool: Tool {
  let box: CoachToolBox

  @available(iOS 26, *)
  @Generable
  struct Arguments {
    @Guide(description: "Why the lifter wants to restart the block") var reason: String
  }

  typealias Output = String

  var description: String {
    "Restart the training block from week one."
  }

  func call(arguments: Arguments) async throws -> String {
    _ = arguments.reason
    await MainActor.run { box.proposed = .restartBlock }
    return "Proposed: restart the block from week one. The lifter confirms in the app."
  }
}

@available(iOS 26, *)
struct RememberTool: Tool {
  let box: CoachToolBox

  @available(iOS 26, *)
  @Generable
  struct Arguments {
    @Guide(description: "A lasting fact to remember, up to 140 characters") var note: String
  }

  typealias Output = String

  var description: String {
    "Remember a lasting fact the lifter states about themselves, their gym or their schedule (for example: trains at home, no cable station, sore knee), even when no question is asked."
  }

  func call(arguments: Arguments) async throws -> String {
    let note = String(arguments.note.prefix(140)).trimmingCharacters(in: .whitespacesAndNewlines)
    await MainActor.run { box.proposed = .remember(note) }
    return "Noted for later: \(note)"
  }
}

#endif

// MARK: - Read tools
//
// Reads, not writes. Each one answers from a local projection and says how fresh it is; a
// missing fact comes back as its own status, never as an empty success the model can read
// as "nothing happened".

@available(iOS 26, *)
struct CurrentWorkoutTool: Tool {
  let box: CoachToolBox

  @available(iOS 26, *)
  @Generable
  struct Arguments {}

  typealias Output = String

  var description: String {
    "Read the lifter's current planned session: exercises, sets and target reps. Read-only."
  }

  func call(arguments: Arguments) async throws -> String {
    await MainActor.run {
      guard let reads = box.reads else {
        return renderEnvelope(.unavailable, asOf: .now, planRevision: PlanRevision.none, lines: [])
      }
      let envelope = reads.currentWorkout()
      guard envelope.status == .ok, let data = envelope.data else {
        return renderEnvelope(envelope.status, asOf: envelope.asOf, planRevision: envelope.planRevision, lines: [])
      }
      let lines = data.prescriptions.map { p in
        "- \(p.exerciseID): \(p.workingSets)×\(p.minimumReps)-\(p.maximumReps)"
          + (p.load.map { " @ \(String(format: "%.1f", $0.value)) \($0.unit.rawValue)" } ?? "")
      }
      return renderEnvelope(
        .ok, asOf: envelope.asOf, planRevision: envelope.planRevision,
        lines: ["day: \(data.dayName)"] + lines)
    }
  }
}

@available(iOS 26, *)
struct ProgramDecisionTool: Tool {
  let box: CoachToolBox

  @available(iOS 26, *)
  @Generable
  struct Arguments {
    @Guide(description: "The decision id to explain") var decisionID: String
  }

  typealias Output = String

  var description: String {
    "Read one already-recorded program decision. Never invent a reason that is not returned."
  }

  func call(arguments: Arguments) async throws -> String {
    let id = arguments.decisionID.trimmingCharacters(in: .whitespacesAndNewlines)
    return await MainActor.run {
      guard let reads = box.reads else {
        return renderEnvelope(.unavailable, asOf: .now, planRevision: PlanRevision.none, lines: [])
      }
      let envelope = reads.decision(id: id)
      guard envelope.status == .ok, let data = envelope.data else {
        return renderEnvelope(envelope.status, asOf: envelope.asOf, planRevision: envelope.planRevision, lines: [])
      }
      return renderEnvelope(
        .ok, asOf: envelope.asOf, planRevision: envelope.planRevision,
        lines: ["decision_id: \(data.decisionID)", "reason_code: \(data.reasonCode)", "scope: \(data.scope.rawValue)"])
    }
  }
}

@available(iOS 26, *)
struct RecentSetsTool: Tool {
  let box: CoachToolBox

  @available(iOS 26, *)
  @Generable
  struct Arguments {
    @Guide(description: "Exercise name as the lifter said it") var exercise: String
  }

  typealias Output = String

  var description: String {
    "Read the lifter's recent logged sets for one exercise. Read-only, workout facts only."
  }

  func call(arguments: Arguments) async throws -> String {
    let raw = arguments.exercise.trimmingCharacters(in: .whitespacesAndNewlines)
    return await MainActor.run {
      guard let reads = box.reads else {
        return renderEnvelope(.unavailable, asOf: .now, planRevision: PlanRevision.none, lines: [])
      }
      // "Bench" is two lifts in most catalogues: ask rather than pick one silently.
      let candidates = ExerciseDB.everything.map { (id: $0.id, name: $0.name) }
      let resolved = CoachReadContracts.resolveExercise(
        raw, candidates: candidates, asOf: .now, planRevision: reads.planRevision)
      guard resolved.status == .ok, let exerciseID = resolved.data else {
        return renderEnvelope(resolved.status, asOf: resolved.asOf, planRevision: resolved.planRevision, lines: [])
      }
      let envelope = reads.recentSets(exerciseID: exerciseID, limit: 12)
      guard envelope.status == .ok, let sets = envelope.data else {
        return renderEnvelope(envelope.status, asOf: envelope.asOf, planRevision: envelope.planRevision, lines: [])
      }
      let lines = sets.map { set in
        "- \(set.reps) reps"
          + (set.load.map { " @ \(String(format: "%.1f", $0.value)) \($0.unit.rawValue)" } ?? "")
          + (set.rpeTenths.map { " RPE \(Double($0) / 10)" } ?? "")
      }
      return renderEnvelope(
        .ok, asOf: envelope.asOf, planRevision: envelope.planRevision,
        lines: ["exercise: \(exerciseID)"] + lines)
    }
  }
}

@available(iOS 26, *)
struct ProgramConstraintsTool: Tool {
  let box: CoachToolBox

  @available(iOS 26, *)
  @Generable
  struct Arguments {}

  typealias Output = String

  var description: String {
    "Read the lifter's equipment, excluded exercises and time budget. Read-only."
  }

  func call(arguments: Arguments) async throws -> String {
    await MainActor.run {
      guard let reads = box.reads else {
        return renderEnvelope(.unavailable, asOf: .now, planRevision: PlanRevision.none, lines: [])
      }
      let envelope = reads.constraints()
      guard envelope.status == .ok, let data = envelope.data else {
        return renderEnvelope(envelope.status, asOf: envelope.asOf, planRevision: envelope.planRevision, lines: [])
      }
      var lines = ["equipment: \(data.equipmentIDs.joined(separator: ", "))"]
      if !data.excludedExerciseIDs.isEmpty {
        lines.append("excluded: \(data.excludedExerciseIDs.joined(separator: ", "))")
      }
      if let minutes = data.minutesPerSession { lines.append("minutes_per_session: \(minutes)") }
      if let days = data.daysPerWeek { lines.append("days_per_week: \(days)") }
      return renderEnvelope(.ok, asOf: envelope.asOf, planRevision: envelope.planRevision, lines: lines)
    }
  }
}

#endif
