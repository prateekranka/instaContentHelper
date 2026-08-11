import Foundation
import Supabase

protocol ReferenceImportRepository: Sendable {
    func previewImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        context: WorkspaceContext
    ) async throws -> ReferenceImportPreview

    func confirmImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        previewChecksum: String,
        context: WorkspaceContext
    ) async throws -> ReferenceImportConfirmResult

    func reviewItem(
        _ request: ReferenceReviewRequest,
        context: WorkspaceContext
    ) async throws -> ReferenceReviewResult
}

struct FixtureReferenceImportRepository: ReferenceImportRepository {
    private let message = "Connect live workspace to import references."

    func previewImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        context: WorkspaceContext
    ) async throws -> ReferenceImportPreview {
        throw RepositoryError.notConfigured(message)
    }

    func confirmImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        previewChecksum: String,
        context: WorkspaceContext
    ) async throws -> ReferenceImportConfirmResult {
        throw RepositoryError.notConfigured(message)
    }

    func reviewItem(
        _ request: ReferenceReviewRequest,
        context: WorkspaceContext
    ) async throws -> ReferenceReviewResult {
        throw RepositoryError.notConfigured(message)
    }
}

struct SupabaseReferenceImportRepository: ReferenceImportRepository {
    let client: SupabaseClient

    func previewImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        context: WorkspaceContext
    ) async throws -> ReferenceImportPreview {
        // Bound the live Instagram probe: an unreachable/slow Instagram must
        // never hang the import flow (onboarding and References alike).
        let response: SupabaseReferenceImportPreviewResponse = try await withThrowingTaskGroup(
            of: SupabaseReferenceImportPreviewResponse.self
        ) { group in
            group.addTask {
                try await self.client.functions.invoke(
                    "import-references",
                    options: FunctionInvokeOptions(
                        body: SupabaseReferenceImportRequest(
                            mode: "preview",
                            creatorID: context.creatorID,
                            inputType: inputType,
                            rawText: rawText,
                            filename: filename,
                            previewChecksum: nil
                        )
                    )
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw PreviewImportTimeoutError()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }

        return response.domainPreview()
    }

    func confirmImport(
        rawText: String,
        inputType: ReferenceImportInputType,
        filename: String?,
        previewChecksum: String,
        context: WorkspaceContext
    ) async throws -> ReferenceImportConfirmResult {
        // Same bound as previewImport: an unreachable backend must never
        // leave the save flow hanging.
        let response: SupabaseReferenceImportConfirmResponse = try await withThrowingTaskGroup(
            of: SupabaseReferenceImportConfirmResponse.self
        ) { group in
            group.addTask {
                try await self.client.functions.invoke(
                    "import-references",
                    options: FunctionInvokeOptions(
                        body: SupabaseReferenceImportRequest(
                            mode: "confirm",
                            creatorID: context.creatorID,
                            inputType: inputType,
                            rawText: rawText,
                            filename: filename,
                            previewChecksum: previewChecksum
                        )
                    )
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw PreviewImportTimeoutError()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }

        return response.domainResult()
    }

    func reviewItem(
        _ request: ReferenceReviewRequest,
        context: WorkspaceContext
    ) async throws -> ReferenceReviewResult {
        let response: SupabaseReferenceReviewResultResponse = try await client.functions.invoke(
            "review-reference",
            options: FunctionInvokeOptions(
                body: SupabaseReferenceReviewRequest(request: request, context: context)
            )
        )

        return response.domainResult()
    }
}
