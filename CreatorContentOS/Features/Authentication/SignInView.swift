import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            PocketSheetTheme.Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: PocketSheetSpace.section) {
                    header
                    welcomeCard
                    signInActions
                }
                .padding(.horizontal, PocketSheetSpace.l)
                .padding(.top, 48)
                .padding(.bottom, 48)
            }
        }
        .tint(PocketSheetTheme.Color.ink)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            Text("Sign in to keep your ideas")
                .font(PocketSheetType.screenTitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
            Text("Sign in with Apple to open your Creator workspace.")
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        }
    }

    private var welcomeCard: some View {
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                HStack(spacing: PocketSheetSpace.xs) {
                    Image(systemName: "checkmark.circle")
                        .font(PocketSheetType.listIcon)
                    Text("Your next ready idea")
                        .font(PocketSheetType.rowTitle)
                }
                .foregroundStyle(PocketSheetTheme.Color.ink)

                Text("Open Today to find one shootable idea, with the hook, format, and effort already clear.")
                    .font(PocketSheetType.bodyText)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                    Text("A quiet reset that makes Monday feel lighter")
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    Text("Short check-in · 10 minutes")
                        .font(PocketSheetType.bodyText)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }
                .padding(.top, PocketSheetSpace.xs)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Your next ready idea. Open Today to find one shootable idea with the hook, format, and effort already clear. A quiet reset that makes Monday feel lighter. Short check-in, 10 minutes.")
        .accessibilityIdentifier("sign-in.welcome")
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
            .frame(minHeight: 44)
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
                HStack(alignment: .top, spacing: PocketSheetSpace.xs) {
                    Image(systemName: "exclamationmark.circle")
                        .accessibilityHidden(true)
                    Text(error)
                        .font(PocketSheetType.rowSubtitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(PocketSheetTheme.Color.ink)
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
