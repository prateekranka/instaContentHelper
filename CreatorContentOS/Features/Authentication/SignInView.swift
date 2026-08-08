import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            PocketSheetTheme.Color.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: PocketSheetSpace.xl) {
                header
                signInActions
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PocketSheetSpace.l)
            .padding(.top, 48)
            .padding(.bottom, 48)
        }
        .tint(PocketSheetTheme.Color.ink)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            Text("ContentHelper")
                .font(PocketSheetType.screenTitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
            Text("Sign in with Apple to open your Creator workspace.")
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        }
    }

    private var signInActions: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { result in
                handleAppleAuthorization(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
            .disabled(isBusy)
            .opacity(isBusy ? 0.52 : 1)
            .accessibilityIdentifier("sign-in-with-apple")

            if isBusy {
                ProgressView()
                    .tint(PocketSheetTheme.Color.ink)
                    .accessibilityIdentifier("sign-in-progress")
            }

            if let error = appState.authenticationError {
                Text(error)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.validationAttention)
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
