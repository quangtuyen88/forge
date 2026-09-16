import Foundation
import ForgeCore
#if canImport(FoundationModels)
import FoundationModels
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

  static func answer(_ question: String, context: String, coachName: String) async -> String? {
    #if canImport(FoundationModels)
    guard #available(iOS 26, *), isAvailable else { return nil }
    do {
      let tone = coachName == "Kai"
        ? "Tone: warm, high energy, direct, still concise."
        : "Tone: calm, precise, short sentences."
      let session = LanguageModelSession(instructions: """
        You are \(coachName), a strength coach inside the Regulift app.
        Answer only about the user's training: programming, load/volume, exercise swaps, deloads, fatigue. Refuse medical, injury-rehab, nutrition-for-conditions and supplement-dosing questions with one sentence pointing to a professional. Be concise.
        \(tone)
        Answer in at most three sentences, use only the numbers in the context, never invent numbers, no ACTION lines.
        """)
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
}
