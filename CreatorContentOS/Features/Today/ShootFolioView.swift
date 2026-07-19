import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ShootFolioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: PackageSection = .storyboard
    @State private var postedPulse = false

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header

                if case .ready = services.todayContentState {
                    ActionFeedbackBanner(message: services.lastActionMessage, tone: .ready)
                    sectionTabs

                    ZStack(alignment: .topLeading) {
                        FolioContentSwap(identity: selection) {
                            packageContent
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .animation(
                        MCOMotion.preferential(reduceMotion, MCOMotion.crossfade),
                        value: selection
                    )
                } else {
                    ShootFolioEmptyState(state: services.todayContentState)
                }
            }
        } bottomBar: {
            if selection == .scenes,
               case .ready = services.todayContentState {
                GlassCommandBar {
                    PrimaryActionButton(
                        title: services.canMarkPosted ? "Mark as posted" : (services.areAllScenesShot ? "All scenes shot" : "Mark all as shot"),
                        systemImage: services.canMarkPosted ? "paperplane.fill" : (services.areAllScenesShot ? "checkmark.circle.fill" : "checkmark.seal")
                    ) {
                        if services.canMarkPosted {
                            services.markPosted()
                            postedPulse.toggle()
                        } else {
                            services.markAllScenesShot()
                        }
                    }
                    .disabled(services.areAllScenesShot && !services.canMarkPosted)
                    .sensoryFeedback(.success, trigger: postedPulse)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var packageContent: some View {
        switch selection {
        case .storyboard:
            CreatorStoryboardPackageView(card: services.todayCard)
        case .scenes:
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                sceneProgress
                SceneListView(card: services.todayCard)
            }
        case .script:
            CreatorScriptPackageView(card: services.todayCard)
        case .caption:
            CreatorCaptionPackageView(card: services.todayCard)
        case .audio:
            CopyBlock(title: "Audio", bodyText: services.todayCard.audioOptionNotes ?? "No audio notes recorded for today.")
        }
    }

    private var sceneProgress: some View {
        JournalBlock {
            HStack(alignment: .center, spacing: MCOSpace.m) {
                Image(systemName: services.areAllScenesShot ? "checkmark.seal.fill" : "target")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(services.areAllScenesShot ? MCOTheme.Color.success : MCOTheme.Color.liveBlue)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    Text(services.areAllScenesShot ? "All scenes shot" : "\(services.shotSceneCount) of \(services.todayCard.scenes.count) scenes shot")
                        .font(MCOType.headline)
                        .foregroundStyle(MCOTheme.Color.ink)
                    Text(services.areAllScenesShot ? "Ready for post assembly." : "\(services.unshotSceneCount) remaining before the shoot is complete.")
                        .font(MCOType.caption)
                        .foregroundStyle(MCOTheme.Color.inkMuted)
                }

                Spacer(minLength: MCOSpace.s)
                StatusChip(
                    text: services.areAllScenesShot ? "Complete" : "\(services.unshotSceneCount) left",
                    tone: services.areAllScenesShot ? .ready : .info
                )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: MCOSpace.xs) {
            VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                Text("Shoot Folio")
                    .font(MCOType.headline)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(services.todayCard.title.nilIfBlank ?? "Today's shoot")
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
            }
            Spacer()
            shootFolioMenu
        }
    }

    private var shootFolioMenu: some View {
        Menu {
            Button {
                services.lastActionMessage = "Issue noted. Share the screen with the manager if this package looks wrong."
            } label: {
                Label("Report issue", systemImage: "exclamationmark.bubble")
            }
            .disabled(!isReady)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 42, height: 42)
                .foregroundStyle(MCOTheme.Color.ink)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Shoot Folio options")
    }

    private var isReady: Bool {
        if case .ready = services.todayContentState {
            return true
        } else {
            return false
        }
    }

    private var sectionTabs: some View {
        FolioPillBar(
            items: PackageSection.allCases.map { ($0, $0.rawValue) },
            selection: $selection,
            height: 34,
            font: MCOType.bodySmall
        )
    }
}

/// Read-only storyboard package for creators — same Gemini visuals and row
/// breakdown as the manager Daily preview, without edit/refresh controls.
struct CreatorStoryboardPackageView: View {
    let card: DailyCard

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.m) {
            if rows.isEmpty {
                JournalBlock {
                    VStack(alignment: .leading, spacing: MCOSpace.s) {
                        Text("Storyboard")
                            .font(MCOType.tinyLabel)
                            .foregroundStyle(MCOTheme.Color.oxblood)
                        Text("This published day does not include a storyboard yet.")
                            .font(MCOType.bodySmall)
                            .foregroundStyle(MCOTheme.Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                JournalBlock {
                    VStack(alignment: .leading, spacing: MCOSpace.s) {
                        HStack(spacing: MCOSpace.s) {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Storyboard")
                                .font(MCOType.tinyLabel)
                            Spacer(minLength: MCOSpace.s)
                            Text(durationLabel)
                                .font(MCOType.caption)
                        }
                        .foregroundStyle(MCOTheme.Color.paperRaised)
                        .padding(.horizontal, MCOSpace.s)
                        .frame(minHeight: 38)
                        .background(MCOTheme.Color.ink, in: RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))

                        Text(card.effectiveHook?.nilIfBlank ?? card.title)
                            .font(MCOType.headline)
                            .foregroundStyle(MCOTheme.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        GeneratedStoryboardTable(rows: rows)

                        if let filmingTip = card.postInstructions?.nilIfBlank {
                            GeneratedStoryboardTip(text: filmingTip)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("today.shootFolio.storyboard")
    }

    private var rows: [GeneratedStoryboardBreakdownRow] {
        GeneratedStoryboardBreakdown.rows(for: card)
    }

    private var durationLabel: String {
        if let seconds = SceneTiming.totalSeconds(for: card.scenes), seconds > 0 {
            return "\(seconds)s"
        }
        return "\(rows.count) scenes"
    }
}

private struct ShootFolioEmptyState: View {
    let state: TodayContentState

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Image(systemName: "bookmark.slash")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(MCOTheme.Color.brass)
                Text("No Shoot Folio yet")
                    .font(MCOType.headline)
                    .foregroundStyle(MCOTheme.Color.ink)
                Text(message)
                    .font(MCOType.bodySmall)
                    .foregroundStyle(MCOTheme.Color.inkMuted)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var message: String {
        switch state {
        case .loading:
            "The app is checking live Supabase content."
        case .ready:
            "Today's published card does not include shoot scenes."
        case .missingPublishedCard(let date):
            "There is no published daily card for \(date), so there are no scenes to shoot yet."
        }
    }
}

struct SceneListView: View {
    @Environment(AppServices.self) private var services
    let card: DailyCard

    var body: some View {
        VStack(spacing: MCOSpace.m) {
            ForEach(Array(card.scenes.enumerated()), id: \.element.id) { index, scene in
                let row = storyboardRows[safe: index]
                NavigationLink {
                    SceneDetailView(card: card, scene: scene)
                } label: {
                    JournalBlock {
                        VStack(alignment: .leading, spacing: MCOSpace.s) {
                            HStack(alignment: .top, spacing: MCOSpace.s) {
                                FolioStoryboardThumbnail(url: row?.thumbnailURL, height: 72)

                                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                                    Text("SCENE \(String(format: "%02d", scene.number))")
                                        .font(MCOType.tinyLabel)
                                        .foregroundStyle(MCOTheme.Color.oxblood)
                                    Text(scene.title)
                                        .font(MCOType.headline)
                                        .foregroundStyle(MCOTheme.Color.ink)
                                    Text(row?.timecode ?? scene.duration)
                                        .font(MCOType.caption)
                                        .foregroundStyle(MCOTheme.Color.inkMuted)
                                }
                                Spacer(minLength: MCOSpace.s)
                                StatusChip(
                                    text: services.isSceneShot(scene) ? "Shot" : (row?.timecode ?? scene.duration),
                                    tone: services.isSceneShot(scene) ? .ready : .info
                                )
                                .scaleEffect(services.isSceneShot(scene) ? 1 : 0.98)
                                .animation(MCOMotion.press, value: services.isSceneShot(scene))
                            }

                            FolioDetailLine(title: "What to capture", text: SceneGuidance.capture(for: scene, at: index, in: card))

                            if let text = SceneGuidance.onScreenText(at: index, in: card) {
                                FolioDetailLine(title: "On-screen text", text: text)
                            }

                            FolioDetailLine(title: "Example", text: SceneGuidance.contextExample(for: scene, in: card))
                        }
                    }
                }
                .buttonStyle(.pressable(scale: 0.985))
                .accessibilityLabel(
                    "Scene \(scene.number), \(scene.title), \(row?.timecode ?? scene.duration), \(services.isSceneShot(scene) ? "shot" : "not shot")"
                )
            }
        }
    }

    private var storyboardRows: [GeneratedStoryboardBreakdownRow] {
        GeneratedStoryboardBreakdown.rows(for: card)
    }
}

struct SceneDetailView: View {
    @Environment(AppServices.self) private var services
    let card: DailyCard
    let scene: ShotScene
    @State private var markShotPulse = false

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                VStack(alignment: .leading, spacing: MCOSpace.xs) {
                    Text("SCENE \(String(format: "%02d", scene.number))")
                        .font(MCOType.tinyLabel)
                        .foregroundStyle(MCOTheme.Color.oxblood)
                    Text(scene.title)
                        .font(MCOType.screenTitle)
                        .tracking(MCOType.screenTitleTracking)
                        .foregroundStyle(MCOTheme.Color.ink)
                    HStack(spacing: MCOSpace.s) {
                        StatusChip(text: storyboardRow?.timecode ?? scene.duration)
                        StatusChip(
                            text: services.isSceneShot(scene) ? "Shot" : "Not shot",
                            tone: services.isSceneShot(scene) ? .ready : .warning
                        )
                        .scaleEffect(services.isSceneShot(scene) ? 1 : 0.97)
                        .animation(MCOMotion.press, value: services.isSceneShot(scene))
                    }
                }

                if let thumbnailURL = storyboardRow?.thumbnailURL {
                    JournalBlock {
                        FolioStoryboardThumbnail(url: thumbnailURL, height: 168)
                            .frame(maxWidth: .infinity)
                    }
                }

                detailBlock(title: "What to capture", text: SceneGuidance.capture(for: scene, at: sceneIndex, in: card))
                detailBlock(title: "Example", text: SceneGuidance.contextExample(for: scene, in: card))

                if let onScreenText = SceneGuidance.onScreenText(at: sceneIndex, in: card) {
                    detailBlock(title: "On-screen text", text: onScreenText)
                }
                if let dialogue = storyboardRow?.audioDialogue.nilIfBlank,
                   dialogue != "No voiceover specified." {
                    detailBlock(title: "Script line", text: dialogue)
                }
                if let postInstructions = services.todayCard.postInstructions?.nilIfBlank {
                    detailBlock(title: "Post guidance", text: postInstructions)
                }
                if let backupStory = services.todayCard.backupStory?.nilIfBlank {
                    detailBlock(title: "Backup option", text: backupStory)
                }
            }
        } bottomBar: {
            GlassCommandBar {
                PrimaryActionButton(
                    title: services.isSceneShot(scene) ? "Scene shot" : "Mark shot",
                    systemImage: services.isSceneShot(scene) ? "checkmark.circle.fill" : "checkmark.seal"
                ) {
                    services.markSceneShot(scene)
                    markShotPulse.toggle()
                }
                .disabled(services.isSceneShot(scene))
                .sensoryFeedback(.success, trigger: markShotPulse)
            }
        }
        .navigationTitle("Scene \(scene.number)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailBlock(title: String, text: String) -> some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.s) {
                Text(title.uppercased())
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Text(text)
                    .font(MCOType.body)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineSpacing(4)
            }
        }
    }

    private var sceneIndex: Int {
        card.scenes.firstIndex { $0.id == scene.id } ?? max(scene.number - 1, 0)
    }

    private var storyboardRow: GeneratedStoryboardBreakdownRow? {
        GeneratedStoryboardBreakdown.rows(for: card)[safe: sceneIndex]
    }
}

/// Script package: voiceover lines with the same storyboard thumbnails + timestamps
/// as the Storyboard tab, plus a full-script copy action.
struct CreatorScriptPackageView: View {
    let card: DailyCard

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.m) {
            if rows.isEmpty {
                CopyBlock(
                    title: "Script",
                    bodyText: card.script?.nilIfBlank ?? "No script recorded for today."
                )
            } else {
                ForEach(rows) { row in
                    FolioTimedContentRow(
                        eyebrow: "SCENE \(String(format: "%02d", row.sceneNumber))",
                        timecode: row.timecode,
                        thumbnailURL: row.thumbnailURL,
                        bodyText: row.audioDialogue
                    )
                }

                CopyBlock(
                    title: "Full script",
                    bodyText: card.script?.nilIfBlank ?? rows.map(\.audioDialogue).joined(separator: "\n")
                )
            }
        }
        .accessibilityIdentifier("today.shootFolio.script")
    }

    private var rows: [GeneratedStoryboardBreakdownRow] {
        GeneratedStoryboardBreakdown.rows(for: card)
    }
}

/// Caption package: Instagram post caption plus timed on-screen captions that
/// reuse storyboard thumbnails and timeline timestamps.
struct CreatorCaptionPackageView: View {
    let card: DailyCard

    var body: some View {
        VStack(alignment: .leading, spacing: MCOSpace.m) {
            CopyBlock(
                title: "Caption",
                bodyText: card.caption?.nilIfBlank ?? "No caption recorded for today."
            )

            if !onScreenRows.isEmpty {
                Text("On-screen captions")
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                    .padding(.top, MCOSpace.xxs)

                ForEach(onScreenRows) { row in
                    FolioTimedContentRow(
                        eyebrow: "SCENE \(String(format: "%02d", row.sceneNumber))",
                        timecode: row.timecode,
                        thumbnailURL: row.thumbnailURL,
                        bodyText: row.onScreenText,
                        secondaryText: row.onScreenTextPlacement
                    )
                }
            }
        }
        .accessibilityIdentifier("today.shootFolio.caption")
    }

    private var onScreenRows: [GeneratedStoryboardBreakdownRow] {
        GeneratedStoryboardBreakdown.rows(for: card).filter { row in
            row.onScreenText.nilIfBlank != nil && row.onScreenText != "No on-screen text."
        }
    }
}

private struct FolioTimedContentRow: View {
    let eyebrow: String
    let timecode: String
    let thumbnailURL: URL?
    let bodyText: String
    var secondaryText: String? = nil

    var body: some View {
        JournalBlock {
            HStack(alignment: .top, spacing: MCOSpace.s) {
                FolioStoryboardThumbnail(url: thumbnailURL, height: 88)

                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: MCOSpace.s) {
                        Text(eyebrow)
                            .font(MCOType.tinyLabel)
                            .foregroundStyle(MCOTheme.Color.oxblood)
                        Spacer(minLength: MCOSpace.s)
                        Text(timecode)
                            .font(MCOType.caption.weight(.semibold))
                            .foregroundStyle(MCOTheme.Color.inkMuted)
                    }
                    Text(bodyText)
                        .font(MCOType.bodySmall)
                        .foregroundStyle(MCOTheme.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let secondaryText = secondaryText?.nilIfBlank {
                        Text(secondaryText)
                            .font(MCOType.caption)
                            .foregroundStyle(MCOTheme.Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(eyebrow), \(timecode), \(bodyText)")
    }
}

private struct FolioStoryboardThumbnail: View {
    let url: URL?
    var height: CGFloat = 88

    var body: some View {
        GeneratedStoryboardThumbnail(url: url)
            .frame(width: height * 16 / 9, height: height)
            .clipped()
    }
}

private struct FolioDetailLine: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(MCOType.tinyLabel)
                .foregroundStyle(MCOTheme.Color.oxblood)
            Text(text)
                .font(MCOType.bodySmall)
                .foregroundStyle(MCOTheme.Color.ink)
                .lineSpacing(3)
        }
    }
}

private enum SceneGuidance {
    static func capture(for scene: ShotScene, at index: Int, in card: DailyCard) -> String {
        if let detail = card.shotTimeline?[safe: index]?.detail.nilIfBlank {
            return detail
        }
        return "Capture \(scene.title.lowercased()) as a steady \(scene.duration) clip. Keep the main subject clear, leave room for on-screen text, and hold the final frame briefly for an easy edit."
    }

    static func onScreenText(at index: Int, in card: DailyCard) -> String? {
        let timelineText = card.onScreenTextTimeline?[safe: index]
        return timelineText?.onScreenText?.nilIfBlank
            ?? timelineText?.title.nilIfBlank
            ?? card.onScreenText?[safe: index]?.nilIfBlank
        // Deliberately NOT falling back to onScreenText.first: that would make
        // multiple scenes render the SAME first on-screen text and look like the
        // card is internally mismatched. A scene without its own on-screen text
        // shows nothing rather than borrowing another scene's text.
    }

    static func contextExample(for scene: ShotScene, in card: DailyCard) -> String {
        let context = [
            card.context,
            card.whyToday,
            card.sourceNote,
            card.postInstructions
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let location = context.contains("bombay") || context.contains("mumbai")
            ? "In Bombay, the creator can shoot this at home, in the society garden, or in the gym"
            : "The creator can shoot this at home, in the society garden, or in the gym"
        return "\(location), choosing the place that makes \(scene.title.lowercased()) easiest to capture clearly and safely."
    }
}

struct CopyBlock: View {
    let title: String
    let bodyText: String
    @State private var didCopy = false

    var body: some View {
        JournalBlock {
            VStack(alignment: .leading, spacing: MCOSpace.m) {
                Text(title)
                    .font(MCOType.tinyLabel)
                    .foregroundStyle(MCOTheme.Color.oxblood)
                Text(bodyText)
                    .font(MCOType.body)
                    .foregroundStyle(MCOTheme.Color.ink)
                    .lineSpacing(5)
                SecondaryActionButton(title: didCopy ? "Copied" : "Copy") {
                    copyBodyText()
                }
            }
        }
        .onChange(of: bodyText) {
            didCopy = false
        }
    }

    private func copyBodyText() {
        #if canImport(UIKit)
        UIPasteboard.general.string = bodyText
        #endif
        didCopy = true
    }
}

#Preview {
    NavigationStack {
        ShootFolioView()
            .environment(AppServices.preview)
            .environment(AppState())
    }
}
