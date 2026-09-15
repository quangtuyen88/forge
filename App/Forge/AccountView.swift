import SwiftUI
import AuthenticationServices

struct AccountView: View {
  @Environment(AuthClient.self) private var auth
  @Environment(\.dismiss) private var dismiss
  @State private var email = ""
  @State private var code = ""
  @State private var codeSent = false
  @State private var devCode: String?
  @State private var busy = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          Text("Sign in to sync your training, measurements and nutrition across your devices.")
            .forgeLabel()
            .multilineTextAlignment(.center)
          SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.email, .fullName]
          } onCompletion: { result in
            handleApple(result)
          }
          .signInWithAppleButtonStyle(.black)
          .frame(height: 52)
          Button {
            run { try await auth.signInWithGoogle(presenting: anchor) }
          } label: {
            Text("Continue with Google")
          }
          .buttonStyle(PillSecondaryButtonStyle())
          .disabled(busy)
          Divider().overlay(Theme.ring)
          VStack(spacing: 10) {
            TextField("Email", text: $email)
              .keyboardType(.emailAddress)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .forgeBody()
              .padding(10)
              .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
            Button("Send code") {
              run {
                devCode = try await auth.startEmail(email)
                if let devCode { code = devCode }
                codeSent = true
              }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(!email.contains("@") || busy)
            if codeSent {
              TextField("6-digit code", text: $code)
                .keyboardType(.numberPad)
                .forgeBody()
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
              if devCode != nil {
                Text("dev code filled").forgeCaption()
              }
              Button("Verify") {
                run { try await auth.verifyEmail(email, code: code) }
              }
              .buttonStyle(PillButtonStyle())
              .disabled(code.count != 6 || busy)
            }
          }
          if let error {
            Text(error).foregroundStyle(Theme.negative).forgeLabel().multilineTextAlignment(.center)
          }
          Link("Privacy Policy", destination: Theme.privacyPolicyURL).forgeCaption()
        }
        .padding(Theme.margin)
      }
      .background(Theme.page)
      .navigationTitle("Account")
      .toolbar { Button("Done") { dismiss() }.bold() }
      .interactiveDismissDisabled(busy)
      .onChange(of: auth.user) { _, user in
        if user != nil { dismiss() }
      }
    }
  }

  private func handleApple(_ result: Result<ASAuthorization, Error>) {
    switch result {
    case .success(let authorization):
      guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
      run { try await auth.signInWithApple(credential: credential) }
    case .failure(let failure):
      error = failure.localizedDescription
    }
  }

  private func run(_ work: @escaping () async throws -> Void) {
    error = nil
    busy = true
    Task {
      do { try await work() } catch { self.error = error.localizedDescription }
      busy = false
    }
  }

  private var anchor: ASPresentationAnchor {
    UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first ?? ASPresentationAnchor()
  }
}
