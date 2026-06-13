import SwiftUI

struct SignInView: View {
    @Environment(AppState.self) private var appState
    @State private var email = ""
    @State private var otp = ""

    var body: some View {
        ZStack {
            MCOTheme.Color.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: MCOSpace.xl) {
                    header
                    signInForm
                }
                .padding(.horizontal, MCOSpace.l)
                .padding(.top, MCOSpace.xxl)
                .padding(.bottom, MCOSpace.xxl)
            }
        }
        .tint(MCOTheme.Color.oxblood)
        .onChange(of: appState.pendingEmail) { _, pendingEmail in
            if let pendingEmail {
                email = pendingEmail
            } else {
                otp = ""
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            Text("ContentHelper")
                .font(MCOType.display)
                .foregroundStyle(MCOTheme.Color.ink)
            Text("Sign in with an approved tester email to access Creator's live workspace.")
                .font(MCOType.body)
                .foregroundStyle(MCOTheme.Color.inkMuted)
        }
    }

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: MCOSpace.m) {
            if appState.pendingEmail == nil {
                emailStep
            } else {
                otpStep
            }

            if let error = appState.authenticationError {
                Text(error)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.clay)
                    .accessibilityIdentifier("authentication-error")
            }
        }
    }

    private var emailStep: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            Text("Email")
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.oxblood)

            TextField("you@example.com", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .submitLabel(.continue)
                .signInFieldStyle()
                .onSubmit(requestCode)
                .accessibilityIdentifier("sign-in-email")

            PrimaryActionButton(
                title: appState.authenticationPhase == .requestingCode
                    ? "Sending code"
                    : "Email me a code",
                systemImage: "envelope"
            ) {
                requestCode()
            }
            .disabled(isBusy || trimmedEmail.isEmpty)
            .opacity(isBusy || trimmedEmail.isEmpty ? 0.52 : 1)
            .accessibilityIdentifier("request-otp")
        }
    }

    private var otpStep: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            Text("Verification code")
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.oxblood)

            Text("Sent to \(appState.pendingEmail ?? email)")
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.inkMuted)

            TextField("000000", text: $otp)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .signInFieldStyle()
                .onChange(of: otp) { _, newValue in
                    otp = String(newValue.filter(\.isNumber).prefix(6))
                }
                .accessibilityIdentifier("sign-in-otp")

            PrimaryActionButton(
                title: appState.authenticationPhase == .verifyingCode
                    ? "Verifying"
                    : "Sign in",
                systemImage: "arrow.right"
            ) {
                verifyCode()
            }
            .disabled(isBusy || otp.count != 6)
            .opacity(isBusy || otp.count != 6 ? 0.52 : 1)
            .accessibilityIdentifier("verify-otp")

            Button("Use a different email") {
                appState.resetSignIn()
            }
            .buttonStyle(.plain)
            .font(MCOType.bodySmall)
            .foregroundStyle(MCOTheme.Color.oxblood)
            .disabled(isBusy)
        }
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isBusy: Bool {
        appState.authenticationPhase == .requestingCode ||
            appState.authenticationPhase == .verifyingCode
    }

    private func requestCode() {
        let value = trimmedEmail
        guard !value.isEmpty, !isBusy else { return }
        Task { await appState.requestEmailOTP(value) }
    }

    private func verifyCode() {
        guard otp.count == 6, !isBusy else { return }
        Task { await appState.verifyEmailOTP(otp) }
    }
}

private extension View {
    func signInFieldStyle() -> some View {
        font(MCOType.body)
            .foregroundStyle(MCOTheme.Color.ink)
            .padding(MCOSpace.m)
            .frame(height: 56)
            .background(MCOTheme.Color.paperRaised)
            .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                    .stroke(MCOTheme.Color.hairlineStrong, lineWidth: 1)
            }
    }
}
