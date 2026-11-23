import AuthenticationServices
import SwiftUI

enum AuthMode {
    case signIn
    case signUp
}

struct AuthView: View {
    var initialMode: AuthMode
    @Environment(AppModel.self) private var app
    @State private var mode: AuthMode
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var displayName = ""
    @State private var message: String?
    @State private var isWorking = false
    @State private var showReset = false
    @State private var appleNonce = ""

    init(initialMode: AuthMode) {
        self.initialMode = initialMode
        _mode = State(initialValue: initialMode)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Wordmark(size: 30, alignment: .leading)
                    .padding(.top, 24)
                Text(mode == .signUp ? "Create the identity your build deserves." : "The city is already moving.")
                    .font(.title3)
                    .foregroundStyle(NightshiftColor.secondaryText)
                if mode == .signUp {
                    NightshiftField(title: "Username", text: $username, identifier: UIID.username, capitalization: .never, contentType: .username)
                    NightshiftField(title: "Display name", text: $displayName, identifier: UIID.displayName, contentType: .name)
                }
                NightshiftField(title: "Email", text: $email, identifier: UIID.email, capitalization: .never, keyboard: .emailAddress, contentType: .emailAddress)
                SecureNightshiftField(
                    title: "Password",
                    text: $password,
                    identifier: UIID.password,
                    contentType: mode == .signUp ? .newPassword : .password
                )
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(NightshiftColor.pink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                NeonPrimaryButton(
                    title: mode == .signUp ? "Create account" : "Sign in",
                    isLoading: isWorking,
                    identifier: UIID.submitAuth
                ) {
                    Task { await submit() }
                }
                SignInWithAppleButton(mode == .signUp ? .signUp : .signIn) { request in
                    let nonce = AppleSignIn.randomNonce()
                    appleNonce = nonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = AppleSignIn.sha256(nonce)
                } onCompletion: { result in
                    Task { await finishApple(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(minHeight: 52)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Sign in with Apple")
                Button(mode == .signUp ? "I already have an account" : "Create an account") {
                    mode = mode == .signUp ? .signIn : .signUp
                    message = nil
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NightshiftColor.purple)
                .accessibilityIdentifier(UIID.toggleAuth)
                Button("Forgot password") { showReset = true }
                    .font(.subheadline)
                    .foregroundStyle(NightshiftColor.secondaryText)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .nightshiftScreen()
        .sheet(isPresented: $showReset) {
            PasswordResetView()
                .environment(app)
        }
    }

    private func submit() async {
        message = nil
        isWorking = true
        defer { isWorking = false }
        do {
            if mode == .signUp {
                let outcome = try await app.repository.signUp(
                    email: email,
                    password: password,
                    username: username,
                    displayName: displayName
                )
                switch outcome {
                case .signedIn(let profile):
                    await app.adopt(profile)
                case .confirmationRequired:
                    message = "Check your email to confirm the account, then sign in."
                    mode = .signIn
                }
            } else {
                let profile = try await app.repository.signIn(email: email, password: password)
                await app.adopt(profile)
            }
        } catch {
            message = nightshiftMessage(error)
        }
    }

    private func finishApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            message = nightshiftMessage(error)
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
            let token = credential.identityToken.flatMap { String(data: $0, encoding: .utf8) }
            do {
                let profile = try await app.repository.signInWithApple(
                    userID: credential.user,
                    idToken: token,
                    nonce: appleNonce,
                    fullName: credential.fullName
                )
                await app.adopt(profile)
            } catch {
                message = nightshiftMessage(error)
            }
        }
    }
}

struct PasswordResetView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(app.usesRemoteBackend
                         ? "We'll email you a link to choose a new password."
                         : "This copy of Nightshift is stored on this iPhone. Set a new password for the email you used here.")
                        .font(.body)
                        .foregroundStyle(NightshiftColor.secondaryText)
                    NightshiftField(title: "Email", text: $email, capitalization: .never, keyboard: .emailAddress, contentType: .emailAddress)
                    if !app.usesRemoteBackend {
                        SecureNightshiftField(title: "New password", text: $password, contentType: .newPassword)
                    }
                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(NightshiftColor.secondaryText)
                    }
                    NeonPrimaryButton(title: app.usesRemoteBackend ? "Send reset email" : "Update password", isLoading: isWorking) {
                        Task { await submit() }
                    }
                }
                .padding(20)
            }
            .nightshiftScreen()
            .navigationTitle("Account recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        isWorking = true
        defer { isWorking = false }
        do {
            if app.usesRemoteBackend {
                try await app.repository.requestPasswordReset(email: email)
                message = "If that account exists, a reset email is on the way."
            } else {
                try await app.repository.setPassword(email: email, newPassword: password)
                message = "Password updated. You can sign in."
            }
        } catch {
            message = nightshiftMessage(error)
        }
    }
}
