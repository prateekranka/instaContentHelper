import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ShootFolioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @State private var selection: PackageSection = .scenes

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header

                if case .ready = services.todayContentState {
                    ActionFeedbackBanner(message: services.lastActionMessage, tone: .ready)
                    sectionTabs

                    switch selection {
                    case .scenes:
                        sceneProgress
                        SceneListView(card: services.todayCard)
                    case .script:
                        CopyBlock(title: "Script", bodyText: services.todayCard.script ?? "No script recorded for today.")
                    case .caption:
                        CopyBlock(title: "Caption", bodyText: services.todayCard.caption ?? "No caption recorded for today.")
                    case .audio:
                        CopyBlock(title: "Audio", bodyText: services.todayCard.audioOptionNotes ?? "No audio notes recorded for today.")
                    }
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
                        } else {
                            services.markAllScenesShot()
                        }
                    }
                    .disabled(services.areAllScenesShot && !services.canMarkPosted)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MCOSpace.s) {
                ForEach(PackageSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        Text(section.rawValue)
                            .font(MCOType.bodySmall)
                            .foregroundStyle(selection == section ? MCOTheme.Color.paperRaised : MCOTheme.Color.ink)
                            .padding(.horizontal, MCOSpace.s)
                            .frame(height: 34)
                            .background(selection == section ? MCOTheme.Color.oxblood : MCOTheme.Color.paperRaised.opacity(0.62))
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(MCOTheme.Color.hairline, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
                NavigationLink {
                    SceneDetailView(card: card, scene: scene)
                } label: {
                    JournalBlock {
                        VStack(alignment: .leading, spacing: MCOSpace.s) {
                            HStack(alignment: .top, spacing: MCOSpace.s) {
                                VStack(alignment: .leading, spacing: MCOSpace.xxs) {
                                    Text("SCENE \(String(format: "%02d", scene.number))")
                                        .font(MCOType.tinyLabel)
                                        .foregroundStyle(MCOTheme.Color.oxblood)
                                    Text(scene.title)
                                        .font(MCOType.headline)
                                        .foregroundStyle(MCOTheme.Color.ink)
                                }
                                Spacer(minLength: MCOSpace.s)
                                StatusChip(
                                    text: services.isSceneShot(scene) ? "Shot" : scene.duration,
                                    tone: services.isSceneShot(scene) ? .ready : .info
                                )
                            }

                            FolioDetailLine(title: "What to capture", text: SceneGuidance.capture(for: scene, at: index, in: card))

                            if let text = SceneGuidance.onScreenText(at: index, in: card) {
                                FolioDetailLine(title: "On-screen text", text: text)
                            }

                            FolioDetailLine(title: "Example", text: SceneGuidance.contextExample(for: scene, in: card))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scene \(scene.number), \(scene.title), \(services.isSceneShot(scene) ? "shot" : "not shot")")
            }
        }
    }
}

struct SceneDetailView: View {
    @Environment(AppServices.self) private var services
    let card: DailyCard
    let scene: ShotScene

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                VStack(alignment: .leading, spacing: MCOSpace.xs) {
                    Text("SCENE \(String(format: "%02d", scene.number))")
                        .font(MCOType.tinyLabel)
                        .foregroundStyle(MCOTheme.Color.oxblood)
                    Text(scene.title)
                        .font(MCOType.screenTitle)
                        .foregroundStyle(MCOTheme.Color.ink)
                    HStack(spacing: MCOSpace.s) {
                        StatusChip(text: scene.duration)
                        StatusChip(
                            text: services.isSceneShot(scene) ? "Shot" : "Not shot",
                            tone: services.isSceneShot(scene) ? .ready : .warning
                        )
                    }
                }

                detailBlock(title: "What to capture", text: SceneGuidance.capture(for: scene, at: sceneIndex, in: card))
                detailBlock(title: "Example", text: SceneGuidance.contextExample(for: scene, in: card))

                if let onScreenText = SceneGuidance.onScreenText(at: sceneIndex, in: card) {
                    detailBlock(title: "On-screen text", text: onScreenText)
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
                }
                .disabled(services.isSceneShot(scene))
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
