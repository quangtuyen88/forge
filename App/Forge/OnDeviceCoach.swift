import Foundation
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, *)
@Generable
private struct SetDraft {
  @Guide(description: "Exercise name copied from the list, or empty") var exercise: String
  @Guide(description: "Weight number only", .range(0...1000)) var weight: Double
  @Guide(description: "kg or lb when the lifter says it", .anyOf(["kg", "lb", ""])) var unit: String
  @Guide(.range(1...100)) var reps: Int
  @Guide(description: "RPE 5 to 10 when given, else 0", .range(0...10)) var rpe: Double
}
#endif

/// Foundation Models (iOS 26) explanations; silently unavailable below iOS 26 or without a ready model.
enum OnDeviceCoach {
  static var isAvailable: Bool {
    #if canImport(FoundationModels)
    if #available(iOS 26, *) {
      return SystemLanguageModel.default.availability == .available
    }
    #endif
    return false
  }

  static func explain(_ a: Adjustment, coachName: String, week: Int, lastSets: [LoggedSet], usesLb: Bool) async -> String? {
    let unit = usesLb ? "lb" : "kg"
    let kind: String
    switch a.kind {
    case .newVariant: kind = "new variant"
    case .decrease: kind = "load decrease"
    case .increase: kind = "load increase"
    case .addReps: kind = "add a rep"
    case .firstTime: kind = "first time"
    case .repeatLoad: kind = "repeat load"
    }
    var facts = [
      "Exercise: \(a.exercise.name)",
      "Adjustment (\(kind)): \(a.detail)",
    ]
    if !lastSets.isEmpty {
      let sets = lastSets.map { s in
        String(format: "%.1f %@ × %d @ RPE %g", usesLb ? Plates.kgToLb(s.weightKg) : s.weightKg, unit, s.reps, s.rpe)
      }
      facts.append("Last session sets: " + sets.joined(separator: ", "))
    }
    facts.append("Week \(week) of \(Mesocycle.weeks)")
    return await answer(
      "Explain today's adjustment to the lifter.",
      context: facts.joined(separator: "\n"),
      coachName: coachName)
  }

  static func wantsChange(_ question: String) -> Bool {
    let triggers = [
      "swap", "replace", "switch", "instead of", "change", "deload", "skip", "missed", "miss",
      "restart", "cover", "交換", "入れ替え", "替換", "替换", "变更", "更换", "減載", "减载",
      "ディロード", "교체", "바꿔", "디로드", "đổi", "thay", "giảm tải",
    ]
    let q = question.lowercased()
    return triggers.contains { q.contains($0) }
  }

  /// Turns a spoken or typed sentence into a quick-log draft using the on-device model.
  static func parseQuickLog(_ text: String, candidateNames: [String], defaultLb: Bool) async -> QuickLogDraft? {
    #if canImport(FoundationModels)
    guard #available(iOS 26, *), isAvailable else { return nil }
    do {
      let instructions = "You turn a lifter's spoken or typed sentence into one strength set. Pick the exercise from this list only, copy its name exactly: \(candidateNames.joined(separator: ", ")). Numbers may be words ('one thirty two and a half' = 132.5). 'at 8' or 'RPE 8' is the rpe; rpe is 0 unless the lifter says 'at N' or 'RPE N'. If no exercise from the list is mentioned, use an empty exercise."
      let session = LanguageModelSession(instructions: instructions)
      let response = try await session.respond(to: text, generating: SetDraft.self)
      let draft = response.content
      let exercise = draft.exercise.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !exercise.isEmpty else { return nil }
      let unitRaw = draft.unit.trimmingCharacters(in: .whitespacesAndNewlines)
      let unit: String? = unitRaw.isEmpty ? nil : unitRaw
      let rpe: Double? = draft.rpe == 0 ? nil : draft.rpe
      return QuickLogDraft(exercise: exercise, weight: draft.weight, unit: unit, reps: draft.reps, rpe: rpe)
    } catch {
      #if DEBUG
      print("on-device quick log:", error)
      #endif
      return nil
    }
    #else
    return nil
    #endif
  }

  private static var replyLanguage: String? {
    switch CoachAPI.languageCode {
    case "ja": return "Japanese"
    case "ko": return "Korean"
    case "zh", "zh-Hans": return "Simplified Chinese"
    case "vi": return "Vietnamese"
    default: return nil
    }
  }

  static func answer(_ question: String, context: String, coachName: String) async -> String? {
    #if canImport(FoundationModels)
    guard #available(iOS 26, *), isAvailable else { return nil }
    do {
      let tone = coachName == "Kai"
        ? "Tone: warm, high energy, direct, still concise."
        : "Tone: calm, precise, short sentences."
      var instructions = """
        You are \(coachName), a strength coach inside the Regulift app.
        Answer only about the user's training: programming, load/volume, exercise swaps, deloads, fatigue. Refuse medical, injury-rehab, nutrition-for-conditions and supplement-dosing questions with one sentence pointing to a professional. Be concise.
        \(tone)
        Answer in at most three sentences, use only the numbers in the context, never invent numbers, no ACTION lines.
        """
      if let name = replyLanguage {
        instructions += "\nReply in \(name)."
      }
      let session = LanguageModelSession(instructions: instructions)
      let response = try await session.respond(to: "\(question)\n\n\(context)")
      let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty ? nil : text
    } catch {
      return nil
    }
    #else
    return nil
    #endif
  }

  /// On-device answer with tool calling; returns the prose answer plus any proposed plan change.
  @MainActor
  static func answer(_ question: String, context: String, coachName: String, tools box: CoachToolBox) async -> (text: String, action: CoachAction?)? {
    #if canImport(FoundationModels)
    guard #available(iOS 26, *), isAvailable else { return nil }
    do {
      let tone = coachName == "Kai"
        ? "Tone: warm, high energy, direct, still concise."
        : "Tone: calm, precise, short sentences."
      var instructions = """
        You are \(coachName), a strength coach inside the Regulift app.
        Answer only about the user's training: programming, load/volume, exercise swaps, deloads, fatigue. Refuse medical, injury-rehab, nutrition-for-conditions and supplement-dosing questions with one sentence pointing to a professional. Be concise.
        \(tone)
        Answer in at most three sentences, use only the numbers in the context, never invent numbers, no ACTION lines.
        Use a tool when the lifter asks to swap an exercise, deload early, or restart the block after a missed week. When the lifter asks to swap but does not name the exercise, ask in one sentence which planned exercise to replace (list the planned names from the training data). When the lifter names the exercise to replace, pick a suitable replacement yourself from the context's exercise ids (same movement pattern, respect injury flags) unless they named one, say the swap in one sentence, and call the swap tool. When the lifter states a lasting fact about themselves, their gym or their schedule (home gym, missing equipment, a sore joint, travel), call the remember tool even if no question is asked. Otherwise answer in prose. After a tool call, say in one sentence what you proposed and that the lifter confirms it below; never claim the change is already made.
        """
      if let name = replyLanguage {
        instructions += "\nReply in \(name)."
      }
      let session = LanguageModelSession(
        tools: [SwapExerciseTool(box: box), EarlyDeloadTool(box: box), RestartBlockTool(box: box), RememberTool(box: box)],
        instructions: instructions)
      let response = try await session.respond(to: "\(question)\n\n\(context)")
      let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty ? nil : (text, box.proposed)
    } catch {
      #if DEBUG
      print("on-device coach (tools):", error)
      #endif
      return nil
    }
    #else
    return nil
    #endif
  }
}
