import Foundation

protocol OnboardingProfileVerifying: Sendable {
    func verify(handle: String) async -> OnboardingProfileVerificationResult
}

/// Uses the same-origin `import-references` preview path — never unavatar.
struct ImportPreviewOnboardingProfileVerifier: OnboardingProfileVerifying {
    let repository: any ReferenceImportRepository
    let context: WorkspaceContext

    func verify(handle: String) async -> OnboardingProfileVerificationResult {
        let normalized = OnboardingReferenceParser.normalizePlainHandle(handle) ?? handle
        let rawText = "@\(normalized)"
        do {
            let preview = try await repository.previewImport(
                rawText: rawText,
                inputType: .paste,
                filename: nil,
                context: context
            )
            return mapPreview(preview, handle: normalized)
        } catch {
            return OnboardingProfileVerificationResult(
                status: .temporarilyUnavailable,
                handle: normalized,
                url: OnboardingReferenceParser.instagramProfileURL(handle: normalized),
                diagnosticReason: "import_preview_error"
            )
        }
    }

    private func mapPreview(
        _ preview: ReferenceImportPreview,
        handle: String
    ) -> OnboardingProfileVerificationResult {
        let url = OnboardingReferenceParser.instagramProfileURL(handle: handle)
        let accountRows = preview.rows.filter { $0.typeChip == .account }

        if accountRows.contains(where: { $0.previewState == .clean || $0.previewState == .needsReview }) {
            return OnboardingProfileVerificationResult(
                status: .verified,
                handle: handle,
                url: url,
                diagnosticReason: nil
            )
        }

        if accountRows.contains(where: {
            $0.previewState == .invalid && isNotFoundReason($0.invalidReason)
        }) {
            return OnboardingProfileVerificationResult(
                status: .notFound,
                handle: handle,
                url: url,
                diagnosticReason: "import_preview_not_found"
            )
        }

        if preview.counts.invalid > 0, preview.counts.cleanAccounts == 0, preview.counts.importable == 0 {
            return OnboardingProfileVerificationResult(
                status: .notFound,
                handle: handle,
                url: url,
                diagnosticReason: "import_preview_invalid_only"
            )
        }

        return OnboardingProfileVerificationResult(
            status: .temporarilyUnavailable,
            handle: handle,
            url: url,
            diagnosticReason: "import_preview_inconclusive"
        )
    }

    private func isNotFoundReason(_ reason: String?) -> Bool {
        guard let reason = reason?.lowercased() else { return false }
        return reason.contains("not found")
            || reason.contains("not_found")
            || reason.contains("404")
            || reason.contains("doesn't exist")
            || reason.contains("does not exist")
    }
}

/// Live runtime adapter that routes through `AppServices` preview import.
@MainActor
struct AppServicesOnboardingProfileVerifier: OnboardingProfileVerifying {
    let services: AppServices

    func verify(handle: String) async -> OnboardingProfileVerificationResult {
        let normalized = OnboardingReferenceParser.normalizePlainHandle(handle) ?? handle
        let preview = await services.previewReferenceImportImmediately(
            rawText: "@\(normalized)",
            inputType: .paste
        )
        guard let preview else {
            return OnboardingProfileVerificationResult(
                status: .temporarilyUnavailable,
                handle: normalized,
                url: OnboardingReferenceParser.instagramProfileURL(handle: normalized),
                diagnosticReason: "import_preview_unavailable"
            )
        }
        return await ImportPreviewOnboardingProfileVerifier(
            repository: PreviewPassthroughRepository(preview: preview),
            context: services.context
        ).verify(handle: normalized)
    }
}

private struct PreviewPassthroughRepository: ReferenceImportRepository {
    let preview: ReferenceImportPreview

    func previewImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        context: WorkspaceContext
    ) async throws -> ReferenceImportPreview {
        preview
    }

    func confirmImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        previewChecksum: String,
        context: WorkspaceContext
    ) async throws -> ReferenceImportConfirmResult {
        throw RepositoryError.notConfigured("Preview passthrough only.")
    }

    func reviewItem(
        _ request: ReferenceReviewRequest,
        context: WorkspaceContext
    ) async throws -> ReferenceReviewResult {
        throw RepositoryError.notConfigured("Preview passthrough only.")
    }
}

/// Fixture / offline sessions: deterministic verification without live import.
struct FixtureOnboardingProfileVerifier: OnboardingProfileVerifying {
    var configuredStatus: OnboardingProfileVerificationStatus = .verified
    var notFoundHandles: Set<String> = []

    func verify(handle: String) async -> OnboardingProfileVerificationResult {
        let normalized = OnboardingReferenceParser.normalizePlainHandle(handle) ?? handle
        let url = OnboardingReferenceParser.instagramProfileURL(handle: normalized)
        let status: OnboardingProfileVerificationStatus
        if notFoundHandles.contains(normalized) {
            status = .notFound
        } else {
            status = configuredStatus
        }
        return OnboardingProfileVerificationResult(
            status: status,
            handle: normalized,
            url: url,
            diagnosticReason: status == .verified ? nil : "fixture_\(status.rawValue)"
        )
    }
}
