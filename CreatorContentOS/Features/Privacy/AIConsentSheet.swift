import SwiftUI

struct AIConsentSheet: View {
    var onAllow: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
            Text(AIConsentCopy.sheetTitle)
                .font(PocketSheetType.screenTitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .accessibilityAddTraits(.isHeader)

            Text(AIConsentCopy.purposeAndDestinations)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: PocketSheetSpace.s)

            VStack(spacing: PocketSheetSpace.s) {
                PocketSheetPrimaryAction(title: AIConsentCopy.allowTitle, action: onAllow)
                    .accessibilityIdentifier("ai.consent.allow")
                PocketSheetSecondaryAction(title: AIConsentCopy.notNowTitle, action: onNotNow)
                    .accessibilityIdentifier("ai.consent.notNow")
            }
        }
        .padding(.horizontal, PocketSheetSpace.l)
        .padding(.top, PocketSheetSpace.xl)
        .padding(.bottom, PocketSheetSpace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PocketSheetTheme.Color.paper.ignoresSafeArea())
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
