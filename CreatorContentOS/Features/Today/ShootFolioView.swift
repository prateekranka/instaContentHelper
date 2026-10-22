import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ShootFolioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @Environment(AppState.self) private var appState
    @State private var pieceID: UUID?
    private var projection: DayCardProjection? { services.todayPieceProjection(pieceID: pieceID) }
    private var card: DailyCard { projection?.card ?? (pieceID == nil ? services.selectedTodayCard : .emptyTodayPlaceholder) }
    private var canMarkPosted: Bool { card.pieceID.map { services.canMarkPosted(pieceID: $0) } ?? false }
    private var allScenesShot: Bool { projection?.areAllScenesShot ?? false }
    @State private var selection: PackageSection = .scenes
    @State private var isEditing = false
    @State private var draftScenes: [ShotScene] = []
    @State private var draftScript = ""
    @State private var saveError: String?
    /// When true, open directly in scene/script light-edit mode (Today → Edit).
    var startsInEditingMode: Bool = false

    var body: some View {
        PocketSheetScreen {
            VStack(alignment: .leading, spacing: PocketSheetSpace.section) {
                header

                if projection != nil {
                    PocketSheetFeedbackBanner(message: services.lastActionMessage, kind: .ready)
                    if let saveError {
                        PocketSheetFeedbackBanner(message: saveError, kind: .issue)
                    }
                    if isEditing, draftScript.nilIfBlank == nil {
                        Text("Enter a script before saving.")
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    sectionTabs

                    switch selection {
                    case .scenes:
                        if !isEditing {
                            sceneProgress
                        }
                        SceneListView(
                            card: card,
                            isEditing: isEditing,
                            draftScenes: $draftScenes
                        )
                    case .script:
                        ScriptTimelineCopyBlock(
                            card: card,
                            isEditing: isEditing,
                            draftScript: $draftScript
                        )
                    case .caption:
                        CopyBlock(title: "Caption", bodyText: PackageCopyText.caption(for: card), emptyText: "No caption recorded for today.")
                    case .audio:
                        CopyBlock(title: "Audio", bodyText: card.audioOptionNotes?.nilIfBlank, emptyText: "No audio notes recorded for today.")
                    }
                } else {
                    ShootFolioEmptyState(state: services.todayContentState)
                }
            }
        } bottomBar: {
            if projection != nil {
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
                            title: canMarkPosted ? "Mark as posted" : (allScenesShot ? "All scenes shot" : "Mark all as shot"),
                            systemImage: canMarkPosted ? "paperplane.fill" : (allScenesShot ? "checkmark.circle.fill" : "checkmark.seal")
                        ) {
                            if canMarkPosted {
                                services.markPosted(pieceID: card.pieceID)
                            } else {
                                services.markAllScenesShot(pieceID: card.pieceID)
                            }
                        }
                        .disabled(allScenesShot && !canMarkPosted)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if pieceID == nil { pieceID = services.selectedTodayPieceID }
            _ = services.hydrateTodayStoryboardThumbnailsFromPlanPackage()
            if startsInEditingMode, !isEditing {
                beginEditing()
            }
        }
    }

    private var sceneProgress: some View {
        PocketSheetCard {
            HStack(alignment: .center, spacing: PocketSheetSpace.m) {
                Image(systemName: allScenesShot ? "checkmark.seal.fill" : "target")
                    .font(PocketSheetType.listIcon)
                    .foregroundStyle(allScenesShot ? PocketSheetTheme.Color.ink : PocketSheetTheme.Color.ink)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                    Text(allScenesShot ? "All scenes shot" : "\((projection?.shotSceneCount ?? 0).formatted()) of \(card.scenes.count.formatted()) \(card.scenes.count == 1 ? "scene" : "scenes") shot")
                        .font(PocketSheetType.rowTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    Text(allScenesShot ? "Ready for post assembly." : "\((projection?.unshotSceneCount ?? 0).formatted()) remaining before the shoot is complete.")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }

                Spacer(minLength: PocketSheetSpace.s)
                PocketSheetStatus(
                    text: allScenesShot ? "Complete" : "\((projection?.unshotSceneCount ?? 0).formatted()) left",
                    kind: allScenesShot ? .ready : .pending
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
                Text(isEditing ? "Editing scenes & script" : (card.title.nilIfBlank ?? "Today's shoot"))
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
                .font(PocketSheetType.actionSecondary)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .padding(.horizontal, PocketSheetSpace.xxs)
                .padding(.horizontal, PocketSheetSpace.m)
                .frame(minHeight: 44)
                .accessibilityIdentifier("shootFolio.cancelEdit")
            } else {
                Button {
                    beginEditing()
                } label: {
                    Text("Edit")
                        .font(PocketSheetType.actionSecondary)
                        .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                        .padding(.horizontal, PocketSheetSpace.xxs)
                        .padding(.horizontal, PocketSheetSpace.m)
                        .frame(minHeight: 44)
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
                    .font(PocketSheetType.navIcon)
                    .frame(minWidth: 44, minHeight: 44)
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
        card.scheduledDate?.nilIfBlank ?? services.currentTodayDateString
    }

    private var isReady: Bool {
        if projection != nil {
            return true
        } else {
            return false
        }
    }

    private var hasDraftChanges: Bool {
        draftScript.nilIfBlank != nil
            && (draftScenes != card.scenes || draftScript != PackageCopyText.script(for: card))
    }

    private var sectionTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PocketSheetSpace.s) {
                ForEach(PackageSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        Text(section.rawValue)
                            .font(PocketSheetType.actionSecondary)
                            .foregroundStyle(selection == section ? PocketSheetTheme.Color.paperRaised : PocketSheetTheme.Color.ink)
                            .padding(.horizontal, PocketSheetSpace.xxs)
                            .padding(.horizontal, PocketSheetSpace.m)
                            .padding(.vertical, PocketSheetSpace.xxs)
                            .frame(minHeight: 44)
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
        draftScenes = card.scenes
        draftScript = PackageCopyText.script(for: card)
        saveError = nil
        isEditing = true
        if selection != .scenes && selection != .script {
            selection = .scenes
        }
    }

    private func cancelEditing() {
        draftScenes = card.scenes
        draftScript = PackageCopyText.script(for: card)
        saveError = nil
        isEditing = false
    }

    private func saveEdits() {
        guard hasDraftChanges, !services.isUpdatingReadyDayPackage else { return }
        let dateString = planDateForReadyCard
        let selectedPieceID = card.pieceID
        let scenes = ShotScript.editing(draftScript, scenes: draftScenes)
        let script = scenes.isEmpty ? draftScript : ShotScript.text(for: scenes)
        Task { @MainActor in
            do {
                _ = try await services.updateReadyDayPackage(
                    scheduledDate: dateString,
                    package: ReadyDayPackageUpdate(
                        script: script,
                        sceneList: scenes
                    ),
                    pieceID: selectedPieceID
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
                    .font(PocketSheetType.listIcon)
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
        case .unavailable:
            "Today could not load. Go back to Today and try again."
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
                    .accessibilityLabel("Scene \(scene.number), \(scene.title), \(timecode(for: index, scene: scene)), \(services.isSceneShot(scene, pieceID: card.pieceID) ? "shot" : "not shot")")
                }
            }
        }
    }

    private func editableSceneRow(scene: Binding<ShotScene>) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            Text("Scene \(scene.wrappedValue.number)")
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
                        Text("Scene \(scene.number)")
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
                        text: services.isSceneShot(scene, pieceID: card.pieceID) ? "Shot" : scene.duration,
                        kind: services.isSceneShot(scene, pieceID: card.pieceID) ? .ready : .pending
                    )
                }

                FolioDetailLine(title: "What to film", text: SceneGuidance.capture(for: scene, at: index, in: card))

                if let text = SceneGuidance.onScreenText(at: index, in: card) {
                    FolioDetailLine(title: "Text on screen", text: text)
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
        if let window = ShotScript.timecodes(for: card.scenes)[safe: index] {
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
            VStack(alignment: .leading, spacing: PocketSheetSpace.section) {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    Text("Scene \(scene.number)")
                        .font(PocketSheetType.sectionLabel)
                        .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                    Text(scene.title)
                        .font(PocketSheetType.screenTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    HStack(spacing: PocketSheetSpace.s) {
                        PocketSheetStatus(text: scene.duration)
                        PocketSheetStatus(
                            text: services.isSceneShot(scene, pieceID: card.pieceID) ? "Shot" : "Not shot",
                            kind: services.isSceneShot(scene, pieceID: card.pieceID) ? .ready : .pending
                        )
                    }
                }

                detailBlock(title: "What to film", text: SceneGuidance.capture(for: scene, at: sceneIndex, in: card))
                detailBlock(title: "Example", text: SceneGuidance.contextExample(for: scene, in: card))

                if let onScreenText = SceneGuidance.onScreenText(at: sceneIndex, in: card) {
                    detailBlock(title: "Text on screen", text: onScreenText)
                }
                if let postInstructions = card.postInstructions?.nilIfBlank {
                    detailBlock(title: "Post guidance", text: postInstructions)
                }
                if let backupStory = card.backupStory?.nilIfBlank {
                    detailBlock(title: "Backup option", text: backupStory)
                }
            }
        } bottomBar: {
            PocketSheetCommandBar {
                PocketSheetPrimaryAction(
                    title: services.isSceneShot(scene, pieceID: card.pieceID) ? "Scene shot" : "Mark shot",
                    systemImage: services.isSceneShot(scene, pieceID: card.pieceID) ? "checkmark.circle.fill" : "checkmark.seal"
                ) {
                    services.markSceneShot(scene, pieceID: card.pieceID)
                }
                .disabled(services.isSceneShot(scene, pieceID: card.pieceID))
            }
        }
        .navigationTitle("Scene \(scene.number)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailBlock(title: String, text: String) -> some View {
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                Text(title)
                    .font(PocketSheetType.sectionLabel)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                Text(text)
                    .font(PocketSheetType.bodyText)
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
            Text(title)
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.inverseInk)
            Text(text)
                .font(PocketSheetType.bodyText)
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
    let bodyText: String?
    let emptyText: String
    @State private var didCopy = false

    var body: some View {
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
                Text(title)
                    .font(PocketSheetType.sectionLabel)
                    .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                Text(bodyText ?? emptyText)
                    .font(PocketSheetType.bodyText)
                    .foregroundStyle(bodyText == nil ? PocketSheetTheme.Color.inkMuted : PocketSheetTheme.Color.ink)
                    .lineSpacing(5)
                if let bodyText {
                    PocketSheetSecondaryAction(title: didCopy ? "Copied" : "Copy") {
                        copy(bodyText)
                    }
                }
            }
        }
        .onChange(of: bodyText) {
            didCopy = false
        }
    }

    private func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
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
                        Text(ShotScript.editorGuidance)
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                        TextEditor(text: $draftScript)
                            .font(PocketSheetType.bodyText)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 180)
                            .accessibilityIdentifier("shootFolio.script.editor")
                    }
                }
            } else if rows.isEmpty {
                CopyBlock(title: "Script", bodyText: nil, emptyText: "No script recorded for today.")
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
                                        .font(PocketSheetType.bodyText)
                                        .foregroundStyle(PocketSheetTheme.Color.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, PocketSheetSpace.l)
                            .padding(.vertical, PocketSheetSpace.s)
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
