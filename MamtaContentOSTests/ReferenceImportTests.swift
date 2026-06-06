import XCTest
@testable import MamtaContentOS

@MainActor
final class ReferenceImportTests: XCTestCase {
    func testPreviewResponseDecodesIntoDomainModel() throws {
        let data = Data(
            """
            {
              "parser_version": "reference-import-v1",
              "preview_checksum": "abc123",
              "destination": { "watchlist_name": "Inspiration" },
              "counts": {
                "total_rows": 3,
                "clean_accounts": 1,
                "clean_reels": 1,
                "clean_audio": 0,
                "needs_review": 1,
                "duplicates": 0,
                "invalid": 0,
                "importable": 3
              },
              "rows": [
                {
                  "client_row_id": "line-1",
                  "line_number": 1,
                  "raw_input": "@creator",
                  "type_chip": "Account",
                  "classification": "account",
                  "title": "@creator",
                  "url": null,
                  "notes": null,
                  "preview_state": "clean",
                  "duplicate_reason": null,
                  "invalid_reason": null
                }
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(SupabaseReferenceImportPreviewResponse.self, from: data)
        let preview = response.domainPreview()

        XCTAssertEqual(preview.parserVersion, "reference-import-v1")
        XCTAssertEqual(preview.previewChecksum, "abc123")
        XCTAssertEqual(preview.destination.watchlistName, "Inspiration")
        XCTAssertEqual(preview.counts.totalRows, 3)
        XCTAssertEqual(preview.counts.cleanAccounts, 1)
        XCTAssertEqual(preview.rows.first?.typeChip, .account)
        XCTAssertEqual(preview.rows.first?.previewState, .clean)
    }

    func testConfirmResponseDecodesIntoDomainResult() throws {
        let data = Data(
            """
            {
              "parser_version": "reference-import-v1",
              "destination": {
                "watchlist_id": "11111111-1111-1111-1111-111111111111",
                "watchlist_name": "Inspiration"
              },
              "counts": {
                "imported": 5,
                "needs_review": 2,
                "duplicates_skipped": 1,
                "invalid": 1
              },
              "toast": "Imported 5. 2 need review. 1 duplicates skipped. 1 could not be imported."
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(SupabaseReferenceImportConfirmResponse.self, from: data)
        let result = response.domainResult()

        XCTAssertEqual(result.destination.watchlistName, "Inspiration")
        XCTAssertEqual(result.counts.imported, 5)
        XCTAssertEqual(result.counts.needsReview, 2)
        XCTAssertEqual(result.counts.duplicatesSkipped, 1)
        XCTAssertEqual(result.counts.invalid, 1)
        XCTAssertTrue(result.toast.contains("Imported 5"))
    }

    func testReviewResponseDecodesIntoDomainResult() throws {
        let data = Data(
            """
            {
              "item_id": "22222222-2222-2222-2222-222222222222",
              "kind": "source_reference",
              "action": "edit",
              "result_status": "confirmed",
              "toast": "Reference confirmed."
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(SupabaseReferenceReviewResultResponse.self, from: data)
        let result = response.domainResult()

        XCTAssertEqual(result.kind, .sourceReference)
        XCTAssertEqual(result.action, .edit)
        XCTAssertEqual(result.resultStatus, "confirmed")
        XCTAssertEqual(result.toast, "Reference confirmed.")
    }

    func testFixtureRuntimeDoesNotPretendReferenceImportWorks() async {
        let services = AppServices.fixtureBacked()

        let preview = await services.previewReferenceImportImmediately(
            rawText: "@creator",
            inputType: .paste
        )

        XCTAssertNil(preview)
        XCTAssertEqual(services.lastReferenceImportError, "Connect live workspace to import references.")
        XCTAssertFalse(services.isLiveSupabaseRuntime)
    }
}
