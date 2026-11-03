import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MiraPage {
            Text("Sign in to keep your ideas").font(.largeTitle)
                .accessibilityIdentifier("sign-in.welcome")
            Text("Sign in with Apple to connect your Mira account.")
                .foregroundStyle(.secondary)
            signInActions
        }
        .tint(MiraTheme.olive)
    }

    private var signInActions: some View {
        VStack(alignment: .leading, spacing: 16) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { result in
                handleAppleAuthorization(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .disabled(isBusy)
            .opacity(isBusy ? 0.52 : 1)
            .accessibilityIdentifier("sign-in-with-apple")

            if isBusy {
                ProgressView()
                    .tint(MiraTheme.ink)
                    .accessibilityIdentifier("sign-in-progress")
            }

            if let error = appState.authenticationError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .accessibilityHidden(true)
                    Text(error)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(MiraTheme.ink)
                .accessibilityIdentifier("authentication-error")
            }
        }
    }

    private var isBusy: Bool {
        appState.authenticationPhase == .signingIn
    }

    private func handleAppleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if isAppleSignInCancellation(error) {
                return
            }
            Task {
                await appState.failSignIn(message: error.localizedDescription)
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                Task {
                    await appState.failSignIn(message: "Apple sign-in returned an unexpected credential.")
                }
                return
            }
            guard
                let identityToken = credential.identityToken.flatMap({
                    String(data: $0, encoding: .utf8)
                })
            else {
                Task {
                    await appState.failSignIn(message: "Apple did not return a usable identity token.")
                }
                return
            }

            let fullName = credential.fullName?.formatted().nilIfBlank
            Task {
                await appState.signInWithApple(idToken: identityToken, fullName: fullName)
            }
        }
    }

    private func isAppleSignInCancellation(_ error: Error) -> Bool {
        let authorizationError = error as? ASAuthorizationError
        return authorizationError?.code == .canceled
    }
}
