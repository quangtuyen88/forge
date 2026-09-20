import Foundation

// MARK: - The local privacy gate
//
// Nothing reaches a model before this runs. The message is reduced to a placeholder
// sentence, the real values stay on the phone, and a message the policy cannot confidently
// reduce is never uploaded at all — it falls back to local controls.

/// One value the local parser found, replaced by a placeholder before anything is sent.
public struct SemanticSlot: Sendable, Equatable {
  public enum Kind: String, Sendable, Equatable {
    case duration
    case equipment
    case load
    case reps
    case exercise
  }

  public let kind: Kind
  /// The placeholder token that goes over the wire, e.g. `[duration_1]`.
  public let placeholder: String
  /// The real text it replaced. Stays on device.
  public let originalText: String
  /// Where it was in the original message, so the app can re-render locally.
  public let range: Range<String.Index>

  public init(kind: Kind, placeholder: String, originalText: String, range: Range<String.Index>) {
    self.kind = kind
    self.placeholder = placeholder
    self.originalText = originalText
    self.range = range
  }
}

/// Why a message may not leave the phone. Each reason routes to a local fallback, never
/// to a different cloud model.
public enum SemanticExportDenial: String, Sendable, Equatable {
  case empty
  case tooLong = "too_long"
  case sensitiveTerm = "sensitive_term"
  case unsupportedLocale = "unsupported_locale"
  case promptInjection = "prompt_injection"
}

public enum SemanticExportResult: Sendable, Equatable {
  case allowed(SemanticProjection)
  case denied(SemanticExportDenial)
}

/// Exactly what may be serialized: a placeholder message, a locale and a UI surface. No
/// user id, plan id, gym name, transcript, receipt or training value.
public struct SemanticProjection: Sendable, Equatable {
  public let message: String
  public let locale: String
  public let surface: String
  /// Local only — never encoded. Kept alongside so the app can resolve slots after routing.
  public let slots: [SemanticSlot]

  public init(message: String, locale: String, surface: String, slots: [SemanticSlot]) {
    self.message = message
    self.locale = locale
    self.surface = surface
    self.slots = slots
  }
}

public enum SemanticExportPolicy {
  /// A product bound, not a provider bound. Over-limit input asks for a shorter request
  /// rather than being truncated — cutting a sentence can remove its negation.
  public static let maxMessageBytes = 1_500

  /// Locales whose routing has actually been evaluated. English, Japanese and Korean are
  /// separate gates: passing one says nothing about the others.
  public static let evaluatedLocales: Set<String> = ["en"]

  /// Terms that mean the message is about private health, not about a workout constraint.
  /// A lifter typing their own HRV does not make it exportable, and no keyword list can
  /// prove arbitrary text is safe — this is a floor, not a guarantee.
  static let sensitiveTerms: [String] = [
    "hrv", "heart rate", "resting heart", "sleep", "slept", "readiness", "recovery score",
    "soreness", "sore", "pain", "hurts", "injury", "injured", "physio", "doctor",
    "medication", "blood pressure", "weight loss", "body fat", "bodyfat", "period",
    "pregnan", "depress", "anxiet", "sick", "illness", "fever",
    "睡眠", "疲労", "痛み", "怪我", "心拍",
    "수면", "피로", "통증", "부상", "심박",
    "giấc ngủ", "đau", "chấn thương", "nhịp tim",
  ]

  /// Reduce a message to what may be sent, or refuse.
  ///
  /// The slots are the values the LOCAL parser already resolved; they are replaced by
  /// placeholders so the provider sees the shape of the request and none of its numbers.
  public static func project(
    message: String,
    locale: String,
    surface: String,
    slots: [SemanticSlot],
    isPromptAttack: (String) -> Bool = { _ in false }
  ) -> SemanticExportResult {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .denied(.empty) }
    guard trimmed.utf8.count <= maxMessageBytes else { return .denied(.tooLong) }
    let language = locale.split(separator: "-").first.map(String.init) ?? locale
    guard evaluatedLocales.contains(language) else { return .denied(.unsupportedLocale) }
    if isPromptAttack(trimmed) { return .denied(.promptInjection) }

    let masked = mask(trimmed, slots: slots)
    // Check the masked text: masking is what the provider sees, so that is what the
    // sensitivity gate has to clear.
    let lowered = masked.lowercased()
    if sensitiveTerms.contains(where: { lowered.contains($0) }) {
      return .denied(.sensitiveTerm)
    }
    return .allowed(
      SemanticProjection(message: masked, locale: language, surface: surface, slots: slots))
  }

  /// Replace each slot text with its placeholder. Ranges are applied back to front so
  /// earlier indices stay valid.
  static func mask(_ message: String, slots: [SemanticSlot]) -> String {
    var out = message
    for slot in slots.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
      guard slot.range.lowerBound >= out.startIndex, slot.range.upperBound <= out.endIndex else {
        continue
      }
      out.replaceSubrange(slot.range, with: slot.placeholder)
    }
    return out
  }

  /// Placeholder naming: [duration_1], [equipment_2]. Stable and value-free.
  public static func placeholder(for kind: SemanticSlot.Kind, index: Int) -> String {
    "[" + kind.rawValue + "_" + String(index) + "]"
  }
}
