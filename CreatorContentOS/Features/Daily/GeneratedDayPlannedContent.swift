import SwiftUI

struct GeneratedDayPlannedContent: View {
    let card: GeneratedDailyCardDraft
    var onStoryboardAssetsChanged: (([StoryboardThumbnailAsset]) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.m) {
            InstagramExecutionSummary(card: card)
            GeneratedStoryboardBreakdownBlock(
                card: card,
                onStoryboardAssetsChanged: onStoryboardAssetsChanged
            )
            GeneratedScriptTimelineBlock(card: card)
            InstagramCaptionPostBlock(card: card)
        }
    }
}

struct GeneratedStoryboardBreakdownBlock: View {
    let card: GeneratedDailyCardDraft
    var onStoryboardAssetsChanged: (([StoryboardThumbnailAsset]) -> Void)?

    var body: some View {
        if !rows.isEmpty {
            JournalBlock {
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
    @State private var refreshInstructions = ""

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                storyboardHeader
                GeneratedStoryboardTable(rows: rows)
                if let filmingTip = effectiveCard.postInstructions.nilIfBlank {
                    GeneratedStoryboardTip(text: filmingTip)
                }
                if let thumbnailError {
                    Text(thumbnailError)
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.oxblood)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .task(id: storyboardPreparationTaskID) {
                guard missingThumbnailCount > 0 else { return }
                await services.prepareStoryboardThumbnailsForVisibleCard(dailyCardID: card.id)
            }
        }
    }

    private var storyboardHeader: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            HStack(spacing: MCOSpace.s) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text("Storyboard")
                    .font(MCOType.tinyLabel)
                Spacer(minLength: MCOSpace.s)
                Text(durationLabel)
                    .font(MCOType.caption)
                visualsButton
            }
            .foregroundStyle(MCOTheme.Color.paperRaised)
            .padding(.horizontal, MCOSpace.s)
            .frame(minHeight: 38)
            .background(MCOTheme.Color.ink, in: RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))

            Text(effectiveCard.hook?.nilIfBlank ?? effectiveCard.title)
                .font(MCOType.headline)
                .foregroundStyle(MCOTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            refreshDirectionField
        }
    }

    private var refreshDirectionField: some View {
        HStack(alignment: .top, spacing: MCOSpace.xs) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MCOTheme.Color.inkMuted)
                .padding(.top, 8)
            TextField("What should change in the visuals?", text: $refreshInstructions, axis: .vertical)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.ink)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .submitLabel(.done)
        }
        .padding(.horizontal, MCOSpace.s)
        .padding(.vertical, MCOSpace.xs)
        .background(
            MCOTheme.Color.paperRaised.opacity(0.78),
            in: RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                .stroke(MCOTheme.Color.hairlineStrong.opacity(0.48), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var visualsButton: some View {
        Button(action: generateThumbnails) {
            HStack(spacing: MCOSpace.xxs) {
                if isGeneratingThumbnails {
                    ProgressView()
                        .controlSize(.small)
                        .tint(MCOTheme.Color.paperRaised)
                } else {
                    Image(systemName: missingThumbnailCount > 0 ? "photo.badge.plus" : "photo.stack")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(visualsButtonLabel)
                    .font(MCOType.caption.weight(.semibold))
            }
            .padding(.horizontal, MCOSpace.xs)
            .frame(minHeight: 28)
            .background(MCOTheme.Color.paperRaised.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
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

    private var storyboardPreparationTaskID: String {
        "\(card.id.uuidString)-\(missingThumbnailCount)"
    }

    private var revisionInstruction: String? {
        let trimmed = refreshInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var visualsButtonLabel: String {
        if isGeneratingThumbnails {
            return missingThumbnailCount > 0 ? "Preparing" : "Refreshing"
        }
        return missingThumbnailCount > 0 ? "Prepare visuals" : "Refresh"
    }

    private var durationLabel: String {
        if let durationSeconds = effectiveCard.durationSeconds, durationSeconds > 0 {
            return "\(durationSeconds)s"
        }
        if let seconds = SceneTiming.totalSeconds(for: effectiveCard.sceneList), seconds > 0 {
            return "\(seconds)s"
        }
        return "\(rows.count) scenes"
    }

    private func generateThumbnails() {
        guard !isGeneratingThumbnails else { return }
        let shouldForceRefresh = missingThumbnailCount == 0
        let instructions = revisionInstruction
        if shouldForceRefresh, instructions == nil {
            thumbnailError = "Add a direction before refreshing visuals."
            return
        }

        thumbnailError = nil
        Task {
            do {
                let assets = try await services.generateStoryboardThumbnails(
                    for: effectiveCard,
                    force: shouldForceRefresh,
                    revisionInstructions: instructions
                )
                if shouldForceRefresh {
                    refreshInstructions = ""
                }
                onStoryboardAssetsChanged?(assets)
            } catch {
                thumbnailError = error.localizedDescription
            }
        }
    }
}

struct GeneratedStoryboardTable: View {
    let rows: [GeneratedStoryboardBreakdownRow]
    private let headerHeight: CGFloat = 38
    private let rowHeight: CGFloat = 168
    private let timeColumnWidth: CGFloat = 96
    private let visualColumnWidth: CGFloat = 188
    private let whatColumnWidth: CGFloat = 182
    private let audioColumnWidth: CGFloat = 194
    private let textColumnWidth: CGFloat = 184

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                GeneratedStoryboardHeaderCell(
                    title: "SCENE",
                    width: timeColumnWidth,
                    height: headerHeight
                )
                ForEach(rows) { row in
                    GeneratedStoryboardTimeCell(
                        row: row,
                        width: timeColumnWidth,
                        height: rowHeight
                    )
                }
            }

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        GeneratedStoryboardHeaderCell(
                            title: "VISUAL / SHOT",
                            width: visualColumnWidth,
                            height: headerHeight
                        )
                        GeneratedStoryboardHeaderCell(
                            title: "WHAT TO SHOW",
                            width: whatColumnWidth,
                            height: headerHeight
                        )
                        GeneratedStoryboardHeaderCell(
                            title: "AUDIO / DIALOGUE",
                            width: audioColumnWidth,
                            height: headerHeight
                        )
                        GeneratedStoryboardHeaderCell(
                            title: "ON-SCREEN TEXT",
                            width: textColumnWidth,
                            height: headerHeight
                        )
                    }
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 0) {
                            GeneratedStoryboardVisualCell(
                                row: row,
                                width: visualColumnWidth,
                                height: rowHeight
                            )
                            GeneratedStoryboardTextCell(
                                text: row.whatToShow,
                                width: whatColumnWidth,
                                height: rowHeight
                            )
                            GeneratedStoryboardDialogueCell(
                                text: row.audioDialogue,
                                width: audioColumnWidth,
                                height: rowHeight
                            )
                            GeneratedStoryboardOnScreenTextCell(
                                row: row,
                                width: textColumnWidth,
                                height: rowHeight
                            )
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous)
                .stroke(MCOTheme.Color.hairlineStrong.opacity(0.78), lineWidth: 1)
        }
    }
}

struct GeneratedStoryboardHeaderCell: View {
    let title: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Text(title)
            .font(MCOType.caption.weight(.black))
            .foregroundStyle(MCOTheme.Color.paperRaised)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(width: width, height: height)
            .background(MCOTheme.Color.ink)
            .storyboardGridLines(isHeader: true)
    }
}

struct GeneratedStoryboardTimeCell: View {
    let row: GeneratedStoryboardBreakdownRow
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: MCOSpace.xxs) {
            GeneratedStoryboardThumbnail(url: row.thumbnailURL)
                .frame(width: width - 16, height: 54)
            Text(row.timecode.replacingOccurrences(of: " ", with: "\n"))
                .font(MCOType.caption.weight(.semibold))
                .foregroundStyle(MCOTheme.Color.ink)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
            Text(String(format: "%02d", row.sceneNumber))
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.inkMuted)
        }
        .padding(.vertical, MCOSpace.xs)
        .frame(width: width, height: height)
        .background(MCOTheme.Color.paperRaised.opacity(0.78))
        .storyboardGridLines()
        .accessibilityLabel("Scene \(row.sceneNumber), \(row.timecode)")
    }
}

struct GeneratedStoryboardVisualCell: View {
    let row: GeneratedStoryboardBreakdownRow
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xs) {
            GeneratedStoryboardThumbnail(url: row.thumbnailURL)
                .frame(height: 88)
            Text(row.visualShot)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(MCOSpace.xs)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(MCOTheme.Color.paperRaised.opacity(0.58))
        .storyboardGridLines()
    }
}

struct GeneratedStoryboardThumbnail: View {
    let url: URL?

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
                .stroke(MCOTheme.Color.hairlineStrong.opacity(0.58), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func thumbnailPlaceholder(isLoading: Bool) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    MCOTheme.Color.paper.opacity(0.9),
                    MCOTheme.Color.paperRaised.opacity(0.72)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
        }
    }
}

struct GeneratedStoryboardTextCell: View {
    let text: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Text(text)
            .font(MCOType.bodySmall)
            .foregroundStyle(MCOTheme.Color.ink)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                width: width - (MCOSpace.s * 2),
                height: height - (MCOSpace.s * 2),
                alignment: .topLeading
            )
            .padding(MCOSpace.s)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(MCOTheme.Color.paperRaised.opacity(0.42))
            .storyboardGridLines()
    }
}

struct GeneratedStoryboardDialogueCell: View {
    let text: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Text("\"\(text)\"")
            .font(MCOType.bodySmall)
            .foregroundStyle(MCOTheme.Color.ink)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                width: width - (MCOSpace.s * 2),
                height: height - (MCOSpace.s * 2),
                alignment: .topLeading
            )
            .padding(MCOSpace.s)
            .frame(width: width, height: height, alignment: .topLeading)
            .background(MCOTheme.Color.paperRaised.opacity(0.52))
            .storyboardGridLines()
    }
}

struct GeneratedStoryboardOnScreenTextCell: View {
    let row: GeneratedStoryboardBreakdownRow
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        VStack(spacing: MCOSpace.xs) {
            Text(row.onScreenText.uppercased())
                .font(MCOType.headline.weight(.black))
                .foregroundStyle(MCOTheme.Color.ink)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.62)

            if let placement = row.onScreenTextPlacement {
                Text(placement)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(width: width - (MCOSpace.s * 2), height: height - (MCOSpace.s * 2))
            .padding(MCOSpace.s)
            .frame(width: width, height: height)
            .background(MCOTheme.Color.paper.opacity(0.86))
            .storyboardGridLines()
    }
}

private struct StoryboardGridLineModifier: ViewModifier {
    let isHeader: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(lineColor)
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(lineColor)
                    .frame(height: 1)
            }
    }

    private var lineColor: Color {
        isHeader
            ? MCOTheme.Color.paperRaised.opacity(0.22)
            : MCOTheme.Color.hairlineStrong.opacity(0.62)
    }
}

private extension View {
    func storyboardGridLines(isHeader: Bool = false) -> some View {
        modifier(StoryboardGridLineModifier(isHeader: isHeader))
    }
}

struct GeneratedStoryboardTip: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: MCOSpace.s) {
            Image(systemName: "lightbulb")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(MCOTheme.Color.brass)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text("Tip for filming")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(text)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(MCOSpace.s)
        .background(MCOTheme.Color.brass.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
    }
}

struct InstagramExecutionSummary: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.m) {
            HStack(alignment: .firstTextBaseline, spacing: MCOSpace.s) {
                Text(formatLabel)
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.paperRaised)
                    .padding(.horizontal, MCOSpace.s)
                    .frame(height: 26)
                    .background(MCOTheme.Color.oxblood, in: Capsule())
                Text(durationLabel)
                    .font(MCOType.caption)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                Spacer(minLength: MCOSpace.s)
            }

            VStack(alignment: .leading, spacing: MCOSpace.s) {
                ExecutionSummaryLine(title: "Hook", value: hook)
                if let postInstructions = card.postInstructions.nilIfBlank {
                    ExecutionSummaryLine(title: "Post instruction", value: postInstructions)
                }
            }
        }
    }

    private var formatLabel: String {
        card.format?.nilIfBlank ?? "Reel"
    }

    private var durationLabel: String {
        if let durationSeconds = card.durationSeconds, durationSeconds > 0 {
            return "\(durationSeconds) sec edit"
        }
        if let seconds = SceneTiming.totalSeconds(for: card.sceneList), seconds > 0 {
            return "\(seconds) sec edit"
        }
        return "\(card.estimatedShootMinutes) min shoot"
    }

    private var hook: String {
        card.hook?.nilIfBlank ?? card.title
    }
}

struct ExecutionSummaryLine: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.xxs) {
            Text(title)
                .font(MCOType.caption)
                .foregroundStyle(MCOTheme.Color.inkMuted)
            Text(value)
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
struct InstagramCaptionPostBlock: View {
    let card: GeneratedDailyCardDraft

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                GeneratedReadOnlyField(title: "Caption", value: card.caption)
                GeneratedReadOnlyField(title: "CTA", value: card.cta)
                GeneratedReadOnlyField(title: "Cover text", value: card.coverText)
                GeneratedReadOnlyField(title: "Post instructions", value: card.postInstructions)
                GeneratedReadOnlyField(title: "Hashtags", value: hashtagSummary)
            }
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
            JournalBlock {
                VStack(alignment: .leading, spacing: MCOSpace.s) {
                    HStack(spacing: MCOSpace.s) {
                        Image(systemName: "text.alignleft")
                            .font(MCOType.captionEmphasis)
                        Text("Script")
                            .font(MCOType.tinyLabel)
                        Spacer(minLength: MCOSpace.s)
                        Text("\(rows.count) lines")
                            .font(MCOType.caption)
                    }
                    .foregroundStyle(MCOTheme.Color.paperRaised)
                    .padding(.horizontal, MCOSpace.s)
                    .frame(minHeight: 38)
                    .background(MCOTheme.Color.ink, in: RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))

                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: MCOSpace.s) {
                            GeneratedStoryboardThumbnail(url: row.thumbnailURL)
                                .frame(width: 72, height: 54)
                            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                                Text(row.timecode)
                                    .font(MCOType.captionEmphasis)
                                    .foregroundStyle(MCOTheme.Color.oxblood)
                                Text(row.audioDialogue)
                                    .font(MCOType.bodySmall)
                                    .foregroundStyle(MCOTheme.Color.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(MCOSpace.s)
                        .background(MCOTheme.Color.paperRaised.opacity(0.58))
                        .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                        .accessibilityIdentifier("plan.script.line.\(row.sceneNumber)")
                    }
                }
            }
            .accessibilityIdentifier("plan.script.timeline")
        }
    }
}
