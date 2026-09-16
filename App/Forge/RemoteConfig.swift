import Foundation
import Observation

struct PaywallCopy: Equatable {
  var variant: String
  var headline: String
  var subline: String
  var annualBadge: String

  static let a = PaywallCopy(
    variant: "A",
    headline: "Train with the coach",
    subline: "Week 1 is built. Start the trial to lift it.",
    annualBadge: "SAVE 49%")
}

/// Paywall copy fetched once per launch from the server; failures keep variant A defaults.
@Observable
final class RemoteConfig {
  static let shared = RemoteConfig()

  var paywall: PaywallCopy = .a

  private var fetched = false

  private init() {
    Task { await refresh() }
  }

  func refresh() async {
    guard !fetched, AppSecret.value != nil else { return }
    fetched = true
    let stored = UserDefaults.standard.string(forKey: "coachServerURL") ?? ""
    let base = stored == Theme.legacyCoachServer || stored.isEmpty ? Theme.coachServer : stored
    guard var components = URLComponents(string: base) else { return }
    components.path += "/config"
    components.queryItems = [URLQueryItem(name: "device", value: Analytics.deviceID)]
    guard let url = components.url else { return }
    var req = URLRequest(url: url)
    req.timeoutInterval = 3
    req.setValue(AppSecret.value, forHTTPHeaderField: "x-forge-secret")
    struct Reply: Decodable {
      struct Body: Decodable { let variant, headline, subline, annualBadge: String }
      let paywall: Body
    }
    guard let (data, response) = try? await URLSession.shared.data(for: req),
          (response as? HTTPURLResponse)?.statusCode == 200,
          let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return }
    paywall = PaywallCopy(
      variant: reply.paywall.variant,
      headline: reply.paywall.headline,
      subline: reply.paywall.subline,
      annualBadge: reply.paywall.annualBadge)
  }
}
