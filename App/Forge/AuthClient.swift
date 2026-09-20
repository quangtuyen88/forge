import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import UIKit

struct RemoteUser: Equatable {
  var id: String
  var email: String?
  var tier: String
  var referralCode: String
  var handle: String?
}

struct APIError: LocalizedError {
  let status: Int
  let message: String
  var errorDescription: String? { message }
}

extension Data {
  fileprivate func base64URL() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

enum ForgeAPI {
  static var baseURL: String {
    let stored = UserDefaults.standard.string(forKey: "coachServerURL") ?? ""
    return stored == Theme.legacyCoachServer || stored.isEmpty ? Theme.coachServer : stored
  }

  @discardableResult
  static func request(
    _ method: String, _ path: String, body: [String: Any]? = nil, authorized: Bool = false
  ) async throws -> [String: Any] {
    guard let url = URL(string: baseURL)?.appending(path: path) else {
      throw APIError(status: 0, message: "Bad server URL")
    }
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.timeoutInterval = 15
    if let body {
      req.setValue("application/json", forHTTPHeaderField: "content-type")
      req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }
    if let secret = AppSecret.value { req.setValue(secret, forHTTPHeaderField: "x-forge-secret") }
    if authorized, let token = Keychain.get("forge-session") {
      req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
    }
    let (data, response) = try await URLSession.shared.data(for: req)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    guard (200..<300).contains(status) else {
      if status == 401 { Keychain.delete("forge-session") }
      throw APIError(
        status: status, message: json["error"] as? String ?? "Server error (\(status))")
    }
    return json
  }
}

@MainActor @Observable final class AuthClient {
  static let shared = AuthClient()

  private(set) var user: RemoteUser?
  private var store: Store?
  private var webSession: ASWebAuthenticationSession?
  private var anchorProvider: AnchorProvider?

  private init() {}

  func configure(store: Store) {
    self.store = store
  }

  var token: String? { Keychain.get("forge-session") }

  func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
    guard
      let identityToken = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) })
    else {
      throw APIError(status: 0, message: "Missing Apple identity token")
    }
    var body: [String: Any] = ["identityToken": identityToken]
    let parts = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }
    if !parts.isEmpty { body["fullName"] = parts.joined(separator: " ") }
    let json = try await ForgeAPI.request("POST", "auth/apple", body: body)
    try await finishSignIn(json, method: "apple")
  }

  func signInWithGoogle(presenting: ASPresentationAnchor) async throws {
    guard let configuration = Self.googleConfiguration else {
      throw APIError(status: 0, message: "Google sign-in is not configured")
    }
    let verifier = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64URL()
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL()
    let state = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64URL()
    let redirect = "\(configuration.callbackScheme):/oauthredirect"
    var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    components.queryItems = [
      URLQueryItem(name: "client_id", value: configuration.clientID),
      URLQueryItem(name: "redirect_uri", value: redirect),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: "openid email profile"),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "prompt", value: "select_account"),
    ]
    guard let authorizationURL = components.url else {
      throw APIError(status: 0, message: "Could not create Google authorization URL")
    }
    let code = try await runWebSession(
      url: authorizationURL,
      scheme: configuration.callbackScheme,
      anchor: presenting,
      expectedState: state)

    var form = URLComponents()
    form.queryItems = [
      URLQueryItem(name: "code", value: code),
      URLQueryItem(name: "client_id", value: configuration.clientID),
      URLQueryItem(name: "code_verifier", value: verifier),
      URLQueryItem(name: "redirect_uri", value: redirect),
      URLQueryItem(name: "grant_type", value: "authorization_code"),
    ]
    guard let formBody = form.percentEncodedQuery?.data(using: .utf8) else {
      throw APIError(status: 0, message: "Could not create Google token request")
    }
    var tokenRequest = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    tokenRequest.httpMethod = "POST"
    tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
    tokenRequest.httpBody = formBody
    let (data, response) = try await URLSession.shared.data(for: tokenRequest)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200,
      let tokenJSON = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let idToken = tokenJSON["id_token"] as? String
    else {
      throw APIError(status: status, message: "Google token exchange failed")
    }
    let json = try await ForgeAPI.request("POST", "auth/google", body: ["idToken": idToken])
    try await finishSignIn(json, method: "google")
  }

  func startEmail(_ email: String) async throws -> String? {
    let json = try await ForgeAPI.request("POST", "auth/email/start", body: ["email": email])
    return json["devCode"] as? String
  }

  func verifyEmail(_ email: String, code: String) async throws {
    let json = try await ForgeAPI.request(
      "POST", "auth/email/verify", body: ["email": email, "code": code])
    try await finishSignIn(json, method: "email")
  }

  func refresh() async {
    guard token != nil else { return }
    guard let json = try? await ForgeAPI.request("GET", "me", authorized: true),
      let refreshedUser = Self.parseUser(json["user"])
    else { return }
    do {
      try SyncEngine.shared.prepareAccountActivation(userID: refreshedUser.id)
      activationError = nil
      user = refreshedUser
    } catch {
      activationError = error.localizedDescription
      Keychain.delete("forge-session")
      user = nil
      await store?.logOut()
    }
  }

  func signOut() async {
    _ = try? await ForgeAPI.request("POST", "auth/logout", authorized: true)
    Keychain.delete("forge-session")
    UserDefaults.standard.removeObject(forKey: SyncEngine.adoptServerKey)
    user = nil
    await store?.logOut()
  }

  func deleteAccount() async throws {
    _ = try await ForgeAPI.request("DELETE", "me", authorized: true)
    Keychain.delete("forge-session")
    user = nil
    await store?.logOut()
  }

  private func finishSignIn(_ json: [String: Any], method: String) async throws {
    guard let token = json["token"] as? String, let user = Self.parseUser(json["user"]) else {
      throw APIError(status: 0, message: "Unexpected server response")
    }
    do {
      try SyncEngine.shared.prepareAccountActivation(userID: user.id)
      activationError = nil
    } catch {
      activationError = error.localizedDescription
      throw error
    }
    Keychain.set(token, for: "forge-session")
    self.user = user
    Analytics.track("signed_in", ["method": method])
    await store?.logIn(userID: user.id)
    await redeemPendingCode()
    SyncEngine.shared.markFreshLogin()
    await SyncEngine.shared.sync()
  }

  private func redeemPendingCode() async {
    let defaults = UserDefaults.standard
    guard let code = defaults.string(forKey: "pendingCode"), !code.isEmpty else { return }
    defaults.removeObject(forKey: "pendingCode")
    do {
      _ = try await ForgeAPI.request(
        "POST", "referral/redeem", body: ["code": code], authorized: true)
      store?.setAttributes(referralCode: code, promoCode: nil)
    } catch let error as APIError where error.status == 404 {
      _ = try? await ForgeAPI.request(
        "POST", "attribution", body: ["promoCode": code], authorized: true)
      store?.setAttributes(referralCode: nil, promoCode: code)
    } catch {}
  }

  private func runWebSession(
    url: URL,
    scheme: String,
    anchor: ASPresentationAnchor,
    expectedState: String
  ) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let url,
          let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else {
          continuation.resume(
            throwing: APIError(status: 0, message: "Google sign-in returned no callback"))
          return
        }
        if let oauthError = items.first(where: { $0.name == "error" })?.value {
          continuation.resume(
            throwing: APIError(status: 0, message: "Google sign-in failed: \(oauthError)"))
          return
        }
        guard items.first(where: { $0.name == "state" })?.value == expectedState else {
          continuation.resume(
            throwing: APIError(status: 0, message: "Google sign-in state did not match"))
          return
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
          continuation.resume(
            throwing: APIError(status: 0, message: "Google sign-in returned no authorization code"))
          return
        }
        continuation.resume(returning: code)
      }
      let provider = AnchorProvider(anchor)
      session.presentationContextProvider = provider
      session.prefersEphemeralWebBrowserSession = true
      anchorProvider = provider
      webSession = session
      session.start()
    }
  }

  private static func parseUser(_ raw: Any?) -> RemoteUser? {
    guard let dict = raw as? [String: Any], let id = dict["id"] as? String else { return nil }
    return RemoteUser(
      id: id,
      email: dict["email"] as? String,
      tier: dict["tier"] as? String ?? "free",
      referralCode: dict["referralCode"] as? String ?? "",
      handle: dict["handle"] as? String)
  }

  var isGoogleSignInConfigured: Bool { Self.googleConfiguration != nil }

  private static var googleConfiguration: (clientID: String, callbackScheme: String)? {
    guard let clientID = AppConfig.value("GOOGLE_CLIENT_ID"),
      let callbackScheme = AppConfig.value("GOOGLE_REVERSED_CLIENT_ID")
    else { return nil }
    return (clientID, callbackScheme)
  }

  private(set) var activationError: String?
}

private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
  let anchor: ASPresentationAnchor
  init(_ anchor: ASPresentationAnchor) { self.anchor = anchor }
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    anchor
  }
}
