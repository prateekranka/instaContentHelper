import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PieceMovieFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PieceMovieFile(url: copy)
        }
    }
}

enum PieceMediaImporter {
    @MainActor
    static func importItem(_ item: PhotosPickerItem, kind: PieceMediaKind, store: PieceStore) async throws -> PieceMedia {
        switch kind {
        case .video:
            guard let movie = try await item.loadTransferable(type: PieceMovieFile.self) else {
                throw CocoaError(.fileReadUnknown)
            }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            let fileName = try store.storeMediaFile(from: movie.url, preferredExtension: "mov")
            let details = await videoDetails(for: movie.url)
            let thumbnail = try details.thumbnail.map { try store.storeMediaData($0, fileExtension: "jpg") }
            return PieceMedia(
                kind: .video,
                fileName: fileName,
                thumbnailFileName: thumbnail,
                durationSeconds: details.duration,
                addedAt: Date()
            )
        case .photo:
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw CocoaError(.fileReadUnknown)
            }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let fileName = try store.storeMediaData(data, fileExtension: ext)
            let thumbnail = UIImage(data: data)?
                .preparingThumbnail(of: CGSize(width: 600, height: 600))?
                .jpegData(compressionQuality: 0.8)
            let thumbnailName = try thumbnail.map { try store.storeMediaData($0, fileExtension: "jpg") }
            return PieceMedia(kind: .photo, fileName: fileName, thumbnailFileName: thumbnailName, addedAt: Date())
        }
    }

    nonisolated static func videoDetails(for url: URL) async -> (thumbnail: Data?, duration: Double?) {
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)
        let image = try? await generator.image(at: .zero).image
        let data = image.flatMap { UIImage(cgImage: $0).jpegData(compressionQuality: 0.8) }
        return (data, duration.map { CMTimeGetSeconds($0) })
    }
}

struct PieceFilmingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    let pieceID: UUID

    @State private var index = 0
    @State private var didPosition = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        Group {
            if let piece = services.pieceStore.piece(pieceID), !piece.filmingShots.isEmpty {
                filming(piece)
            } else {
                ContentUnavailableView("No shots to film", systemImage: "video.slash", description: Text("Add shots to this piece first."))
            }
        }
        .onAppear(perform: position)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            attach(item)
        }
    }

    private func filming(_ piece: ContentPiece) -> some View {
        let shots = piece.filmingShots
        let current = min(max(index, 0), shots.count - 1)
        let shot = shots[current]
        let capture = piece.capture(for: shot.id)
        return PieceScreen(title: "Shoot Folio") {
            PieceLargeTitle(title: piece.isFilmingInProgress ? "Continue filming" : "Start filming")
            Group {
                if shots.count <= 24 {
                    HStack(spacing: PocketSheetSpace.xs) {
                        ForEach(shots) { item in
                            Capsule()
                                .fill(piece.capturedShotIDs.contains(item.id) || item.id == shot.id ? PocketSheetTheme.Color.ink : PocketSheetTheme.Color.hairline)
                                .frame(height: item.id == shot.id ? 6 : 4)
                        }
                    }
                } else {
                    ProgressView(value: Double(piece.capturedFilmingShotCount), total: Double(shots.count))
                        .tint(PocketSheetTheme.Color.ink)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(piece.capturedFilmingShotCount) of \(shots.count) shots captured")
            VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                Text("Shot \((current + 1).formatted()) of \(shots.count.formatted())".uppercased())
                    .font(PocketSheetType.sectionLabel)
                    .tracking(0.4)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
                    .accessibilityIdentifier("filming.progress")
                Text(shot.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("filming.shotTitle")
            }
            shotMedia(shot: shot, capture: capture, format: piece.content.format)
            if let direction = shot.direction.nilIfBlank {
                Text(direction)
                    .font(.body)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let line = shot.line.nilIfBlank {
                VStack(alignment: .leading, spacing: PocketSheetSpace.xs) {
                    PieceSectionLabel(text: "Say this")
                    Text(line)
                        .font(.body)
                        .foregroundStyle(PocketSheetTheme.Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(PocketSheetSpace.m)
                        .background(PocketSheetTheme.Color.fillMuted, in: RoundedRectangle(cornerRadius: PocketSheetShape.controlRadius, style: .continuous))
                }
            }
            PieceGroup {
                PhotosPicker(selection: $pickerItem, matching: .videos) {
                    PieceInfoRow(
                        systemImage: "photo.on.rectangle",
                        title: capture?.clip == nil ? "Attach a clip from Photos" : "Replace clip",
                        subtitle: isImporting ? "Adding your clip…" : nil
                    )
                }
                .buttonStyle(.plain)
                .disabled(isImporting)
                .accessibilityIdentifier("filming.attachClip")
                if capture != nil {
                    PocketSheetDivider()
                    Button {
                        services.pieceStore.update { library, now in
                            try library.unmarkCaptured(pieceID, shotID: shot.id, now: now)
                        }
                    } label: {
                        PieceInfoRow(systemImage: "arrow.uturn.backward", title: "Mark not captured") { EmptyView() }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("filming.unmark")
                }
            }
            if let importError {
                PieceNote(text: importError, systemImage: "exclamationmark.circle")
            } else {
                PieceNote(text: "Only the media you choose is added. Attaching is optional.")
            }
        } footer: {
            PieceFooter {
                if capture == nil {
                    PiecePrimaryButton(title: "Mark captured") {
                        markCaptured(shot: shot, in: piece)
                    }
                    .accessibilityIdentifier("filming.markCaptured")
                } else if let next = nextUncaptured(after: current, in: piece) {
                    PiecePrimaryButton(title: "Next shot") { index = next }
                        .accessibilityIdentifier("filming.next")
                } else {
                    NavigationLink(value: PieceRoute.shotsReview(pieceID)) {
                        PieceFooterLinkLabel(title: "Review captured shots")
                    }
                    .buttonStyle(PocketSheetPressFeedbackStyle())
                    .accessibilityIdentifier("filming.reviewShots")
                }
            } secondary: {
                HStack(spacing: 0) {
                    PieceTextButton(title: "Previous") {
                        index = max(current - 1, 0)
                    }
                    .disabled(current == 0)
                    .opacity(current == 0 ? 0.4 : 1)
                    .accessibilityIdentifier("filming.previous")
                    Rectangle()
                        .fill(PocketSheetTheme.Color.hairline)
                        .frame(width: 1, height: 24)
                        .accessibilityHidden(true)
                    PieceTextButton(title: "Pause") {
                        services.lastActionMessage = "Filming paused. Your progress is saved."
                        dismiss()
                    }
                    .accessibilityIdentifier("filming.pause")
                }
            }
        }
        .onChange(of: index) { _, newValue in
            let shots = piece.filmingShots
            guard shots.indices.contains(newValue) else { return }
            services.pieceStore.update { library, _ in
                library.setFilmingPosition(pieceID, shotID: shots[newValue].id)
            }
        }
    }

    @ViewBuilder
    private func shotMedia(shot: PieceShot, capture: ShotCapture?, format: PieceFormat) -> some View {
        if let clip = capture?.clip {
            VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                PieceLocalImage(url: clip.thumbnailFileName.flatMap { services.pieceStore.mediaURL(for: $0) }, fallbackSystemImage: "film")
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous))
                Text(clipCaption(clip, needsReview: capture?.needsReview == true))
                    .font(.footnote)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("filming.clip")
        } else if let url = shot.previewURL {
            VStack(alignment: .leading, spacing: PocketSheetSpace.xxs) {
                PieceRemoteImage(url: url, fallbackSystemImage: format.systemImage)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: PocketSheetShape.sheetRadius, style: .continuous))
                Text(capture == nil ? "Shot preview · generated" : "Captured · shot preview · generated")
                    .font(.footnote)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            .accessibilityElement(children: .combine)
        } else if capture != nil {
            PieceStatusLabel(text: capture?.needsReview == true ? "Captured · needs review" : "Captured", systemImage: "checkmark.circle")
                .accessibilityIdentifier("filming.captured")
        }
    }

    private func clipCaption(_ clip: PieceMedia, needsReview: Bool) -> String {
        var parts = ["Your clip"]
        if let duration = clip.durationSeconds {
            let total = Int(duration.rounded())
            parts.append(String(format: "%d:%02d", total / 60, total % 60))
        }
        if needsReview { parts.append("needs review") }
        return parts.joined(separator: " · ")
    }

    private func position() {
        guard !didPosition, let piece = services.pieceStore.piece(pieceID) else { return }
        didPosition = true
        let shots = piece.filmingShots
        if let last = piece.lastFilmingShotID, let lastIndex = shots.firstIndex(where: { $0.id == last }) {
            index = piece.capture(for: last) == nil ? lastIndex : (nextUncaptured(after: lastIndex, in: piece) ?? lastIndex)
        } else {
            index = shots.firstIndex { piece.capture(for: $0.id) == nil } ?? 0
        }
        services.pieceStore.update { library, now in
            try library.startFilming(pieceID, now: now)
        }
    }

    private func nextUncaptured(after current: Int, in piece: ContentPiece) -> Int? {
        let shots = piece.filmingShots
        let captured = piece.capturedShotIDs
        let later = shots.indices.filter { $0 > current && !captured.contains(shots[$0].id) }
        if let first = later.first { return first }
        return shots.indices.first { $0 != current && !captured.contains(shots[$0].id) }
    }

    private func markCaptured(shot: PieceShot, in piece: ContentPiece) {
        services.pieceStore.update { library, now in
            try library.markCaptured(pieceID, shotID: shot.id, now: now)
        }
        if let updated = services.pieceStore.piece(pieceID),
           let next = nextUncaptured(after: index, in: updated) {
            index = next
        }
    }

    private func attach(_ item: PhotosPickerItem) {
        guard let piece = services.pieceStore.piece(pieceID) else { return }
        let shots = piece.filmingShots
        guard shots.indices.contains(index) else { return }
        let shotID = shots[index].id
        isImporting = true
        importError = nil
        Task { @MainActor in
            defer {
                isImporting = false
                pickerItem = nil
            }
            do {
                let media = try await PieceMediaImporter.importItem(item, kind: .video, store: services.pieceStore)
                services.pieceStore.update { library, now in
                    try library.markCaptured(pieceID, shotID: shotID, clip: media, now: now)
                }
            } catch {
                importError = "That clip could not be added. Your progress is saved."
            }
        }
    }
}

struct PieceShotsReviewView: View {
    @Environment(AppServices.self) private var services
    let pieceID: UUID

    var body: some View {
        if let piece = services.pieceStore.piece(pieceID) {
            let shots = piece.filmingShots
            PieceScreen(title: "Shoot Folio") {
                PieceLargeTitle(title: piece.allFilmingShotsCaptured ? "All \(shots.count) shots captured" : "\(piece.capturedFilmingShotCount) of \(shots.count) shots captured")
                    .accessibilityIdentifier("shots.title")
                PieceGroup {
                    ForEach(Array(shots.enumerated()), id: \.element.id) { offset, shot in
                        if offset > 0 { PocketSheetDivider() }
                        shotRow(shot, capture: piece.capture(for: shot.id), format: piece.content.format)
                    }
                }
                NavigationLink(value: PieceRoute.filming(pieceID)) {
                    PieceGroup {
                        PieceInfoRow(systemImage: "film.stack", title: "Attach or replace clips")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shots.attach")
                PieceNote(text: piece.markedShotAt == nil ? "Confirm when this piece is ready. Captured clips are not an edited video." : "Marked as shot. Next, choose your final video.")
            } footer: {
                PieceFooter {
                    if piece.markedShotAt == nil {
                        PiecePrimaryButton(title: "Mark as shot", isEnabled: piece.allFilmingShotsCaptured) {
                            _ = services.markPieceShot(pieceID)
                        }
                        .accessibilityIdentifier("shots.markShot")
                    } else {
                        NavigationLink(value: PieceRoute.readyToPost(pieceID)) {
                            PieceFooterLinkLabel(title: "Prepare to post")
                        }
                        .buttonStyle(PocketSheetPressFeedbackStyle())
                        .accessibilityIdentifier("shots.preparePost")
                    }
                }
            }
        } else {
            ContentUnavailableView("This piece is no longer here", systemImage: "doc")
        }
    }

    private func shotRow(_ shot: PieceShot, capture: ShotCapture?, format: PieceFormat) -> some View {
        HStack(spacing: PocketSheetSpace.s) {
            Group {
                if let thumb = capture?.clip?.thumbnailFileName {
                    PieceLocalImage(url: services.pieceStore.mediaURL(for: thumb), fallbackSystemImage: "film")
                } else {
                    PieceRemoteImage(url: shot.previewURL, fallbackSystemImage: format.systemImage)
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(shot.title)
                    .font(.headline)
                    .foregroundStyle(PocketSheetTheme.Color.ink)
                Text(rowDetail(capture))
                    .font(.footnote)
                    .foregroundStyle(PocketSheetTheme.Color.inkMuted)
            }
            Spacer(minLength: PocketSheetSpace.xs)
            Image(systemName: capture == nil ? "circle" : (capture?.needsReview == true ? "exclamationmark.circle" : "checkmark.circle.fill"))
                .font(.title2)
                .foregroundStyle(PocketSheetTheme.Color.ink)
                .accessibilityHidden(true)
        }
        .padding(PocketSheetSpace.s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(shot.title), \(rowDetail(capture))")
    }

    private func rowDetail(_ capture: ShotCapture?) -> String {
        guard let capture else { return "Not captured" }
        var parts = [capture.needsReview ? "Captured · needs review" : "Captured"]
        if capture.clip != nil { parts.append("clip attached") }
        return parts.joined(separator: " · ")
    }
}
