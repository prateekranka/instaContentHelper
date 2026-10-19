import PhotosUI
import SwiftUI
import UIKit

struct PieceReadyToPostView: View {
    @Environment(AppServices.self) private var services
    let pieceID: UUID
    @State private var pickerItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        Group {
            if let piece = services.pieceStore.piece(pieceID) {
                ready(piece)
            } else {
                ContentUnavailableView("This piece is no longer here", systemImage: "doc")
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            attachFinal(item)
        }
    }

    private func ready(_ piece: ContentPiece) -> some View {
        let isVideo = piece.content.format.usesFilming
        return PieceScreen(title: "Content") {
            PieceLargeTitle(title: piece.title)
            if piece.markedShotAt != nil {
                PieceBadge(text: isVideo ? "Shot" : "Ready", systemImage: "checkmark")
                    .accessibilityIdentifier("ready.status")
            }
            PieceMediaHero(piece: piece, height: 260)
            PieceGroup {
                PhotosPicker(selection: $pickerItem, matching: isVideo ? .videos : .images) {
                    PieceInfoRow(
                        systemImage: isVideo ? "play.circle" : "photo",
                        title: piece.finalMedia == nil ? (isVideo ? "Choose final video" : "Choose final photo") : (isVideo ? "Final video" : "Final photo"),
                        subtitle: finalMediaSubtitle(piece, isImporting: isImporting)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isImporting)
                .accessibilityIdentifier("ready.finalMedia")
                ForEach(PiecePlatform.allCases) { platform in
                    PocketSheetDivider()
                    PieceInfoRow(
                        systemImage: "text.bubble",
                        title: "\(platform.title) caption",
                        subtitle: piece.content.caption(for: platform).nilIfBlank ?? "No caption yet"
                    ) {
                        PieceCopyButton(text: piece.content.postText(for: platform))
                    }
                    .accessibilityIdentifier("ready.caption.\(platform.rawValue)")
                }
            }
            if let importError {
                PieceNote(text: importError, systemImage: "exclamationmark.circle")
            } else if let media = piece.finalMedia, services.pieceStore.mediaURL(for: media.fileName) == nil {
                PieceNote(text: "Your final \(media.kind == .video ? "video" : "photo") was added on another device. Choose it again here to post from this phone.", systemImage: "iphone")
                    .accessibilityIdentifier("ready.mediaElsewhere")
            } else if piece.finalMedia == nil {
                PieceNote(text: isVideo
                    ? "Captured clips are not a finished video. Edit them in your usual app, then choose the final video here."
                    : "Choose the photo you will post. Only the media you choose is added.")
            } else {
                PieceNote(text: "You can edit captions before posting.")
            }
        } footer: {
            PieceFooter {
                if piece.content.format.usesFilming || piece.markedShotAt != nil {
                    NavigationLink(value: PieceRoute.postOptions(pieceID)) {
                        PieceFooterLinkLabel(title: "Prepare to post")
                    }
                    .buttonStyle(PocketSheetPressFeedbackStyle())
                    .accessibilityIdentifier("ready.preparePost")
                } else {
                    PiecePrimaryButton(title: "Mark ready") {
                        _ = services.markPieceShot(pieceID)
                    }
                    .accessibilityIdentifier("ready.markReady")
                }
            }
        }
    }

    private func finalMediaSubtitle(_ piece: ContentPiece, isImporting: Bool) -> String {
        if isImporting { return "Adding…" }
        guard let media = piece.finalMedia else { return "From Photos" }
        if let duration = media.durationSeconds {
            let total = Int(duration.rounded())
            return "Selected · \(String(format: "%d:%02d", total / 60, total % 60))"
        }
        return "Selected"
    }

    private func attachFinal(_ item: PhotosPickerItem) {
        guard let piece = services.pieceStore.piece(pieceID) else { return }
        let kind: PieceMediaKind = piece.content.format.usesFilming ? .video : .photo
        isImporting = true
        importError = nil
        Task { @MainActor in
            defer {
                isImporting = false
                pickerItem = nil
            }
            do {
                let media = try await PieceMediaImporter.importItem(item, kind: kind, store: services.pieceStore)
                services.pieceStore.update { library, now in
                    try library.setFinalMedia(pieceID, media: media, now: now)
                }
            } catch {
                importError = "That file could not be added. Try another one."
            }
        }
    }
}

struct PiecePostOptionsView: View {
    @Environment(AppServices.self) private var services
    let pieceID: UUID

    var body: some View {
        if let piece = services.pieceStore.piece(pieceID) {
            PieceScreen(title: "Post content") {
                PieceLargeTitle(title: "Where would you like to post?")
                PieceMediaHero(piece: piece, height: 220)
                PieceGroup {
                    ForEach(Array(PiecePlatform.allCases.enumerated()), id: \.element.id) { offset, platform in
                        if offset > 0 { PocketSheetDivider() }
                        Button {
                            toggle(platform, in: piece)
                        } label: {
                            PieceInfoRow(
                                systemImage: platform == .instagram ? "camera" : "music.note",
                                title: platform.title,
                                subtitle: piece.postingState(for: platform) == .notPosted ? "Finish in the \(platform.title) app" : piece.postingState(for: platform).label(for: platform)
                            ) {
                                Image(systemName: piece.targets.contains(platform) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(PocketSheetTheme.Color.ink)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(piece.targets.contains(platform) ? .isSelected : [])
                        .accessibilityIdentifier("post.target.\(platform.rawValue)")
                    }
                }
                PieceGroup {
                    ShareLink(item: shareText(piece)) {
                        PieceInfoRow(systemImage: "square.and.arrow.up", title: "Finish in another app")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("post.shareCaption")
                    if let url = finalMediaURL(piece) {
                        PocketSheetDivider()
                        ShareLink(item: url) {
                            PieceInfoRow(systemImage: "film", title: "Share final media")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("post.shareMedia")
                    }
                }
                PieceNote(text: "Review each platform separately. ContentHelper does not post for you yet; you finish in each app and mark it posted.")
            } footer: {
                PieceFooter {
                    if let next = nextPlatform(piece) {
                        NavigationLink(value: PieceRoute.platformFinish(pieceID, next)) {
                            PieceFooterLinkLabel(title: "Review \(next.title)")
                        }
                        .buttonStyle(PocketSheetPressFeedbackStyle())
                        .accessibilityIdentifier("post.review")
                    } else if piece.targets.isEmpty {
                        PiecePrimaryButton(title: "Choose where to post", isEnabled: false) {}
                            .accessibilityIdentifier("post.review")
                    } else {
                        NavigationLink(value: PieceRoute.postResults(pieceID)) {
                            PieceFooterLinkLabel(title: "View posting status")
                        }
                        .buttonStyle(PocketSheetPressFeedbackStyle())
                        .accessibilityIdentifier("post.results")
                    }
                }
            }
        } else {
            ContentUnavailableView("This piece is no longer here", systemImage: "doc")
        }
    }

    private func toggle(_ platform: PiecePlatform, in piece: ContentPiece) {
        var targets = piece.targets
        if let index = targets.firstIndex(of: platform) {
            targets.remove(at: index)
        } else {
            targets.append(platform)
        }
        services.pieceStore.update { library, now in
            try library.setTargets(pieceID, targets: targets, now: now)
        }
    }

    private func nextPlatform(_ piece: ContentPiece) -> PiecePlatform? {
        piece.targets.first { !piece.postingState(for: $0).isPostedOutcome }
    }

    private func shareText(_ piece: ContentPiece) -> String {
        piece.content.postText(for: piece.targets.first ?? .instagram)
    }

    private func finalMediaURL(_ piece: ContentPiece) -> URL? {
        piece.finalMedia.flatMap { services.pieceStore.mediaURL(for: $0.fileName) }
    }
}

struct PiecePlatformFinishView: View {
    @Environment(AppServices.self) private var services
    let pieceID: UUID
    let platform: PiecePlatform
    @State private var link = ""
    @State private var copied = false
    @State private var showsResults = false

    var body: some View {
        Group {
            if let piece = services.pieceStore.piece(pieceID) {
                finish(piece)
            } else {
                ContentUnavailableView("This piece is no longer here", systemImage: "doc")
            }
        }
        .navigationDestination(isPresented: $showsResults) {
            PiecePostResultsView(pieceID: pieceID)
        }
    }

    private func finish(_ piece: ContentPiece) -> some View {
        let text = piece.content.postText(for: platform)
        return PieceScreen(title: platform.title) {
            PieceLargeTitle(title: "Finish in \(platform.title)", subtitle: piece.title)
            PieceMediaHero(piece: piece, height: 220)
            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                PieceSectionLabel(text: "Caption")
                Text(text.nilIfBlank ?? "No caption yet")
                    .font(.body)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(PocketSheetSpace.m)
                    .background(PocketSheetTheme.Color.paperRaised, in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                    .accessibilityIdentifier("finish.caption")
            }
            PieceGroup {
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    let appURL = platform.appURL
                    let webURL = platform.webURL
                    Task { @MainActor in
                        if let appURL, await UIApplication.shared.open(appURL) {
                            return
                        }
                        if let webURL {
                            _ = await UIApplication.shared.open(webURL)
                        }
                    }
                } label: {
                    PieceInfoRow(
                        systemImage: "arrow.up.forward.app",
                        title: "Copy caption and open \(platform.title)",
                        subtitle: copied ? "Caption copied" : nil
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("finish.open")
                if let media = piece.finalMedia, let url = services.pieceStore.mediaURL(for: media.fileName) {
                    PocketSheetDivider()
                    ShareLink(item: url) {
                        PieceInfoRow(systemImage: "square.and.arrow.up", title: "Share final \(media.kind == .video ? "video" : "photo")")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("finish.shareMedia")
                }
            }
            VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                PieceSectionLabel(text: "Post link (optional)")
                TextField("Paste the link after posting", text: $link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(PocketSheetSpace.m)
                    .frame(minHeight: 52)
                    .background(PocketSheetTheme.Color.paperRaised, in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                    .accessibilityIdentifier("finish.link")
            }
            PieceNote(text: "Mark it posted after it is live. This is your own record; ContentHelper does not check \(platform.title).")
        } footer: {
            PieceFooter {
                PiecePrimaryButton(title: "Mark posted on \(platform.title)") {
                    services.recordPiecePosting(pieceID, platform: platform, link: link)
                    showsResults = true
                }
                .accessibilityIdentifier("finish.markPosted")
            }
        }
    }
}

struct PiecePostResultsView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppState.self) private var appState
    let pieceID: UUID

    var body: some View {
        if let piece = services.pieceStore.piece(pieceID) {
            PieceScreen(title: "Posting status") {
                PieceLargeTitle(title: piece.title)
                PieceMediaHero(piece: piece, height: 200)
                PieceGroup {
                    let platforms = shownPlatforms(piece)
                    ForEach(Array(platforms.enumerated()), id: \.element.id) { offset, platform in
                        if offset > 0 { PocketSheetDivider() }
                        resultRow(piece: piece, platform: platform)
                    }
                    if platforms.isEmpty, let legacy = piece.legacyPostedMark, legacy.state.isPostedOutcome {
                        PieceInfoRow(systemImage: legacy.state.systemImage, title: "Posted", subtitle: legacy.state.label(for: nil)) { EmptyView() }
                    }
                }
                .accessibilityIdentifier("results.list")
                PieceNote(text: "Each platform keeps its own status.")
                NavigationLink(value: PieceRoute.postOptions(pieceID)) {
                    PieceGroup {
                        PieceInfoRow(systemImage: "pencil", title: "Mark a post manually")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("results.manual")
            } footer: {
                PieceFooter {
                    PiecePrimaryButton(title: "Back to today") {
                        appState.returnToToday()
                    }
                    .accessibilityIdentifier("results.backToToday")
                }
            }
        } else {
            ContentUnavailableView("This piece is no longer here", systemImage: "doc")
        }
    }

    private func shownPlatforms(_ piece: ContentPiece) -> [PiecePlatform] {
        PiecePlatform.allCases.filter { piece.targets.contains($0) || piece.latestPosting(for: $0) != nil }
    }

    private func resultRow(piece: ContentPiece, platform: PiecePlatform) -> some View {
        let record = piece.latestPosting(for: platform)
        let state = record?.state ?? .notPosted
        return HStack(spacing: PocketSheetSpace.s) {
            Image(systemName: state.systemImage)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text(state.label(for: platform))
                    .font(.footnote)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                if let record, state.isPostedOutcome {
                    Text("Version \(record.versionNumber) · \(PieceDates.relative(record.recordedAt))")
                        .font(.footnote)
                        .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                }
            }
            Spacer(minLength: PocketSheetSpace.xs)
            if state.isPostedOutcome {
                if let link = record?.link, let url = URL(string: link) {
                    Link("View post", destination: url)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .frame(minHeight: 44)
                }
                if state == .markedByYou {
                    Button("Undo") {
                        services.pieceStore.update { library, now in
                            try library.removeManualPostedMark(pieceID, platform: platform, now: now)
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Undo \(platform.title) posted mark")
                    .accessibilityIdentifier("results.undo.\(platform.rawValue)")
                }
            } else {
                NavigationLink(value: PieceRoute.platformFinish(pieceID, platform)) {
                    Text("Review and post")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("results.review.\(platform.rawValue)")
            }
        }
        .padding(.horizontal, PocketSheetSpace.m)
        .padding(.vertical, PocketSheetSpace.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("results.\(platform.rawValue)")
    }
}
