import Foundation

enum OnboardingReferenceImport {
    /// Builds the raw paste text Intelligence import expects for a single onboarding reference.
    static func rawText(for reference: OnboardingReference) -> String {
        switch reference.kind {
        case .profile:
            if reference.key.hasPrefix("handle:") {
                let handle = String(reference.key.dropFirst("handle:".count))
                return "@\(handle)"
            }
            if let handle = OnboardingReferenceParser.normalizePlainHandle(reference.label) {
                return "@\(handle)"
            }
            return reference.url
        case .reel:
            return reference.url
        }
    }

    static func inputType(for reference: OnboardingReference) -> ReferenceImportInputType {
        .paste
    }
}

struct OnboardingReferenceImportOutcome: Sendable, Equatable {
    var confirmed: Int
    var skipped: Int
    var failed: Int
}

/// Confirms onboarding references into Intelligence via preview-then-confirm import.
struct OnboardingReferenceImporter: Sendable {
    var preview: @Sendable (String, ReferenceImportInputType) async -> ReferenceImportPreview?
    var confirm: @Sendable (String, ReferenceImportInputType, String) async -> ReferenceImportConfirmResult?

    func importReferences(_ references: [OnboardingReference]) async -> OnboardingReferenceImportOutcome {
        var outcome = OnboardingReferenceImportOutcome(confirmed: 0, skipped: 0, failed: 0)
        for reference in references {
            let rawText = OnboardingReferenceImport.rawText(for: reference)
            let inputType = OnboardingReferenceImport.inputType(for: reference)

            guard let preview = await preview(rawText, inputType) else {
                outcome.failed += 1
                continue
            }
            guard preview.counts.importable > 0 else {
                outcome.skipped += 1
                continue
            }
            if await confirm(rawText, inputType, preview.previewChecksum) != nil {
                outcome.confirmed += 1
            } else {
                outcome.failed += 1
            }
        }
        return outcome
    }
}

extension OnboardingReferenceImporter {
    @MainActor
    static func live(services: AppServices) -> Self {
        Self(
            preview: { rawText, inputType in
                await services.previewReferenceImportImmediately(
                    rawText: rawText,
                    inputType: inputType
                )
            },
            confirm: { rawText, inputType, previewChecksum in
                await services.confirmReferenceImportImmediately(
                    rawText: rawText,
                    inputType: inputType,
                    previewChecksum: previewChecksum
                )
            }
        )
    }
}
