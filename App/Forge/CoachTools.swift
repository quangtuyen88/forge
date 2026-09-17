import Foundation
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Mirrors the server's note sanitiser: trim, collapse whitespace, strip newlines,
/// cap at 140 chars, and reject notes that read like instructions rather than facts.
func sanitizeNote(_ raw: String) -> String? {
  let collapsed = raw
    .trimmingCharacters(in: .whitespacesAndNewlines)
    .split(whereSeparator: { $0.isWhitespace })
    .joined(separator: " ")
  let capped = String(collapsed.prefix(140))
  guard !capped.isEmpty else { return nil }
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

  init(exercises: [Exercise]) {
    self.exercises = exercises
  }
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
