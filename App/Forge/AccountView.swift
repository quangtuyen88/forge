import SwiftUI
import AuthenticationServices

struct AccountView: View {
  @Environment(AuthClient.self) private var auth
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @State private var email = ""
  @State private var code = ""
  @State private var codeSent = false
  #if DEBUG
  @State private var devCode: String?
  #endif
  @State private var busy = false
  @State private var busyButton: BusyButton?
  @State private var error: String?

  /// The Settings agent pushes this view inside its own stack with this false.
  var showsOwnNavigationStack = true

  private enum BusyButton { case apple, google, send, verify }

  var body: some View {
    if showsOwnNavigationStack {
      NavigationStack { content }
    } else {
      content
    }
  }

  private var content: some View {
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
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 56)
        .clipShape(Capsule())
        .overlay {
          if busyButton == .apple { ProgressView() }
        }
        #if DEBUG
        googleButton
          .disabled(busy || !auth.isGoogleSignInConfigured)
        if !auth.isGoogleSignInConfigured {
          Text("Google sign-in is not configured in this build.")
            .forgeCaption()
            .multilineTextAlignment(.center)
        }
        #else
        if auth.isGoogleSignInConfigured {
          googleButton
            .disabled(busy)
        }
        #endif
        Divider().overlay(Theme.ring)
        VStack(spacing: 10) {
          TextField("Email", text: $email)
            .keyboardType(.emailAddress)
            .textContentType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.send)
            .onSubmit(sendCode)
            .accessibilityLabel("Email")
            .forgeBody()
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
          Button {
            sendCode()
          } label: {
            HStack(spacing: 8) {
              if busyButton == .send { ProgressView() }
              Text("Send code")
            }
          }
          .buttonStyle(PillButtonStyle())
          .disabled(!email.contains("@") || busy)
          if codeSent {
            TextField("6-digit code", text: $code)
              .keyboardType(.numberPad)
              .textContentType(.oneTimeCode)
              .accessibilityLabel("6-digit code")
              .forgeBody()
              .padding(10)
              .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
            #if DEBUG
            if devCode != nil {
              Text("dev code filled").forgeCaption()
            }
            #endif
            Button {
              run(.verify) { try await auth.verifyEmail(email, code: code) }
            } label: {
              HStack(spacing: 8) {
                if busyButton == .verify { ProgressView() }
                Text("Verify")
              }
            }
            .buttonStyle(PillButtonStyle())
            .disabled(code.count != 6 || busy)
          }
        }
        if let message = errorMessage {
          Text(message).foregroundStyle(Theme.negative).forgeLabel().multilineTextAlignment(.center)
        }
        Link(destination: Theme.privacyPolicyURL) {
          Text("Privacy Policy")
            .forgeCaption()
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
      }
      .padding(Theme.margin)
    }
    .background(Theme.page)
    .navigationTitle("Account")
    .toolbar {
      if showsOwnNavigationStack {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }.bold()
        }
      }
    }
    .interactiveDismissDisabled(busy)
    .onChange(of: auth.user) { _, user in
      if user != nil { dismiss() }
    }
  }

  private var googleButton: some View {
    Button {
      run(.google) { try await auth.signInWithGoogle(presenting: anchor) }
    } label: {
      HStack(spacing: 8) {
        if busyButton == .google { ProgressView() }
        Text("Continue with Google")
      }
    }
    .buttonStyle(PillSecondaryButtonStyle())
  }

  private var errorMessage: String? {
    if let error, let activationError = auth.activationError {
      return error == activationError ? error : "\(error)\n\(activationError)"
    }
    return error ?? auth.activationError
  }

  private func handleApple(_ result: Result<ASAuthorization, Error>) {
    switch result {
    case .success(let authorization):
      guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
      run(.apple) { try await auth.signInWithApple(credential: credential) }
    case .failure(let failure):
      if !isUserCancellation(failure) { error = failure.localizedDescription }
    }
  }

  private func sendCode() {
    run(.send) {
      #if DEBUG
      devCode = try await auth.startEmail(email)
      if let devCode { code = devCode }
      #else
      _ = try await auth.startEmail(email)
      #endif
      codeSent = true
    }
  }

  private func run(_ button: BusyButton, _ work: @escaping () async throws -> Void) {
    error = nil
    busy = true
    busyButton = button
    Task {
      do {
          try await work()
        } catch let failure {
          if !isUserCancellation(failure) { self.error = failure.localizedDescription }
      }
      busy = false
      busyButton = nil
    }
  }

  private func isUserCancellation(_ failure: Error) -> Bool {
    if let authorization = failure as? ASAuthorizationError {
      return authorization.code == .canceled
    }
    if let web = failure as? ASWebAuthenticationSessionError {
      return web.code == .canceledLogin
    }
    return false
  }

  private var anchor: ASPresentationAnchor {
    UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }
      .first ?? ASPresentationAnchor()
  }
}
