import SwiftUI

struct YouAccountPrivacyBlock: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        PocketSheetBlock(header: "Privacy") {
            VStack(spacing: 0) {
                privacyPolicyRow
                PocketSheetDivider()
                aiConsentRows
            }
        }
    }

    private var privacyPolicyRow: some View {
        HStack(alignment: .center, spacing: PocketSheetSpace.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PrivacyPolicyLinks.rowTitle)
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkQuiet)
                Text(PrivacyPolicyLinks.unpublishedSubtitle)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            Spacer(minLength: PocketSheetSpace.s)
        }
        .frame(minHeight: 44, alignment: .center)
        .padding(.horizontal, PocketSheetSpace.m)
        .padding(.vertical, PocketSheetSpace.s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(PrivacyPolicyLinks.rowTitle). \(PrivacyPolicyLinks.unpublishedSubtitle)")
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
            .padding(.horizontal, PocketSheetSpace.m)
            .padding(.top, PocketSheetSpace.s)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("you.account.aiConsent.status")

            if services.canRetryAIConsent {
                PocketSheetSecondaryAction(title: AIConsentCopy.accountRetryTitle) {
                    services.requestAIConsentPrompt()
                }
                .accessibilityIdentifier("you.account.aiConsent.allow")
                .padding(.horizontal, PocketSheetSpace.m)
                .padding(.bottom, PocketSheetSpace.s)
            } else {
                Color.clear.frame(height: PocketSheetSpace.s)
            }
        }
    }
}
