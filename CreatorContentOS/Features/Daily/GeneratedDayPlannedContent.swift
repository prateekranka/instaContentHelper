import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct GeneratedReadOnlyField: View {
    let title: String
    let value: String

    var body: some View {
        if let normalizedValue = value.nilIfBlank {
            VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                Text(title)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                Text(normalizedValue)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

enum SceneTiming {
    static func windows(for scenes: [ShotScene]) -> [String] {
        var cursor = 0
        return scenes.map { scene in
            let start = cursor
            cursor += seconds(from: scene.duration) ?? 0
            return "\(timecode(start))-\(timecode(cursor))"
        }
    }

    static func totalSeconds(for scenes: [ShotScene]) -> Int? {
        let durations = scenes.compactMap { seconds(from: $0.duration) }
        guard durations.count == scenes.count else { return nil }
        return durations.reduce(0, +)
    }

    static func sceneTitle(for scenes: [ShotScene], index: Int) -> String? {
        guard let scene = scenes[safe: index] else { return nil }
        return "Scene \(String(format: "%02d", scene.number)): \(scene.title)"
    }

    private static func seconds(from duration: String) -> Int? {
        Int(duration.prefix { $0.isNumber })
    }

    private static func timecode(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension ProductionTimelineItem {
    var timelineTarget: String? {
        videoPortion?.nilIfBlank ?? placement?.nilIfBlank ?? shot?.nilIfBlank
    }

    var timelineBody: String {
        voiceover?.nilIfBlank
            ?? onScreenText?.nilIfBlank
            ?? detail.nilIfBlank
            ?? title.nilIfBlank
            ?? "Detail not specified."
    }
}

extension String {
    var containsTimestamp: Bool {
        range(of: #"(\d{1,2}:\d{2}|\d+\s?-\s?\d+\s?s|\d+\s?s)"#, options: .regularExpression) != nil
    }
}

struct GeneratedDayPlannedContent: View {
    let card: GeneratedDailyCardDraft
    var onStoryboardAssetsChanged: (([StoryboardThumbnailAsset]) -> Void)?
    /// When true, Storyboard / Script / Caption use folder tabs (Plan + Today).
    var usesFolderTabs: Bool = true
    @State private var selectedFolderTab: PackageFolderTab = .storyboard

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            InstagramExecutionSummary(card: card)
            if usesFolderTabs {
                PackageFolderTabs(selection: $selectedFolderTab) { tab in
                    folderPanel(for: tab)
                        .id(tab)
                }
            } else {
                GeneratedStoryboardBreakdownBlock(
                    card: card,
                    onStoryboardAssetsChanged: onStoryboardAssetsChanged
                )
                GeneratedScriptTimelineBlock(card: card)
                InstagramCaptionPostBlock(card: card)
            }
        }
        .onChange(of: card.id) { _, _ in
            selectedFolderTab = .storyboard
        }
    }

    @ViewBuilder
    private func folderPanel(for tab: PackageFolderTab) -> some View {
        switch tab {
        case .storyboard:
            GeneratedStoryboardBreakdownContent(
                card: card,
                onStoryboardAssetsChanged: onStoryboardAssetsChanged
            )
        case .script:
            GeneratedScriptTimelineContent(card: card, showsSectionChrome: false)
        case .caption:
            InstagramCaptionPostContent(card: card)
        }
    }
}

struct GeneratedStoryboardBreakdownBlock: View {
    let card: GeneratedDailyCardDraft
    var onStoryboardAssetsChanged: (([StoryboardThumbnailAsset]) -> Void)?

    var body: some View {
        if !rows.isEmpty {
            PocketSheetCard {
                GeneratedStoryboardBreakdownContent(
                    card: card,
                    onStoryboardAssetsChanged: onStoryboardAssetsChanged
                )
            }
        }
    }

    private var rows: [GeneratedStoryboardBreakdownRow] {
        GeneratedStoryboardBreakdown.rows(for: card)
    }
}

struct GeneratedStoryboardBreakdownContent: View {
    @Environment(AppServices.self) private var services
    let card: GeneratedDailyCardDraft
    var onStoryboardAssetsChanged: (([StoryboardThumbnailAsset]) -> Void)?
    @State private var thumbnailError: String?

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                storyboardHeader
                GeneratedStoryboardTable(rows: rows)
                if let filmingTip = effectiveCard.postInstructions.nilIfBlank {
                    GeneratedStoryboardTip(text: filmingTip)
                }
                if let displayedThumbnailError {
                    Text(displayedThumbnailError)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .task(id: storyboardPreparationTaskID) {
                guard missingThumbnailCount > 0 else { return }
                await services.prepareStoryboardThumbnailsForVisibleCard(dailyCardID: card.id)
            }
        } else {
            Text("No storyboard scenes yet.")
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        }
    }

    private var storyboardHeader: some View {
        HStack {
            Spacer(minLength: 0)
            visualsButton
        }
    }

    @ViewBuilder
    private var visualsButton: some View {
        Button(action: generateThumbnails) {
            HStack(spacing: PocketSheetSpace.xxs) {
                if isGeneratingThumbnails {
                    ProgressView()
                        .controlSize(.small)
                        .tint(PocketSheetTheme.Color.ink)
                } else {
                    Image(systemName: missingThumbnailCount > 0 ? "photo.badge.plus" : "photo.stack")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(visualsButtonLabel)
                    .font(PocketSheetType.status)
            }
            .padding(.horizontal, PocketSheetSpace.xs)
            .frame(minHeight: 44)
            .background(PocketSheetTheme.Color.paperRaised, in: Capsule())
        }
        .buttonStyle(PocketSheetPressFeedbackStyle())
        // Keep label ink-on-paper; do not inherit inversePaper from the ink storyboard chrome.
        .foregroundStyle(PocketSheetTheme.Color.ink)
        .disabled(isGeneratingThumbnails)
        .opacity(isGeneratingThumbnails ? 0.72 : 1)
        .accessibilityIdentifier("weekly.storyboard.generateVisuals")
    }

    private var rows: [GeneratedStoryboardBreakdownRow] {
        GeneratedStoryboardBreakdown.rows(for: effectiveCard)
    }

    private var missingThumbnailCount: Int {
        rows.filter { $0.thumbnailURL == nil }.count
    }

    private var isGeneratingThumbnails: Bool {
        services.generatingStoryboardThumbnailCardIDs.contains(card.id)
    }

    private var effectiveCard: GeneratedDailyCardDraft {
        services.generatedDailyCard(for: card.id) ?? card
    }

    private var displayedThumbnailError: String? {
        services.storyboardThumbnailErrors[card.id] ?? thumbnailError
    }

    private var storyboardPreparationTaskID: String {
        "\(card.id.uuidString)-\(missingThumbnailCount)-\(services.aiConsentEpoch)"
    }

    private var visualsButtonLabel: String {
        if isGeneratingThumbnails {
            return missingThumbnailCount > 0 ? "Preparing" : "Refreshing"
        }
        return missingThumbnailCount > 0 ? "Prepare visuals" : "Refresh"
    }

    private func generateThumbnails() {
        guard !isGeneratingThumbnails else { return }
        let shouldForceRefresh = missingThumbnailCount == 0

        thumbnailError = nil
        Task {
            do {
                let assets = try await services.generateStoryboardThumbnails(
                    for: effectiveCard,
                    force: shouldForceRefresh,
                    revisionInstructions: nil
                )
                onStoryboardAssetsChanged?(assets)
            } catch {
                let description = error.localizedDescription
                thumbnailError = description == AIConsentCopy.errorCode
                    ? AIConsentCopy.blockedMessage
                    : description
            }
        }
    }
}

/// Phone-first storyboard presentation. Each shot keeps its source thumbnail,
/// timing, and production copy together so long content wraps without clipping.
struct GeneratedStoryboardTable: View {
    let rows: [GeneratedStoryboardBreakdownRow]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            ForEach(rows) { row in
                GeneratedStoryboardShotCard(row: row)
            }
        }
    }
}

struct GeneratedStoryboardShotCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let row: GeneratedStoryboardBreakdownRow

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            headerLayout {
                Text("SHOT \(String(format: "%02d", row.sceneNumber))")
                    .font(PocketSheetType.sectionLabel)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .tracking(0.44)
                Spacer(minLength: PocketSheetSpace.s)
                Text(row.timecode)
                    .font(PocketSheetType.status)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }

            GeneratedStoryboardThumbnail(
                url: row.thumbnailURL,
                fallbackSystemImage: "camera"
            )

            GeneratedStoryboardShotField(title: "Title", value: row.visualShot)
            GeneratedStoryboardShotField(title: "Instructions", value: row.whatToShow)
            GeneratedStoryboardShotField(title: "Dialogue", value: "\"\(row.audioDialogue)\"")

            VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                Text("Overlay")
                    .font(PocketSheetType.status)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                Text(row.onScreenText)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let placement = row.onScreenTextPlacement?.nilIfBlank {
                    Text(placement)
                        .font(PocketSheetType.status)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PocketSheetSpace.m)
        .background(PocketSheetTheme.Color.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                .stroke(PocketSheetTheme.Color.hairline.opacity(0.78), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Shot \(row.sceneNumber), \(row.timecode). Title: \(row.visualShot). Instructions: \(row.whatToShow). Dialogue: \(row.audioDialogue). Overlay: \(row.onScreenText)"
        )
    }

    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PocketSheetSpace.s))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: PocketSheetSpace.s))
    }
}

private struct GeneratedStoryboardShotField: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
            Text(title)
                .font(PocketSheetType.status)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            Text(value)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GeneratedStoryboardThumbnail: View {
    let url: URL?
    var fallbackSystemImage: String? = nil

    var body: some View {
        ZStack {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        thumbnailPlaceholder(isLoading: true)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        thumbnailPlaceholder(isLoading: false)
                    @unknown default:
                        thumbnailPlaceholder(isLoading: false)
                    }
                }
            } else {
                thumbnailPlaceholder(isLoading: false)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(PocketSheetTheme.Color.hairline.opacity(0.58), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func thumbnailPlaceholder(isLoading: Bool) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    PocketSheetTheme.Color.paper.opacity(0.9),
                    PocketSheetTheme.Color.paperRaised.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: fallbackSystemImage?.nilIfBlank ?? "photo")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
        }
    }
}

struct GeneratedStoryboardTip: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: PocketSheetSpace.s) {
            Image(systemName: "lightbulb")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                Text("Tips for Filming")
                    .font(PocketSheetType.sectionLabel)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: PocketSheetSpace.xs) {
                        Text("•")
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        Text(bullet)
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(PocketSheetSpace.s)
        .background(PocketSheetTheme.Color.fillMuted)
        .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
    }

    private var bullets: [String] {
        var lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.count == 1, let single = lines.first {
            lines = single
                .components(separatedBy: ". ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { $0.hasSuffix(".") ? $0 : $0 + "." }
        }
        return lines
    }
}

struct InstagramExecutionSummary: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            HStack(alignment: .firstTextBaseline, spacing: PocketSheetSpace.s) {
                Text(formatLabel)
                    .font(PocketSheetType.sectionLabel)
                    .foregroundStyle(PocketSheetTheme.Color.inversePaper)
                    .padding(.horizontal, PocketSheetSpace.s)
                    .frame(minHeight: 26)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(PocketSheetTheme.Color.inverseInk, in: Capsule())
                    .accessibilityIdentifier("plan.package.format")
                Text(durationLabel)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .accessibilityIdentifier("plan.package.duration")
                Spacer(minLength: PocketSheetSpace.s)
            }
        }
    }

    private var formatLabel: String {
        card.format?.nilIfBlank ?? "Reel"
    }

    private var durationLabel: String {
        if card.format?.lowercased() == "post" { return "Photo / carousel" }
        if let durationSeconds = card.durationSeconds, durationSeconds > 0 {
            return "\(durationSeconds.formatted()) sec edit"
        }
        if let seconds = SceneTiming.totalSeconds(for: card.sceneList), seconds > 0 {
            return "\(seconds.formatted()) sec edit"
        }
        return "\(card.estimatedShootMinutes) min shoot"
    }

}

struct InstagramCaptionPostBlock: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        PocketSheetCard {
            InstagramCaptionPostContent(card: card)
        }
    }
}

struct InstagramCaptionPostContent: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            GeneratedReadOnlyField(title: "Caption", value: card.caption)
            GeneratedReadOnlyField(title: "CTA", value: card.cta)
            GeneratedReadOnlyField(title: "Cover text", value: card.coverText)
            GeneratedReadOnlyField(title: "Post instructions", value: card.postInstructions)
            GeneratedReadOnlyField(title: "Hashtags", value: hashtagSummary)
            PackageCopyButton(
                title: "Copy caption",
                text: PackageCopyText.caption(for: card)
            )
            .accessibilityIdentifier("plan.package.copyCaption")
        }
    }

    private var hashtagSummary: String {
        card.hashtags.map { "#\($0.trimmingCharacters(in: CharacterSet(charactersIn: "#")))" }
            .joined(separator: " ")
    }
}

struct GeneratedScriptTimelineBlock: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        let rows = GeneratedStoryboardBreakdown.rows(for: card)
        if !rows.isEmpty {
            PocketSheetCard {
                GeneratedScriptTimelineContent(card: card, showsSectionChrome: true)
            }
            .accessibilityIdentifier("plan.script.timeline")
        }
    }
}

struct GeneratedScriptTimelineContent: View {
    let card: GeneratedDailyCardDraft
    var showsSectionChrome: Bool = true

    private var rows: [GeneratedStoryboardBreakdownRow] {
        GeneratedStoryboardBreakdown.rows(for: card)
    }

    private var copyableScript: String {
        PackageCopyText.script(for: card)
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                if showsSectionChrome {
                    HStack(spacing: PocketSheetSpace.s) {
                        Image(systemName: "text.alignleft")
                            .font(PocketSheetType.status)
                        Text("Script")
                            .font(PocketSheetType.sectionLabel)
                            .foregroundStyle(PocketSheetTheme.Color.inversePaper)
                        Spacer(minLength: PocketSheetSpace.s)
                        Text("\(rows.count.formatted()) \(rows.count == 1 ? "line" : "lines")")
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inversePaper)
                    }
                    .foregroundStyle(PocketSheetTheme.Color.inversePaper)
                    .padding(.horizontal, PocketSheetSpace.s)
                    .frame(minHeight: 38)
                    .background(PocketSheetTheme.Color.ink, in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                } else {
                    Text("\(rows.count.formatted()) \(rows.count == 1 ? "line" : "lines")")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .accessibilityIdentifier("plan.script.lineCount")
                }

                ForEach(rows) { row in
                    HStack(alignment: .top, spacing: PocketSheetSpace.s) {
                        GeneratedStoryboardThumbnail(
                            url: row.thumbnailURL,
                            fallbackSystemImage: card.sceneList[safe: row.sceneNumber - 1]?.symbol
                        )
                        .frame(width: 72, height: 54)
                        VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                            Text(row.timecode)
                                .font(PocketSheetType.status)
                                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            Text(row.audioDialogue)
                                .font(PocketSheetType.rowSubtitle)
                                .foregroundStyle(PocketSheetTheme.Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(PocketSheetSpace.s)
                    .background(PocketSheetTheme.Color.fillMuted)
                    .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                    .accessibilityIdentifier("plan.script.line.\(row.sceneNumber)")
                }

                PackageCopyButton(title: "Copy full script", text: copyableScript)
                    .accessibilityIdentifier("plan.package.copyScript")
            }
            .accessibilityIdentifier("plan.script.timeline")
        } else {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                Text("No script lines yet.")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                PackageCopyButton(title: "Copy full script", text: copyableScript)
                    .accessibilityIdentifier("plan.package.copyScript")
            }
        }
    }
}

struct PackageCopyButton: View {
    let title: String
    let text: String
    @State private var didCopy = false

    var body: some View {
        PocketSheetSecondaryAction(title: didCopy ? "Copied" : title) {
            #if canImport(UIKit)
            UIPasteboard.general.string = text
            #endif
            didCopy = true
        }
        .onChange(of: text) {
            didCopy = false
        }
    }
}
