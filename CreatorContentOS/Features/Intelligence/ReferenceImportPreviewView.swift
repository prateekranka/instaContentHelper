import SwiftUI

struct ReferenceImportPreviewView: View {
    let preview: ReferenceImportPreview

    @State private var showsDuplicates = false

    private var cleanRows: [ReferenceImportRow] {
        preview.rows.filter { $0.previewState == .clean }
    }

    private var needsReviewRows: [ReferenceImportRow] {
        preview.rows.filter { $0.previewState == .needsReview }
    }

    private var duplicateRows: [ReferenceImportRow] {
        preview.rows.filter { $0.previewState == .duplicate }
    }

    private var invalidRows: [ReferenceImportRow] {
        preview.rows.filter { $0.previewState == .invalid }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.l) {
            ReferenceImportSummaryBlock(preview: preview)

            if !cleanRows.isEmpty {
                ReferenceImportRowSection(
                    title: "Clean rows",
                    subtitle: "Will be imported after confirmation.",
                    rows: cleanRows
                )
            }

            if !needsReviewRows.isEmpty {
                ReferenceImportRowSection(
                    title: "Needs your call",
                    subtitle: "Imported as review items, not ready ideas.",
                    rows: needsReviewRows
                )
            }

            if !invalidRows.isEmpty {
                ReferenceImportRowSection(
                    title: "Invalid rows",
                    subtitle: "Not stored. Story URLs cannot be used.",
                    rows: invalidRows
                )
            }

            if !duplicateRows.isEmpty {
                ReferenceImportDuplicateSection(
                    rows: duplicateRows,
                    isExpanded: $showsDuplicates
                )
            }
        }
    }
}

struct ReferenceImportSummaryBlock: View {
    let preview: ReferenceImportPreview

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: MCOSpace.xs) {
                        Text("INSPIRATION")
                            .font(MCOType.tinyLabel)
                            .foregroundStyle(MCOTheme.Color.oxblood)
                        Text("Preview")
                            .font(MCOType.cardTitle)
                            .foregroundStyle(MCOTheme.Color.ink)
                    }

                    Spacer(minLength: MCOSpace.s)

                    StatusChip(
                        text: "\(preview.counts.importable) importable",
                        tone: preview.counts.needsReview > 0 ? .warning : .ready
                    )
                }

                Text("Rows are parsed by the server. Confirming will import clean references and keep ambiguous rows in Needs your call.")
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: MCOSpace.s),
                        GridItem(.flexible(), spacing: MCOSpace.s),
                        GridItem(.flexible(), spacing: MCOSpace.s)
                    ],
                    alignment: .leading,
                    spacing: MCOSpace.s
                ) {
                    ReferenceImportMetric(value: preview.counts.cleanAccounts, label: "Accounts")
                    ReferenceImportMetric(value: preview.counts.cleanReels, label: "Reels")
                    ReferenceImportMetric(value: preview.counts.cleanAudio, label: "Audio")
                    ReferenceImportMetric(value: preview.counts.needsReview, label: "Review")
                    ReferenceImportMetric(value: preview.counts.duplicates, label: "Duplicate")
                    ReferenceImportMetric(value: preview.counts.invalid, label: "Invalid")
                }
            }
        }
    }
}

struct ReferenceImportMetric: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xxs) {
            Text("\(value)")
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundStyle(value == 0 ? MCOTheme.Color.inkMuted : MCOTheme.Color.ink)
            Text(label.uppercased())
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ReferenceImportRowSection: View {
    let title: String
    let subtitle: String
    let rows: [ReferenceImportRow]

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            ShelfHeader(title: title, trailing: "\(rows.count)")
            Text(subtitle)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.inkMuted)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    ReferenceImportPreviewRow(row: row)
                    Hairline()
                }
            }
        }
    }
}

struct ReferenceImportDuplicateSection: View {
    let rows: [ReferenceImportRow]
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    ReferenceImportPreviewRow(row: row)
                    Hairline()
                }
            }
            .padding(.top, MCOSpace.s)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text("DUPLICATES")
                        .font(MCOType.tinyLabel)
                        .foregroundStyle(MCOTheme.Color.oxblood)
                    Text("\(rows.count) rows skipped unless reviewed later")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                }
                Spacer(minLength: MCOSpace.s)
                StatusChip(text: "\(rows.count)", tone: .quiet)
            }
        }
        .tint(MCOTheme.Color.oxblood)
    }
}

struct ReferenceImportPreviewRow: View {
    let row: ReferenceImportRow

    var body: some View {
        HStack(alignment: .top, spacing: MCOSpace.m) {
            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text("\(row.lineNumber)")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                ReferenceImportTypeChipView(typeChip: row.typeChip)
            }
            .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                HStack(alignment: .firstTextBaseline, spacing: MCOSpace.s) {
                    Text(row.title)
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .foregroundStyle(row.previewState == .invalid ? MCOTheme.Color.clay : MCOTheme.Color.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)

                    Spacer(minLength: MCOSpace.xs)

                    StatusChip(text: row.previewState.label, tone: row.previewState.tone)
                }

                if let url = row.url, !url.isEmpty {
                    Text(url)
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let note = rowDisplayNote {
                    Text(note)
                        .font(MCOType.caption)
                        .foregroundStyle(row.previewState == .invalid ? MCOTheme.Color.clay : MCOTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, MCOSpace.s)
        .accessibilityElement(children: .combine)
    }

    private var rowDisplayNote: String? {
        if let invalidReason = row.invalidReason, !invalidReason.isEmpty {
            return invalidReason
        }

        if let duplicateReason = row.duplicateReason, !duplicateReason.isEmpty {
            return duplicateReason
        }

        if let notes = row.notes, !notes.isEmpty {
            return notes
        }

        return row.rawInput.isEmpty ? nil : row.rawInput
    }
}

struct ReferenceImportTypeChipView: View {
    let typeChip: ReferenceImportTypeChip

    var body: some View {
        Text(typeChip.rawValue)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(typeChip.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, MCOSpace.xs)
            .padding(.vertical, 5)
            .background(typeChip.foreground.opacity(0.08))
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(typeChip.foreground.opacity(0.28), lineWidth: 1)
            }
    }
}

extension ReferenceImportPreviewState {
    var label: String {
        switch self {
        case .clean:
            "Clean"
        case .needsReview:
            "Needs call"
        case .duplicate:
            "Duplicate"
        case .invalid:
            "Invalid"
        }
    }

    var tone: ChipTone {
        switch self {
        case .clean:
            .ready
        case .needsReview, .invalid:
            .warning
        case .duplicate:
            .quiet
        }
    }
}

extension ReferenceImportTypeChip {
    var foreground: Color {
        switch self {
        case .account:
            MCOTheme.Color.sageDeep
        case .reel:
            MCOTheme.Color.oxblood
        case .audio:
            MCOTheme.Color.brass
        case .unknown:
            MCOTheme.Color.inkMuted
        }
    }
}

#Preview {
    ZStack {
        MCOTheme.Color.paper.ignoresSafeArea()
        ScrollView {
            ReferenceImportPreviewView(preview: .referenceImportFixture)
                .padding(MCOSpace.l)
        }
    }
}

extension ReferenceImportPreview {
    static let referenceImportFixture = ReferenceImportPreview(
        parserVersion: "v1",
        previewChecksum: "fixture",
        destination: ReferenceImportDestination(
            watchlistID: nil,
            watchlistName: "Inspiration"
        ),
        counts: ReferenceImportCounts(
            totalRows: 8,
            cleanAccounts: 2,
            cleanReels: 2,
            cleanAudio: 1,
            needsReview: 1,
            duplicates: 1,
            invalid: 1,
            importable: 6
        ),
        rows: [
            ReferenceImportRow(
                clientRowID: "1",
                lineNumber: 1,
                rawInput: "@fitover60",
                typeChip: .account,
                classification: "account",
                title: "@fitover60",
                url: nil,
                notes: "Benchmark creator",
                previewState: .clean,
                duplicateReason: nil,
                invalidReason: nil
            ),
            ReferenceImportRow(
                clientRowID: "2",
                lineNumber: 2,
                rawInput: "https://www.instagram.com/reel/ABC123/",
                typeChip: .reel,
                classification: "reel",
                title: "Race week warmup reel",
                url: "https://www.instagram.com/reel/ABC123/",
                notes: "Confirmed because admin pasted it intentionally.",
                previewState: .clean,
                duplicateReason: nil,
                invalidReason: nil
            ),
            ReferenceImportRow(
                clientRowID: "3",
                lineNumber: 3,
                rawInput: "keep an eye on post-run family moment",
                typeChip: .unknown,
                classification: "unknown",
                title: "keep an eye on post-run family moment",
                url: nil,
                notes: "Needs your call",
                previewState: .needsReview,
                duplicateReason: nil,
                invalidReason: nil
            ),
            ReferenceImportRow(
                clientRowID: "4",
                lineNumber: 4,
                rawInput: "https://www.instagram.com/stories/creator/123",
                typeChip: .unknown,
                classification: "invalid_story",
                title: "Instagram story URL",
                url: "https://www.instagram.com/stories/creator/123",
                notes: nil,
                previewState: .invalid,
                duplicateReason: nil,
                invalidReason: "Story URLs can't be used as references."
            ),
            ReferenceImportRow(
                clientRowID: "5",
                lineNumber: 5,
                rawInput: "@fitover60",
                typeChip: .account,
                classification: "account",
                title: "@fitover60",
                url: nil,
                notes: nil,
                previewState: .duplicate,
                duplicateReason: "Already active in Inspiration.",
                invalidReason: nil
            )
        ]
    )
}
