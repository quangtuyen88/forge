import Foundation
import ForgeCore

/// Rescue classifier for phrasings the local parser never wrote down ("can we take two
/// minutes here"). Sends only the sentence and its language — no name, no weights, no
/// history, no workout. The local parser stays in charge; this is only consulted after
/// it returned `.unrecognised`.
enum VoiceIntentClient {
  struct Result: Sendable {
    let intent: VoiceIntent
    let confidence: Double
  }

  private struct Reply: Decodable {
    let intent: String
    let confidence: Double
  }

  /// 1.5 s request timeout: anything slower has already lost the lifter's attention.
  private static let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 1.5
    return URLSession(configuration: config)
  }()

  /// `nil` on any failure, any non-200, an unknown intent, or `none`. Never throws.
  static func classify(_ transcript: String, language: VoiceLanguage) async -> Result? {
    let stored = UserDefaults.standard.string(forKey: "coachServerURL") ?? ""
    let base = stored == Theme.legacyCoachServer || stored.isEmpty ? Theme.coachServer : stored
    guard let url = URL(string: base)?.appending(path: "voice/intent"),
          let secret = AppSecret.value else { return nil }
    // The vocabulary lives in the app so the server never has to know our commands.
    let body: [String: Any] = [
      "transcript": transcript,
      "language": language.rawValue,
      "intents": VoiceIntent.allCases.map(\.rawValue),
      "rubrics": Dictionary(uniqueKeysWithValues: VoiceIntent.allCases.map { ($0.rawValue, $0.rubric) }),
    ]
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.setValue(secret, forHTTPHeaderField: "x-forge-secret")
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    do {
      let (data, response) = try await session.data(for: req)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
      guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
            let intent = VoiceIntent(rawValue: reply.intent),
            intent != .none else { return nil }
      return Result(intent: intent, confidence: reply.confidence)
    } catch {
      return nil
    }
  }
}
