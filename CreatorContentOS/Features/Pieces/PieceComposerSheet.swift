import SwiftUI

struct PieceComposerRequest: Identifiable, Hashable {
    let id = UUID()
    var date: String
    var startsManual = false
    var topic = ""
}

struct PieceComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    let request: PieceComposerRequest
    var onCreated: ((ContentPiece) -> Void)?

    @State private var date = Date()
    @State private var topic = ""
    @State private var format: PieceFormat = .reel
    @State private var minutes = 5
    @State private var keepItSimple = false
    @State private var isCreating = false
    @State private var failure: String?
    @State private var createdPiece: ContentPiece?
    @FocusState private var topicFocused: Bool

    private static let minuteChoices = [5, 10, 15, 30]

    var body: some View {
        NavigationStack {
            Group {
                if let createdPiece {
                    PieceDetailView(pieceID: createdPiece.id, isInComposer: true)
                } else if let failure {
                    failureView(message: failure)
                } else {
                    form
                }
            }
            .pieceDestinations()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(createdPiece == nil ? "Cancel" : "Done") { dismiss() }
                        .accessibilityIdentifier("composer.cancel")
                }
            }
        }
        .tint(PocketSheetTheme.Color.ink)
        .onAppear {
            date = PieceDates.localDate(from: request.date)
            topic = request.topic
        }
        .interactiveDismissDisabled(isCreating)
    }

    private var form: some View {
        PieceScreen(title: "New content") {
            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                PieceSectionLabel(text: "Date")
                PieceGroup {
                    DatePicker(selection: $date, displayedComponents: .date) {
                        Label("Date", systemImage: "calendar")
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, PocketSheetSpace.m)
                    .padding(.vertical, PocketSheetSpace.xs)
                    .accessibilityIdentifier("composer.date")
                }
            }
            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                PieceSectionLabel(text: "Topic")
                TextField("What is it about?", text: $topic, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...4)
                    .focused($topicFocused)
                    .padding(PocketSheetSpace.m)
                    .frame(minHeight: 52)
                    .background(PocketSheetTheme.Color.paperRaised, in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                            .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
                    }
                    .accessibilityIdentifier("composer.topic")
            }
            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                PieceSectionLabel(text: "Format")
                HStack(spacing: PocketSheetSpace.xs) {
                    ForEach(PieceFormat.creationChoices) { choice in
                        Button {
                            format = choice
                        } label: {
                            VStack(spacing: PocketSheetSpace.xxs) {
                                Image(systemName: choice.systemImage)
                                    .font(.title3)
                                Text(choice.title)
                                    .font(.subheadline.weight(.medium))
                            }
                            .frame(maxWidth: .infinity, minHeight: 72)
                            .foregroundStyle(format == choice ? PocketSheetTheme.Color.inversePaper : PocketSheetTheme.Color.ink)
                            .background(
                                format == choice ? PocketSheetTheme.Color.inverseInk : PocketSheetTheme.Color.paperRaised,
                                in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
                                    .stroke(PocketSheetTheme.Color.hairline, lineWidth: format == choice ? 0 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(format == choice ? .isSelected : [])
                        .accessibilityIdentifier("composer.format.\(choice.rawValue)")
                    }
                }
            }
            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                PieceSectionLabel(text: format.usesFilming ? "Time to film" : "Time to prepare")
                PieceGroup {
                    Menu {
                        ForEach(Self.minuteChoices, id: \.self) { value in
                            Button("\(value) minutes") { minutes = value }
                        }
                    } label: {
                        PieceInfoRow(systemImage: "clock", title: "\(minutes) minutes")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("composer.minutes")
                    PocketSheetDivider()
                    Toggle(isOn: $keepItSimple) {
                        Label("Make it easier", systemImage: "lightbulb")
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                    }
                    .tint(PocketSheetTheme.Color.inverseInk)
                    .frame(minHeight: 44)
                    .padding(.horizontal, PocketSheetSpace.m)
                    .padding(.vertical, PocketSheetSpace.xs)
                    .accessibilityIdentifier("composer.easier")
                }
            }
            if !services.aiConsentAllowsOutbound && services.isLiveSupabaseRuntime {
                PieceNote(text: "AI drafts need your permission first. Writing it yourself never sends anything to AI.", systemImage: "info.circle")
            }
        } footer: {
            PieceFooter {
                PiecePrimaryButton(title: isCreating ? "Creating draft…" : "Create draft", isEnabled: canCreate && !isCreating) {
                    createWithAI()
                }
                .accessibilityIdentifier("composer.createDraft")
            } secondary: {
                PieceTextButton(title: "Write it myself") {
                    createManually()
                }
                .disabled(isCreating)
                .accessibilityIdentifier("composer.writeMyself")
            }
        }
        .onAppear {
            if request.startsManual {
                topicFocused = true
            }
        }
    }

    private func failureView(message: String) -> some View {
        PieceScreen(title: "Create draft") {
            PieceLargeTitle(title: "Your idea is saved")
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            PieceGroup {
                PieceInfoRow(systemImage: "doc.text", title: topicText) { EmptyView() }
                PocketSheetDivider()
                PieceInfoRow(systemImage: "calendar", title: PieceDates.shortLabel(dateString, today: services.currentTodayDateString)) { EmptyView() }
                PocketSheetDivider()
                PieceInfoRow(systemImage: format.systemImage, title: format.title) { EmptyView() }
            }
            Text(message)
                .font(.body)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("composer.failure")
        } footer: {
            PieceFooter {
                PiecePrimaryButton(title: "Try again") {
                    failure = nil
                    createWithAI()
                }
                .accessibilityIdentifier("composer.retry")
            } secondary: {
                PieceTextButton(title: "Write it myself") {
                    createManually()
                }
                .accessibilityIdentifier("composer.failure.writeMyself")
            }
        }
    }

    private var dateString: String { PieceDates.string(fromLocal: date) }

    private var topicText: String { topic.nilIfBlank ?? "Untitled idea" }

    private var canCreate: Bool { topic.nilIfBlank != nil }

    private func createManually() {
        let content = PieceContent(
            title: topic.nilIfBlank ?? "New \(format.title.lowercased())",
            format: format,
            minutesToFilm: minutes,
            shots: format.usesFilming ? [PieceShot(title: "Opening shot")] : []
        )
        let piece = services.pieceStore.addPiece(
            date: dateString,
            content: content,
            origin: .manual,
            topic: topic.nilIfBlank
        )
        finish(with: piece)
    }

    private func createWithAI() {
        guard canCreate, !isCreating else { return }
        isCreating = true
        let requestedTopic = topicText
        let requestedDate = dateString
        let requestedFormat = self.format
        let requestedMinutes = self.minutes
        let simple = keepItSimple
        Task { @MainActor in
            defer { isCreating = false }
            do {
                let piece = try await services.createAIPiece(
                    date: requestedDate,
                    topic: requestedTopic,
                    format: requestedFormat,
                    minutesToFilm: requestedMinutes,
                    keepItSimple: simple
                )
                finish(with: piece)
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? "We could not create a draft. Try again when you are ready."
            }
        }
    }

    private func finish(with piece: ContentPiece) {
        failure = nil
        if let onCreated {
            onCreated(piece)
            dismiss()
        } else {
            createdPiece = piece
        }
    }
}
