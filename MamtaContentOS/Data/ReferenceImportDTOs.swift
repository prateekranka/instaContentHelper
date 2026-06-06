import Foundation

struct SupabaseReferenceImportRequest: Encodable, Sendable {
    var mode: String
    var creatorID: UUID
    var inputType: ReferenceImportInputType
    var rawText: String
    var filename: String?
    var previewChecksum: String?

    enum CodingKeys: String, CodingKey {
        case mode
        case creatorID = "creator_id"
        case inputType = "input_type"
        case rawText = "raw_text"
        case filename
        case previewChecksum = "preview_checksum"
    }
}

struct SupabaseReferenceImportPreviewResponse: Decodable, Hashable, Sendable {
    var parserVersion: String
    var previewChecksum: String
    var destination: SupabaseReferenceImportDestinationResponse
    var counts: SupabaseReferenceImportCountsResponse
    var rows: [SupabaseReferenceImportRowResponse]

    enum CodingKeys: String, CodingKey {
        case parserVersion = "parser_version"
        case previewChecksum = "preview_checksum"
        case destination
        case counts
        case rows
    }

    func domainPreview() -> ReferenceImportPreview {
        ReferenceImportPreview(
            parserVersion: parserVersion,
            previewChecksum: previewChecksum,
            destination: destination.domainDestination(),
            counts: counts.domainCounts(),
            rows: rows.map { $0.domainRow() }
        )
    }
}

struct SupabaseReferenceImportDestinationResponse: Decodable, Hashable, Sendable {
    var watchlistID: UUID?
    var watchlistName: String

    enum CodingKeys: String, CodingKey {
        case watchlistID = "watchlist_id"
        case watchlistName = "watchlist_name"
    }

    func domainDestination() -> ReferenceImportDestination {
        ReferenceImportDestination(watchlistID: watchlistID, watchlistName: watchlistName)
    }
}

struct SupabaseReferenceImportCountsResponse: Decodable, Hashable, Sendable {
    var totalRows: Int?
    var cleanAccounts: Int?
    var cleanReels: Int?
    var cleanAudio: Int?
    var needsReview: Int?
    var duplicates: Int?
    var invalid: Int?
    var importable: Int?

    enum CodingKeys: String, CodingKey {
        case totalRows = "total_rows"
        case cleanAccounts = "clean_accounts"
        case cleanReels = "clean_reels"
        case cleanAudio = "clean_audio"
        case needsReview = "needs_review"
        case duplicates
        case invalid
        case importable
    }

    func domainCounts() -> ReferenceImportCounts {
        ReferenceImportCounts(
            totalRows: totalRows ?? 0,
            cleanAccounts: cleanAccounts ?? 0,
            cleanReels: cleanReels ?? 0,
            cleanAudio: cleanAudio ?? 0,
            needsReview: needsReview ?? 0,
            duplicates: duplicates ?? 0,
            invalid: invalid ?? 0,
            importable: importable ?? 0
        )
    }
}

struct SupabaseReferenceImportRowResponse: Decodable, Hashable, Sendable {
    var clientRowID: String
    var lineNumber: Int
    var rawInput: String
    var typeChip: ReferenceImportTypeChip
    var classification: String
    var title: String
    var url: String?
    var notes: String?
    var previewState: ReferenceImportPreviewState
    var duplicateReason: String?
    var invalidReason: String?

    enum CodingKeys: String, CodingKey {
        case clientRowID = "client_row_id"
        case lineNumber = "line_number"
        case rawInput = "raw_input"
        case typeChip = "type_chip"
        case classification
        case title
        case url
        case notes
        case previewState = "preview_state"
        case duplicateReason = "duplicate_reason"
        case invalidReason = "invalid_reason"
    }

    func domainRow() -> ReferenceImportRow {
        ReferenceImportRow(
            clientRowID: clientRowID,
            lineNumber: lineNumber,
            rawInput: rawInput,
            typeChip: typeChip,
            classification: classification,
            title: title,
            url: url,
            notes: notes,
            previewState: previewState,
            duplicateReason: duplicateReason,
            invalidReason: invalidReason
        )
    }
}

struct SupabaseReferenceImportConfirmResponse: Decodable, Hashable, Sendable {
    var parserVersion: String
    var destination: SupabaseReferenceImportDestinationResponse
    var counts: SupabaseReferenceImportConfirmCountsResponse
    var toast: String?

    enum CodingKeys: String, CodingKey {
        case parserVersion = "parser_version"
        case destination
        case counts
        case toast
    }

    func domainResult() -> ReferenceImportConfirmResult {
        ReferenceImportConfirmResult(
            parserVersion: parserVersion,
            destination: destination.domainDestination(),
            counts: counts.domainCounts(),
            toast: toast ?? "Reference import complete."
        )
    }
}

struct SupabaseReferenceImportConfirmCountsResponse: Decodable, Hashable, Sendable {
    var imported: Int?
    var needsReview: Int?
    var duplicatesSkipped: Int?
    var invalid: Int?

    enum CodingKeys: String, CodingKey {
        case imported
        case needsReview = "needs_review"
        case duplicatesSkipped = "duplicates_skipped"
        case invalid
    }

    func domainCounts() -> ReferenceImportConfirmCounts {
        ReferenceImportConfirmCounts(
            imported: imported ?? 0,
            needsReview: needsReview ?? 0,
            duplicatesSkipped: duplicatesSkipped ?? 0,
            invalid: invalid ?? 0
        )
    }
}

struct SupabaseReferenceReviewRequest: Encodable, Sendable {
    var creatorID: UUID
    var item: ReferenceReviewItem
    var action: ReferenceReviewAction
    var edit: SupabaseReferenceReviewEditRequest?

    enum CodingKeys: String, CodingKey {
        case creatorID = "creator_id"
        case item
        case action
        case edit
    }

    init(request: ReferenceReviewRequest, context: WorkspaceContext) {
        creatorID = context.creatorID
        item = request.item
        action = request.action
        edit = request.edit.map(SupabaseReferenceReviewEditRequest.init)
    }
}

struct SupabaseReferenceReviewEditRequest: Encodable, Sendable {
    var targetType: ReferenceReviewEditTarget
    var handle: String?
    var url: String?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case targetType = "target_type"
        case handle
        case url
        case notes
    }

    init(edit: ReferenceReviewEdit) {
        targetType = edit.targetType
        handle = edit.handle
        url = edit.url
        notes = edit.notes
    }
}

struct SupabaseReferenceReviewResultResponse: Decodable, Hashable, Sendable {
    var itemID: UUID
    var kind: ReferenceReviewItemKind
    var action: ReferenceReviewAction
    var resultStatus: String
    var toast: String?

    enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case kind
        case action
        case resultStatus = "result_status"
        case toast
    }

    func domainResult() -> ReferenceReviewResult {
        ReferenceReviewResult(
            itemID: itemID,
            kind: kind,
            action: action,
            resultStatus: resultStatus,
            toast: toast ?? "Reference updated."
        )
    }
}
