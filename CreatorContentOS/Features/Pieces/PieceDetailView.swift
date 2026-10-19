import SwiftUI

enum PieceEditorKind: String, Identifiable {
    case script
    case shots
    case caption

    var id: String { rawValue }
}

struct PieceDetailView: View {
    @Environment(AppServices.self) private var services
    let pieceID: UUID
    var isInComposer = false

    @State private var editor: PieceEditorKind?
    @State private var showsMove = false
    @State private var showsEditChoice = false
    @State private var showsPostedEditChoice = false
    @State private var duplicatedPieceID: UUID?

    var body: some View {
        Group {
            if let piece = services.pieceStore.piece(pieceID) {
                detail(piece)
            } else {
                ContentUnavailableView("This piece is no longer here", systemImage: "doc")
            }
        }
        .onAppear {
            services.pieceStore.update { library, now in
                library.markReviewed(pieceID, now: now)
            }
        }
        .sheet(item: $editor) { kind in
            PieceEditorSheet(pieceID: pieceID, kind: kind)
        }
        .sheet(isPresented: $showsMove) {
            PieceMoveSheet(pieceID: pieceID)
        }
        .navigationDestination(item: $duplicatedPieceID) { id in
            PieceDetailView(pieceID: id)
        }
    }

    private func detail(_ piece: ContentPiece) -> some View {
        PieceScreen(title: piece.needsReview && !piece.isApproved ? "Review draft" : "Content") {
            PieceLargeTitle(title: piece.title)
                .accessibilityIdentifier("piece.title")
            badges(piece)
            Button {
                showsMove = true
            } label: {
                PieceGroup {
                    PieceInfoRow(
                        systemImage: "calendar",
                        title: PieceDates.shortLabel(piece.date, today: services.currentTodayDateString)
                    )
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Planned for \(PieceDates.longLabel(piece.date)). Move to another day")
            .accessibilityIdentifier("piece.date")
            PieceMediaHero(piece: piece)
            sections(piece)
            if !piece.shotsNeedingReview.isEmpty {
                filmingImpact(piece)
            }
            if piece.hasPostedOutcome || !piece.targets.isEmpty {
                postingRows(piece)
            }
            PieceNote(text: note(for: piece), systemImage: piece.needsReview && !piece.isApproved ? "doc.text" : nil)
                .accessibilityIdentifier("piece.note")
        } footer: {
            footer(piece)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showsMove = true
                    } label: {
                        Label("Move to another day", systemImage: "calendar")
                    }
                    Button {
                        duplicate(piece)
                    } label: {
                        Label("Duplicate as new draft", systemImage: "plus.square.on.square")
                    }
                    NavigationLink(value: PieceRoute.versions(piece.id)) {
                        Label("Versions", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Content options")
                .accessibilityIdentifier("piece.options")
            }
        }
        .confirmationDialog("What would you like to edit?", isPresented: $showsEditChoice, titleVisibility: .visible) {
            Button("Script") { editor = .script }
            Button(piece.content.format.usesFilming ? "Shots" : "Media plan") { editor = .shots }
            Button("Caption") { editor = .caption }
        } message: {
            Text(piece.isApproved ? "Your approved version stays saved until you approve the changes." : "Saved as a draft until you approve.")
        }
        .confirmationDialog("Edit saved content", isPresented: $showsPostedEditChoice, titleVisibility: .visible) {
            Button("Update saved notes") { showsEditChoice = true }
            Button("Create a new version to post again") { duplicate(piece) }
        } message: {
            Text("Your \(piece.postedPlatforms.first?.title ?? "posted") post stays as published. The original remains in your history.")
        }
    }

    @ViewBuilder
    private func badges(_ piece: ContentPiece) -> some View {
        HStack(spacing: PocketSheetSpace.xs) {
            switch piece.stage {
            case .draft:
                PieceBadge(text: piece.isReviewedForApproval ? "Draft · reviewed" : "Draft", systemImage: "doc.text")
            case .approved:
                PieceBadge(text: approvedText(piece), systemImage: "checkmark.circle.fill")
            case .shot:
                PieceBadge(text: piece.content.format.usesFilming ? "Shot" : "Ready", systemImage: "checkmark")
            case .posted:
                PieceBadge(text: piece.postingSummary ?? "Posted", systemImage: "checkmark.circle")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("piece.status")
        if piece.hasUnapprovedChanges, let draft = piece.draftVersion {
            NavigationLink(value: PieceRoute.reviewChanges(piece.id)) {
                PieceBadge(text: "Draft version \(draft.number) · review changes", systemImage: "doc.badge.clock")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("piece.draftBadge")
        }
    }

    private func approvedText(_ piece: ContentPiece) -> String {
        guard let approved = piece.approvedVersion else { return "Approved" }
        return "Approved · version \(approved.number)"
    }

    private func sections(_ piece: ContentPiece) -> some View {
        let content = piece.content
        return PieceGroup {
            Button {
                editor = .script
            } label: {
                PieceInfoRow(systemImage: "doc.text", title: "Script", subtitle: content.script.nilIfBlank ?? "Add what you will say") {
                    editLabel
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("piece.edit.script")
            PocketSheetDivider()
            Button {
                editor = .shots
            } label: {
                PieceInfoRow(
                    systemImage: "list.bullet",
                    title: shotsTitle(content),
                    subtitle: content.shotSummary.nilIfBlank ?? (content.format.usesFilming ? "Plan your shots" : "Plan your photos")
                ) {
                    editLabel
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("piece.edit.shots")
            PocketSheetDivider()
            Button {
                editor = .caption
            } label: {
                PieceInfoRow(systemImage: "text.bubble", title: "Caption", subtitle: content.instagramCaption.nilIfBlank ?? "Write a caption") {
                    editLabel
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("piece.edit.caption")
            PocketSheetDivider()
            NavigationLink(value: PieceRoute.versions(piece.id)) {
                PieceInfoRow(
                    systemImage: "clock.arrow.circlepath",
                    title: "View versions",
                    subtitle: piece.versions.count == 1 ? "1 version" : "\(piece.versions.count) versions"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("piece.versions")
        }
    }

    private func shotsTitle(_ content: PieceContent) -> String {
        let noun = content.format.usesFilming ? "shot" : "photo"
        return content.shots.count == 1 ? "1 \(noun)" : "\(content.shots.count) \(noun)s"
    }

    private var editLabel: some View {
        Text("Edit")
            .font(.body.weight(.medium))
            .foregroundStyle(PocketSheetTheme.Color.ink)
            .frame(minWidth: 44, minHeight: 44)
    }

    private func filmingImpact(_ piece: ContentPiece) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
            Text("Filming impact")
                .font(.headline)
                .foregroundStyle(PocketSheetTheme.Color.ink)
            PieceGroup {
                ForEach(piece.shotsNeedingReview) { shot in
                    PieceInfoRow(systemImage: "video", title: "\(shot.title) needs review") { EmptyView() }
                }
            }
            PieceNote(text: "Other captured shots stay saved.")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("piece.filmingImpact")
    }

    private func postingRows(_ piece: ContentPiece) -> some View {
        NavigationLink(value: PieceRoute.postResults(piece.id)) {
            PieceGroup {
                ForEach(platformsToShow(piece)) { platform in
                    let state = piece.postingState(for: platform)
                    PieceInfoRow(
                        systemImage: state.systemImage,
                        title: platform.title,
                        subtitle: state.label(for: platform)
                    )
                }
                if piece.legacyPostedMark?.state.isPostedOutcome == true && piece.postedPlatforms.isEmpty && piece.targets.isEmpty {
                    PieceInfoRow(systemImage: "checkmark.circle", title: "Posted", subtitle: "Marked posted by you")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("piece.postingStatus")
    }

    private func platformsToShow(_ piece: ContentPiece) -> [PiecePlatform] {
        PiecePlatform.allCases.filter { piece.targets.contains($0) || piece.latestPosting(for: $0) != nil }
    }

    private func note(for piece: ContentPiece) -> String {
        if piece.hasPostedOutcome {
            return "Changes here do not update the live post."
        }
        if piece.needsReview && !piece.isApproved {
            return "Saved as a draft until you approve. Approval saves a version. It does not post."
        }
        if piece.hasUnapprovedChanges {
            return "Your approved version stays available until you approve the changes."
        }
        return "You can still make changes."
    }

    @ViewBuilder
    private func footer(_ piece: ContentPiece) -> some View {
        if piece.needsReview {
            PieceFooter {
                PiecePrimaryButton(title: piece.hasUnapprovedChanges ? "Approve new version" : "Approve content") {
                    services.approvePieces([piece.id])
                }
                .accessibilityIdentifier("piece.approve")
            } secondary: {
                PieceTextButton(title: "Edit") { showsEditChoice = true }
                    .accessibilityIdentifier("piece.edit")
            }
        } else {
            switch piece.stage {
            case .approved:
                PieceFooter {
                    NavigationLink(value: approvedRoute(piece)) {
                        PieceFooterLinkLabel(title: approvedActionTitle(piece))
                    }
                    .buttonStyle(PocketSheetPressFeedbackStyle())
                    .accessibilityIdentifier("piece.primary")
                } secondary: {
                    PieceTextButton(title: "Edit content") { showsEditChoice = true }
                        .accessibilityIdentifier("piece.edit")
                }
            case .shot:
                PieceFooter {
                    NavigationLink(value: PieceRoute.readyToPost(piece.id)) {
                        PieceFooterLinkLabel(title: "Prepare to post")
                    }
                    .buttonStyle(PocketSheetPressFeedbackStyle())
                    .accessibilityIdentifier("piece.primary")
                } secondary: {
                    PieceTextButton(title: "Edit content") { showsEditChoice = true }
                        .accessibilityIdentifier("piece.edit")
                }
            case .posted:
                PieceFooter {
                    PiecePrimaryButton(title: "Make changes") { showsPostedEditChoice = true }
                        .accessibilityIdentifier("piece.makeChanges")
                } secondary: {
                    NavigationLink(value: PieceRoute.postResults(piece.id)) {
                        Text("Posting status")
                            .font(PocketSheetType.actionSecondary)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("piece.postingStatusLink")
                }
            case .draft:
                EmptyView()
            }
        }
    }

    private func approvedRoute(_ piece: ContentPiece) -> PieceRoute {
        if piece.content.format.usesFilming && !piece.filmingShots.isEmpty {
            return piece.allFilmingShotsCaptured ? .shotsReview(piece.id) : .filming(piece.id)
        }
        return .readyToPost(piece.id)
    }

    private func approvedActionTitle(_ piece: ContentPiece) -> String {
        guard piece.content.format.usesFilming && !piece.filmingShots.isEmpty else { return "Prepare media" }
        if piece.allFilmingShotsCaptured { return "Review captured shots" }
        return piece.isFilmingInProgress ? "Continue filming" : "Start filming"
    }

    private func duplicate(_ piece: ContentPiece) {
        var created: ContentPiece?
        services.pieceStore.update { library, now in
            created = try library.duplicate(piece.id, to: services.currentTodayDateString, now: now)
        }
        if let created {
            services.lastActionMessage = "New draft created. The original stays in your history."
            duplicatedPieceID = created.id
        }
    }
}

struct PieceFooterLinkLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(PocketSheetType.actionPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(PocketSheetTheme.Color.inversePaper)
            .background(
                PocketSheetTheme.Color.inverseInk,
                in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous)
            )
    }
}

struct PieceMoveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    let pieceID: UUID
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            PieceScreen(title: "Move content") {
                PieceLargeTitle(title: "Move to another day", subtitle: services.pieceStore.piece(pieceID)?.title)
                DatePicker("New date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(PocketSheetTheme.Color.inverseInk)
                    .accessibilityIdentifier("move.calendar")
                PieceGroup {
                    PieceInfoRow(systemImage: "calendar", title: PieceDates.longLabel(PieceDates.string(fromLocal: date))) { EmptyView() }
                }
                PieceNote(text: "Your script, shots and progress stay saved. Posted dates stay as they happened.")
            } footer: {
                PieceFooter {
                    PiecePrimaryButton(title: "Move content") {
                        let target = PieceDates.string(fromLocal: date)
                        services.pieceStore.update { library, now in
                            try library.move(pieceID, to: target, now: now)
                        }
                        services.lastActionMessage = "Moved to \(PieceDates.longLabel(target))."
                        dismiss()
                    }
                    .accessibilityIdentifier("move.confirm")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(PocketSheetTheme.Color.ink)
        .onAppear {
            if let piece = services.pieceStore.piece(pieceID) {
                date = PieceDates.localDate(from: piece.date)
            }
        }
    }
}
