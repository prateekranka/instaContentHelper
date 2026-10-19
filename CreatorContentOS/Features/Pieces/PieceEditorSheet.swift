import SwiftUI

struct PieceEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    let pieceID: UUID
    let kind: PieceEditorKind

    @State private var content = PieceContent(title: "")
    @State private var original = PieceContent(title: "")
    @State private var platform: PiecePlatform = .instagram
    @State private var loaded = false
    @State private var showsDiscardConfirmation = false
    @FocusState private var focusedField: String?

    var body: some View {
        NavigationStack {
            Group {
                switch kind {
                case .script: scriptEditor
                case .shots: shotsEditor
                case .caption: captionEditor
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PieceFooter {
                    PiecePrimaryButton(title: "Save changes", isEnabled: content != original) {
                        save()
                    }
                    .accessibilityIdentifier("editor.save")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if content != original {
                            showsDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("editor.cancel")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .accessibilityIdentifier("editor.keyboardDone")
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
        }
        .tint(PocketSheetTheme.Color.ink)
        .interactiveDismissDisabled(content != original)
        .onAppear(perform: load)
    }

    private var title: String {
        switch kind {
        case .script: "Edit script"
        case .shots: content.format.usesFilming ? "Edit shots" : "Edit media plan"
        case .caption: "Edit caption"
        }
    }

    private func load() {
        guard !loaded, let piece = services.pieceStore.piece(pieceID) else { return }
        content = piece.content
        original = piece.content
        loaded = true
    }

    private func save() {
        let updated = content
        let saved = services.pieceStore.update { library, now in
            try library.saveDraft(pieceID, content: updated, now: now)
        }
        guard saved else { return }
        if services.pieceStore.piece(pieceID)?.isApproved == true {
            services.lastActionMessage = "Saved as a new draft. Your approved version stays available."
        }
        dismiss()
    }

    private var draftNote: some View {
        PieceNote(text: "Saved as a draft until you approve.", systemImage: "doc.text")
    }

    private var scriptEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    PieceSectionLabel(text: "Title")
                    TextField("Title", text: $content.title, axis: .vertical)
                        .font(.title2.weight(.bold))
                        .focused($focusedField, equals: "title")
                        .accessibilityIdentifier("editor.title")
                }
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    PieceSectionLabel(text: "Script")
                    PieceTextArea(text: $content.script, placeholder: "What will you say?", minHeight: 220, identifier: "editor.script", focus: $focusedField)
                }
                draftNote
            }
            .padding(PocketSheetSpace.m)
        }
        .background(PocketSheetTheme.Color.paper.ignoresSafeArea())
    }

    private var shotsEditor: some View {
        List {
            Section {
                ForEach($content.shots) { $shot in
                    PieceShotEditorRow(
                        shot: $shot,
                        number: (content.shots.firstIndex(where: { $0.id == shot.id }) ?? 0) + 1,
                        isFilming: content.format.usesFilming,
                        focusedField: $focusedField
                    )
                    .accessibilityActions {
                        Button("Move up") { move(shot.id, by: -1) }
                        Button("Move down") { move(shot.id, by: 1) }
                    }
                }
                .onMove { source, destination in
                    content.shots.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    content.shots.remove(atOffsets: offsets)
                }
                Button {
                    content.shots.append(PieceShot(title: content.format.usesFilming ? "New shot" : "New photo"))
                } label: {
                    Label(content.format.usesFilming ? "Add shot" : "Add photo", systemImage: "plus")
                        .font(.body.weight(.medium))
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("editor.addShot")
            } footer: {
                Text("Captured clips stay with their shot when you reorder. Removing a shot from this draft keeps its footage in earlier versions.")
                    .font(.footnote)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PocketSheetTheme.Color.paper.ignoresSafeArea())
        .environment(\.editMode, .constant(.active))
        .accessibilityIdentifier("editor.shots")
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = content.shots.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard content.shots.indices.contains(target) else { return }
        content.shots.swapAt(index, target)
    }

    private var captionEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
                Picker("Platform", selection: $platform) {
                    ForEach(PiecePlatform.allCases) { platform in
                        Text(platform.title).tag(platform)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("editor.platform")
                PieceTextArea(
                    text: captionBinding,
                    placeholder: platform == .tiktok ? "Leave empty to use the Instagram caption" : "Write your caption",
                    minHeight: 160,
                    identifier: "editor.caption",
                    focus: $focusedField
                )
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    PieceSectionLabel(text: "Hashtags")
                    PieceTextArea(text: $content.hashtags, placeholder: "#training #smallsteps", minHeight: 56, identifier: "editor.hashtags", focus: $focusedField)
                }
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    PieceSectionLabel(text: "Accessibility notes")
                    PieceTextArea(text: $content.accessibilityNote, placeholder: "Describe what people will see", minHeight: 72, identifier: "editor.accessibilityNote", focus: $focusedField)
                }
                PieceNote(text: "Saved with your plan. Each platform keeps its own caption.")
            }
            .padding(PocketSheetSpace.m)
        }
        .background(PocketSheetTheme.Color.paper.ignoresSafeArea())
    }

    private var captionBinding: Binding<String> {
        Binding(
            get: {
                platform == .instagram ? content.instagramCaption : content.tiktokCaption
            },
            set: { newValue in
                content.setCaption(newValue, for: platform)
            }
        )
    }
}

private struct PieceShotEditorRow: View {
    @Binding var shot: PieceShot
    let number: Int
    let isFilming: Bool
    var focusedField: FocusState<String?>.Binding

    var body: some View {
        HStack(alignment: .top, spacing: PocketSheetSpace.s) {
            PieceRemoteImage(url: shot.previewURL, fallbackSystemImage: isFilming ? "video" : "photo")
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                TextField("\(number) · Shot title", text: $shot.title, axis: .vertical)
                    .font(.body.weight(.semibold))
                    .focused(focusedField, equals: "shot-title-\(shot.id.uuidString)")
                    .accessibilityLabel("Shot \(number) title")
                TextField(isFilming ? "What to film" : "What to show", text: $shot.direction, axis: .vertical)
                    .font(.footnote)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .focused(focusedField, equals: "shot-direction-\(shot.id.uuidString)")
                    .accessibilityLabel("Shot \(number) direction")
                if isFilming {
                    TextField("What to say", text: $shot.line, axis: .vertical)
                        .font(.footnote)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                        .focused(focusedField, equals: "shot-line-\(shot.id.uuidString)")
                        .accessibilityLabel("Shot \(number) line")
                }
            }
        }
        .padding(.vertical, PocketSheetSpace.xxs)
        .listRowBackground(PocketSheetTheme.Color.paperRaised)
    }
}

struct PieceTextArea: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 120
    let identifier: String
    var focus: FocusState<String?>.Binding

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.body)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .padding(.horizontal, PocketSheetSpace.m)
                    .padding(.vertical, PocketSheetSpace.s + 2)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .font(.body)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, PocketSheetSpace.s)
                .padding(.vertical, PocketSheetSpace.xs)
                .frame(minHeight: minHeight)
                .focused(focus, equals: identifier)
                .accessibilityLabel(placeholder)
                .accessibilityIdentifier(identifier)
        }
        .background(PocketSheetTheme.Color.paperRaised, in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
        }
    }
}
