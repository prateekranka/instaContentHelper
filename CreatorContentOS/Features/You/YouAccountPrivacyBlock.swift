import SwiftUI

struct YouAccountPrivacyBlock: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        PocketSheetBlock(header: "Privacy") {
            VStack(spacing: 0) {
                if let url = PrivacyPolicyLinks.privacyPolicyURL {
                    privacyPolicyRow(url: url)
                    PocketSheetDivider()
                }
                aiConsentRows
            }
        }
    }

    private func privacyPolicyRow(url: URL) -> some View {
        Link(destination: url) {
            PocketSheetRow(title: PrivacyPolicyLinks.rowTitle, leadingSymbol: "hand.raised")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("you.account.privacyPolicy")
    }

    private var aiConsentRows: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            HStack {
                Text(AIConsentCopy.accountHeader)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Spacer(minLength: PocketSheetSpace.s)
                PocketSheetStatus(
                    text: services.aiConsentStatusCopy,
                    kind: services.aiConsentAllowsOutbound ? .ready : .pending
                )
            }
            .padding(.horizontal, PocketSheetSpace.l)
            .padding(.top, PocketSheetSpace.s)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("you.account.aiConsent.status")

            if services.canRetryAIConsent {
                PocketSheetSecondaryAction(title: AIConsentCopy.accountRetryTitle) {
                    services.requestAIConsentPrompt()
                }
                .accessibilityIdentifier("you.account.aiConsent.allow")
                .padding(.horizontal, PocketSheetSpace.l)
                .padding(.bottom, PocketSheetSpace.s)
            } else {
                Color.clear.frame(height: PocketSheetSpace.s)
            }
        }
    }
}
