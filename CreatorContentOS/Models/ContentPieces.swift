import Foundation

enum PieceFormat: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case reel
    case carousel
    case story
    case photo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reel: "Reel"
        case .carousel: "Carousel"
        case .story: "Story"
        case .photo: "Photo"
        }
    }

    var systemImage: String {
        switch self {
        case .reel: "play.fill"
        case .carousel: "square.on.square"
        case .story: "camera.circle"
        case .photo: "photo"
        }
    }

    var usesFilming: Bool {
        self == .reel || self == .story
    }

    static let creationChoices: [PieceFormat] = [.reel, .carousel, .story]

    init(legacyFormat: String?, hasScenes: Bool) {
        let normalized = legacyFormat?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if normalized.contains("carousel") {
            self = .carousel
        } else if normalized.contains("story") {
            self = .story
        } else if normalized.contains("photo") || (normalized == "post" && !hasScenes) {
            self = .photo
        } else {
            self = .reel
        }
    }
}

enum PiecePlatform: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case instagram
    case tiktok

    var id: String { rawValue }

    var title: String {
        switch self {
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        }
    }

    var appURL: URL? {
        switch self {
        case .instagram: URL(string: "instagram://app")
        case .tiktok: nil
        }
    }

    var webURL: URL? {
        switch self {
        case .instagram: URL(string: "https://www.instagram.com/")
        case .tiktok: URL(string: "https://www.tiktok.com/")
        }
    }
}

struct PieceShot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var direction: String
    var line: String
    var durationSeconds: Int?
    var previewURL: URL?

    init(
        id: UUID = UUID(),
        title: String,
        direction: String = "",
        line: String = "",
        durationSeconds: Int? = nil,
        previewURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.direction = direction
        self.line = line
        self.durationSeconds = durationSeconds
        self.previewURL = previewURL
    }

    func hasSameFilmingPlan(as other: PieceShot) -> Bool {
        title == other.title && direction == other.direction && line == other.line
    }
}

struct PieceContent: Codable, Hashable, Sendable {
    var title: String
    var format: PieceFormat
    var durationSeconds: Int?
    var minutesToFilm: Int?
    var script: String
    var shots: [PieceShot]
    var instagramCaption: String
    var tiktokCaption: String
    var hashtags: String
    var accessibilityNote: String
    var notes: String

    init(
        title: String,
        format: PieceFormat = .reel,
        durationSeconds: Int? = nil,
        minutesToFilm: Int? = nil,
        script: String = "",
        shots: [PieceShot] = [],
        instagramCaption: String = "",
        tiktokCaption: String = "",
        hashtags: String = "",
        accessibilityNote: String = "",
        notes: String = ""
    ) {
        self.title = title
        self.format = format
        self.durationSeconds = durationSeconds
        self.minutesToFilm = minutesToFilm
        self.script = script
        self.shots = shots
        self.instagramCaption = instagramCaption
        self.tiktokCaption = tiktokCaption
        self.hashtags = hashtags
        self.accessibilityNote = accessibilityNote
        self.notes = notes
    }

    func caption(for platform: PiecePlatform) -> String {
        switch platform {
        case .instagram: instagramCaption
        case .tiktok: tiktokCaption.isBlankText ? instagramCaption : tiktokCaption
        }
    }

    mutating func setCaption(_ caption: String, for platform: PiecePlatform) {
        switch platform {
        case .instagram: instagramCaption = caption
        case .tiktok: tiktokCaption = caption
        }
    }

    func postText(for platform: PiecePlatform) -> String {
        [caption(for: platform), hashtags]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    var firstPreviewURL: URL? {
        shots.lazy.compactMap(\.previewURL).first
    }

    var shotSummary: String {
        let titles = shots.map(\.title).filter { !$0.isBlankText }
        return titles.prefix(3).joined(separator: ", ")
    }

    func changes(from previous: PieceContent) -> [String] {
        var changes: [String] = []
        if title != previous.title { changes.append("Title changed") }
        if format != previous.format { changes.append("Format changed to \(format.title)") }
        if script != previous.script { changes.append("Script updated") }
        let previousByID = Dictionary(uniqueKeysWithValues: previous.shots.map { ($0.id, $0) })
        let currentIDs = Set(shots.map(\.id))
        for (index, shot) in shots.enumerated() {
            if let old = previousByID[shot.id] {
                if !shot.hasSameFilmingPlan(as: old) {
                    changes.append("Shot \(index + 1) updated")
                }
            } else {
                changes.append("Shot \(index + 1) added")
            }
        }
        let removed = previous.shots.filter { !currentIDs.contains($0.id) }.count
        if removed == 1 {
            changes.append("1 shot removed")
        } else if removed > 1 {
            changes.append("\(removed) shots removed")
        }
        let keptOrder = shots.map(\.id).filter { previousByID[$0] != nil }
        let previousOrder = previous.shots.map(\.id).filter { currentIDs.contains($0) }
        if keptOrder != previousOrder { changes.append("Shots reordered") }
        if instagramCaption != previous.instagramCaption { changes.append("Instagram caption updated") }
        if tiktokCaption != previous.tiktokCaption { changes.append("TikTok caption updated") }
        if hashtags != previous.hashtags { changes.append("Hashtags updated") }
        if accessibilityNote != previous.accessibilityNote { changes.append("Accessibility notes updated") }
        if notes != previous.notes { changes.append("Notes updated") }
        return changes
    }

    func shotsNeedingReview(comparedWith approved: PieceContent, captured: Set<UUID>) -> [PieceShot] {
        let approvedByID = Dictionary(uniqueKeysWithValues: approved.shots.map { ($0.id, $0) })
        return shots.filter { shot in
            guard captured.contains(shot.id), let old = approvedByID[shot.id] else { return false }
            return !shot.hasSameFilmingPlan(as: old)
        }
    }

    func copyWithNewShotIdentities() -> PieceContent {
        var copy = self
        copy.shots = shots.map { shot in
            PieceShot(
                title: shot.title,
                direction: shot.direction,
                line: shot.line,
                durationSeconds: shot.durationSeconds,
                previewURL: shot.previewURL
            )
        }
        return copy
    }
}

enum PieceVersionOrigin: Codable, Hashable, Sendable {
    case generated
    case manual
    case imported
    case edit
    case restored(fromNumber: Int)

    var label: String {
        switch self {
        case .generated: "Created with AI"
        case .manual: "Written by you"
        case .imported: "From your plan"
        case .edit: "Edited"
        case .restored(let number): "Restored from version \(number)"
        }
    }
}

struct PieceVersion: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let number: Int
    var content: PieceContent
    var origin: PieceVersionOrigin
    let createdAt: Date
    var updatedAt: Date
    var reviewedAt: Date?
    var approvedAt: Date?
    var changeSummary: [String]

    init(
        id: UUID = UUID(),
        number: Int,
        content: PieceContent,
        origin: PieceVersionOrigin,
        createdAt: Date,
        reviewedAt: Date? = nil,
        approvedAt: Date? = nil,
        changeSummary: [String] = []
    ) {
        self.id = id
        self.number = number
        self.content = content
        self.origin = origin
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.reviewedAt = reviewedAt
        self.approvedAt = approvedAt
        self.changeSummary = changeSummary
    }

    var isReviewed: Bool { reviewedAt != nil }
}

enum PieceMediaKind: String, Codable, Hashable, Sendable {
    case video
    case photo
}

struct PieceMedia: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: PieceMediaKind
    var fileName: String
    var thumbnailFileName: String?
    var durationSeconds: Double?
    var addedAt: Date

    init(
        id: UUID = UUID(),
        kind: PieceMediaKind,
        fileName: String,
        thumbnailFileName: String? = nil,
        durationSeconds: Double? = nil,
        addedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.durationSeconds = durationSeconds
        self.addedAt = addedAt
    }
}

struct ShotCapture: Codable, Hashable, Sendable {
    let shotID: UUID
    var capturedAt: Date
    var versionNumber: Int
    var clip: PieceMedia?
    var needsReview: Bool
}

enum PostingState: String, Codable, CaseIterable, Hashable, Sendable {
    case notPosted
    case uploading
    case processing
    case finishInApp
    case posted
    case markedByYou
    case failed
    case unknown

    var isPostedOutcome: Bool {
        self == .posted || self == .markedByYou
    }

    func label(for platform: PiecePlatform?) -> String {
        let name = platform?.title
        switch self {
        case .notPosted: return "Not posted"
        case .uploading: return "Uploading"
        case .processing: return name.map { "Processing on \($0)" } ?? "Processing"
        case .finishInApp: return name.map { "Finish in \($0)" } ?? "Finish in the app"
        case .posted: return "Posted"
        case .markedByYou: return "Marked posted by you"
        case .failed: return "Failed"
        case .unknown: return "Result unknown"
        }
    }

    var systemImage: String {
        switch self {
        case .notPosted: "clock"
        case .uploading: "arrow.up.circle"
        case .processing: "hourglass"
        case .finishInApp: "arrow.up.forward.app"
        case .posted: "checkmark.circle.fill"
        case .markedByYou: "checkmark.circle"
        case .failed: "exclamationmark.circle"
        case .unknown: "questionmark.circle"
        }
    }
}

struct PostingRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var platform: PiecePlatform?
    var state: PostingState
    var versionNumber: Int
    var finalMediaID: UUID?
    var recordedAt: Date
    var link: String?
    var verificationSource: String

    init(
        id: UUID = UUID(),
        platform: PiecePlatform?,
        state: PostingState,
        versionNumber: Int,
        finalMediaID: UUID? = nil,
        recordedAt: Date,
        link: String? = nil,
        verificationSource: String = "creator"
    ) {
        self.id = id
        self.platform = platform
        self.state = state
        self.versionNumber = versionNumber
        self.finalMediaID = finalMediaID
        self.recordedAt = recordedAt
        self.link = link
        self.verificationSource = verificationSource
    }
}

enum PieceStage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case draft
    case approved
    case shot
    case posted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: "Draft"
        case .approved: "Approved"
        case .shot: "Shot"
        case .posted: "Posted"
        }
    }

    var systemImage: String {
        switch self {
        case .draft: "doc.text"
        case .approved: "checkmark.circle"
        case .shot: "camera"
        case .posted: "paperplane"
        }
    }
}

struct ContentPiece: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var date: String
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date
    var versions: [PieceVersion]
    var approvedVersionID: UUID?
    var draftVersionID: UUID?
    var filmingStartedAt: Date?
    var lastFilmingShotID: UUID?
    var captures: [ShotCapture]
    var markedShotAt: Date?
    var finalMedia: PieceMedia?
    var targets: [PiecePlatform]
    var postings: [PostingRecord]
    var linkedDailyCardID: UUID?
    var basedOnPieceID: UUID?
    var topic: String?

    init(
        id: UUID = UUID(),
        date: String,
        sortOrder: Int,
        createdAt: Date,
        firstVersion: PieceVersion,
        linkedDailyCardID: UUID? = nil,
        basedOnPieceID: UUID? = nil,
        topic: String? = nil
    ) {
        self.id = id
        self.date = date
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.versions = [firstVersion]
        if firstVersion.approvedAt != nil {
            approvedVersionID = firstVersion.id
            draftVersionID = nil
        } else {
            approvedVersionID = nil
            draftVersionID = firstVersion.id
        }
        captures = []
        targets = []
        postings = []
        self.linkedDailyCardID = linkedDailyCardID
        self.basedOnPieceID = basedOnPieceID
        self.topic = topic
    }

    var approvedVersion: PieceVersion? {
        approvedVersionID.flatMap { id in versions.first { $0.id == id } }
    }

    var draftVersion: PieceVersion? {
        draftVersionID.flatMap { id in versions.first { $0.id == id } }
    }

    var currentVersion: PieceVersion {
        draftVersion ?? approvedVersion ?? versions[versions.count - 1]
    }

    var content: PieceContent { currentVersion.content }

    var filmingContent: PieceContent { (approvedVersion ?? currentVersion).content }

    var title: String { content.title.isBlankText ? "Untitled" : content.title }

    var hasUnapprovedChanges: Bool { draftVersionID != nil && approvedVersionID != nil }

    var isApproved: Bool { approvedVersionID != nil }

    var needsReview: Bool { draftVersionID != nil }

    var isReviewedForApproval: Bool { draftVersion?.isReviewed ?? false }

    var nextVersionNumber: Int { (versions.map(\.number).max() ?? 0) + 1 }

    var capturedShotIDs: Set<UUID> { Set(captures.map(\.shotID)) }

    func capture(for shotID: UUID) -> ShotCapture? {
        captures.first { $0.shotID == shotID }
    }

    var filmingShots: [PieceShot] { filmingContent.shots }

    var capturedFilmingShotCount: Int {
        filmingShots.filter { capturedShotIDs.contains($0.id) }.count
    }

    var allFilmingShotsCaptured: Bool {
        !filmingShots.isEmpty && capturedFilmingShotCount == filmingShots.count
    }

    var isFilmingInProgress: Bool {
        markedShotAt == nil && (filmingStartedAt != nil || capturedFilmingShotCount > 0)
    }

    var shotsNeedingReview: [PieceShot] {
        guard let approved = approvedVersion, let draft = draftVersion else { return [] }
        return draft.content.shotsNeedingReview(comparedWith: approved.content, captured: capturedShotIDs)
    }

    var capturedShotsFlaggedForReview: [PieceShot] {
        let flagged = Set(captures.filter(\.needsReview).map(\.shotID))
        return filmingShots.filter { flagged.contains($0.id) }
    }

    func latestPosting(for platform: PiecePlatform) -> PostingRecord? {
        postings.last { $0.platform == platform }
    }

    var legacyPostedMark: PostingRecord? {
        postings.last { $0.platform == nil }
    }

    func postingState(for platform: PiecePlatform) -> PostingState {
        latestPosting(for: platform)?.state ?? .notPosted
    }

    var postedPlatforms: [PiecePlatform] {
        PiecePlatform.allCases.filter { postingState(for: $0).isPostedOutcome }
    }

    var hasPostedOutcome: Bool {
        !postedPlatforms.isEmpty || legacyPostedMark?.state.isPostedOutcome == true
    }

    var stage: PieceStage {
        if hasPostedOutcome { return .posted }
        if markedShotAt != nil { return .shot }
        if approvedVersionID != nil { return .approved }
        return .draft
    }

    var postingSummary: String? {
        let platforms = targets.isEmpty ? postedPlatforms : targets
        if platforms.isEmpty {
            return legacyPostedMark?.state.isPostedOutcome == true ? "Marked posted by you" : nil
        }
        let parts = platforms.map { platform -> String in
            let state = postingState(for: platform)
            switch state {
            case .posted: return "\(platform.title) posted"
            case .markedByYou: return "\(platform.title) marked posted"
            case .notPosted: return "\(platform.title) not posted"
            default: return "\(platform.title): \(state.label(for: platform))"
            }
        }
        return parts.joined(separator: " · ")
    }

    var statusLine: String {
        var parts: [String] = []
        switch stage {
        case .posted:
            parts.append(postingSummary ?? "Posted")
        case .shot:
            parts.append(content.format.usesFilming ? "Shot" : "Ready")
            if let summary = postingSummary, !targets.isEmpty { parts.append(summary) }
        case .approved:
            if isFilmingInProgress && !filmingShots.isEmpty {
                parts.append("Filming · \(capturedFilmingShotCount) of \(filmingShots.count) shots")
            } else {
                parts.append("Approved")
            }
        case .draft:
            parts.append(isReviewedForApproval ? "Draft · reviewed" : "Draft")
        }
        if hasUnapprovedChanges {
            parts.append("New draft to review")
        }
        return parts.joined(separator: " · ")
    }

    var approvalLabel: String {
        if let draft = draftVersion {
            return approvedVersion == nil ? "Draft" : "Draft version \(draft.number)"
        }
        if let approved = approvedVersion {
            return "Approved · version \(approved.number)"
        }
        return "Draft"
    }

    func versionLabel(_ version: PieceVersion) -> String {
        if version.id == draftVersionID { return "Draft" }
        if version.id == approvedVersionID { return "Approved" }
        if version.approvedAt != nil { return "Approved earlier" }
        return "Earlier draft"
    }

    var postedVersionNumbers: Set<Int> {
        Set(postings.filter(\.state.isPostedOutcome).map(\.versionNumber))
    }
}

struct PieceDaySummary: Hashable, Sendable {
    var total: Int
    var approved: Int
    var needsReview: Int

    var line: String {
        guard total > 0 else { return "No pieces yet" }
        let pieces = total == 1 ? "1 piece" : "\(total) pieces"
        if needsReview == 0 && approved == total {
            return "Day approved · \(pieces)"
        }
        var parts = [pieces]
        if approved > 0 { parts.append("\(approved) approved") }
        if needsReview > 0 { parts.append("\(needsReview) \(needsReview == 1 ? "needs" : "need") review") }
        return parts.joined(separator: " · ")
    }
}

enum PieceLibraryError: Error, Equatable {
    case missingPiece
    case nothingToApprove
    case shotsIncomplete
}

struct PieceLibrary: Codable, Hashable, Sendable {
    var pieces: [ContentPiece] = []
    var schemaVersion: Int = 1

    func piece(_ id: UUID) -> ContentPiece? {
        pieces.first { $0.id == id }
    }

    func pieces(on date: String) -> [ContentPiece] {
        pieces
            .filter { $0.date == date }
            .sorted { lhs, rhs in
                lhs.sortOrder == rhs.sortOrder ? lhs.createdAt < rhs.createdAt : lhs.sortOrder < rhs.sortOrder
            }
    }

    func summary(on date: String) -> PieceDaySummary {
        let dayPieces = pieces(on: date)
        return PieceDaySummary(
            total: dayPieces.count,
            approved: dayPieces.filter { $0.isApproved && !$0.needsReview }.count,
            needsReview: dayPieces.filter(\.needsReview).count
        )
    }

    var datesWithPieces: Set<String> {
        Set(pieces.map(\.date))
    }

    private func nextSortOrder(on date: String) -> Int {
        (pieces.filter { $0.date == date }.map(\.sortOrder).max() ?? -1) + 1
    }

    private func index(of id: UUID) throws -> Int {
        guard let index = pieces.firstIndex(where: { $0.id == id }) else {
            throw PieceLibraryError.missingPiece
        }
        return index
    }

    @discardableResult
    mutating func addPiece(
        date: String,
        content: PieceContent,
        origin: PieceVersionOrigin,
        approved: Bool = false,
        linkedDailyCardID: UUID? = nil,
        basedOnPieceID: UUID? = nil,
        topic: String? = nil,
        now: Date
    ) -> ContentPiece {
        let version = PieceVersion(
            number: 1,
            content: content,
            origin: origin,
            createdAt: now,
            reviewedAt: approved ? now : nil,
            approvedAt: approved ? now : nil
        )
        let piece = ContentPiece(
            date: date,
            sortOrder: nextSortOrder(on: date),
            createdAt: now,
            firstVersion: version,
            linkedDailyCardID: linkedDailyCardID,
            basedOnPieceID: basedOnPieceID,
            topic: topic
        )
        pieces.append(piece)
        return piece
    }

    mutating func saveDraft(_ id: UUID, content: PieceContent, now: Date) throws {
        let index = try index(of: id)
        var piece = pieces[index]
        if let draftID = piece.draftVersionID,
           let versionIndex = piece.versions.firstIndex(where: { $0.id == draftID }) {
            guard piece.versions[versionIndex].content != content else { return }
            piece.versions[versionIndex].content = content
            piece.versions[versionIndex].updatedAt = now
            piece.versions[versionIndex].reviewedAt = nil
            if let approved = piece.approvedVersion {
                piece.versions[versionIndex].changeSummary = content.changes(from: approved.content)
            }
        } else {
            let base = piece.currentVersion.content
            guard base != content else { return }
            let version = PieceVersion(
                number: piece.nextVersionNumber,
                content: content,
                origin: .edit,
                createdAt: now,
                changeSummary: content.changes(from: base)
            )
            piece.versions.append(version)
            piece.draftVersionID = version.id
        }
        piece.updatedAt = now
        pieces[index] = piece
    }

    mutating func markReviewed(_ id: UUID, now: Date) {
        guard let index = pieces.firstIndex(where: { $0.id == id }),
              let draftID = pieces[index].draftVersionID,
              let versionIndex = pieces[index].versions.firstIndex(where: { $0.id == draftID }),
              pieces[index].versions[versionIndex].reviewedAt == nil
        else { return }
        pieces[index].versions[versionIndex].reviewedAt = now
    }

    @discardableResult
    mutating func approve(_ ids: [UUID], now: Date) -> Int {
        var approvedCount = 0
        for id in ids {
            guard let index = pieces.firstIndex(where: { $0.id == id }),
                  let draftID = pieces[index].draftVersionID,
                  let versionIndex = pieces[index].versions.firstIndex(where: { $0.id == draftID })
            else { continue }
            var piece = pieces[index]
            let flagged = Set(piece.shotsNeedingReview.map(\.id))
            piece.versions[versionIndex].approvedAt = now
            if piece.versions[versionIndex].reviewedAt == nil {
                piece.versions[versionIndex].reviewedAt = now
            }
            piece.approvedVersionID = draftID
            piece.draftVersionID = nil
            for captureIndex in piece.captures.indices where flagged.contains(piece.captures[captureIndex].shotID) {
                piece.captures[captureIndex].needsReview = true
            }
            if piece.markedShotAt != nil && !flagged.isEmpty {
                piece.markedShotAt = nil
            }
            piece.updatedAt = now
            pieces[index] = piece
            approvedCount += 1
        }
        return approvedCount
    }

    mutating func restore(_ id: UUID, versionID: UUID, now: Date) throws {
        let index = try index(of: id)
        var piece = pieces[index]
        guard let source = piece.versions.first(where: { $0.id == versionID }) else {
            throw PieceLibraryError.missingPiece
        }
        let base = piece.currentVersion.content
        let version = PieceVersion(
            number: piece.nextVersionNumber,
            content: source.content,
            origin: .restored(fromNumber: source.number),
            createdAt: now,
            changeSummary: source.content.changes(from: base)
        )
        piece.versions.append(version)
        piece.draftVersionID = version.id
        piece.updatedAt = now
        pieces[index] = piece
    }

    mutating func move(_ id: UUID, to date: String, now: Date) throws {
        let index = try index(of: id)
        guard pieces[index].date != date else { return }
        let order = nextSortOrder(on: date)
        pieces[index].date = date
        pieces[index].sortOrder = order
        pieces[index].updatedAt = now
    }

    @discardableResult
    mutating func duplicate(_ id: UUID, to date: String, now: Date) throws -> ContentPiece {
        let source = pieces[try index(of: id)]
        var content = source.content.copyWithNewShotIdentities()
        if !content.title.hasSuffix("(new version)") {
            content.title = content.title.isBlankText ? "New version" : "\(content.title) (new version)"
        }
        return addPiece(
            date: date,
            content: content,
            origin: .edit,
            basedOnPieceID: source.id,
            topic: source.topic,
            now: now
        )
    }

    mutating func startFilming(_ id: UUID, now: Date) throws {
        let index = try index(of: id)
        if pieces[index].filmingStartedAt == nil {
            pieces[index].filmingStartedAt = now
            pieces[index].updatedAt = now
        }
    }

    mutating func setFilmingPosition(_ id: UUID, shotID: UUID) {
        guard let index = pieces.firstIndex(where: { $0.id == id }) else { return }
        pieces[index].lastFilmingShotID = shotID
    }

    mutating func markCaptured(_ id: UUID, shotID: UUID, clip: PieceMedia? = nil, now: Date) throws {
        let index = try index(of: id)
        var piece = pieces[index]
        let versionNumber = (piece.approvedVersion ?? piece.currentVersion).number
        if let captureIndex = piece.captures.firstIndex(where: { $0.shotID == shotID }) {
            piece.captures[captureIndex].capturedAt = now
            piece.captures[captureIndex].versionNumber = versionNumber
            piece.captures[captureIndex].needsReview = false
            if let clip { piece.captures[captureIndex].clip = clip }
        } else {
            piece.captures.append(
                ShotCapture(shotID: shotID, capturedAt: now, versionNumber: versionNumber, clip: clip, needsReview: false)
            )
        }
        if piece.filmingStartedAt == nil { piece.filmingStartedAt = now }
        piece.lastFilmingShotID = shotID
        piece.updatedAt = now
        pieces[index] = piece
    }

    mutating func unmarkCaptured(_ id: UUID, shotID: UUID, now: Date) throws {
        let index = try index(of: id)
        guard let captureIndex = pieces[index].captures.firstIndex(where: { $0.shotID == shotID }) else { return }
        if pieces[index].captures[captureIndex].clip == nil {
            pieces[index].captures.remove(at: captureIndex)
        } else {
            pieces[index].captures[captureIndex].needsReview = true
        }
        pieces[index].markedShotAt = nil
        pieces[index].updatedAt = now
    }

    mutating func markShot(_ id: UUID, now: Date) throws {
        let index = try index(of: id)
        let piece = pieces[index]
        if piece.content.format.usesFilming && !piece.filmingShots.isEmpty {
            guard piece.allFilmingShotsCaptured else { throw PieceLibraryError.shotsIncomplete }
        }
        for captureIndex in pieces[index].captures.indices {
            pieces[index].captures[captureIndex].needsReview = false
        }
        pieces[index].markedShotAt = now
        pieces[index].updatedAt = now
    }

    mutating func undoShot(_ id: UUID, now: Date) throws {
        let index = try index(of: id)
        pieces[index].markedShotAt = nil
        pieces[index].updatedAt = now
    }

    mutating func setFinalMedia(_ id: UUID, media: PieceMedia?, now: Date) throws {
        let index = try index(of: id)
        pieces[index].finalMedia = media
        pieces[index].updatedAt = now
    }

    mutating func setTargets(_ id: UUID, targets: [PiecePlatform], now: Date) throws {
        let index = try index(of: id)
        pieces[index].targets = PiecePlatform.allCases.filter { targets.contains($0) }
        pieces[index].updatedAt = now
    }

    mutating func recordPosting(
        _ id: UUID,
        platform: PiecePlatform,
        state: PostingState,
        link: String?,
        now: Date
    ) throws {
        let index = try index(of: id)
        var piece = pieces[index]
        let versionNumber = (piece.approvedVersion ?? piece.currentVersion).number
        piece.postings.append(
            PostingRecord(
                platform: platform,
                state: state,
                versionNumber: versionNumber,
                finalMediaID: piece.finalMedia?.id,
                recordedAt: now,
                link: link?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankText
            )
        )
        if !piece.targets.contains(platform) {
            piece.targets = PiecePlatform.allCases.filter { piece.targets.contains($0) || $0 == platform }
        }
        piece.updatedAt = now
        pieces[index] = piece
    }

    mutating func recordUnspecifiedPostedMark(_ id: UUID, now: Date) throws {
        let index = try index(of: id)
        guard !pieces[index].hasPostedOutcome else { return }
        let versionNumber = (pieces[index].approvedVersion ?? pieces[index].currentVersion).number
        pieces[index].postings.append(
            PostingRecord(platform: nil, state: .markedByYou, versionNumber: versionNumber, recordedAt: now)
        )
        pieces[index].updatedAt = now
    }

    mutating func replaceUntouchedContent(_ id: UUID, with content: PieceContent, linkedDailyCardID: UUID, approved: Bool, now: Date) throws {
        let index = try index(of: id)
        var piece = pieces[index]
        let version = PieceVersion(
            number: 1,
            content: content,
            origin: .imported,
            createdAt: now,
            reviewedAt: approved ? now : nil,
            approvedAt: approved ? now : nil
        )
        piece.versions = [version]
        piece.approvedVersionID = approved ? version.id : nil
        piece.draftVersionID = approved ? nil : version.id
        piece.linkedDailyCardID = linkedDailyCardID
        piece.updatedAt = now
        pieces[index] = piece
    }

    mutating func removeManualPostedMark(_ id: UUID, platform: PiecePlatform?, now: Date) throws {
        let index = try index(of: id)
        guard let latest = pieces[index].postings.last(where: { $0.platform == platform }),
              latest.state == .markedByYou
        else { return }
        pieces[index].postings.append(
            PostingRecord(
                platform: platform,
                state: .notPosted,
                versionNumber: latest.versionNumber,
                finalMediaID: latest.finalMediaID,
                recordedAt: now
            )
        )
        pieces[index].updatedAt = now
    }
}

extension String {
    var isBlankText: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var nilIfBlankText: String? {
        isBlankText ? nil : self
    }
}
