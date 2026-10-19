import SwiftUI

struct PieceVersionsView: View {
    @Environment(AppServices.self) private var services
    let pieceID: UUID

    var body: some View {
        if let piece = services.pieceStore.piece(pieceID) {
            PieceScreen(title: "Versions") {
                PieceLargeTitle(title: piece.title)
                ForEach(piece.versions.reversed()) { version in
                    NavigationLink(value: PieceRoute.version(piece.id, version.id)) {
                        PieceVersionCard(piece: piece, version: version)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("versions.version.\(version.number)")
                }
            } footer: {
                if piece.hasUnapprovedChanges {
                    PieceFooter {
                        NavigationLink(value: PieceRoute.reviewChanges(piece.id)) {
                            PieceFooterLinkLabel(title: "Review changes")
                        }
                        .buttonStyle(PocketSheetPressFeedbackStyle())
                        .accessibilityIdentifier("versions.reviewChanges")
                    } secondary: {
                        if let approved = piece.approvedVersion {
                            NavigationLink(value: PieceRoute.version(piece.id, approved.id)) {
                                Text("Preview approved version")
                                    .font(PocketSheetType.actionSecondary)
                                    .foregroundStyle(PocketSheetTheme.Color.ink)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("versions.previewApproved")
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView("This piece is no longer here", systemImage: "doc")
        }
    }
}

private struct PieceVersionCard: View {
    let piece: ContentPiece
    let version: PieceVersion

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.s) {
            HStack(spacing: PocketSheetSpace.s) {
                PieceRemoteImage(url: version.content.firstPreviewURL, fallbackSystemImage: version.content.format.systemImage)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(version.number)")
                        .font(.headline)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }
                Spacer(minLength: PocketSheetSpace.xs)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            if isCurrentDraft && !version.changeSummary.isEmpty {
                PocketSheetDivider()
                VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                    Label("Changed", systemImage: "doc.text")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                    ForEach(version.changeSummary, id: \.self) { change in
                        Text("• \(change)")
                            .font(.footnote)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                    }
                }
            }
        }
        .padding(PocketSheetSpace.s)
        .background(PocketSheetTheme.Color.paperRaised, in: RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous)
                .stroke(isCurrentDraft ? PocketSheetTheme.Color.ink : PocketSheetTheme.Color.hairline, lineWidth: isCurrentDraft ? 1.5 : 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var isCurrentDraft: Bool { version.id == piece.draftVersionID }

    private var subtitle: String {
        var parts = [piece.versionLabel(version)]
        if piece.postedVersionNumbers.contains(version.number) { parts.append("Posted") }
        parts.append(PieceDates.relative(version.approvedAt ?? version.updatedAt))
        return parts.joined(separator: " · ")
    }
}

struct PieceVersionPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    let pieceID: UUID
    let versionID: UUID

    var body: some View {
        if let piece = services.pieceStore.piece(pieceID),
           let version = piece.versions.first(where: { $0.id == versionID }) {
            PieceScreen(title: "Version \(version.number)") {
                PieceLargeTitle(title: version.content.title, eyebrow: "\(piece.versionLabel(version)) · \(version.origin.label)")
                PieceContentPreview(content: version.content)
            } footer: {
                if version.id != piece.draftVersionID {
                    PieceFooter {
                        PiecePrimaryButton(title: "Restore as new draft") {
                            services.pieceStore.update { library, now in
                                try library.restore(pieceID, versionID: versionID, now: now)
                            }
                            services.lastActionMessage = "Restored as a new draft. Later versions stay in history."
                            dismiss()
                        }
                        .accessibilityIdentifier("version.restore")
                    }
                }
            }
        } else {
            ContentUnavailableView("This version is no longer here", systemImage: "doc")
        }
    }
}

struct PieceContentPreview: View {
    let content: PieceContent

    var body: some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.m) {
            previewSection("Script", text: content.script.nilIfBlank ?? "No script yet")
            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                PieceSectionLabel(text: content.format.usesFilming ? "Shots" : "Media plan")
                if content.shots.isEmpty {
                    Text("No shots planned")
                        .font(.body)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }
                ForEach(Array(content.shots.enumerated()), id: \.element.id) { index, shot in
                    HStack(alignment: .top, spacing: PocketSheetSpace.s) {
                        PieceRemoteImage(url: shot.previewURL, fallbackSystemImage: content.format.usesFilming ? "video" : "photo")
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(index + 1) · \(shot.title)")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(PocketSheetTheme.Color.ink)
                            if let direction = shot.direction.nilIfBlank {
                                Text(direction)
                                    .font(.footnote)
                                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                            }
                            if let line = shot.line.nilIfBlank {
                                Text("“\(line)”")
                                    .font(.footnote)
                                    .foregroundStyle(PocketSheetTheme.Color.ink)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            previewSection("Instagram caption", text: content.instagramCaption.nilIfBlank ?? "No caption yet")
            if let tiktok = content.tiktokCaption.nilIfBlank {
                previewSection("TikTok caption", text: tiktok)
            }
            if let hashtags = content.hashtags.nilIfBlank {
                previewSection("Hashtags", text: hashtags)
            }
        }
    }

    private func previewSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
            PieceSectionLabel(text: title)
            Text(text)
                .font(.body)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PocketSheetSpace.m)
                .background(PocketSheetTheme.Color.paperRaised, in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
        }
    }
}

struct PieceReviewChangesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    let pieceID: UUID
    @State private var editor: PieceEditorKind?
    @State private var showsEditChoice = false

    var body: some View {
        Group {
            if let piece = services.pieceStore.piece(pieceID),
               let draft = piece.draftVersion {
                PieceScreen(title: "Review changes") {
                    PieceLargeTitle(title: draft.content.title)
                    PieceBadge(text: "Draft version \(draft.number)", systemImage: "doc.text")
                    HStack(alignment: .top, spacing: PocketSheetSpace.s) {
                        if let approved = piece.approvedVersion {
                            comparisonColumn(heading: "Approved version \(approved.number)", content: approved.content)
                        }
                        comparisonColumn(heading: "New draft", content: draft.content)
                    }
                    if !draft.changeSummary.isEmpty {
                        VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                            Text("What changed")
                                .font(.headline)
                            ForEach(draft.changeSummary, id: \.self) { change in
                                Text("• \(change)")
                                    .font(.body)
                            }
                        }
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .accessibilityIdentifier("changes.summary")
                    }
                    if !piece.shotsNeedingReview.isEmpty {
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
                        .accessibilityIdentifier("changes.filmingImpact")
                    }
                } footer: {
                    PieceFooter {
                        PiecePrimaryButton(title: "Approve new version") {
                            services.approvePieces([pieceID])
                            dismiss()
                        }
                        .accessibilityIdentifier("changes.approve")
                    } secondary: {
                        PieceTextButton(title: "Continue editing") { showsEditChoice = true }
                            .accessibilityIdentifier("changes.continueEditing")
                    }
                }
                .onAppear {
                    services.pieceStore.update { library, now in
                        library.markReviewed(pieceID, now: now)
                    }
                }
                .confirmationDialog("What would you like to edit?", isPresented: $showsEditChoice, titleVisibility: .visible) {
                    Button("Script") { editor = .script }
                    Button(draft.content.format.usesFilming ? "Shots" : "Media plan") { editor = .shots }
                    Button("Caption") { editor = .caption }
                }
            } else {
                ContentUnavailableView("No changes to review", systemImage: "checkmark.circle")
            }
        }
        .sheet(item: $editor) { kind in
            PieceEditorSheet(pieceID: pieceID, kind: kind)
        }
    }

    private func comparisonColumn(heading: String, content: PieceContent) -> some View {
        VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
            Text(heading)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            Text(content.script.nilIfBlank ?? content.title)
                .font(.subheadline)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .lineLimit(6)
            PieceRemoteImage(url: content.firstPreviewURL, fallbackSystemImage: content.format.systemImage)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(content.shots.count == 1 ? "1 shot" : "\(content.shots.count) shots")
                .font(.footnote)
                .foregroundStyle(PocketSheetTheme.Color.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PocketSheetSpace.s)
        .background(PocketSheetTheme.Color.paperRaised, in: RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous)
                .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ReviewDayView: View {
    @Environment(AppServices.self) private var services
    let date: String
    @State private var selection: Set<UUID> = []
    @State private var didSeedSelection = false

    var body: some View {
        let pieces = services.pieceStore.pieces(on: date)
        let pending = pieces.filter(\.needsReview)
        let selectable = Set(pending.filter(\.isReviewedForApproval).map(\.id))
        let selected = selection.intersection(selectable)
        PieceScreen(title: "Review day") {
            PieceLargeTitle(title: PieceDates.longLabel(date), subtitle: services.pieceStore.summary(on: date).line)
                .accessibilityIdentifier("reviewDay.title")
            ForEach(Array(pieces.enumerated()), id: \.element.id) { index, piece in
                ReviewDayRow(
                    piece: piece,
                    isSelected: selected.contains(piece.id),
                    onToggle: {
                        if selection.contains(piece.id) {
                            selection.remove(piece.id)
                        } else {
                            selection.insert(piece.id)
                        }
                    }
                )
                .accessibilityIdentifier("reviewDay.piece.\(index)")
            }
            PieceNote(text: "Approval saves a version. It does not post.")
        } footer: {
            PieceFooter {
                PiecePrimaryButton(title: approveTitle(count: selected.count), isEnabled: !selected.isEmpty) {
                    services.approvePieces(Array(selected))
                    selection.removeAll()
                }
                .accessibilityIdentifier("reviewDay.approve")
            }
        }
        .onAppear {
            guard !didSeedSelection else { return }
            selection = selectable
            didSeedSelection = true
        }
    }

    private func approveTitle(count: Int) -> String {
        switch count {
        case 0: "Select reviewed pieces"
        case 1: "Approve 1 piece"
        default: "Approve \(count) pieces"
        }
    }
}

private struct ReviewDayRow: View {
    let piece: ContentPiece
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: PocketSheetSpace.s) {
            if piece.needsReview && piece.isReviewedForApproval {
                Button(action: onToggle) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.title2)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "Selected for approval" : "Not selected")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                Image(systemName: piece.needsReview ? "doc.text" : "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            NavigationLink(value: PieceRoute.piece(piece.id)) {
                HStack(spacing: PocketSheetSpace.s) {
                    PieceThumbnail(piece: piece, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(piece.title)
                            .font(.headline)
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                        Text(rowStatus)
                            .font(.footnote)
                            .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    }
                    Spacer(minLength: PocketSheetSpace.xs)
                    if piece.needsReview && !piece.isReviewedForApproval {
                        Text("Review")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(PocketSheetTheme.Color.ink)
                            .padding(.horizontal, PocketSheetSpace.s)
                            .frame(minHeight: 36)
                            .overlay {
                                Capsule().stroke(PocketSheetTheme.Color.ink, lineWidth: 1)
                            }
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(PocketSheetSpace.xs)
        .background(PocketSheetTheme.Color.paperRaised, in: RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous)
                .stroke(PocketSheetTheme.Color.hairline, lineWidth: 1)
        }
    }

    private var rowStatus: String {
        if piece.needsReview {
            return piece.isReviewedForApproval ? "Reviewed" : "Needs review"
        }
        return piece.statusLine
    }
}
