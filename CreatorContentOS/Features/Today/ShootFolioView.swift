import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ShootFolioView: View {
    @Environment(AppServices.self) private var services
    @State private var selection: PackageSection = .scenes

    var body: some View {
        EditorialScreen {
            VStack(alignment: .leading, spacing: MCOSpace.l) {
                header

                if case .ready = services.todayContentState {
                    sectionTabs

                    switch selection {
                    case .scenes:
                        sceneProgress
                        SceneListView(scenes: services.todayCard.scenes)
                    case .script:
                        CopyBlock(title: "Script", bodyText: services.todayCard.script ?? "Race week isn't about doing more. It's about doing what matters. Simple plan. Steady steps. Let's go.")
                    case .caption:
                        CopyBlock(title: "Caption", bodyText: services.todayCard.caption ?? "Race week has entered the house. Keeping it simple, steady, and real today.")
                    case .audio:
                        CopyBlock(title: "Audio", bodyText: services.todayCard.audioOptionNotes ?? "Calm Drive - Instrumental - fallback ready")
                    case .post:
                        CopyBlock(title: "Post", bodyText: services.todayCard.postInstructions ?? "Open Instagram, use the saved audio if available, add cover text: Race week mindset.")
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
                        title: services.areAllScenesShot ? "All scenes shot" : "Mark all as shot",
                        systemImage: services.areAllScenesShot ? "checkmark.circle.fill" : "checkmark.seal"
                    ) {
                        services.markAllScenesShot()
                    }
                    .disabled(services.areAllScenesShot)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sceneProgress: some View {
        HStack(spacing: MCOSpace.s) {
            Label("\(services.shotSceneCount) shot", systemImage: "checkmark.circle.fill")
                .foregroundStyle(MCOTheme.Color.sageDeep)
            Text("\(services.unshotSceneCount) not shot")
                .foregroundStyle(MCOTheme.Color.inkMuted)
            Spacer()
        }
        .font(MCOType.caption)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack {
            Text("Shoot Folio")
                .font(MCOType.screenTitle)
                .foregroundStyle(MCOTheme.Color.ink)
            Spacer()
            FloatingIconButton(systemImage: "ellipsis", label: "More") {}
        }
    }

    private var sectionTabs: some View {
        HStack(spacing: MCOSpace.m) {
            ForEach(PackageSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    VStack(spacing: MCOSpace.xs) {
                        Text(section.rawValue)
                            .font(MCOType.bodySmall)
                            .foregroundStyle(selection == section ? MCOTheme.Color.oxblood : MCOTheme.Color.inkMuted)
                        Rectangle()
                            .fill(selection == section ? MCOTheme.Color.oxblood : .clear)
                            .frame(height: 1)
                    }
                }
                .buttonStyle(.plain)
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
    let scenes: [ShotScene]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(scenes) { scene in
                NavigationLink {
                    SceneDetailView(scene: scene)
                } label: {
                    FolioRow(title: scene.title, subtitle: services.isSceneShot(scene) ? "Shot" : "Not shot") {
                        Text(String(format: "%02d", scene.number))
                            .font(.system(size: 46, weight: .regular, design: .serif))
                            .foregroundStyle(MCOTheme.Color.sageDeep)
                    } trailing: {
                        HStack(spacing: MCOSpace.s) {
                            StatusChip(text: scene.duration)
                            Image(systemName: services.isSceneShot(scene) ? "checkmark.circle.fill" : scene.symbol)
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(services.isSceneShot(scene) ? MCOTheme.Color.sageDeep : MCOTheme.Color.brass)
                                .frame(width: 54, height: 54)
                                .background(MCOTheme.Color.paperRaised)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scene \(scene.number), \(scene.title), \(services.isSceneShot(scene) ? "shot" : "not shot")")
                Hairline()
            }
        }
    }
}

struct SceneDetailView: View {
    @Environment(AppServices.self) private var services
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

                detailBlock(title: "What to capture", text: captureGuidance)
                detailBlock(title: "Supports", text: services.todayCard.title)

                if let onScreenText = services.todayCard.onScreenText?.first?.nilIfBlank {
                    detailBlock(title: "On-screen text", text: onScreenText)
                }
            }
        } bottomBar: {
            GlassCommandBar {
                PrimaryActionButton(
                    title: services.isSceneShot(scene) ? "Shot" : "Mark shot",
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

    private var captureGuidance: String {
        "Capture \(scene.title.lowercased()) as a steady \(scene.duration) clip. Keep the main subject clear, leave room for on-screen text, and hold the final frame briefly for an easy edit."
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
                SecondaryActionButton(title: didCopy ? "Copied" : "Copy \(title.lowercased())") {
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
