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

  static func answer(_ question: String, context: String, coachName: String) async -> String? {
    #if canImport(FoundationModels)
    guard #available(iOS 26, *), isAvailable else { return nil }
    do {
      let session = LanguageModelSession(instructions: """
        You are \(coachName), a strength coach. Answer in at most two sentences. Use the numbers given. No medical claims, no guarantees, no emojis.
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
