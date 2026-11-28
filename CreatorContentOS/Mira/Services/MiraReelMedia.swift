import AVFoundation
import CoreTransferable
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct MiraPickedMovie: Transferable {
    let url: URL
    let originalName: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let original = received.file
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension(original.pathExtension)
            try FileManager.default.copyItem(at: original, to: destination)
            return Self(url: destination, originalName: original.deletingPathExtension().lastPathComponent)
        }
    }
}

struct MiraReelMedia {
    let directory: URL
    private static let frameSize = CGSize(width: 1080, height: 1920)

    func url(for export: MiraReelExport) -> URL {
        directory.appendingPathComponent(export.filename)
    }

    func url(for clip: MiraClip) -> URL {
        directory.appendingPathComponent(clip.filename)
    }

    @MainActor func importClips(
        _ items: [PhotosPickerItem], known: [MiraClip], onIssue: (String) -> Void
    ) async throws -> [MiraClip] {
        var sources = Set(known.compactMap(\.sourceID))
        var clips: [MiraClip] = []
        var failures = 0
        for item in items {
            if let id = item.itemIdentifier, sources.contains(id) { continue }
            do {
                guard let movie = try await item.loadTransferable(type: MiraPickedMovie.self) else {
                    throw MiraError.invalid("Mira could not open this clip.")
                }
                defer { try? FileManager.default.removeItem(at: movie.url) }
                let clip = try await copyClip(movie.url, name: movie.originalName, sourceID: item.itemIdentifier)
                clips.append(clip)
                if let id = clip.sourceID { sources.insert(id) }
            } catch {
                failures += 1
            }
        }
        if failures > 0 {
            let issue = "\(failures) clips could not be added. Check that they play in Photos and try again."
            if clips.isEmpty { throw MiraError.invalid(issue) }
            onIssue(issue)
        }
        return clips
    }

    @MainActor func copyClip(_ source: URL, name: String, sourceID: String?) async throws -> MiraClip {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MiraError.invalid("This file has no video.")
        }
        let duration = try await track.load(.timeRange).duration.seconds
        guard duration.isFinite, duration > 0 else { throw MiraError.invalid("This clip has no playable duration.") }
        let metadata = try? await asset.load(.creationDate)
        let date = try? await metadata?.load(.dateValue)
        let access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let photo: PHAsset?
        if let sourceID, access == .authorized || access == .limited {
            photo = PHAsset.fetchAssets(withLocalIdentifiers: [sourceID], options: nil).firstObject
        } else {
            photo = nil
        }
        let fileExtension = source.pathExtension.lowercased()
        let clip = MiraClip(id: UUID(), fileExtension: ["mp4", "mov", "m4v"].contains(fileExtension) ? fileExtension : "mov",
            sourceID: sourceID, name: name.isEmpty ? "Video" : name, seconds: duration,
            createdAt: photo?.creationDate ?? date, bytes: try fileBytes(source))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: url(for: clip))
        return clip
    }

    @MainActor func render(_ recipe: MiraRenderRecipe) async throws -> MiraReelExport {
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw MiraError.invalid("Mira could not set up the Reel.") }
        var cursor = CMTime.zero
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var overlays: [(String, CMTimeRange)] = []
        for cut in recipe.cuts {
            let asset = AVURLAsset(url: url(for: cut.clip))
            guard let source = try await asset.loadTracks(withMediaType: .video).first else {
                throw MiraError.invalid("Mira cannot read \(cut.clip.name). Pick that clip again.")
            }
            let sourceRange = try await source.load(.timeRange)
            let planned = CMTime(seconds: Double(cut.seconds), preferredTimescale: 600)
            guard sourceRange.duration.seconds + 0.05 >= planned.seconds else {
                throw MiraError.invalid("\(cut.clip.name) is too short for its shot.")
            }
            let duration = CMTimeMinimum(sourceRange.duration, planned)
            let range = CMTimeRange(start: sourceRange.start, duration: duration)
            try video.insertTimeRange(range, of: source, at: cursor)
            if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first {
                let audioRange = try await sourceAudio.load(.timeRange).intersection(range)
                if !audioRange.isEmpty, audioRange.isValid {
                    try audio.insertTimeRange(audioRange, of: sourceAudio, at: cursor + (audioRange.start - range.start))
                }
            }
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: duration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
            let transform = try await source.load(.preferredTransform)
            let size = try await source.load(.naturalSize)
            layer.setTransform(Self.portraitTransform(transform, size: size), at: cursor)
            instruction.layerInstructions = [layer]
            instructions.append(instruction)
            overlays.append((cut.text, instruction.timeRange))
            cursor = cursor + duration
        }
        guard cursor.seconds > 0 else { throw MiraError.invalid("Add a clip to every shot first.") }
        let layout = AVMutableVideoComposition()
        layout.renderSize = Self.frameSize
        layout.frameDuration = CMTime(value: 1, timescale: 30)
        layout.instructions = instructions
        layout.animationTool = Self.animationTool(recipe, overlays: overlays, duration: cursor.seconds)

        let id = UUID()
        let output = directory.appendingPathComponent("\(id.uuidString).mp4")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        else { throw MiraError.invalid("Mira could not start the export.") }
        exporter.videoComposition = layout
        exporter.shouldOptimizeForNetworkUse = true
        do {
            try await exporter.export(to: output, as: .mp4)
            return MiraReelExport(id: id, recipe: recipe, bytes: try fileBytes(output))
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }

    func saveToPhotos(_ export: MiraReelExport) async throws {
        let access = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard access == .authorized || access == .limited else {
            throw MiraError.invalid("Allow Mira to add photos in Settings. Your Reel is still saved in Mira.")
        }
        let file = url(for: export)
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: file)
        }
    }

    private func fileBytes(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size > 0 else { throw MiraError.invalid("The video file is empty.") }
        return Int64(size)
    }

    private static func portraitTransform(_ orientation: CGAffineTransform, size: CGSize) -> CGAffineTransform {
        let bounds = CGRect(origin: .zero, size: size).applying(orientation).standardized
        let scale = max(frameSize.width / bounds.width, frameSize.height / bounds.height)
        let x = (frameSize.width - bounds.width * scale) / 2 - bounds.minX * scale
        let y = (frameSize.height - bounds.height * scale) / 2 - bounds.minY * scale
        return orientation.concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: x, y: y))
    }

    @MainActor private static func animationTool(
        _ recipe: MiraRenderRecipe, overlays: [(String, CMTimeRange)], duration: Double
    ) -> AVVideoCompositionCoreAnimationTool {
        let root = CALayer()
        root.frame = CGRect(origin: .zero, size: frameSize)
        let video = CALayer()
        video.frame = root.bounds
        root.addSublayer(video)
        addText(recipe.hook, to: root, region: CGRect(x: 112, y: 1160, width: 856, height: 430),
            font: 82, from: 0, until: min(3, duration), duration: duration)
        for (text, range) in overlays {
            addText(text, to: root, region: CGRect(x: 112, y: 670, width: 856, height: 340),
                font: 60, from: range.start.seconds, until: range.end.seconds, duration: duration)
        }
        addText(recipe.extraText, to: root, region: CGRect(x: 112, y: 246, width: 856, height: 375),
            font: 60, from: 0, until: duration, duration: duration)
        return AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: video, in: root)
    }

    @MainActor private static func addText(
        _ text: String, to root: CALayer, region: CGRect, font: CGFloat,
        from start: Double, until end: Double, duration: Double
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, end > start else { return }
        let layer = CALayer()
        layer.frame = region
        layer.contents = textImage(text, size: region.size, font: font)
        if start > 0 || end < duration {
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            var times: [NSNumber] = [0]
            var values = [start > 0 ? 0 : 1]
            if start > 0 { times.append(NSNumber(value: start / duration)); values.append(1) }
            if end < duration { times.append(NSNumber(value: end / duration)); values.append(0) }
            times.append(1)
            values.append(values.last ?? 0)
            animation.values = values
            animation.keyTimes = times
            animation.calculationMode = .discrete
            animation.beginTime = AVCoreAnimationBeginTimeAtZero
            animation.duration = duration
            animation.isRemovedOnCompletion = false
            animation.fillMode = .both
            layer.add(animation, forKey: "visible")
        }
        root.addSublayer(layer)
    }

    @MainActor private static func textImage(_ text: String, size: CGSize, font: CGFloat) -> CGImage? {
        let horizontal: CGFloat = 32
        let vertical: CGFloat = 22
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byCharWrapping
        let bounds = CGSize(width: size.width - 2 * horizontal, height: .greatestFiniteMagnitude)
        var fontSize = font
        var attributed = NSAttributedString()
        var height: CGFloat = 0
        repeat {
            attributed = NSAttributedString(string: text, attributes: [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white, .paragraphStyle: paragraph
            ])
            height = ceil(attributed.boundingRect(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
            fontSize -= 2
        } while height > size.height - 2 * vertical && fontSize >= 4
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let box = CGRect(x: 0, y: max(0, (size.height - height) / 2 - vertical),
                width: size.width, height: min(size.height, height + 2 * vertical))
            UIColor.black.withAlphaComponent(0.82).setFill()
            UIBezierPath(roundedRect: box, cornerRadius: 20).fill()
            attributed.draw(with: box.insetBy(dx: horizontal, dy: vertical),
                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }.cgImage
    }
}
