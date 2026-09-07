import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ShootFolioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @Environment(AppState.self) private var appState
    @State private var selection: PackageSection = .scenes
    @State private var isEditing = false
    @State private var draftScenes: [ShotScene] = []
    @State private var draftScript = ""
    @State private var saveError: String?
    /// When true, open directly in scene/script light-edit mode (Today → Edit).
    var startsInEditingMode: Bool = false

    var body: some View {
        PocketSheetScreen {
            VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                header

                if case .ready = services.todayContentState {
                    PocketSheetFeedbackBanner(message: services.lastActionMessage, kind: .ready)
                    if let saveError {
                        PocketSheetFeedbackBanner(message: saveError, kind: .issue)
                    }
                    sectionTabs

                    switch selection {
                    case .scenes:
                        if !isEditing {
                            sceneProgress
                        }
                        SceneListView(
                            card: services.todayShootFolioCard,
                            isEditing: isEditing,
                            draftScenes: $draftScenes
                        )
                    case .script:
                        ScriptTimelineCopyBlock(
                            card: services.todayShootFolioCard,
                            isEditing: isEditing,
                            draftScript: $draftScript
                        )
                    case .caption:
                        CopyBlock(title: "Caption", bodyText: PackageCopyText.caption(for: services.todayCard))
                    case .audio:
                        CopyBlock(title: "Audio", bodyText: services.todayCard.audioOptionNotes ?? "No audio notes recorded for today.")
                    }
                } else {
                    ShootFolioEmptyState(state: services.todayContentState)
                }
            }
        } bottomBar: {
            if case .ready = services.todayContentState {
                if isEditing {
                    PocketSheetCommandBar {
                        PocketSheetPrimaryAction(
                            title: services.isUpdatingReadyDayPackage ? "Saving…" : "Save edits",
                            systemImage: "checkmark"
                        ) {
                            saveEdits()
                        }
                        .disabled(services.isUpdatingReadyDayPackage || !hasDraftChanges)
                        .opacity(services.isUpdatingReadyDayPackage || !hasDraftChanges ? 0.48 : 1)
                        .accessibilityIdentifier("shootFolio.saveEdits")
                    }
                } else if selection == .scenes {
                    PocketSheetCommandBar {
                        PocketSheetPrimaryAction(
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
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            _ = services.hydrateTodayStoryboardThumbnailsFromPlanPackage()
            if startsInEditingMode, !isEditing {
                beginEditing()
            }
        }
    }

    private var sceneProgress: some View {
        PocketSheetCard {
            HStack(alignment: .center, spacing: PocketSheetSpace.m) {
                Image(systemName: services.areAllScenesShot ? "checkmark.seal.fill" : "target")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(services.areAllScenesShot ? PocketSheetTheme.Color.ink : PocketSheetTheme.Color.ink)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                    Text(services.areAllScenesShot ? "All scenes shot" : "\(services.shotSceneCount) of \(services.todayCard.scenes.count) scenes shot")
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    Text(services.areAllScenesShot ? "Ready for post assembly." : "\(services.unshotSceneCount) remaining before the shoot is complete.")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }

                Spacer(minLength: PocketSheetSpace.s)
                PocketSheetStatus(
                    text: services.areAllScenesShot ? "Complete" : "\(services.unshotSceneCount) left",
                    kind: services.areAllScenesShot ? .ready : .pending
                )
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: PocketSheetSpace.xs) {
            VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                Text("Shoot Folio")
                    .font(PocketSheetType.screenTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text(isEditing ? "Editing scenes & script" : (services.todayCard.title.nilIfBlank ?? "Today's shoot"))
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            Spacer(minLength: PocketSheetSpace.s)
            if isReady {
                shootFolioHeaderActions
            }
        }
    }

    private var shootFolioHeaderActions: some View {
        HStack(spacing: PocketSheetSpace.xs) {
            if isEditing {
                Button("Cancel") {
                    cancelEditing()
                }
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .padding(.horizontal, PocketSheetSpace.s)
                .frame(height: 42)
                .accessibilityIdentifier("shootFolio.cancelEdit")
            } else {
                Button {
                    beginEditing()
                } label: {
                    Text("Edit")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                        .padding(.horizontal, PocketSheetSpace.s)
                        .frame(height: 42)
                        .background(PocketSheetTheme.Color.paperRaised.opacity(0.72), in: Capsule())
                        .overlay {
                            Capsule().stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit today’s scenes and script")
                .accessibilityIdentifier("shootFolio.edit")
            }

            Menu {
                NavigationLink(value: CreatorRoute.plan(selectedDate: planDateForReadyCard)) {
                    Label("Plan", systemImage: "calendar")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 42, height: 42)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .background(PocketSheetTheme.Color.paperRaised, in: Circle())
                    .overlay {
                        Circle().stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                    }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("Shoot Folio options")
            .accessibilityIdentifier("shootFolio.overflow")
        }
    }

    private var planDateForReadyCard: String {
        services.todayCard.scheduledDate?.nilIfBlank ?? services.currentTodayDateString
    }

    private var isReady: Bool {
        if case .ready = services.todayContentState {
            return true
        } else {
            return false
        }
    }

    private var hasDraftChanges: Bool {
        draftScenes != services.todayCard.scenes
            || draftScript != (services.todayCard.script ?? "")
    }

    private var sectionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PocketSheetSpace.s) {
                ForEach(PackageSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        Text(section.rawValue)
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(selection == section ? PocketSheetTheme.Color.paperRaised : PocketSheetTheme.Color.ink)
                            .padding(.horizontal, PocketSheetSpace.s)
                            .frame(height: 34)
                            .background(selection == section ? PocketSheetTheme.Color.inverseInk : PocketSheetTheme.Color.paperRaised.opacity(0.62))
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func beginEditing() {
        draftScenes = services.todayCard.scenes
        draftScript = services.todayCard.script ?? ""
        saveError = nil
        isEditing = true
        if selection != .scenes && selection != .script {
            selection = .scenes
        }
    }

    private func cancelEditing() {
        draftScenes = services.todayCard.scenes
        draftScript = services.todayCard.script ?? ""
        saveError = nil
        isEditing = false
    }

    private func saveEdits() {
        let dateString = planDateForReadyCard
        let scenes = draftScenes
        let script = draftScript
        Task { @MainActor in
            do {
                _ = try await services.updateReadyDayPackage(
                    scheduledDate: dateString,
                    package: ReadyDayPackageUpdate(
                        script: script,
                        sceneList: scenes
                    )
                )
                saveError = nil
                isEditing = false
            } catch {
                saveError = services.lastReadyDayPackageEditError
                    ?? error.localizedDescription
            }
        }
    }
}

private struct ShootFolioEmptyState: View {
    let state: TodayContentState

    var body: some View {
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                Image(systemName: "bookmark.slash")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                Text("No Shoot Folio yet")
                    .font(PocketSheetType.rowTitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text(message)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
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
            "Today's ready card does not include shoot scenes."
        case .missingPublishedCard(let date):
            "There is no published daily card for \(date), so there are no scenes to shoot yet."
        }
    }
}

struct SceneListView: View {
    @Environment(AppServices.self) private var services
    let card: DailyCard
    var isEditing: Bool = false
    @Binding var draftScenes: [ShotScene]

    init(
        card: DailyCard,
        isEditing: Bool = false,
        draftScenes: Binding<[ShotScene]> = .constant([])
    ) {
        self.card = card
        self.isEditing = isEditing
        self._draftScenes = draftScenes
    }

    var body: some View {
        VStack(spacing: PocketSheetSpace.m) {
            if isEditing {
                ForEach($draftScenes) { $scene in
                    PocketSheetCard {
                        editableSceneRow(scene: $scene)
                    }
                }
            } else {
                ForEach(Array(card.scenes.enumerated()), id: \.element.id) { index, scene in
                    NavigationLink {
                        SceneDetailView(card: card, scene: scene)
                    } label: {
                        PocketSheetCard {
                            readOnlySceneRow(scene: scene, index: index)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scene \(scene.number), \(scene.title), \(timecode(for: index, scene: scene)), \(services.isSceneShot(scene) ? "shot" : "not shot")")
                }
            }
        }
    }

    private func editableSceneRow(scene: Binding<ShotScene>) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            Text("SCENE \(String(format: "%02d", scene.wrappedValue.number))")
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.inverseInk)
            TextField("Scene title", text: scene.title)
                .font(PocketSheetType.rowTitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("shootFolio.scene.\(scene.wrappedValue.number).title")
            TextField("Duration (e.g. 3 sec)", text: scene.duration)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .textFieldStyle(.plain)
                .accessibilityIdentifier("shootFolio.scene.\(scene.wrappedValue.number).duration")
        }
    }

    private func readOnlySceneRow(scene: ShotScene, index: Int) -> some View {
        let row = storyboardRows[safe: index]
        return HStack(alignment: .top, spacing: PocketSheetSpace.s) {
            GeneratedStoryboardThumbnail(
                url: row?.thumbnailURL,
                fallbackSystemImage: scene.symbol
            )
                .frame(width: 88, height: 66)

            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                HStack(alignment: .top, spacing: PocketSheetSpace.s) {
                    VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                        Text("SCENE \(String(format: "%02d", scene.number))")
                            .font(PocketSheetType.sectionLabel)
                            .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                        Text(scene.title)
                            .font(PocketSheetType.rowTitle)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                        Text(row?.timecode ?? timecode(for: index, scene: scene))
                            .font(PocketSheetType.status)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    }
                    Spacer(minLength: PocketSheetSpace.s)
                    PocketSheetStatus(
                        text: services.isSceneShot(scene) ? "Shot" : scene.duration,
                        kind: services.isSceneShot(scene) ? .ready : .pending
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

    private var storyboardRows: [GeneratedStoryboardBreakdownRow] {
        GeneratedStoryboardBreakdown.rows(for: card)
    }

    private func thumbnailURL(for index: Int) -> URL? {
        storyboardRows[safe: index]?.thumbnailURL
            ?? (card.storyboardThumbnailAssets ?? [])
            .first(where: { $0.rowIndex == index })?
            .publicURL
            .flatMap(URL.init(string:))
    }

    private func timecode(for index: Int, scene: ShotScene) -> String {
        if let stamped = card.shotTimeline?[safe: index]?.timestamp.nilIfBlank {
            return stamped
        }
        if let window = SceneTiming.windows(for: card.scenes)[safe: index] {
            return window
        }
        return scene.duration
    }
}

struct SceneDetailView: View {
    @Environment(AppServices.self) private var services
    let card: DailyCard
    let scene: ShotScene

    var body: some View {
        PocketSheetScreen {
            VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    Text("SCENE \(String(format: "%02d", scene.number))")
                        .font(PocketSheetType.sectionLabel)
                        .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                    Text(scene.title)
                        .font(PocketSheetType.screenTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    HStack(spacing: PocketSheetSpace.s) {
                        PocketSheetStatus(text: scene.duration)
                        PocketSheetStatus(
                            text: services.isSceneShot(scene) ? "Shot" : "Not shot",
                            kind: services.isSceneShot(scene) ? .ready : .pending
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
            PocketSheetCommandBar {
                PocketSheetPrimaryAction(
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
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                Text(title.uppercased())
                    .font(PocketSheetType.sectionLabel)
                    .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                Text(text)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
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
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.inverseInk)
            Text(text)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
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

    static func contextExample(for _: ShotScene, in _: DailyCard) -> String {
        "You can shoot this at home or wherever makes the scene easiest to capture clearly and safely."
    }
}

struct CopyBlock: View {
    let title: String
    let bodyText: String
    @State private var didCopy = false

    var body: some View {
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
                Text(title)
                    .font(PocketSheetType.sectionLabel)
                    .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                Text(bodyText)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .lineSpacing(5)
                PocketSheetSecondaryAction(title: didCopy ? "Copied" : "Copy") {
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

struct ScriptTimelineCopyBlock: View {
    let card: DailyCard
    var isEditing: Bool = false
    @Binding var draftScript: String
    @State private var didCopy = false

    init(
        card: DailyCard,
        isEditing: Bool = false,
        draftScript: Binding<String> = .constant("")
    ) {
        self.card = card
        self.isEditing = isEditing
        self._draftScript = draftScript
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            if isEditing {
                PocketSheetCard {
                    VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                        Text("Script")
                            .font(PocketSheetType.sectionLabel)
                            .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                        Text("One line per beat. Timestamps stay tied to scene order.")
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        TextEditor(text: $draftScript)
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 180)
                            .accessibilityIdentifier("shootFolio.script.editor")
                    }
                }
            } else if rows.isEmpty {
                CopyBlock(title: "Script", bodyText: "No script recorded for today.")
            } else {
                PocketSheetCard {
                    VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                        HStack(spacing: PocketSheetSpace.s) {
                            Text("Script")
                                .font(PocketSheetType.sectionLabel)
                                .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                            Spacer(minLength: PocketSheetSpace.s)
                            Text("\(rows.count) lines")
                                .font(PocketSheetType.rowSubtitle)
                                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        }

                        ForEach(rows) { row in
                            HStack(alignment: .top, spacing: PocketSheetSpace.s) {
                                GeneratedStoryboardThumbnail(
                                    url: row.thumbnailURL,
                                    fallbackSystemImage: card.scenes[safe: row.sceneNumber - 1]?.symbol
                                )
                                    .frame(width: 72, height: 54)
                                VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                                    Text(row.timecode)
                                        .font(PocketSheetType.status)
                                        .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                                    Text(row.audioDialogue)
                                        .font(PocketSheetType.rowSubtitle)
                                        .foregroundStyle(PocketSheetTheme.Color.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(PocketSheetSpace.s)
                            .background(PocketSheetTheme.Color.paperRaised.opacity(0.58))
                            .clipShape(RoundedRectangle(cornerRadius: MCOShape.controlRadius, style: .continuous))
                            .accessibilityIdentifier("shoot.script.line.\(row.sceneNumber)")
                        }

                        PocketSheetSecondaryAction(title: didCopy ? "Copied" : "Copy full script") {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = copyableScript
                            #endif
                            didCopy = true
                        }
                    }
                }
                .accessibilityIdentifier("shoot.script.timeline")
            }
        }
        .onChange(of: card.script) {
            didCopy = false
        }
    }

    private var rows: [GeneratedStoryboardBreakdownRow] {
        GeneratedStoryboardBreakdown.rows(for: card)
    }

    private var copyableScript: String {
        PackageCopyText.script(for: card)
    }
}

#Preview {
    NavigationStack {
        ShootFolioView()
            .environment(AppServices.preview)
            .environment(AppState())
    }
}
