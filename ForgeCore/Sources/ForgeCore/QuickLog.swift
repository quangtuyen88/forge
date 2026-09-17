import Foundation

public struct QuickLogCandidate {
  public var id: String
  public var name: String

  public init(id: String, name: String) {
    self.id = id
    self.name = name
  }
}

public struct QuickLogParse: Equatable, Sendable {
  public var exerciseID: String
  public var weightKg: Double
  public var reps: Int
  public var rpe: Double?

  public init(exerciseID: String, weightKg: Double, reps: Int, rpe: Double?) {
    self.exerciseID = exerciseID
    self.weightKg = weightKg
    self.reps = reps
    self.rpe = rpe
  }
}

/// A parsed spoken/typed quick-log set before it is matched to a database exercise.
public struct QuickLogDraft {
  public var exercise: String
  public var weight: Double
  public var unit: String?
  public var reps: Int
  public var rpe: Double?

  public init(exercise: String, weight: Double, unit: String?, reps: Int, rpe: Double?) {
    self.exercise = exercise
    self.weight = weight
    self.unit = unit
    self.reps = reps
    self.rpe = rpe
  }
}

/// Parses a free-text "quick log" line like `deadlift 132.5x8 @8` into a concrete set.
public enum QuickLog {
  private static let aliases: [String: String] = [
    "dl": "deadlift",
    "rdl": "romanian deadlift",
    "ohp": "overhead press",
    "bb": "barbell",
    "db": "dumbbell",
    "sq": "squat",
    "bp": "bench press",
    "pulldown": "lat pulldown",
  ]

  public static func parse(_ text: String, candidates: [QuickLogCandidate], defaultLb: Bool) -> QuickLogParse? {
    let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return nil }
    let pattern = #"^\s*(.+?)\s+([0-9][0-9.,]*)\s*(kg|kgs|lb|lbs)?\s*(?:x|×|\*|for)\s*([0-9]{1,3})(?:\s*reps?)?(?:\s*(?:@|rpe|at)\s*([0-9][0-9.,]*))?\s*$"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let ns = s as NSString
    let range = NSRange(location: 0, length: ns.length)
    guard let match = regex.firstMatch(in: s, options: [], range: range) else { return nil }

    func group(_ index: Int) -> String? {
      guard index < match.numberOfRanges, let r = Range(match.range(at: index), in: s) else { return nil }
      return String(s[r])
    }
    guard let exerciseText = group(1), let weightText = group(2), let repsText = group(4) else { return nil }
    let unit = group(3)
    let rpeText = group(5)

    guard let weightValue = Double(weightText.replacingOccurrences(of: ",", with: ".")), weightValue > 0 else { return nil }
    guard let reps = Int(repsText), reps >= 1, reps <= 100 else { return nil }
    var rpe: Double? = nil
    if let rpeText {
      guard let value = Double(rpeText.replacingOccurrences(of: ",", with: ".")), value >= 5, value <= 10 else { return nil }
      rpe = value
    }

    let usesLb: Bool
    if let unit {
      let u = unit.lowercased()
      usesLb = u == "lb" || u == "lbs"
    } else {
      usesLb = defaultLb
    }
    let weightKg = usesLb ? Plates.lbToKg(weightValue) : weightValue

    guard let exerciseID = matchExercise(exerciseText, candidates: candidates) else { return nil }
    return QuickLogParse(exerciseID: exerciseID, weightKg: weightKg, reps: reps, rpe: rpe)
  }

  private static func matchExercise(_ raw: String, candidates: [QuickLogCandidate]) -> String? {
    let words = expandedWords(raw)
    guard !words.isEmpty else { return nil }
    let phrase = words.joined(separator: " ")
    var bestID: String? = nil
    var bestScore = 0
    for candidate in candidates {
      let name = normalized(candidate.name)
      let nameWords = name.split(separator: " ").map(String.init)
      var score = 0
      if phrase == name {
        score = 3
      } else if allPrefixes(words, in: nameWords) {
        score = 2
      } else if name.contains(phrase) {
        score = 1
      }
      if score > bestScore {
        bestScore = score
        bestID = candidate.id
      }
    }
    return bestScore > 0 ? bestID : nil
  }

  private static func expandedWords(_ raw: String) -> [String] {
    normalized(raw)
      .split(separator: " ")
      .map(String.init)
      .flatMap { word -> [String] in
        if let expansion = aliases[word] {
          return expansion.split(separator: " ").map(String.init)
        }
        return [word]
      }
  }

  private static func allPrefixes(_ typed: [String], in nameWords: [String]) -> Bool {
    var remaining = nameWords
    for word in typed {
      guard let index = remaining.firstIndex(where: { $0.hasPrefix(word) }) else { return false }
      remaining.remove(at: index)
    }
    return true
  }

  /// Renders a draft back into the regex-friendly form `<exercise> <weight><unit?> x <reps>[ @<rpe>]`.
  public static func canonical(_ d: QuickLogDraft) -> String {
    var out = "\(d.exercise) \(weightText(d.weight))\(d.unit ?? "") x \(d.reps)"
    if let rpe = d.rpe {
      out += " @\(String(format: "%.1f", rpe))"
    }
    return out
  }

  private static func weightText(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded == rounded.rounded() {
      return String(Int(rounded))
    }
    return String(format: "%.1f", rounded)
  }

  private static func normalized(_ string: String) -> String {
    let lower = string.lowercased()
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
}
