import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The Today package in the Pocket flow. It keeps the source package data intact
/// while presenting the first useful action and a vertical shot list.
struct TodayPocketPresentation: View {
    @Environment(AppServices.self) private var services
    let card: GeneratedDailyCardDraft

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
            packageSummary

            if !rows.isEmpty {
                LazyVStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                    Text("Shot list")
                        .font(PocketSheetType.sectionLabel)
                        .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                    Text("\(services.shotSceneCount.formatted()) of \(services.todayCard.scenes.count.formatted()) \(services.todayCard.scenes.count == 1 ? "shot" : "shots") done")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .accessibilityIdentifier("today.package.sceneProgress")
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        TodayPocketShotCard(
                            row: row,
                            scene: services.todayCard.scenes[safe: index],
                            isShot: services.todayCard.scenes[safe: index].map { services.isSceneShot($0) } ?? false
                        )
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("today.shotList")
            }
        }
        .task(id: storyboardPreparationTaskID) {
            guard missingThumbnailCount > 0 else { return }
            await services.prepareStoryboardThumbnailsForVisibleCard(dailyCardID: card.id)
        }
    }

    private var effectiveCard: GeneratedDailyCardDraft {
        services.generatedDailyCard(for: card.id) ?? card
    }

    private var rows: [GeneratedStoryboardBreakdownRow] {
        GeneratedStoryboardBreakdown.rows(for: effectiveCard)
    }

    private var missingThumbnailCount: Int {
        rows.filter { $0.thumbnailURL == nil }.count
    }

    private var storyboardPreparationTaskID: String {
        "\(card.id.uuidString)-\(missingThumbnailCount)-\(services.aiConsentEpoch)"
    }

    @ViewBuilder
    private var packageSummary: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            Text(effectiveCard.title)
                .font(PocketSheetType.screenTitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("today.package.title")

            if let hook = effectiveCard.hook?.nilIfBlank {
                PocketSheetCard {
                    VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                        Text("Opening line")
                            .font(PocketSheetType.sectionLabel)
                            .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                        Text(hook)
                            .font(PocketSheetType.rowTitle)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("today.package.hook")
            }

            HStack(alignment: .top, spacing: PocketSheetSpace.s) {
                if let format = effectiveCard.format?.nilIfBlank {
                    TodayPocketMeta(label: "Format", value: format.displayTitle + (effectiveCard.durationSeconds.map { " · \($0.formatted()) sec" } ?? ""))
                }
                if let minutes = effortMinutes {
                    TodayPocketMeta(label: "Effort", value: effortText(minutes: minutes))
                } else if let shootability = effectiveCard.shootability.nilIfBlank {
                    TodayPocketMeta(label: "Effort", value: shootability.displayTitle)
                }
            }

            if let source = effectiveCard.sourceNote.nilIfBlank {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    Text("Source")
                        .font(PocketSheetType.sectionLabel)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    Text(source)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("today.package.source")
            }

            if let whyToday = effectiveCard.whyToday.nilIfBlank {
                DisclosureGroup {
                    Text(whyToday)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, PocketSheetSpace.xxs)
                } label: {
                    Text("Why today")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }
                .tint(PocketSheetTheme.Color.inkMuted)
                .accessibilityIdentifier("today.package.whyToday")
            }

            if let url = rows.first?.thumbnailURL {
                GeneratedStoryboardThumbnail(url: url, fallbackSystemImage: "photo")
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .accessibilityLabel("Source reference media")
                    .accessibilityIdentifier("today.package.referenceMedia")
            }
        }
    }

    private var effortMinutes: Int? {
        effectiveCard.estimatedShootMinutes > 0 ? effectiveCard.estimatedShootMinutes : nil
    }

    private func effortText(minutes: Int) -> String {
        let pace = effectiveCard.shootability.nilIfBlank?.displayTitle
        if let pace {
            return "\(pace) · about \(minutes) min"
        }
        return "about \(minutes) min"
    }
}

private struct TodayPocketMeta: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
            Text(label)
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            Text(value)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PocketSheetSpace.s)
        .background(PocketSheetTheme.Color.paperRaised.opacity(0.62), in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
    }
}

private struct TodayPocketShotCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let row: GeneratedStoryboardBreakdownRow
    let scene: ShotScene?
    let isShot: Bool

    var body: some View {
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                headerLayout {
                    if let url = row.thumbnailURL {
                        GeneratedStoryboardThumbnail(url: url, fallbackSystemImage: scene?.symbol ?? "video")
                            .frame(width: 76, height: 58)
                    } else {
                        Image(systemName: scene?.symbol ?? "video")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                            .frame(width: 76, height: 58)
                            .background(PocketSheetTheme.Color.paperRaised, in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                        Text("SHOT \(String(format: "%02d", scene?.number ?? row.sceneNumber))")
                            .font(PocketSheetType.sectionLabel)
                            .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                        Text(scene?.title ?? row.visualShot)
                            .font(PocketSheetType.rowTitle)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(row.timecode)
                            .font(PocketSheetType.status)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    }
                    Spacer(minLength: 0)
                    PocketSheetStatus(text: isShot ? "Shot" : (scene?.duration ?? "Ready"), kind: isShot ? .ready : .pending)
                }

                TodayPocketInstruction(label: "Capture", text: row.whatToShow)
                if row.audioDialogue != "No voiceover specified.", let dialogue = row.audioDialogue.nilIfBlank {
                    TodayPocketInstruction(label: "Dialogue", text: dialogue)
                }
                if row.onScreenText != "No on-screen text.", let overlay = row.onScreenText.nilIfBlank {
                    TodayPocketInstruction(label: "Overlay", text: overlay)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.shot.\(row.sceneNumber)")
    }

    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PocketSheetSpace.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: PocketSheetSpace.s))
    }
}

private struct TodayPocketInstruction: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
            Text(label.uppercased())
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            Text(text)
                .font(PocketSheetType.rowSubtitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One-shot execution route. Previous and next only move the visible scene;
/// completion always goes through `AppServices.markSceneShot`.
struct TodayShootSessionView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sceneIndex = 0
    @State private var showingPost = false

    var body: some View {
        Group {
            if showingPost || services.areAllScenesShot || services.todayCard.isNonFilmingPost {
                TodayPostPreparationView()
            } else {
                shootView
            }
        }
        .onAppear {
            sceneIndex = firstUnshotSceneIndex
            showingPost = services.areAllScenesShot
        }
        .onChange(of: services.areAllScenesShot) { _, allShot in
            if allShot { showingPost = true }
        }
        .onChange(of: services.todayCard.id) { _, _ in
            sceneIndex = firstUnshotSceneIndex
            showingPost = services.areAllScenesShot
        }
    }

    private var shootView: some View {
        PocketSheetScreen {
            VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                    Text("Start filming")
                        .font(PocketSheetType.screenTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(services.todayCard.title)
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    }
                }

                Text("Shot \((sceneIndex + 1).formatted()) of \(services.todayCard.scenes.count.formatted())")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .accessibilityIdentifier("shoot.progress")
                if let scene {
                    sessionScene(scene)
                } else {
                    PocketSheetCard {
                        Text("No scenes are ready for filming.")
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    }
                }
            }
        } bottomBar: {
            if let scene {
                PocketSheetCommandBar {
                    PocketSheetPrimaryAction(
                        title: services.isSceneShot(scene) ? "Done" : "Mark shot",
                        systemImage: services.isSceneShot(scene) ? "checkmark.circle.fill" : "checkmark.seal"
                    ) {
                        services.markSceneShot(scene)
                        // Completion never advances the visible scene. The creator
                        // chooses Next, so repeated taps cannot complete another shot.
                        if services.areAllScenesShot {
                            showingPost = true
                        }
                    }
                    .disabled(services.isSceneShot(scene))
                    .accessibilityIdentifier("shoot.complete")

                    HStack(spacing: PocketSheetSpace.s) {
                        Button {
                            sceneIndex = max(sceneIndex - 1, 0)
                        } label: {
                            shotNavigationLabel("Previous", symbol: "chevron.left")
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 52)
                        }
                        .buttonStyle(.bordered)
                        .tint(PocketSheetTheme.Color.ink)
                        .disabled(sceneIndex == 0)
                        .accessibilityLabel("Previous shot")
                        .accessibilityIdentifier("shoot.previous")

                        Button {
                            sceneIndex = min(sceneIndex + 1, max(services.todayCard.scenes.count - 1, 0))
                        } label: {
                            shotNavigationLabel("Next", symbol: "chevron.right")
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 52)
                        }
                        .buttonStyle(.bordered)
                        .tint(PocketSheetTheme.Color.ink)
                        .disabled(sceneIndex >= services.todayCard.scenes.count - 1)
                        .accessibilityLabel("Next shot")
                        .accessibilityIdentifier("shoot.next")
                    }
                }
            }
        }
        .navigationTitle("Filming")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func shotNavigationLabel(_ title: String, symbol: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
        } else {
            Label(title, systemImage: symbol)
                .font(PocketSheetType.actionSecondary)
        }
    }

    @ViewBuilder
    private func sessionScene(_ scene: ShotScene) -> some View {
        let card = services.todayShootFolioCard
        let rows = GeneratedStoryboardBreakdown.rows(for: card)
        let row = rows[safe: sceneIndex]
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
                sceneHeaderLayout {
                    VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                        Text("SHOT \(String(format: "%02d", scene.number))")
                            .font(PocketSheetType.sectionLabel)
                            .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                        Text(scene.title)
                            .font(PocketSheetType.screenTitle)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: PocketSheetSpace.s)
                    PocketSheetStatus(text: row?.timecode ?? scene.duration, kind: services.isSceneShot(scene) ? .ready : .pending)
                }

                sessionBlock(title: "Capture", text: row?.whatToShow ?? "Capture this scene clearly.")
                if let dialogue = row?.audioDialogue.nilIfBlank, dialogue != "No voiceover specified." {
                    sessionBlock(title: "Dialogue", text: dialogue)
                }
                if let overlay = row?.onScreenText.nilIfBlank, overlay != "No on-screen text." {
                    sessionBlock(title: "Overlay", text: overlay)
                }
                Text("Use your usual camera app. Hold the final frame for \(scene.duration).")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("shoot.scene.\(scene.number)")
    }

    private var sceneHeaderLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PocketSheetSpace.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: PocketSheetSpace.s))
    }

    private func sessionBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
            Text(title.uppercased())
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            Text(text)
                .font(PocketSheetType.rowTitle)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scene: ShotScene? {
        services.todayCard.scenes[safe: sceneIndex]
    }

    private var firstUnshotSceneIndex: Int {
        services.todayCard.scenes.firstIndex(where: { !services.isSceneShot($0) }) ?? 0
    }
}

/// Post assembly stays local until the creator confirms the external action.
struct TodayPostPreparationView: View {
    private enum EditorField: Hashable { case script, caption }
    @Environment(AppServices.self) private var services
    @FocusState private var focusedEditor: EditorField?
    @State private var isEditing = false
    @State private var isSavingEdits = false
    @State private var draftScript = ""
    @State private var draftCaption = ""
    @State private var saveError: String?
    @State private var didCopyScript = false
    @State private var didCopyCaption = false

    var body: some View {
        PocketSheetScreen {
            VStack(alignment: .leading, spacing: PocketSheetSpace.l) {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                    Text("Post")
                        .font(PocketSheetType.screenTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(services.todayCard.title)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }

                PocketSheetFeedbackBanner(message: services.lastActionMessage, kind: .ready)
                if let error = services.lastTodayDecisionSyncError?.nilIfBlank {
                    PocketSheetFeedbackBanner(message: "Could not save the posting decision — \(error)", kind: .issue)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("post.syncError")
                }
                if let saveError {
                    PocketSheetFeedbackBanner(message: saveError, kind: .issue)
                }

                if services.todayCard.completionState == .posted {
                    PocketSheetCard {
                        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                            Label("Posted", systemImage: "checkmark.circle.fill")
                                .font(PocketSheetType.rowTitle)
                                .foregroundStyle(PocketSheetTheme.Color.ink)
                            Text("Posted status is saved for this card. You can undo it while keeping all completed shots.")
                                .font(PocketSheetType.rowSubtitle)
                                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        }
                    }
                    .accessibilityIdentifier("post.posted")
                } else {
                    Text("Post in your usual app. ContentHelper does not publish it. Confirm here after the post is live.")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("post.manualInstructions")
                }

                if isEditing {
                    editor.disabled(isSavingEdits)
                } else {
                    if !services.todayCard.isNonFilmingPost || services.todayCard.script?.nilIfBlank != nil {
                        copyBlock(title: "Script", text: services.todayCard.script?.nilIfBlank, emptyText: "No script recorded.", didCopy: $didCopyScript)
                    }
                    copyBlock(title: "Caption", text: services.todayCard.caption?.nilIfBlank, emptyText: "No caption recorded.", didCopy: $didCopyCaption)
                }
            }
        } bottomBar: {
            PocketSheetCommandBar {
                if isEditing {
                    HStack(spacing: PocketSheetSpace.s) {
                        PocketSheetSecondaryAction(title: "Cancel") { cancelEditing() }
                            .disabled(isSavingEdits)
                            .accessibilityIdentifier("post.cancel")
                        PocketSheetPrimaryAction(
                            title: services.isUpdatingReadyDayPackage ? "Saving…" : "Save",
                            systemImage: "checkmark"
                        ) { saveEdits() }
                            .disabled(isSavingEdits || services.isUpdatingReadyDayPackage)
                            .accessibilityIdentifier("post.save")
                    }
                } else {
                    HStack(spacing: PocketSheetSpace.s) {
                        PocketSheetSecondaryAction(title: "Edit script and caption") { beginEditing() }
                            .accessibilityIdentifier("post.edit")
                        if services.todayCard.completionState == .posted {
                            PocketSheetPrimaryAction(title: "Undo posted", systemImage: "arrow.uturn.backward") {
                                services.undoPosted()
                            }
                            .accessibilityIdentifier("post.undoPosted")
                        } else {
                            PocketSheetPrimaryAction(title: "Mark posted", systemImage: "paperplane.fill") {
                                services.markPosted()
                            }
                            .disabled(!services.canMarkPosted)
                            .accessibilityIdentifier("post.markPosted")
                        }
                    }
                }
            }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSavingEdits)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedEditor = nil }
                    .accessibilityIdentifier("post.keyboardDone")
            }
        }
        .onAppear {
            if draftScript.isEmpty { draftScript = services.todayCard.script ?? "" }
            if draftCaption.isEmpty { draftCaption = services.todayCard.caption ?? "" }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            PocketSheetCard {
                VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                    Text("Script")
                        .font(PocketSheetType.sectionLabel)
                        .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                    TextEditor(text: $draftScript)
                        .focused($focusedEditor, equals: .script)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 150)
                        .accessibilityIdentifier("post.script.editor")
                }
            }
            PocketSheetCard {
                VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                    Text("Caption")
                        .font(PocketSheetType.sectionLabel)
                        .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                    TextEditor(text: $draftCaption)
                        .focused($focusedEditor, equals: .caption)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("post.caption.editor")
                }
            }
        }
    }

    private func copyBlock(title: String, text: String?, emptyText: String, didCopy: Binding<Bool>) -> some View {
        PocketSheetCard {
            VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
                Text(title)
                    .font(PocketSheetType.sectionLabel)
                    .foregroundStyle(PocketSheetTheme.Color.inverseInk)
                Text(text ?? emptyText)
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(text == nil ? PocketSheetTheme.Color.inkMuted : PocketSheetTheme.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("post.\(title.lowercased()).text")
                if let text {
                    PocketSheetSecondaryAction(title: didCopy.wrappedValue ? "Copied" : "Copy") {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = text
                        #endif
                        didCopy.wrappedValue = true
                    }
                    .accessibilityIdentifier("post.copy.\(title.lowercased())")
                }
            }
        }
    }

    private func beginEditing() {
        draftScript = services.todayCard.script ?? ""
        draftCaption = services.todayCard.caption ?? ""
        saveError = nil
        isEditing = true
    }

    private func cancelEditing() {
        guard !isSavingEdits else { return }
        focusedEditor = nil
        draftScript = services.todayCard.script ?? ""
        draftCaption = services.todayCard.caption ?? ""
        saveError = nil
        isEditing = false
    }

    private func saveEdits() {
        guard !isSavingEdits else { return }
        if (draftScript.nilIfBlank == nil && services.todayCard.script?.nilIfBlank != nil)
            || (draftCaption.nilIfBlank == nil && services.todayCard.caption?.nilIfBlank != nil) {
            saveError = "Keep some text in Script and Caption before saving."
            return
        }
        isSavingEdits = true
        focusedEditor = nil
        let cardID = services.todayCard.id
        let date = services.todayCard.scheduledDate?.nilIfBlank ?? services.currentTodayDateString
        let script = draftScript
        let caption = draftCaption
        Task { @MainActor in
            defer { isSavingEdits = false }
            guard services.todayCard.id == cardID else { return }
            do {
                _ = try await services.updateReadyDayPackage(
                    scheduledDate: date,
                    package: ReadyDayPackageUpdate(caption: caption, script: script)
                )
                if services.todayCard.id == cardID {
                    saveError = nil
                    isEditing = false
                }
            } catch {
                saveError = services.lastReadyDayPackageEditError ?? error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        TodayShootSessionView()
            .environment(AppServices.preview)
            .environment(AppState())
    }
}
