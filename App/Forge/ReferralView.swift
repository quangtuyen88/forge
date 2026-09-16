import SwiftUI

struct ReferralView: View {
  @Environment(AuthClient.self) private var auth
  @State private var referred = 0
  @State private var rewarded = 0
  @State private var codeInput = ""
  @State private var message: String?
  @State private var showSignIn = false

  private var referralCode: String { auth.user?.referralCode ?? "" }

  var body: some View {
    Group {
      if auth.user == nil {
        Button {
          showSignIn = true
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("Invite friends").forgeBodyStrong()
              Text("Give a month, get a month — sign in to share your code.").forgeLabel()
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
          }
          .frame(minHeight: 44)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      } else {
        VStack(spacing: 12) {
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
              Text("Your invite code").forgeLabel()
              Text(referralCode).forge(20, .bold).monospacedDigit()
            }
            Spacer()
            ShareLink(item: shareText) {
              Image(systemName: "square.and.arrow.up")
                .foregroundColor(Theme.text)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Theme.innerSurface))
            }
          }
          Text("\(referred) invited · \(rewarded) rewarded").forgeLabel()
          Divider().overlay(Theme.ring)
          HStack(spacing: 10) {
            TextField("Have a code?", text: $codeInput)
              .textInputAutocapitalization(.characters)
              .autocorrectionDisabled()
              .forgeBody()
              .padding(10)
              .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
            Button("Redeem") { redeem() }
              .foregroundStyle(Theme.accent)
              .forgeBodyStrong()
              .disabled(codeInput.isEmpty)
          }
          if let message {
            Text(message).forgeCaption()
          }
        }
      }
    }
    .sheet(isPresented: $showSignIn) { AccountView() }
    .task(id: auth.user?.id) {
      await loadCounts()
    }
  }

  private var shareText: String {
    "Train with me on Regulift. Use code \(referralCode) for a free month: https://forge-coach.quangtuyen88.workers.dev/r/\(referralCode)"
  }

  private func loadCounts() async {
    guard auth.user != nil, auth.token != nil,
          let json = try? await ForgeAPI.request("GET", "referral", authorized: true) else { return }
    referred = json["referred"] as? Int ?? 0
    rewarded = json["rewarded"] as? Int ?? 0
  }

  private func redeem() {
    let code = codeInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !code.isEmpty else { return }
    message = nil
    Task {
      do {
        _ = try await ForgeAPI.request("POST", "referral/redeem", body: ["code": code], authorized: true)
        message = "Code redeemed — your free month applies on first purchase."
        codeInput = ""
      } catch {
        message = (error as? APIError)?.message ?? error.localizedDescription
      }
    }
  }
}
