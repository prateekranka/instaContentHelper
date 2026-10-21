import SwiftUI

struct AIConsentSheet: View {
    var onAllow: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        PocketSheetScreen(bottomContentPadding: PocketSheetSpace.l) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.section) {
                Text(AIConsentCopy.sheetTitle)
                    .font(PocketSheetType.screenTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .accessibilityAddTraits(.isHeader)

                Text(AIConsentCopy.purposeAndDestinations)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } bottomBar: {
            PocketSheetCommandBar {
                PocketSheetPrimaryAction(title: AIConsentCopy.allowTitle, action: onAllow)
                    .accessibilityIdentifier("ai.consent.allow")
                PocketSheetSecondaryAction(title: AIConsentCopy.notNowTitle, action: onNotNow)
                    .accessibilityIdentifier("ai.consent.notNow")
            }
        }
        .accessibilityIdentifier("ai.consent.sheet")
    }
}

struct AIConsentSheetPresenter: ViewModifier {
    @Environment(AppServices.self) private var services

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: presentationBinding) {
                AIConsentSheet(
                    onAllow: { services.acceptAIConsent() },
                    onNotNow: { services.declineAIConsent() }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
    }

    private var presentationBinding: Binding<Bool> {
        Binding(
            get: { services.isAIConsentSheetPresented },
            set: { services.setAIConsentSheetPresented($0) }
        )
    }
}

extension View {
    func aiConsentSheet() -> some View {
        modifier(AIConsentSheetPresenter())
    }
}
