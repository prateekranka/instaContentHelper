import SwiftUI
import UniformTypeIdentifiers

typealias ReferenceImportPreviewAction = @MainActor (
    _ rawText: String,
    _ inputType: ReferenceImportInputType,
    _ filename: String?
) async throws -> ReferenceImportPreview

typealias ReferenceImportConfirmAction = @MainActor (
    _ rawText: String,
    _ inputType: ReferenceImportInputType,
    _ filename: String?,
    _ previewChecksum: String
) async throws -> ReferenceImportConfirmResult

struct ReferenceImportView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool

    let isLiveRuntime: Bool
    let previewReferenceImport: ReferenceImportPreviewAction
    let confirmReferenceImport: ReferenceImportConfirmAction
    var onFinished: () -> Void

    @State private var rawText = ""
    @State private var inputType: ReferenceImportInputType = .paste
    @State private var filename: String?
    @State private var preview: ReferenceImportPreview?
    @State private var result: ReferenceImportConfirmResult?
    @State private var isPreviewing = false
    @State private var isConfirming = false
    @State private var isFileImporterPresented = false
    @State private var message: ReferenceImportMessage?

    init(
        isLiveRuntime: Bool,
        previewReferenceImport: @escaping ReferenceImportPreviewAction,
        confirmReferenceImport: @escaping ReferenceImportConfirmAction,
        onFinished: @escaping () -> Void = {}
    ) {
        self.isLiveRuntime = isLiveRuntime
        self.previewReferenceImport = previewReferenceImport
        self.confirmReferenceImport = confirmReferenceImport
        self.onFinished = onFinished
    }

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header

                if !isLiveRuntime {
                    ReferenceImportLiveGate()
                }

                ReferenceImportInputBlock(
                    rawText: $rawText,
                    inputType: inputType,
                    filename: filename,
                    isEnabled: isLiveRuntime && !isBusy,
                    isInputFocused: $isInputFocused,
                    onChooseCSV: { isFileImporterPresented = true },
                    onClear: clearInput
                )

                if let message {
                    ReferenceImportMessageBanner(message: message)
                }

                if let preview {
                    ReferenceImportPreviewView(preview: preview)
                } else {
                    ReferenceImportEmptyGuidance()
                }

                if let result {
                    ReferenceImportSuccessBlock(result: result)
                }
            }
        } bottomBar: {
            GlassCommandBar {
                SecondaryActionButton(title: preview == nil ? "Close" : "Edit paste") {
                    if preview == nil {
                        dismiss()
                    } else {
                        preview = nil
                        result = nil
                        isInputFocused = true
                    }
                }
                .frame(maxWidth: 132)

                PrimaryActionButton(
                    title: primaryButtonTitle,
                    systemImage: preview == nil ? "text.badge.plus" : "checkmark.circle"
                ) {
                    Task {
                        if preview == nil {
                            await previewImport()
                        } else {
                            await confirmImport()
                        }
                    }
                }
                .disabled(!canRunPrimaryAction)
            }
        }
        .navigationBarHidden(true)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: ReferenceImportFileType.allowedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result.map { $0.first })
        }
        .overlay(alignment: .top) {
            if isBusy {
                ReferenceImportProgressPill(text: isConfirming ? "Saving import" : "Preparing preview")
                    .padding(.top, MCOSpace.s)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: MCOSpace.m) {
            HStack(alignment: .top, spacing: MCOSpace.s) {
                Text("MC")
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.brass)
                    .frame(width: 42, height: 42)
                    .background(MCOTheme.Color.paperRaised, in: Circle())
                    .overlay {
                        Circle().stroke(MCOTheme.Color.hairline, lineWidth: 1)
                    }

                Spacer()

                FloatingIconButton(systemImage: "xmark", label: "Close Reference Import") {
                    dismiss()
                }
            }

            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text("MANAGER INTELLIGENCE")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Text("Inspiration")
                    .font(MCOType.display)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("Paste handles, reel links, audio links, or a CSV. The server decides what is clean and what needs your call.")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var primaryButtonTitle: String {
        if isPreviewing {
            return "Previewing"
        }

        if isConfirming {
            return "Saving"
        }

        return preview == nil ? "Preview import" : "Import clean rows"
    }

    private var canRunPrimaryAction: Bool {
        guard isLiveRuntime, !isBusy else { return false }
        if preview == nil {
            return !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return result == nil
    }

    private var isBusy: Bool {
        isPreviewing || isConfirming
    }

    private func clearInput() {
        rawText = ""
        filename = nil
        inputType = .paste
        preview = nil
        result = nil
        message = nil
    }

    private func previewImport() async {
        guard canRunPrimaryAction else { return }
        isInputFocused = false
        isPreviewing = true
        message = nil
        result = nil
        defer { isPreviewing = false }

        do {
            preview = try await previewReferenceImport(rawText, inputType, filename)
        } catch {
            preview = nil
            message = .error(error.localizedDescription)
        }
    }

    private func confirmImport() async {
        guard let preview, canRunPrimaryAction else { return }
        isConfirming = true
        message = nil
        defer { isConfirming = false }

        do {
            let confirmResult = try await confirmReferenceImport(
                rawText,
                inputType,
                filename,
                preview.previewChecksum
            )
            result = confirmResult
            message = .success(confirmResult.toast)
            onFinished()
        } catch {
            message = .error(error.localizedDescription)
        }
    }

    private func handleFileImport(_ result: Result<URL?, Error>) {
        switch result {
        case .success(let optionalURL):
            guard let url = optionalURL else {
                message = .error("No file selected.")
                return
            }

            do {
                let fileText = try ReferenceImportFileLoader.loadText(from: url)
                rawText = fileText
                filename = url.lastPathComponent
                inputType = .csv
                preview = nil
                self.result = nil
                message = .success("Loaded \(url.lastPathComponent). Preview before importing.")
            } catch {
                message = .error(error.localizedDescription)
            }
        case .failure(let error):
            message = .error(error.localizedDescription)
        }
    }
}

struct ReferenceImportInputBlock: View {
    @Binding var rawText: String
    let inputType: ReferenceImportInputType
    let filename: String?
    let isEnabled: Bool
    var isInputFocused: FocusState<Bool>.Binding
    let onChooseCSV: () -> Void
    let onClear: () -> Void

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                        Text("INPUT")
                            .font(MCOType.tinyLabel)
                            .foregroundStyle(MCOTheme.Color.oxblood)
                        Text(inputLabel)
                            .font(.system(size: 18, weight: .regular, design: .serif))
                            .foregroundStyle(MCOTheme.Color.ink)
                            .lineLimit(1)
                    }

                    Spacer(minLength: MCOSpace.s)

                    HStack(spacing: MCOSpace.xs) {
                        Button(action: onChooseCSV) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isEnabled ? MCOTheme.Color.ink : MCOTheme.Color.inkMuted)
                        .disabled(!isEnabled)
                        .accessibilityLabel("Choose CSV")

                        Button(action: onClear) {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(rawText.isEmpty ? MCOTheme.Color.inkMuted : MCOTheme.Color.clay)
                        .disabled(rawText.isEmpty || !isEnabled)
                        .accessibilityLabel("Clear import input")
                    }
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous)
                        .fill(MCOTheme.Color.paper.opacity(0.72))
                        .overlay {
                            RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous)
                                .stroke(MCOTheme.Color.hairline, lineWidth: 1)
                        }

                    if rawText.isEmpty {
                        Text("Paste Instagram handles, profile URLs, reel/audio links, one note per line, or CSV text.")
                            .font(MCOType.bodySmall)
                            .foregroundStyle(MCOTheme.Color.inkMuted)
                            .padding(MCOSpace.s)
                    }

                    TextEditor(text: $rawText)
                        .focused(isInputFocused)
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.ink)
                        .scrollContentBackground(.hidden)
                        .padding(MCOSpace.xs)
                        .disabled(!isEnabled)
                        .opacity(isEnabled ? 1 : 0.55)
                }
                .frame(minHeight: 168)

                HStack(alignment: .firstTextBaseline) {
                    Text("Max 500 rows. Story URLs are rejected.")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                    Spacer(minLength: MCOSpace.s)
                    Text("\(nonEmptyLineCount) rows")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                }
            }
        }
    }

    private var inputLabel: String {
        if let filename {
            return filename
        }

        return inputType == .csv ? "CSV import" : "Paste import"
    }

    private var nonEmptyLineCount: Int {
        rawText
            .split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }
}

struct ReferenceImportLiveGate: View {
    var body: some View {
        HStack(alignment: .top, spacing: MCOSpace.s) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(MCOTheme.Color.brass)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: MCOSpace.xs) {
                Text("Live workspace required")
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                Text("Reference Import writes through Supabase Edge Functions. Fixtures keep Creator Mode unchanged but do not import.")
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(MCOSpace.m)
        .background(MCOTheme.Color.brass.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous)
                .stroke(MCOTheme.Color.brass.opacity(0.32), lineWidth: 1)
        }
    }
}

struct ReferenceImportEmptyGuidance: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.s) {
            ShelfHeader(title: "What the preview will separate", trailing: nil)

            VStack(spacing: 0) {
                ReferenceImportGuideRow(
                    symbol: "person.crop.circle",
                    title: "Accounts",
                    detail: "Confirmed profile URLs and handles join Inspiration."
                )
                Hairline()
                ReferenceImportGuideRow(
                    symbol: "play.rectangle",
                    title: "Reels and audio",
                    detail: "Clean links are accepted because you pasted them intentionally."
                )
                Hairline()
                ReferenceImportGuideRow(
                    symbol: "questionmark.circle",
                    title: "Unknown rows",
                    detail: "Ambiguous notes become Needs your call review items."
                )
                Hairline()
                ReferenceImportGuideRow(
                    symbol: "exclamationmark.triangle",
                    title: "Stories",
                    detail: "Story URLs are rejected and never stored."
                )
            }
        }
    }
}

struct ReferenceImportGuideRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: MCOSpace.m) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(MCOTheme.Color.brass)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text(title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(detail)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: MCOSpace.s)
        }
        .padding(.vertical, MCOSpace.s)
    }
}

struct ReferenceImportSuccessBlock: View {
    let result: ReferenceImportConfirmResult

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text("CONFIRMED")
                        .font(MCOType.tinyLabel)
                        .foregroundStyle(MCOTheme.Color.sageDeep)
                    Spacer(minLength: MCOSpace.s)
                    StatusChip(text: result.destination.watchlistName, tone: .ready)
                }

                Text(result.toast)
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(MCOTheme.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: MCOSpace.m) {
                    ReferenceImportMetric(value: result.counts.imported, label: "Imported")
                    ReferenceImportMetric(value: result.counts.needsReview, label: "Review")
                    ReferenceImportMetric(value: result.counts.duplicatesSkipped, label: "Skipped")
                }
            }
        }
    }
}

enum ReferenceImportMessage: Equatable {
    case success(String)
    case error(String)

    var text: String {
        switch self {
        case .success(let text), .error(let text):
            text
        }
    }

    var tone: ChipTone {
        switch self {
        case .success:
            .ready
        case .error:
            .warning
        }
    }

    var symbol: String {
        switch self {
        case .success:
            "checkmark.circle"
        case .error:
            "exclamationmark.triangle"
        }
    }
}

struct ReferenceImportMessageBanner: View {
    let message: ReferenceImportMessage

    var body: some View {
        HStack(alignment: .top, spacing: MCOSpace.s) {
            Image(systemName: message.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(message.tone.foreground)
                .frame(width: 24)

            Text(message.text)
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: MCOSpace.s)
        }
        .padding(MCOSpace.s)
        .background(message.tone.background)
        .clipShape(RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MCOShape.blockRadius, style: .continuous)
                .stroke(message.tone.stroke, lineWidth: 1)
        }
    }
}

struct ReferenceImportProgressPill: View {
    let text: String

    var body: some View {
        HStack(spacing: MCOSpace.xs) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.ink)
        }
        .padding(.horizontal, MCOSpace.m)
        .padding(.vertical, MCOSpace.xs)
        .background(MCOTheme.Color.paperRaised.opacity(0.86))
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(MCOTheme.Color.hairline, lineWidth: 1)
        }
    }
}

enum ReferenceImportFileType {
    static let allowedTypes: [UTType] = [
        .commaSeparatedText,
        .plainText,
        .text
    ]
}

enum ReferenceImportFileLoader {
    static func loadText(from url: URL) throws -> String {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try String(contentsOf: url, encoding: .utf8)
    }
}

#Preview("Reference Import - Live") {
    NavigationStack {
        ReferenceImportView(
            isLiveRuntime: true,
            previewReferenceImport: { _, _, _ in .referenceImportFixture },
            confirmReferenceImport: { _, _, _, _ in
                ReferenceImportConfirmResult(
                    parserVersion: "v1",
                    destination: ReferenceImportDestination(
                        watchlistID: nil,
                        watchlistName: "Inspiration"
                    ),
                    counts: ReferenceImportConfirmCounts(
                        imported: 5,
                        needsReview: 1,
                        duplicatesSkipped: 1,
                        invalid: 1
                    ),
                    toast: "Imported 5. 1 needs review. 1 duplicate skipped."
                )
            }
        )
    }
}

#Preview("Reference Import - Fixture Gate") {
    NavigationStack {
        ReferenceImportView(
            isLiveRuntime: false,
            previewReferenceImport: { _, _, _ in .referenceImportFixture },
            confirmReferenceImport: { _, _, _, _ in
                ReferenceImportConfirmResult(
                    parserVersion: "v1",
                    destination: ReferenceImportDestination(watchlistID: nil, watchlistName: "Inspiration"),
                    counts: ReferenceImportConfirmCounts(imported: 0, needsReview: 0, duplicatesSkipped: 0, invalid: 0),
                    toast: "Fixture runtime."
                )
            }
        )
    }
}
