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
        VStack(alignment: .leading, spacing: PocketSheetSpace.section) {
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
                    TodayPocketMeta(
                        label: "Format",
                        value: format.displayTitle,
                        detail: effectiveCard.durationSeconds.flatMap { $0 > 0 ? "\($0.formatted()) sec" : nil }
                    )
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
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
            Text(label)
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            Text(detail.map { "\(value) · \($0)" } ?? value)
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
                            .font(PocketSheetType.listIcon)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                            .frame(width: 76, height: 58)
                            .background(PocketSheetTheme.Color.paperRaised, in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
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

                TodayPocketInstruction(label: "What to film", text: row.whatToShow)
                if row.audioDialogue != "No voiceover specified.", let dialogue = row.audioDialogue.nilIfBlank {
                    TodayPocketInstruction(label: "What to say", text: dialogue)
                }
                if row.onScreenText != "No on-screen text.", let overlay = row.onScreenText.nilIfBlank {
                    TodayPocketInstruction(label: "Text on screen", text: overlay)
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
            Text(label)
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            Text(text)
                .font(PocketSheetType.bodyText)
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
    @State private var movingForward = true
    @State private var lastMarkedAt: ContinuousClock.Instant?
    @State private var completedFilming = false
    @Environment(\.pocketReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if showingPost || services.areAllScenesShot || services.todayCard.isNonFilmingPost {
                TodayPostPreparationView(filmedShotCount: completedFilming ? services.todayCard.scenes.count : nil)
            } else {
                shootView
            }
        }
        .onAppear {
            sceneIndex = firstUnshotSceneIndex
            showingPost = services.areAllScenesShot
        }
        .onChange(of: services.areAllScenesShot) { _, allShot in
            if allShot {
                completedFilming = true
                showingPost = true
            }
        }
        .onChange(of: services.todayCard.id) { _, _ in
            sceneIndex = firstUnshotSceneIndex
            showingPost = services.areAllScenesShot
            completedFilming = false
            lastMarkedAt = nil
        }
    }

    private var shootView: some View {
        PocketSheetScreen {
            VStack(alignment: .leading, spacing: PocketSheetSpace.section) {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                    Text(scene?.title ?? "Start filming")
                        .font(PocketSheetType.screenTitle)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("shoot.scene.\(scene?.number ?? 0)")
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
                        .id(scene.id)
                        .transition(shotTransition)
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
                        title: services.isSceneShot(scene) ? "Next shot"
                            : (services.unshotSceneCount == 1 ? "Finish filming" : "Mark shot"),
                        systemImage: services.isSceneShot(scene) ? "checkmark.circle.fill" : "checkmark.seal",
                        animatesSymbol: true
                    ) {
                        completeOrAdvance(scene)
                    }
                    .accessibilityIdentifier("shoot.complete")

                    HStack(spacing: PocketSheetSpace.s) {
                        Button {
                            changeScene(to: max(sceneIndex - 1, 0))
                        } label: {
                            shotNavigationLabel("Previous", symbol: "chevron.left")
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, PocketSheetSpace.m)
                                .padding(.vertical, PocketSheetSpace.xxs)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(PocketSheetPressFeedbackStyle())
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .background(PocketSheetTheme.Color.fillMuted, in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                        .disabled(sceneIndex == 0)
                        .accessibilityLabel("Previous shot")
                        .accessibilityIdentifier("shoot.previous")

                        Button {
                            changeScene(to: min(sceneIndex + 1, max(services.todayCard.scenes.count - 1, 0)))
                        } label: {
                            shotNavigationLabel("Next", symbol: "chevron.right")
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, PocketSheetSpace.m)
                                .padding(.vertical, PocketSheetSpace.xxs)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(PocketSheetPressFeedbackStyle())
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .background(PocketSheetTheme.Color.fillMuted, in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
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
                .font(PocketSheetType.navIcon)
        } else {
            HStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(PocketSheetType.navIcon)
                Text(title)
                    .font(PocketSheetType.actionSecondary)
                    .padding(.horizontal, PocketSheetSpace.xxs)
            }
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
                    Spacer(minLength: PocketSheetSpace.s)
                    PocketSheetStatus(text: row?.timecode ?? scene.duration, kind: services.isSceneShot(scene) ? .ready : .pending)
                }

                sessionBlock(title: "What to film", text: row?.whatToShow ?? "Capture this scene clearly.")
                if let dialogue = row?.audioDialogue.nilIfBlank, dialogue != "No voiceover specified." {
                    sessionBlock(title: "What to say", text: dialogue)
                }
                if let overlay = row?.onScreenText.nilIfBlank, overlay != "No on-screen text." {
                    sessionBlock(title: "Text on screen", text: overlay)
                }
                Text("Use your usual camera app. Hold the final frame for \(scene.duration).")
                    .font(PocketSheetType.rowSubtitle)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("shoot.scene.\(scene.number)")
    }

    private var shotTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func changeScene(to index: Int) {
        guard index != sceneIndex else { return }
        movingForward = index > sceneIndex
        withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.25)) {
            sceneIndex = index
        }
    }

    private func completeOrAdvance(_ scene: ShotScene) {
        if services.isSceneShot(scene) {
            guard lastMarkedAt.map({ $0.duration(to: ContinuousClock().now) >= .milliseconds(600) }) ?? true else { return }
            let nextIndex = sceneIndex + 1 < services.todayCard.scenes.count
                ? sceneIndex + 1 : firstUnshotSceneIndex
            changeScene(to: nextIndex)
        } else {
            lastMarkedAt = ContinuousClock().now
            services.markSceneShot(scene)
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            if services.areAllScenesShot {
                completedFilming = true
                showingPost = true
            }
        }
    }

    private var sceneHeaderLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PocketSheetSpace.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: PocketSheetSpace.s))
    }

    private func sessionBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
            Text(title)
                .font(PocketSheetType.sectionLabel)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            Text(text)
                .font(PocketSheetType.bodyText)
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
    var filmedShotCount: Int? = nil
    @Environment(\.pocketReduceMotion) private var reduceMotion
    @State private var completionVisible = false
    @State private var didShowCompletion = false
    private enum EditorField: Hashable { case script, caption }
    @Environment(AppServices.self) private var services
    @FocusState private var focusedEditor: EditorField?
    @State private var isEditing = false
    @State private var isSavingEdits = false
    @State private var draftScript = ""
    @State private var draftScenes: [ShotScene] = []
    @State private var draftCaption = ""
    @State private var saveError: String?
    @State private var didCopyScript = false
    @State private var didCopyCaption = false

    var body: some View {
        PocketSheetScreen {
            VStack(alignment: .leading, spacing: PocketSheetSpace.section) {
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
                    PocketSheetFeedbackBanner(message: "Not saved to your account yet. \(error) ContentHelper tries again each time it refreshes.", kind: .issue)
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
                            Text(!services.hasPendingTodayDecision
                                ? "Posted status is saved for this card. You can undo it while keeping all completed shots."
                                : "Posted on this phone. It is not saved to your account yet.")
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
                    if !canSaveEdits {
                        Text(saveRequirementMessage)
                            .font(PocketSheetType.rowSubtitle)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    if !services.todayCard.isNonFilmingPost || PackageCopyText.script(for: services.todayCard).nilIfBlank != nil {
                        copyBlock(title: "Script", text: PackageCopyText.script(for: services.todayCard).nilIfBlank, emptyText: "No script recorded.", didCopy: $didCopyScript)
                    }
                    copyBlock(title: "Caption", text: services.todayCard.caption?.nilIfBlank, emptyText: "No caption recorded.", didCopy: $didCopyCaption)
                }
            }
        } bottomBar: {
            PocketSheetCommandBar {
                if let filmedShotCount, !isEditing {
                    Text("All \(filmedShotCount.formatted()) \(filmedShotCount == 1 ? "shot" : "shots") filmed")
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .opacity(completionVisible ? 1 : 0)
                        .accessibilityHidden(!completionVisible)
                        .allowsHitTesting(false)
                }
                if isEditing {
                    HStack(spacing: PocketSheetSpace.s) {
                        PocketSheetSecondaryAction(title: "Cancel") { cancelEditing() }
                            .disabled(isSavingEdits)
                            .accessibilityIdentifier("post.cancel")
                        PocketSheetPrimaryAction(
                            title: services.isUpdatingReadyDayPackage ? "Saving…" : "Save",
                            systemImage: "checkmark"
                        ) { saveEdits() }
                            .disabled(isSavingEdits || services.isUpdatingReadyDayPackage || !canSaveEdits)
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
        .task(id: filmedShotCount) {
            guard filmedShotCount != nil, !didShowCompletion else { return }
            didShowCompletion = true
            withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.18)) {
                completionVisible = true
            }
            do {
                try await Task.sleep(for: .milliseconds(340))
            } catch {
                completionVisible = false
                return
            }
            withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.18)) {
                completionVisible = false
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
                    .font(PocketSheetType.actionSecondary)
                    .accessibilityIdentifier("post.keyboardDone")
            }
        }
        .onAppear {
            if !isEditing {
                draftScenes = services.todayCard.scenes
                draftScript = PackageCopyText.script(for: services.todayCard)
            }
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
                    Text(ShotScript.editorGuidance)
                        .font(PocketSheetType.rowSubtitle)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: $draftScript)
                        .focused($focusedEditor, equals: .script)
                        .font(PocketSheetType.bodyText)
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
                        .font(PocketSheetType.bodyText)
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
        draftScenes = services.todayCard.scenes
        draftScript = PackageCopyText.script(for: services.todayCard)
        draftCaption = services.todayCard.caption ?? ""
        saveError = nil
        isEditing = true
    }

    private func cancelEditing() {
        guard !isSavingEdits else { return }
        focusedEditor = nil
        draftScenes = services.todayCard.scenes
        draftScript = PackageCopyText.script(for: services.todayCard)
        draftCaption = services.todayCard.caption ?? ""
        saveError = nil
        isEditing = false
    }

    private var canSaveEdits: Bool {
        draftCaption.nilIfBlank != nil && (services.todayCard.isNonFilmingPost || draftScript.nilIfBlank != nil)
    }

    private var saveRequirementMessage: String {
        services.todayCard.isNonFilmingPost ? "Keep some text in Caption before saving." : "Keep some text in Script and Caption before saving."
    }

    private func saveEdits() {
        guard !isSavingEdits else { return }
        if !canSaveEdits {
            saveError = saveRequirementMessage
            return
        }
        isSavingEdits = true
        focusedEditor = nil
        let cardID = services.todayCard.id
        let date = services.todayCard.scheduledDate?.nilIfBlank ?? services.currentTodayDateString
        let scenes = ShotScript.editing(draftScript, scenes: draftScenes)
        let script = scenes.isEmpty ? draftScript : ShotScript.text(for: scenes)
        let caption = draftCaption
        Task { @MainActor in
            defer { isSavingEdits = false }
            guard services.todayCard.id == cardID else { return }
            do {
                _ = try await services.updateReadyDayPackage(
                    scheduledDate: date,
                    package: ReadyDayPackageUpdate(caption: caption, script: script.nilIfBlank == nil ? nil : script, sceneList: services.todayCard.isNonFilmingPost ? nil : scenes)
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
