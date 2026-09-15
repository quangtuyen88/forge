import Foundation
import AuthenticationServices
import CryptoKit
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

private extension Data {
  func base64URL() -> String {
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
  static func request(_ method: String, _ path: String, body: [String: Any]? = nil, authorized: Bool = false) async throws -> [String: Any] {
    guard let url = URL(string: baseURL)?.appending(path: path) else { throw APIError(status: 0, message: "Bad server URL") }
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
      throw APIError(status: status, message: json["error"] as? String ?? "Server error (\(status))")
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
    guard let identityToken = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
      throw APIError(status: 0, message: "Missing Apple identity token")
    }
    var body: [String: Any] = ["identityToken": identityToken]
    let parts = [credential.fullName?.givenName, credential.fullName?.familyName].compactMap { $0 }
    if !parts.isEmpty { body["fullName"] = parts.joined(separator: " ") }
    let json = try await ForgeAPI.request("POST", "auth/apple", body: body)
    try await finishSignIn(json, method: "apple")
  }

  func signInWithGoogle(presenting: ASPresentationAnchor) async throws {
    let clientID = (Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !clientID.isEmpty else { throw APIError(status: 0, message: "Google sign-in is not configured") }
    let verifier = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64URL()
    let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL()
    let redirect = "com.vnbnode.forge:/oauth"
    var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    comps.queryItems = [
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "redirect_uri", value: redirect),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "scope", value: "openid email profile"),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
    ]
    let code = try await runWebSession(url: comps.url!, scheme: "com.vnbnode.forge", anchor: presenting)
    var tokenReq = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
    tokenReq.httpMethod = "POST"
    tokenReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
    let form = [
      "code": code, "client_id": clientID, "code_verifier": verifier,
      "redirect_uri": redirect, "grant_type": "authorization_code",
    ].map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
    tokenReq.httpBody = Data(form.utf8)
    let (data, response) = try await URLSession.shared.data(for: tokenReq)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200,
          let tokenJSON = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let idToken = tokenJSON["id_token"] as? String else {
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
    let json = try await ForgeAPI.request("POST", "auth/email/verify", body: ["email": email, "code": code])
    try await finishSignIn(json, method: "email")
  }

  func refresh() async {
    guard token != nil else { return }
    guard let json = try? await ForgeAPI.request("GET", "me", authorized: true) else { return }
    user = Self.parseUser(json["user"]) ?? user
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
      _ = try await ForgeAPI.request("POST", "referral/redeem", body: ["code": code], authorized: true)
      store?.setAttributes(referralCode: code, promoCode: nil)
    } catch let error as APIError where error.status == 404 {
      _ = try? await ForgeAPI.request("POST", "attribution", body: ["promoCode": code], authorized: true)
      store?.setAttributes(referralCode: nil, promoCode: code)
    } catch {}
  }

  private func runWebSession(url: URL, scheme: String, anchor: ASPresentationAnchor) async throws -> String {
    try await withCheckedThrowingContinuation { cont in
      let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
        if let error {
          cont.resume(throwing: error)
        } else if let url,
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let code = items.first(where: { $0.name == "code" })?.value {
          cont.resume(returning: code)
        } else {
          cont.resume(throwing: APIError(status: 0, message: "Sign-in cancelled"))
        }
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
}

private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
  let anchor: ASPresentationAnchor
  init(_ anchor: ASPresentationAnchor) { self.anchor = anchor }
  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}
