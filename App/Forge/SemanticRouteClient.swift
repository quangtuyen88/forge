import Foundation
import ForgeCore

/// The client half of the Situational Coach Router.
///
/// Everything that protects the lifter happens before this type is reached: the local
/// parser gets first refusal, `SemanticExportPolicy` decides whether anything may leave at
/// all, and the values are already placeholders. What comes back is a classification, not
/// an instruction — `SemanticRouter.decide` and the app`s own capability checks turn it
/// into a handler, and the lifter still approves an exact preview.
enum SemanticRouteClient {
  /// Off by default. Shadow classifies for measurement without acting; enabled routes.
  enum Mode: String, Sendable { case off, shadow, enabled }

  static let modeKey = "semanticRouteMode"

  static var mode: Mode {
    Mode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .off
  }

  struct Candidate: Sendable {
    let requestID: UUID
    let contextToken: UUID
    let answers: SemanticAnswers
    let questionSetVersion: String
    let providerModel: String
    /// True in shadow mode: measured, never acted on.
    let isShadow: Bool
  }

  /// Everything that is not a usable candidate. Each one keeps the lifter on the local
  /// path they already had.
  enum Failure: Error, Sendable, Equatable {
    case disabled
    case denied(SemanticExportDenial)
    case offline
    case provider(String)
    case mismatchedResponse
  }

  /// 2.5 s end-to-end: past that the lifter has moved on, and a late answer must not open
  /// a modal over whatever they are doing instead.
  private static let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 2.5
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: config)
  }()

  private struct Wire: Encodable {
    let schemaVersion = 1
    let requestId: String
    let contextToken: String
    let locale: String
    let surface: String
    let message: String
  }

  struct Reply: Decodable {
    struct Answer: Decodable {
      let choice: String
      let confidence: Double
      let probabilities: [String: Double]
    }
    let requestId: String
    let contextToken: String
    let status: String
    let reason: String?
    let questionSetVersion: String?
    let providerModel: String?
    let answers: [String: Answer]?
  }

  /// Route one message. Returns a candidate, or the reason the app should stay local.
  ///
  /// `projection` must come from `SemanticExportPolicy.project`: this function does not
  /// re-derive it, so a message that was never approved cannot be sent by calling here.
  static func route(
    projection: SemanticProjection,
    requestID: UUID = UUID(),
    contextToken: UUID = UUID()
  ) async -> Result<Candidate, Failure> {
    guard mode != .off else { return .failure(.disabled) }
    let stored = UserDefaults.standard.string(forKey: "coachServerURL") ?? ""
    let base = stored == Theme.legacyCoachServer || stored.isEmpty ? Theme.coachServer : stored
    guard let url = URL(string: base)?.appending(path: "coach/semantic-route"),
          let secret = AppSecret.value
    else { return .failure(.disabled) }

    let wire = Wire(
      requestId: requestID.uuidString, contextToken: contextToken.uuidString,
      locale: projection.locale, surface: projection.surface, message: projection.message)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.setValue(secret, forHTTPHeaderField: "x-forge-secret")
    request.httpBody = try? JSONEncoder().encode(wire)

    do {
      let (data, response) = try await session.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        return .failure(.provider("http"))
      }
      guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else {
        return .failure(.provider("decode"))
      }
      // A reply for a different turn is discarded: a late answer never reopens a
      // question the lifter has already moved past.
      guard reply.requestId == requestID.uuidString,
            reply.contextToken == contextToken.uuidString
      else { return .failure(.mismatchedResponse) }
      guard reply.status == "candidate" || reply.status == "shadow" else {
        return .failure(.provider(reply.reason ?? "fallback"))
      }
      guard let answers = reply.answers, let parsed = parse(answers) else {
        return .failure(.provider("incomplete"))
      }
      return .success(
        Candidate(
          requestID: requestID, contextToken: contextToken, answers: parsed,
          questionSetVersion: reply.questionSetVersion ?? "",
          providerModel: reply.providerModel ?? "",
          isShadow: reply.status == "shadow"))
    } catch {
      return .failure(.offline)
    }
  }

  /// All six answers, every choice inside its own enum, or nothing. A partial answer set
  /// is malformed output, never a confident one.
  static func parse(_ answers: [String: Reply.Answer]) -> SemanticAnswers? {
    func evidence<C: RawRepresentable & Sendable & Equatable>(
      _ key: String, _ type: C.Type
    ) -> SemanticEvidence<C>? where C.RawValue == String {
      guard let answer = answers[key], let choice = C(rawValue: answer.choice) else { return nil }
      return SemanticEvidence(
        choice: choice, confidence: answer.confidence, probabilities: answer.probabilities)
    }
    guard let form = evidence("form", SemanticForm.self),
          let shorten = evidence("shorten", SemanticTri.self),
          let equipment = evidence("equipment", SemanticTri.self),
          let explain = evidence("explain", SemanticTri.self),
          let scope = evidence("scope", SemanticScope.self),
          let remaining = evidence("remaining", SemanticRemaining.self)
    else { return nil }
    return SemanticAnswers(
      form: form, shorten: shorten, equipment: equipment, explain: explain, scope: scope,
      remaining: remaining)
  }
}
