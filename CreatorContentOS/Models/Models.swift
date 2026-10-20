import Foundation

struct DailyCard: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var context: String
    var effortLabel: String
    var whyToday: String
    var hook: String?
    var sourceNote: String?
    var scheduledDate: String?
    /// Optional so caches written before execution metadata remain readable.
    var format: String?
    var primarySurface: String?
    var durationSeconds: Int?
    var scenes: [ShotScene]
    var shotTimeline: [ProductionTimelineItem]?
    var voiceoverTimeline: [ProductionTimelineItem]?
    var onScreenTextTimeline: [ProductionTimelineItem]?
    var completionState: CompletionState?
    var script: String?
    var noVoiceoverVersion: String?
    var onScreenText: [String]?
    var caption: String?
    var cta: String?
    var hashtags: [String]?
    var coverText: String?
    var postInstructions: String?
    var brandEventNotes: String?
    var backupStory: String?
    var backupCaptionOnly: String?
    var audioOptionNotes: String?
    var creatorFitScore: Double?
    var riskNotes: [String]?
    var assumptions: [String]?
    /// Storyboard frame thumbnails keyed by scene/script row. Optional for older Today cache payloads.
    var storyboardThumbnailAssets: [StoryboardThumbnailAsset]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case context
        case effortLabel
        case whyToday
        case hook
        case sourceNote
        case scheduledDate
        case format
        case primarySurface
        case durationSeconds
        case scenes
        case shotTimeline
        case voiceoverTimeline
        case onScreenTextTimeline
        case completionState
        case script
        case noVoiceoverVersion
        case onScreenText
        case caption
        case cta
        case hashtags
        case coverText
        case postInstructions
        case brandEventNotes
        case backupStory
        case backupCaptionOnly
        case audioOptionNotes
        case creatorFitScore
        case riskNotes
        case assumptions
        case storyboardThumbnailAssets
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        context = try values.decodeIfPresent(String.self, forKey: .context) ?? ""
        effortLabel = try values.decodeIfPresent(String.self, forKey: .effortLabel) ?? ""
        whyToday = try values.decodeIfPresent(String.self, forKey: .whyToday) ?? ""
        hook = try values.decodeIfPresent(String.self, forKey: .hook)
        sourceNote = try values.decodeIfPresent(String.self, forKey: .sourceNote)
        scheduledDate = try values.decodeIfPresent(String.self, forKey: .scheduledDate)
        format = try values.decodeIfPresent(String.self, forKey: .format)
        primarySurface = try values.decodeIfPresent(String.self, forKey: .primarySurface)
        durationSeconds = try values.decodeIfPresent(Int.self, forKey: .durationSeconds)
        scenes = try values.decodeIfPresent([ShotScene].self, forKey: .scenes) ?? []
        shotTimeline = try values.decodeIfPresent([ProductionTimelineItem].self, forKey: .shotTimeline)
        voiceoverTimeline = try values.decodeIfPresent([ProductionTimelineItem].self, forKey: .voiceoverTimeline)
        onScreenTextTimeline = try values.decodeIfPresent([ProductionTimelineItem].self, forKey: .onScreenTextTimeline)
        completionState = try values.decodeIfPresent(CompletionState.self, forKey: .completionState)
        script = try values.decodeIfPresent(String.self, forKey: .script)
        noVoiceoverVersion = try values.decodeIfPresent(String.self, forKey: .noVoiceoverVersion)
        onScreenText = try values.decodeIfPresent([String].self, forKey: .onScreenText)
        caption = try values.decodeIfPresent(String.self, forKey: .caption)
        cta = try values.decodeIfPresent(String.self, forKey: .cta)
        hashtags = try values.decodeIfPresent([String].self, forKey: .hashtags)
        coverText = try values.decodeIfPresent(String.self, forKey: .coverText)
        postInstructions = try values.decodeIfPresent(String.self, forKey: .postInstructions)
        brandEventNotes = try values.decodeIfPresent(String.self, forKey: .brandEventNotes)
        backupStory = try values.decodeIfPresent(String.self, forKey: .backupStory)
        backupCaptionOnly = try values.decodeIfPresent(String.self, forKey: .backupCaptionOnly)
        audioOptionNotes = try values.decodeIfPresent(String.self, forKey: .audioOptionNotes)
        creatorFitScore = try values.decodeIfPresent(Double.self, forKey: .creatorFitScore)
        riskNotes = try values.decodeIfPresent([String].self, forKey: .riskNotes)
        assumptions = try values.decodeIfPresent([String].self, forKey: .assumptions)
        storyboardThumbnailAssets = try values.decodeIfPresent([StoryboardThumbnailAsset].self, forKey: .storyboardThumbnailAssets)
    }

    init(
        id: UUID = UUID(),
        title: String,
        context: String,
        effortLabel: String,
        whyToday: String,
        hook: String? = nil,
        sourceNote: String? = nil,
        scheduledDate: String? = nil,
        format: String? = nil,
        primarySurface: String? = nil,
        durationSeconds: Int? = nil,
        scenes: [ShotScene],
        shotTimeline: [ProductionTimelineItem]? = nil,
        voiceoverTimeline: [ProductionTimelineItem]? = nil,
        onScreenTextTimeline: [ProductionTimelineItem]? = nil,
        completionState: CompletionState? = nil,
        script: String? = nil,
        noVoiceoverVersion: String? = nil,
        onScreenText: [String]? = nil,
        caption: String? = nil,
        cta: String? = nil,
        hashtags: [String]? = nil,
        coverText: String? = nil,
        postInstructions: String? = nil,
        brandEventNotes: String? = nil,
        backupStory: String? = nil,
        backupCaptionOnly: String? = nil,
        audioOptionNotes: String? = nil,
        creatorFitScore: Double? = nil,
        riskNotes: [String]? = nil,
        assumptions: [String]? = nil,
        storyboardThumbnailAssets: [StoryboardThumbnailAsset]? = nil
    ) {
        self.id = id
        self.title = title
        self.context = context
        self.effortLabel = effortLabel
        self.whyToday = whyToday
        self.hook = hook
        self.sourceNote = sourceNote
        self.scheduledDate = scheduledDate
        self.format = format
        self.primarySurface = primarySurface
        self.durationSeconds = durationSeconds
        self.scenes = scenes
        self.shotTimeline = shotTimeline
        self.voiceoverTimeline = voiceoverTimeline
        self.onScreenTextTimeline = onScreenTextTimeline
        self.completionState = completionState
        self.script = script
        self.noVoiceoverVersion = noVoiceoverVersion
        self.onScreenText = onScreenText
        self.caption = caption
        self.cta = cta
        self.hashtags = hashtags
        self.coverText = coverText
        self.postInstructions = postInstructions
        self.brandEventNotes = brandEventNotes
        self.backupStory = backupStory
        self.backupCaptionOnly = backupCaptionOnly
        self.audioOptionNotes = audioOptionNotes
        self.creatorFitScore = creatorFitScore
        self.riskNotes = riskNotes
        self.assumptions = assumptions
        self.storyboardThumbnailAssets = storyboardThumbnailAssets
    }
}

extension DailyCard {
    /// A photo or caption post has no filming work to complete.
    var isNonFilmingPost: Bool {
        format?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "post" && scenes.isEmpty
    }

    /// The hook shown on the Today card. Prefers the generated `hook`. When missing,
    /// derives a fallback from the richest available copy.
    var effectiveHook: String? {
        if let hook { return hook }
        return caption?.nilIfBlank
            ?? script?.nilIfBlank
            ?? title.nilIfBlank
    }
}

struct ShotScene: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let number: Int
    var title: String
    var duration: String
    let symbol: String

    static func stableID(revisionID: UUID, number: Int) -> UUID {
        UUID(uuidString: String(revisionID.uuidString.prefix(24)) + String(format: "%012x", number))!
    }

    init(
        id: UUID = UUID(),
        number: Int,
        title: String,
        duration: String,
        symbol: String
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.duration = duration
        self.symbol = symbol
    }
}

struct ProductionTimelineItem: Identifiable, Codable, Hashable, Sendable {
    var timestamp: String
    var title: String
    var detail: String
    var shot: String?
    var videoPortion: String?
    var voiceover: String?
    var onScreenText: String?
    var placement: String?
    var durationSeconds: Int?

    var id: String {
        [
            timestamp.nilIfBlank,
            title.nilIfBlank,
            detail.nilIfBlank,
            videoPortion?.nilIfBlank,
            voiceover?.nilIfBlank,
            onScreenText?.nilIfBlank,
            placement?.nilIfBlank
        ]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case time
        case title
        case text
        case detail
        case body
        case shot
        case videoPortion = "video_portion"
        case voiceover
        case onScreenText = "on_screen_text"
        case placement
        case durationSeconds = "duration_seconds"
    }

    init(
        timestamp: String,
        title: String,
        detail: String,
        shot: String? = nil,
        videoPortion: String? = nil,
        voiceover: String? = nil,
        onScreenText: String? = nil,
        placement: String? = nil,
        durationSeconds: Int? = nil
    ) {
        self.timestamp = timestamp
        self.title = title
        self.detail = detail
        self.shot = shot
        self.videoPortion = videoPortion
        self.voiceover = voiceover
        self.onScreenText = onScreenText
        self.placement = placement
        self.durationSeconds = durationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title)
        let decodedText = try container.decodeIfPresent(String.self, forKey: .text)
        let decodedVideoPortion = try container.decodeIfPresent(String.self, forKey: .videoPortion)
        let decodedPlacement = try container.decodeIfPresent(String.self, forKey: .placement)
        let decodedShot = try container.decodeIfPresent(String.self, forKey: .shot)
        let decodedVoiceover = try container.decodeIfPresent(String.self, forKey: .voiceover)
        let decodedOnScreenText = try container.decodeIfPresent(String.self, forKey: .onScreenText)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
            ?? container.decodeIfPresent(String.self, forKey: .time)
            ?? ""
        title = decodedTitle ?? decodedVideoPortion ?? decodedText ?? decodedPlacement ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
            ?? container.decodeIfPresent(String.self, forKey: .body)
            ?? decodedVoiceover
            ?? decodedOnScreenText
            ?? decodedShot
            ?? decodedPlacement
            ?? (decodedTitle == nil ? "" : decodedText ?? "")
        shot = decodedShot
        videoPortion = decodedVideoPortion
        voiceover = decodedVoiceover
        onScreenText = decodedOnScreenText ?? decodedText
        placement = decodedPlacement
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encodeIfPresent(shot, forKey: .shot)
        try container.encodeIfPresent(videoPortion, forKey: .videoPortion)
        try container.encodeIfPresent(voiceover, forKey: .voiceover)
        try container.encodeIfPresent(onScreenText, forKey: .onScreenText)
        try container.encodeIfPresent(placement, forKey: .placement)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
    }
}

struct StoryboardThumbnailAsset: Identifiable, Codable, Hashable, Sendable {
    var rowIndex: Int
    var promptHash: String
    var storagePath: String?
    var publicURL: String?
    var model: String?
    var promptVersion: String?
    var status: String?
    var generatedAt: String?

    var id: Int { rowIndex }

    enum CodingKeys: String, CodingKey {
        case rowIndex = "row_index"
        case promptHash = "prompt_hash"
        case storagePath = "storage_path"
        case publicURL = "public_url"
        case model
        case promptVersion = "prompt_version"
        case status
        case generatedAt = "generated_at"
    }

    init(
        rowIndex: Int,
        promptHash: String,
        storagePath: String? = nil,
        publicURL: String? = nil,
        model: String? = nil,
        promptVersion: String? = nil,
        status: String? = nil,
        generatedAt: String? = nil
    ) {
        self.rowIndex = rowIndex
        self.promptHash = promptHash
        self.storagePath = storagePath
        self.publicURL = publicURL
        self.model = model
        self.promptVersion = promptVersion
        self.status = status
        self.generatedAt = generatedAt
    }
}

struct ProductionPlanDetail: Codable, Hashable, Sendable {
    var title: String?
    var detail: String
    var instructions: [String]
    var onScreenText: [String]
    var caption: String?

    enum CodingKeys: String, CodingKey {
        case title
        case detail
        case body
        case text
        case summary
        case line
        case instructions
        case onScreenText = "on_screen_text"
        case caption
    }

    init(
        title: String? = nil,
        detail: String,
        instructions: [String] = [],
        onScreenText: [String] = [],
        caption: String? = nil
    ) {
        self.title = title
        self.detail = detail
        self.instructions = instructions
        self.onScreenText = onScreenText
        self.caption = caption
    }

    init(from decoder: Decoder) throws {
        let singleValue = try decoder.singleValueContainer()
        if let value = try? singleValue.decode(String.self) {
            title = nil
            detail = value
            instructions = []
            onScreenText = []
            caption = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
            ?? container.decodeIfPresent(String.self, forKey: .body)
            ?? container.decodeIfPresent(String.self, forKey: .text)
            ?? container.decodeIfPresent(String.self, forKey: .summary)
            ?? container.decodeIfPresent(String.self, forKey: .line)
            ?? ""
        instructions = (try? container.decode([String].self, forKey: .instructions))
            ?? container.decodeOptionalStringArray(forKey: .instructions)
        onScreenText = try container.decodeIfPresent([String].self, forKey: .onScreenText) ?? []
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(detail, forKey: .detail)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(onScreenText, forKey: .onScreenText)
        try container.encodeIfPresent(caption, forKey: .caption)
    }
}

private extension KeyedDecodingContainer {
    func decodeOptionalStringArray(forKey key: Key) -> [String] {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return [value]
        }
        return []
    }
}

enum CompletionState: String, CaseIterable, Codable, Hashable, Sendable {
    case shot
    case posted
    case usedBackup
    case savedForTomorrow
    case skippedIntentionally

    var archiveLabel: String {
        switch self {
        case .shot:
            "Shot"
        case .posted:
            "Posted"
        case .usedBackup:
            "Used backup"
        case .savedForTomorrow:
            "Saved for tomorrow"
        case .skippedIntentionally:
            "Skipped after decision"
        }
    }
}

struct DailyDecision: Codable, Hashable, Sendable {
    var completionState: CompletionState
    var outputLine: String
    var hasPostThumbnail: Bool

    /// Short confirmation copy for immediate creator-facing feedback.
    /// Archive output can remain more descriptive without making the toast overly long.
    var confirmationMessage: String {
        switch completionState {
        case .savedForTomorrow:
            "Saved for tomorrow"
        default:
            outputLine
        }
    }

    init(
        completionState: CompletionState,
        outputLine: String? = nil,
        hasPostThumbnail: Bool? = nil
    ) {
        self.completionState = completionState
        self.outputLine = outputLine ?? completionState.archiveLabel
        self.hasPostThumbnail = hasPostThumbnail ?? (completionState == .shot || completionState == .posted)
    }

    static let shot = DailyDecision(
        completionState: .shot,
        outputLine: "Shot today, ready to post",
        hasPostThumbnail: true
    )

    static let posted = DailyDecision(
        completionState: .posted,
        outputLine: "Posted",
        hasPostThumbnail: true
    )

    static let backupStory = DailyDecision(
        completionState: .usedBackup,
        outputLine: "Used backup: 10-second story",
        hasPostThumbnail: false
    )

    static let captionOnly = DailyDecision(
        completionState: .usedBackup,
        outputLine: "Used backup: caption-only post",
        hasPostThumbnail: false
    )

    static let savedForTomorrow = DailyDecision(
        completionState: .savedForTomorrow,
        outputLine: "Saved this card for tomorrow",
        hasPostThumbnail: false
    )

    static let skippedIntentionally = DailyDecision(
        completionState: .skippedIntentionally,
        outputLine: "Skipped after decision",
        hasPostThumbnail: false
    )
}

struct ArchiveEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let dailyCardID: UUID?
    let day: String
    let date: String
    let cardTitle: String
    var decision: CompletionState
    let outputLine: String
    let hasPostThumbnail: Bool
    var captionSnapshot: String? = nil
    var scheduledDate: String? = nil
    var decisionAt: String? = nil

    init(
        id: UUID = UUID(),
        dailyCardID: UUID? = nil,
        day: String,
        date: String,
        cardTitle: String,
        decision: CompletionState,
        outputLine: String,
        hasPostThumbnail: Bool
    ) {
        self.id = id
        self.dailyCardID = dailyCardID
        self.day = day
        self.date = date
        self.cardTitle = cardTitle
        self.decision = decision
        self.outputLine = outputLine
        self.hasPostThumbnail = hasPostThumbnail
    }
}

enum PackageSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case scenes = "Scenes"
    case script = "Script"
    case caption = "Caption"
    case audio = "Audio"

    var id: String { rawValue }
}

enum CreatorTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case today = "Today"
    case plan = "Plan"
    case you = "You"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .today: "sun.min"
        case .plan: "calendar"
        case .you: "person.circle"
        }
    }

    var isCenterTab: Bool { self == .plan }
}

enum YouRoute: Hashable, Sendable {
    case contentCategories
    case productionPreferences
    case currentContext
    case creatorVoice
    case references
    case account
    case archive
}

enum CreatorRoute: Hashable, Sendable {
    /// Opens Shoot Folio; `editing` starts scene/script light-edit mode.
    case shootFolio(editing: Bool = false)
    /// Opens the one-shot Today execution flow.
    case todayShootSession
    /// Opens Plan; optional `selectedDate` (`yyyy-MM-dd`) preselects that day.
    case plan(selectedDate: String?)
}

enum TodaySheet: Identifiable, Hashable, Sendable {
    case notToday

    var id: String { "not-today" }
}

struct WeeklyPlan: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var eyebrow: String
    var weekRange: String
    var weekStartDate: String?
    var weekEndDate: String?
    var readinessLine: String
    var isSoftLocked: Bool
    var days: [WeeklyDay]
    var weeklyBriefText: String
    var setupSections: [WeeklySetupSection]

    init(
        id: UUID = UUID(),
        title: String,
        eyebrow: String,
        weekRange: String,
        weekStartDate: String? = nil,
        weekEndDate: String? = nil,
        readinessLine: String,
        isSoftLocked: Bool,
        days: [WeeklyDay],
        weeklyBriefText: String = "",
        setupSections: [WeeklySetupSection]
    ) {
        self.id = id
        self.title = title
        self.eyebrow = eyebrow
        self.weekRange = weekRange
        self.weekStartDate = weekStartDate
        self.weekEndDate = weekEndDate
        self.readinessLine = readinessLine
        self.isSoftLocked = isSoftLocked
        self.days = days
        self.weeklyBriefText = weeklyBriefText
        self.setupSections = setupSections
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case eyebrow
        case weekRange
        case weekStartDate
        case weekEndDate
        case readinessLine
        case isSoftLocked
        case days
        case weeklyBriefText
        case setupSections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        eyebrow = try container.decode(String.self, forKey: .eyebrow)
        weekRange = try container.decode(String.self, forKey: .weekRange)
        weekStartDate = try container.decodeIfPresent(String.self, forKey: .weekStartDate)
        weekEndDate = try container.decodeIfPresent(String.self, forKey: .weekEndDate)
        readinessLine = try container.decode(String.self, forKey: .readinessLine)
        isSoftLocked = try container.decode(Bool.self, forKey: .isSoftLocked)
        days = try container.decode([WeeklyDay].self, forKey: .days)
        weeklyBriefText = try container.decodeIfPresent(String.self, forKey: .weeklyBriefText) ?? ""
        setupSections = try container.decode([WeeklySetupSection].self, forKey: .setupSections)
    }
}

extension WeeklyPlan {
    var plannedDayCount: Int {
        days.filter { $0.state == .planned }.count
    }

    var backupDayCount: Int {
        days.filter { $0.state == .backup }.count
    }

    var openDayCount: Int {
        days.filter { $0.state == .open }.count
    }

    var computedReadinessLine: String {
        "\(plannedDayCount) ready, \(backupDayCount) backup, \(openDayCount) open"
    }
}

struct WeeklyDay: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var weekday: String
    var date: String
    var scheduledDate: String?
    var title: String
    var reason: String
    var source: WeeklySourceReason
    var state: WeeklyDayState
    var isSoftLocked: Bool

    init(
        id: UUID = UUID(),
        weekday: String,
        date: String,
        scheduledDate: String? = nil,
        title: String,
        reason: String,
        source: WeeklySourceReason,
        state: WeeklyDayState,
        isSoftLocked: Bool
    ) {
        self.id = id
        self.weekday = weekday
        self.date = date
        self.scheduledDate = scheduledDate
        self.title = title
        self.reason = reason
        self.source = source
        self.state = state
        self.isSoftLocked = isSoftLocked
    }
}

extension WeeklyDay {
    var detailHeaderDateText: String {
        guard let scheduledDate,
              let date = Self.parseAPIDate(scheduledDate)
        else {
            return [weekday.capitalized, date.nilIfBlank]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        return Self.formatDetailHeaderDate(date)
    }

    private static func parseAPIDate(_ scheduledDate: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: scheduledDate)
    }

    private static func formatDetailHeaderDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, dd MMMM yyyy"
        return formatter.string(from: date)
    }
}

enum WeeklyDayState: String, CaseIterable, Codable, Hashable, Sendable {
    case planned
    case backup
    case open

    var label: String {
        switch self {
        case .planned:
            "Ready"
        case .backup:
            "Backup"
        case .open:
            "Open"
        }
    }

    var sourceTone: ChipTone {
        switch self {
        case .planned: .ready
        case .backup: .warning
        case .open: .quiet
        }
    }
}

extension WeeklyDayState {
    init(generatedDraftStatus status: String) {
        switch status.lowercased() {
        case "published", "planned", "ready":
            self = .planned
        case "backup":
            self = .backup
        default:
            self = .open
        }
    }

    var generatedDraftStatus: String {
        switch self {
        case .planned:
            "ready"
        case .backup:
            "backup"
        case .open:
            "open"
        }
    }

}

enum WeeklySourceReason: String, CaseIterable, Codable, Hashable, Sendable {
    case routine = "Routine"
    case pattern = "Pattern"
    case trend = "Trend"
    case brand = "Brand"
    case moment = "Moment"
    case audio = "Audio"
    case open = "Open"
}

struct WeeklySetupSection: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var systemImage: String
    var title: String
    var summary: String
    var state: String

    init(
        id: UUID = UUID(),
        systemImage: String,
        title: String,
        summary: String,
        state: String
    ) {
        self.id = id
        self.systemImage = systemImage
        self.title = title
        self.summary = summary
        self.state = state
    }
}

struct WeeklyIdea: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var reason: String
    var source: WeeklySourceReason
    var effortLabel: String
    var selectedDay: String?

    init(
        id: UUID = UUID(),
        title: String,
        reason: String,
        source: WeeklySourceReason,
        effortLabel: String,
        selectedDay: String? = nil
    ) {
        self.id = id
        self.title = title
        self.reason = reason
        self.source = source
        self.effortLabel = effortLabel
        self.selectedDay = selectedDay
    }
}

struct GeneratedWeekDraft: Identifiable, Hashable, Sendable {
    let id: UUID
    var weeklyPlanID: UUID
    var status: String
    var strategySummary: String
    var warnings: [String]
    var assumptions: [String]
    var dailyCards: [GeneratedDailyCardDraft]
    var ideaBank: [WeeklyIdea]
    var sourceSummary: String
    var generatedAt: String

    init(
        id: UUID,
        weeklyPlanID: UUID,
        status: String = "draft",
        strategySummary: String,
        warnings: [String],
        assumptions: [String],
        dailyCards: [GeneratedDailyCardDraft],
        ideaBank: [WeeklyIdea],
        sourceSummary: String,
        generatedAt: String
    ) {
        self.id = id
        self.weeklyPlanID = weeklyPlanID
        self.status = status
        self.strategySummary = strategySummary
        self.warnings = warnings
        self.assumptions = assumptions
        self.dailyCards = dailyCards
        self.ideaBank = ideaBank
        self.sourceSummary = sourceSummary
        self.generatedAt = generatedAt
    }
}

extension GeneratedWeekDraft {
    var isCompleteWeekDraft: Bool {
        let scheduledDates = Set(dailyCards.map(\.scheduledDate))
        return dailyCards.count == 7 && scheduledDates.count == 7
    }

    func weeklyPlan(
        setupSections: [WeeklySetupSection],
        weeklyBriefText: String = ""
    ) -> WeeklyPlan {
        let generatedDays = dailyCards.map(\.weeklyDay)

        return WeeklyPlan(
            id: weeklyPlanID,
            title: "Generate a Week",
            eyebrow: "MANAGER AI REVIEW",
            weekRange: dailyCards.first.map { SupabaseDateFormatting.weekRange(starting: $0.scheduledDate) } ?? "Generated week",
            weekStartDate: dailyCards.first?.scheduledDate,
            weekEndDate: dailyCards.last?.scheduledDate,
            readinessLine: "\(generatedDays.filter { $0.state == .open }.count) open, confirm before publishing",
            isSoftLocked: status == "published",
            days: generatedDays,
            weeklyBriefText: weeklyBriefText,
            setupSections: setupSections
        )
    }

    var publishedWeekCards: [DailyCard] {
        dailyCards.map { $0.dailyCard(completionState: nil) }
    }

    var markedPublished: GeneratedWeekDraft {
        var draft = self
        draft.status = "published"
        draft.dailyCards = draft.dailyCards.map { card in
            var publishedCard = card
            publishedCard.status = "published"
            return publishedCard
        }
        return draft
    }
}

struct GeneratedDailyCardDraft: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var scheduledDate: String
    var status: String
    var title: String
    var whyToday: String
    var growthJob: String
    var contentPillar: String
    var shootability: String
    var estimatedShootMinutes: Int
    var energyRequired: String
    var languageMode: String
    var format: String?
    var primarySurface: String?
    var durationSeconds: Int?
    var hook: String?
    var saveShareReason: String?
    var sceneList: [ShotScene]
    var shotTimeline: [ProductionTimelineItem]
    var voiceoverTimeline: [ProductionTimelineItem]
    var onScreenTextTimeline: [ProductionTimelineItem]
    var silentVersionTimeline: [ProductionTimelineItem]
    var script: String
    var noVoiceoverVersion: String
    var onScreenText: [String]
    var caption: String
    var cta: String
    var hashtags: [String]
    var coverText: String
    var postInstructions: String
    var brandEventNotes: String
    var backupStory: String
    var backupCaptionOnly: String
    var backupStoryDetail: [ProductionTimelineItem]
    var captionBackupDetail: String?
    var audioOptionNotes: String
    var creatorFitScore: Double
    var riskNotes: [String]
    var assumptions: [String]
    var sourceNote: String
    var storyboardThumbnailAssets: [StoryboardThumbnailAsset]

    enum CodingKeys: String, CodingKey {
        case id
        case scheduledDate
        case status
        case title
        case whyToday
        case growthJob
        case contentPillar
        case shootability
        case estimatedShootMinutes
        case energyRequired
        case languageMode
        case format
        case primarySurface
        case durationSeconds
        case hook
        case saveShareReason
        case sceneList
        case shotTimeline
        case voiceoverTimeline
        case onScreenTextTimeline
        case silentVersionTimeline
        case script
        case noVoiceoverVersion
        case onScreenText
        case caption
        case cta
        case hashtags
        case coverText
        case postInstructions
        case brandEventNotes
        case backupStory
        case backupCaptionOnly
        case backupStoryDetail
        case captionBackupDetail
        case audioOptionNotes
        case creatorFitScore
        case riskNotes
        case assumptions
        case sourceNote
        case storyboardThumbnailAssets
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        scheduledDate = try values.decode(String.self, forKey: .scheduledDate)
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? ""
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        whyToday = try values.decodeIfPresent(String.self, forKey: .whyToday) ?? ""
        growthJob = try values.decodeIfPresent(String.self, forKey: .growthJob) ?? ""
        contentPillar = try values.decodeIfPresent(String.self, forKey: .contentPillar) ?? ""
        shootability = try values.decodeIfPresent(String.self, forKey: .shootability) ?? ""
        estimatedShootMinutes = try values.decodeIfPresent(Int.self, forKey: .estimatedShootMinutes) ?? 0
        energyRequired = try values.decodeIfPresent(String.self, forKey: .energyRequired) ?? ""
        languageMode = try values.decodeIfPresent(String.self, forKey: .languageMode) ?? ""
        format = try values.decodeIfPresent(String.self, forKey: .format)
        primarySurface = try values.decodeIfPresent(String.self, forKey: .primarySurface)
        durationSeconds = try values.decodeIfPresent(Int.self, forKey: .durationSeconds)
        hook = try values.decodeIfPresent(String.self, forKey: .hook)
        saveShareReason = try values.decodeIfPresent(String.self, forKey: .saveShareReason)
        sceneList = try values.decodeIfPresent([ShotScene].self, forKey: .sceneList) ?? []
        shotTimeline = try values.decodeIfPresent([ProductionTimelineItem].self, forKey: .shotTimeline) ?? []
        voiceoverTimeline = try values.decodeIfPresent([ProductionTimelineItem].self, forKey: .voiceoverTimeline) ?? []
        onScreenTextTimeline = try values.decodeIfPresent([ProductionTimelineItem].self, forKey: .onScreenTextTimeline) ?? []
        silentVersionTimeline = try values.decodeIfPresent([ProductionTimelineItem].self, forKey: .silentVersionTimeline) ?? []
        script = try values.decodeIfPresent(String.self, forKey: .script) ?? ""
        noVoiceoverVersion = try values.decodeIfPresent(String.self, forKey: .noVoiceoverVersion) ?? ""
        onScreenText = try values.decodeIfPresent([String].self, forKey: .onScreenText) ?? []
        caption = try values.decodeIfPresent(String.self, forKey: .caption) ?? ""
        cta = try values.decodeIfPresent(String.self, forKey: .cta) ?? ""
        hashtags = try values.decodeIfPresent([String].self, forKey: .hashtags) ?? []
        coverText = try values.decodeIfPresent(String.self, forKey: .coverText) ?? ""
        postInstructions = try values.decodeIfPresent(String.self, forKey: .postInstructions) ?? ""
        brandEventNotes = try values.decodeIfPresent(String.self, forKey: .brandEventNotes) ?? ""
        backupStory = try values.decodeIfPresent(String.self, forKey: .backupStory) ?? ""
        backupCaptionOnly = try values.decodeIfPresent(String.self, forKey: .backupCaptionOnly) ?? ""
        backupStoryDetail = try values.decodeIfPresent([ProductionTimelineItem].self, forKey: .backupStoryDetail) ?? []
        captionBackupDetail = try values.decodeIfPresent(String.self, forKey: .captionBackupDetail)
        audioOptionNotes = try values.decodeIfPresent(String.self, forKey: .audioOptionNotes) ?? ""
        creatorFitScore = try values.decodeIfPresent(Double.self, forKey: .creatorFitScore) ?? 0
        riskNotes = try values.decodeIfPresent([String].self, forKey: .riskNotes) ?? []
        assumptions = try values.decodeIfPresent([String].self, forKey: .assumptions) ?? []
        sourceNote = try values.decodeIfPresent(String.self, forKey: .sourceNote) ?? ""
        storyboardThumbnailAssets = try values.decodeIfPresent([StoryboardThumbnailAsset].self, forKey: .storyboardThumbnailAssets) ?? []
    }

    init(
        id: UUID,
        scheduledDate: String,
        status: String,
        title: String,
        whyToday: String,
        growthJob: String,
        contentPillar: String,
        shootability: String,
        estimatedShootMinutes: Int,
        energyRequired: String,
        languageMode: String,
        format: String? = nil,
        primarySurface: String? = nil,
        durationSeconds: Int? = nil,
        hook: String? = nil,
        saveShareReason: String? = nil,
        sceneList: [ShotScene],
        shotTimeline: [ProductionTimelineItem] = [],
        voiceoverTimeline: [ProductionTimelineItem] = [],
        onScreenTextTimeline: [ProductionTimelineItem] = [],
        silentVersionTimeline: [ProductionTimelineItem] = [],
        script: String,
        noVoiceoverVersion: String,
        onScreenText: [String],
        caption: String,
        cta: String,
        hashtags: [String],
        coverText: String,
        postInstructions: String,
        brandEventNotes: String,
        backupStory: String,
        backupCaptionOnly: String,
        backupStoryDetail: [ProductionTimelineItem] = [],
        captionBackupDetail: String? = nil,
        audioOptionNotes: String,
        creatorFitScore: Double,
        riskNotes: [String],
        assumptions: [String],
        sourceNote: String,
        storyboardThumbnailAssets: [StoryboardThumbnailAsset] = []
    ) {
        self.id = id
        self.scheduledDate = scheduledDate
        self.status = status
        self.title = title
        self.whyToday = whyToday
        self.growthJob = growthJob
        self.contentPillar = contentPillar
        self.shootability = shootability
        self.estimatedShootMinutes = estimatedShootMinutes
        self.energyRequired = energyRequired
        self.languageMode = languageMode
        self.format = format
        self.primarySurface = primarySurface
        self.durationSeconds = durationSeconds
        self.hook = hook
        self.saveShareReason = saveShareReason
        self.sceneList = sceneList
        self.shotTimeline = shotTimeline
        self.voiceoverTimeline = voiceoverTimeline
        self.onScreenTextTimeline = onScreenTextTimeline
        self.silentVersionTimeline = silentVersionTimeline
        self.script = script
        self.noVoiceoverVersion = noVoiceoverVersion
        self.onScreenText = onScreenText
        self.caption = caption
        self.cta = cta
        self.hashtags = hashtags
        self.coverText = coverText
        self.postInstructions = postInstructions
        self.brandEventNotes = brandEventNotes
        self.backupStory = backupStory
        self.backupCaptionOnly = backupCaptionOnly
        self.backupStoryDetail = backupStoryDetail
        self.captionBackupDetail = captionBackupDetail
        self.audioOptionNotes = audioOptionNotes
        self.creatorFitScore = creatorFitScore
        self.riskNotes = riskNotes
        self.assumptions = assumptions
        self.sourceNote = sourceNote
        self.storyboardThumbnailAssets = storyboardThumbnailAssets
    }
}

extension GeneratedDailyCardDraft {
    var weeklyDay: WeeklyDay {
        WeeklyDay(
            id: id,
            weekday: SupabaseDateFormatting.weekdayAbbreviation(for: scheduledDate),
            date: SupabaseDateFormatting.dayNumber(for: scheduledDate),
            scheduledDate: scheduledDate,
            title: title,
            reason: whyToday,
            source: WeeklySourceReason(rawValue: contentPillar.displayTitle) ?? .pattern,
            state: WeeklyDayState(generatedDraftStatus: status),
            isSoftLocked: status == "published"
        )
    }

    func dailyCard(completionState: CompletionState?) -> DailyCard {
        DailyCard(
            id: id,
            title: title,
            context: SupabaseDateFormatting.contextLine(for: scheduledDate),
            effortLabel: SupabaseDateFormatting.effortLabel(
                shootability: shootability,
                minutes: estimatedShootMinutes
            ),
            whyToday: whyToday,
            hook: hook?.nilIfBlank,
            sourceNote: sourceNote.nilIfBlank ?? contentPillar,
            scheduledDate: scheduledDate,
            format: format,
            primarySurface: primarySurface,
            durationSeconds: durationSeconds,
            scenes: sceneList,
            shotTimeline: shotTimeline.isEmpty ? nil : shotTimeline,
            voiceoverTimeline: voiceoverTimeline.isEmpty ? nil : voiceoverTimeline,
            onScreenTextTimeline: onScreenTextTimeline.isEmpty ? nil : onScreenTextTimeline,
            completionState: completionState,
            script: script,
            noVoiceoverVersion: noVoiceoverVersion,
            onScreenText: onScreenText,
            caption: caption,
            cta: cta,
            hashtags: hashtags,
            coverText: coverText,
            postInstructions: postInstructions,
            brandEventNotes: brandEventNotes,
            backupStory: backupStory,
            backupCaptionOnly: backupCaptionOnly,
            audioOptionNotes: audioOptionNotes,
            creatorFitScore: creatorFitScore,
            riskNotes: riskNotes,
            assumptions: assumptions,
            storyboardThumbnailAssets: storyboardThumbnailAssets
        )
    }

    /// Builds a Plan-style draft model from a published Today card for inline package rendering.
    init(fromPublishedCard card: DailyCard, status: String = "published") {
        self.init(
            id: card.id,
            scheduledDate: card.scheduledDate ?? "",
            status: status,
            title: card.title,
            whyToday: card.whyToday,
            growthJob: card.whyToday,
            contentPillar: card.sourceNote ?? "lifestyle",
            shootability: "easy",
            estimatedShootMinutes: 10,
            energyRequired: "low",
            languageMode: "English",
            format: card.format,
            primarySurface: card.primarySurface,
            durationSeconds: card.durationSeconds,
            hook: card.hook,
            sceneList: card.scenes,
            shotTimeline: card.shotTimeline ?? [],
            voiceoverTimeline: card.voiceoverTimeline ?? [],
            onScreenTextTimeline: card.onScreenTextTimeline ?? [],
            script: card.script ?? "",
            noVoiceoverVersion: card.noVoiceoverVersion ?? "",
            onScreenText: card.onScreenText ?? [],
            caption: card.caption ?? "",
            cta: card.cta ?? "",
            hashtags: card.hashtags ?? [],
            coverText: card.coverText ?? "",
            postInstructions: card.postInstructions ?? "",
            brandEventNotes: card.brandEventNotes ?? "",
            backupStory: card.backupStory ?? "",
            backupCaptionOnly: card.backupCaptionOnly ?? "",
            audioOptionNotes: card.audioOptionNotes ?? "",
            creatorFitScore: card.creatorFitScore ?? 90,
            riskNotes: card.riskNotes ?? [],
            assumptions: card.assumptions ?? [],
            sourceNote: card.sourceNote ?? "",
            storyboardThumbnailAssets: card.storyboardThumbnailAssets ?? []
        )
    }
}

struct GrowthReference: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var summary: String
    var whyItWorks: String
    var hookFormulas: [String]
    var useWhen: [String]
    var sampleCreatorIdea: String
    var sourceURLs: [String]
    var tags: [String]
    var relevanceLabel: String
    var symbol: String

    static let creatorFitnessGrowthReferences: [GrowthReference] = [
        GrowthReference(
            id: "creator-age-myth-reversal",
            title: "Age Myth Reversal",
            summary: "Lead with a belief women are told after 60, then show the creator disproving it through movement.",
            whyItWorks: "The creator's strongest visible Reel uses identity and proof, not a generic workout tip. It gives viewers a reason to watch because it challenges the cultural script around age, strength, and women.",
            hookFormulas: [
                "They told women my age to slow down. I started lifting.",
                "At 62, this is what I refuse to give up.",
                "Fitness after 60 is not about looking young."
            ],
            useWhen: [
                "A training, HYROX, race, or gym moment is available.",
                "The weekly brief includes confidence, return to routine, or proof of consistency.",
                "The content needs a stronger first two seconds than a simple exercise demo."
            ],
            sampleCreatorIdea: "Open on the creator loading a weight or tying shoes, then voiceover: 'Women are told to be careful after a certain age. I agree with careful. I do not agree with stopping.'",
            sourceURLs: [
                "https://transparency.meta.com/features/explaining-ranking/ig-reels-chaining/",
                "https://about.instagram.com/blog/announcements/instagram-ranking-explained"
            ],
            tags: ["belief shift", "fitness after 60", "identity", "proof"],
            relevanceLabel: "Highest fit",
            symbol: "figure.strengthtraining.traditional"
        ),
        GrowthReference(
            id: "creator-real-life-contradiction-hook",
            title: "Real-Life Contradiction Hook",
            summary: "Start with a tension that feels honest: eating out, travel, family, missed workouts, and still staying consistent.",
            whyItWorks: "Contradiction hooks create curiosity without hype. They fit the creator because her authority comes from sustainable discipline, not perfection.",
            hookFormulas: [
                "I eat out. I drink sometimes. I still stay fit at 62.",
                "I missed the perfect routine, so I did this instead.",
                "This is how I restart after travel without guilt."
            ],
            useWhen: [
                "The week includes travel, Bombay routine, family plans, eating out, or irregular timing.",
                "The card can show a normal-life moment before the fitness takeaway.",
                "The idea should feel relatable and shareable."
            ],
            sampleCreatorIdea: "Shoot a quick restaurant/home/gym contrast: one real-life clip, one gym clip, one recovery clip. End with a practical consistency rule.",
            sourceURLs: [
                "https://about.instagram.com/blog/announcements/instagram-ranking-explained",
                "https://buffer.com/resources/instagram-algorithms/"
            ],
            tags: ["contradiction", "real life", "consistency", "retention"],
            relevanceLabel: "High fit",
            symbol: "arrow.left.arrow.right"
        ),
        GrowthReference(
            id: "creator-proof-before-advice",
            title: "Proof Before Advice",
            summary: "Show the action first, then explain the lesson. Do not open with abstract advice.",
            whyItWorks: "Reels need fast visual confirmation. A clip of the creator lifting, walking into the gym, stretching, or finishing a set gives immediate credibility before the voiceover teaches.",
            hookFormulas: [
                "One thing I learned after showing up for years...",
                "This is why you do the boring work.",
                "Before I give advice, let me show you the part nobody sees."
            ],
            useWhen: [
                "There is footage of training, recovery, HYROX prep, or a daily routine.",
                "The idea risks sounding preachy if it starts as advice.",
                "The weekly card needs stronger watch-time potential."
            ],
            sampleCreatorIdea: "Open with a 2-second set, cut to breath/reset, then voiceover explains one useful cue or mindset from that exact movement.",
            sourceURLs: [
                "https://buffer.com/resources/instagram-algorithms/",
                "https://transparency.meta.com/features/explaining-ranking/ig-reels-chaining/"
            ],
            tags: ["visual proof", "watch time", "movement first"],
            relevanceLabel: "High fit",
            symbol: "play.rectangle"
        ),
        GrowthReference(
            id: "creator-saveable-practical-cue",
            title: "Saveable Practical Cue",
            summary: "Make one Reel around one small cue followers can save for their own gym day.",
            whyItWorks: "Saves and sends are useful distribution signals, and practical fitness cues turn inspiration into utility. This keeps growth content useful without becoming generic.",
            hookFormulas: [
                "Save this before your next lower-body day.",
                "One warm-up I do before lifting.",
                "If your back feels stiff, try this first."
            ],
            useWhen: [
                "The day has gym, mobility, strength, or recovery content.",
                "The card should be more instructional than emotional.",
                "The output needs a clear CTA."
            ],
            sampleCreatorIdea: "Film one movement from two angles, add on-screen text with the cue, and close with 'save this for your next gym day.'",
            sourceURLs: [
                "https://www.theverge.com/2024/10/1/24259462/instagram-best-practices-business-profiles-tips-reach",
                "https://acsm.org/top-fitness-trends-2026/"
            ],
            tags: ["saveable", "cue", "utility", "strength"],
            relevanceLabel: "High fit",
            symbol: "bookmark"
        ),
        GrowthReference(
            id: "creator-hyrox-hybrid-proof",
            title: "HYROX / Hybrid Proof",
            summary: "Use HYROX, running, and strength as authority signals, but only when the weekly brief supports it.",
            whyItWorks: "HYROX and hybrid training are culturally current and already part of the creator's credibility. The risk is overusing old race context when the current week is about normal life.",
            hookFormulas: [
                "HYROX taught me this, but it applies to regular gym days.",
                "You do not train for events. You train for the life you want.",
                "The race is over. The routine is the real win."
            ],
            useWhen: [
                "The week includes race reflection, training proof, or hybrid conditioning.",
                "The story can bridge achievement back into everyday routine.",
                "The weekly brief does not conflict with race/HYROX context."
            ],
            sampleCreatorIdea: "Use one race/HYROX clip as the first beat, then cut to a simple Bombay gym routine to show how event confidence becomes daily discipline.",
            sourceURLs: [
                "https://www.womenshealthmag.com/fitness/a71592589/menopause-symptoms-endometriosis-strength-endurance-hyrox-transformation/",
                "https://www.nasm.org/resource-center/blog/top-fitness-trends"
            ],
            tags: ["HYROX", "hybrid", "authority", "routine"],
            relevanceLabel: "Conditional",
            symbol: "medal"
        ),
        GrowthReference(
            id: "creator-instagram-reels-default",
            title: "Instagram Reels Default",
            summary: "Default growth ideas to short, specific Reels with one idea, one hook, timestamped shots, and a save/share CTA.",
            whyItWorks: "Instagram guidance and platform analysis consistently point to retention, originality, shares, and saves. For this creator, that means clear movement, specific context, and no overproduced influencer language.",
            hookFormulas: [
                "0:00-0:02: motion plus bold text.",
                "0:03-0:08: one real context line.",
                "0:09-0:25: one useful takeaway."
            ],
            useWhen: [
                "The generator is choosing between Reel, Post, and Story.",
                "The day needs growth potential rather than only documentation.",
                "The admin needs shot, voiceover, and on-screen text details."
            ],
            sampleCreatorIdea: "Any weekly idea should specify the Reel length, first-frame visual, voiceover timing, on-screen text timing, CTA, and backup story.",
            sourceURLs: [
                "https://about.instagram.com/blog/announcements/instagram-ranking-explained",
                "https://buffer.com/resources/instagram-algorithms/",
                "https://transparency.meta.com/features/explaining-ranking/ig-reels-chaining/"
            ],
            tags: ["reels", "retention", "shares", "saves"],
            relevanceLabel: "System rule",
            symbol: "rectangle.portrait.on.rectangle.portrait"
        )
    ]
}

struct IntelligenceHome: Identifiable, Hashable, Sendable {
    let id: UUID
    var sourcePulse: SourcePulseSummary
    var growthReferences: [GrowthReference]
    var readyForThisWeek: [IntelligenceItem]
    var needsReview: [IntelligenceItem]
    var ideaCandidates: [IntelligenceItem]
    var recentlyUsed: [IntelligenceItem]
    var librarySections: [IntelligenceLibrarySection]

    init(
        id: UUID = UUID(),
        sourcePulse: SourcePulseSummary,
        growthReferences: [GrowthReference] = GrowthReference.creatorFitnessGrowthReferences,
        readyForThisWeek: [IntelligenceItem],
        needsReview: [IntelligenceItem],
        ideaCandidates: [IntelligenceItem],
        recentlyUsed: [IntelligenceItem],
        librarySections: [IntelligenceLibrarySection]
    ) {
        self.id = id
        self.sourcePulse = sourcePulse
        self.growthReferences = growthReferences
        self.readyForThisWeek = readyForThisWeek
        self.needsReview = needsReview
        self.ideaCandidates = ideaCandidates
        self.recentlyUsed = recentlyUsed
        self.librarySections = librarySections
    }
}

struct SourcePulseSummary: Hashable, Sendable {
    var title: String
    var subtitle: String
    var references: [ReferenceSummary]
}

struct ReferenceSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var sourceType: String
    var note: String
    var state: IntelligenceReviewState
    var symbol: String
    var sourceURL: String?

    init(
        id: UUID = UUID(),
        title: String,
        sourceType: String,
        note: String,
        state: IntelligenceReviewState,
        symbol: String,
        sourceURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceType = sourceType
        self.note = note
        self.state = state
        self.symbol = symbol
        self.sourceURL = sourceURL
    }
}

struct IntelligenceItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var subtitle: String
    var kind: IntelligenceKind
    var state: IntelligenceReviewState
    var trailingNote: String
    var symbol: String
    var typeChip: ReferenceImportTypeChip?
    var sourceURL: String?
    var reviewItem: ReferenceReviewItem?
    var sortKey: String?

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        kind: IntelligenceKind,
        state: IntelligenceReviewState,
        trailingNote: String,
        symbol: String,
        typeChip: ReferenceImportTypeChip? = nil,
        sourceURL: String? = nil,
        reviewItem: ReferenceReviewItem? = nil,
        sortKey: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.state = state
        self.trailingNote = trailingNote
        self.symbol = symbol
        self.typeChip = typeChip
        self.sourceURL = sourceURL
        self.reviewItem = reviewItem
        self.sortKey = sortKey
    }
}

enum IntelligenceKind: String, CaseIterable, Codable, Hashable, Sendable {
    case pattern = "Pattern"
    case trend = "Trend"
    case audio = "Audio"
    case idea = "Idea"
    case watchlist = "Watchlist"
}

enum IntelligenceReviewState: String, CaseIterable, Codable, Hashable, Sendable {
    case ready
    case needsReview
    case approved
    case usedThisWeek

    var label: String {
        switch self {
        case .ready:
            "Ready"
        case .needsReview:
            "Needs review"
        case .approved:
            "Approved"
        case .usedThisWeek:
            "Used this week"
        }
    }
}

struct IntelligenceLibrarySection: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var subtitle: String
    var count: Int
    var symbol: String

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        count: Int,
        symbol: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.count = count
        self.symbol = symbol
    }
}

enum ReferenceImportInputType: String, Codable, Hashable, Sendable {
    case paste
    case csv
}

struct ReferenceImportPreview: Hashable, Sendable {
    var parserVersion: String
    var previewChecksum: String
    var destination: ReferenceImportDestination
    var counts: ReferenceImportCounts
    var rows: [ReferenceImportRow]
}

struct ReferenceImportDestination: Hashable, Sendable {
    var watchlistID: UUID?
    var watchlistName: String
}

struct ReferenceImportCounts: Hashable, Sendable {
    var totalRows: Int
    var cleanAccounts: Int
    var cleanReels: Int
    var cleanAudio: Int
    var needsReview: Int
    var duplicates: Int
    var invalid: Int
    var importable: Int
}

struct ReferenceImportRow: Identifiable, Hashable, Sendable {
    var clientRowID: String
    var lineNumber: Int
    var rawInput: String
    var typeChip: ReferenceImportTypeChip
    var classification: String
    var title: String
    var url: String?
    var notes: String?
    var previewState: ReferenceImportPreviewState
    var duplicateReason: String?
    var invalidReason: String?

    var id: String { clientRowID }
}

enum ReferenceImportTypeChip: String, CaseIterable, Codable, Hashable, Sendable {
    case account = "Account"
    case reel = "Reel"
    case audio = "Audio"
    case unknown = "Unknown"

    init(sourceType: String) {
        switch sourceType {
        case "reel_link", "benchmark_post":
            self = .reel
        case "audio_link":
            self = .audio
        case "benchmark_creator":
            self = .account
        default:
            self = .unknown
        }
    }
}

enum ReferenceImportPreviewState: String, CaseIterable, Codable, Hashable, Sendable {
    case clean
    case needsReview = "needs_review"
    case duplicate
    case invalid
}

struct ReferenceImportConfirmResult: Hashable, Sendable {
    var parserVersion: String
    var destination: ReferenceImportDestination
    var counts: ReferenceImportConfirmCounts
    var toast: String
}

struct ReferenceImportConfirmCounts: Hashable, Sendable {
    var imported: Int
    var needsReview: Int
    var duplicatesSkipped: Int
    var invalid: Int
}

struct ReferenceReviewRequest: Hashable, Sendable {
    var item: ReferenceReviewItem
    var action: ReferenceReviewAction
    var edit: ReferenceReviewEdit?

    init(
        item: ReferenceReviewItem,
        action: ReferenceReviewAction,
        edit: ReferenceReviewEdit? = nil
    ) {
        self.item = item
        self.action = action
        self.edit = edit
    }
}

struct ReferenceReviewItem: Hashable, Codable, Sendable {
    var kind: ReferenceReviewItemKind
    var id: UUID
}

enum ReferenceReviewItemKind: String, Codable, Hashable, Sendable {
    case benchmarkCreator = "benchmark_creator"
    case sourceReference = "source_reference"
}

enum ReferenceReviewAction: String, Codable, Hashable, Sendable {
    case approve
    case dismiss
    case edit
}

struct ReferenceReviewEdit: Hashable, Sendable {
    var targetType: ReferenceReviewEditTarget
    var handle: String?
    var url: String?
    var notes: String?
}

enum ReferenceReviewEditTarget: String, Codable, Hashable, Sendable {
    case account
    case reel
    case audio
    case unknown
}

struct ReferenceReviewResult: Hashable, Sendable {
    var itemID: UUID
    var kind: ReferenceReviewItemKind
    var action: ReferenceReviewAction
    var resultStatus: String
    var toast: String
}


struct DayIdentity: Codable, Hashable, Sendable {
    let workspaceID: UUID
    let creatorID: UUID
    let scheduledDate: String
}

struct DayGenerationRun: Codable, Hashable, Sendable {
    var requestID: UUID
    var generationID: UUID?
}

struct FilmingProgress: Codable, Hashable, Sendable {
    let revisionID: UUID
    var shotSceneIDs: Set<UUID>
    var isComplete: Bool

    init(revisionID: UUID, shotSceneIDs: Set<UUID> = [], isComplete: Bool = false) {
        self.revisionID = revisionID
        self.shotSceneIDs = shotSceneIDs
        self.isComplete = isComplete
    }

    enum CodingKeys: String, CodingKey {
        case revisionID, shotSceneIDs, isComplete
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        revisionID = try values.decode(UUID.self, forKey: .revisionID)
        shotSceneIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .shotSceneIDs) ?? []
        isComplete = try values.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false
    }
}

enum DayOutcome: String, Codable, Hashable, Sendable {
    case posted
    case backup
    case skipped
}

enum DayLifecycle: Codable, Hashable, Sendable {
    case empty
    case generating(DayGenerationRun)
    case draft
    case ready
    case filming(FilmingProgress)
    case decided(DayOutcome)
    case unavailable

    var exposesReadyPackage: Bool {
        switch self {
        case .ready, .filming, .decided: true
        default: false
        }
    }
}

struct DayRevision: Codable, Hashable, Sendable, Identifiable {
    var id: UUID { content.id }
    var content: GeneratedDailyCardDraft
    var filmingProgress: FilmingProgress
    var decision: DailyDecision?

    init(content: GeneratedDailyCardDraft) {
        self.content = content
        filmingProgress = FilmingProgress(revisionID: content.id)
    }

    enum CodingKeys: String, CodingKey {
        case content, filmingProgress, decision
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        content = try values.decode(GeneratedDailyCardDraft.self, forKey: .content)
        filmingProgress = try values.decodeIfPresent(FilmingProgress.self, forKey: .filmingProgress)
            ?? FilmingProgress(revisionID: content.id)
        decision = try values.decodeIfPresent(DailyDecision.self, forKey: .decision)
    }

    var dailyCard: DailyCard {
        let completion = decision?.completionState
            ?? (filmingProgress.isComplete ? CompletionState.shot : nil)
        return content.dailyCard(completionState: completion)
    }
}

enum DayTransition {
    case reconcile(GeneratedDailyCardDraft, CompletionState?, String?)
    case generate(DayGenerationRun, replacing: Bool)
    case generated(GeneratedDailyCardDraft)
    case generationFailed
    case retain(GeneratedDailyCardDraft, CompletionState?)
    case makeReady
    case returnToDraft
    case markShots(Set<UUID>)
    case decide(DailyDecision)
    case edit(GeneratedDailyCardDraft)
    case missingReady
    case removed
    case unavailable
}

enum DayTransitionError: LocalizedError {
    case illegalMove
    case mismatchedRevision
    case staleAnswer
    case incompletePackage

    var errorDescription: String? {
        switch self {
        case .illegalMove: "This action is not available for the day's current state."
        case .mismatchedRevision: "This package changed. Reload the day and try again."
        case .staleAnswer: "A newer version of this day is already saved."
        case .incompletePackage: "This package is incomplete. Reload the day and try again."
        }
    }
}

struct Day: Codable, Hashable, Sendable, Identifiable {
    var id: DayIdentity { identity }
    let identity: DayIdentity
    private(set) var revision: DayRevision?
    private(set) var lifecycle: DayLifecycle = .unavailable
    private(set) var previousRevisions: [DayRevision] = []
    private(set) var lastKnownLifecycle: DayLifecycle?
    private(set) var serverUpdatedAt: String?

    init(identity: DayIdentity) {
        self.identity = identity
    }

    enum CodingKeys: String, CodingKey {
        case identity, revision, lifecycle, previousRevisions, lastKnownLifecycle, serverUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        identity = try values.decode(DayIdentity.self, forKey: .identity)
        revision = try values.decodeIfPresent(DayRevision.self, forKey: .revision)
        lifecycle = try values.decodeIfPresent(DayLifecycle.self, forKey: .lifecycle) ?? .unavailable
        previousRevisions = try values.decodeIfPresent([DayRevision].self, forKey: .previousRevisions) ?? []
        lastKnownLifecycle = try values.decodeIfPresent(DayLifecycle.self, forKey: .lastKnownLifecycle)
        serverUpdatedAt = try values.decodeIfPresent(String.self, forKey: .serverUpdatedAt)
        if let revision, revision.content.scheduledDate != identity.scheduledDate || revision.filmingProgress.revisionID != revision.id {
            throw DecodingError.dataCorruptedError(forKey: .revision, in: values, debugDescription: "Mismatched Day revision")
        }
        if revision == nil, lifecycle.exposesReadyPackage || lifecycle == .draft {
            lastKnownLifecycle = lifecycle
            lifecycle = .unavailable
        }
        if let content = revision?.content, content.title.nilIfBlank == nil
            || content.sceneList.isEmpty && content.script.nilIfBlank == nil && content.caption.nilIfBlank == nil {
            lastKnownLifecycle = lifecycle
            lifecycle = .unavailable
        }
        if case .filming(let progress) = lifecycle, progress != revision?.filmingProgress {
            throw DecodingError.dataCorruptedError(forKey: .lifecycle, in: values, debugDescription: "Mismatched filming progress")
        }
    }

    mutating func transition(_ move: DayTransition) throws {
        var next = self
        switch move {
        case .reconcile(let content, let completion, let updatedAt):
            guard content.scheduledDate == identity.scheduledDate else {
                throw DayTransitionError.mismatchedRevision
            }
            if let updatedAt, let previous = serverUpdatedAt,
               let incoming = Self.timestamp(updatedAt),
               let current = Self.timestamp(previous), incoming < current {
                throw DayTransitionError.staleAnswer
            }
            try next.install(content)
            next.serverUpdatedAt = updatedAt ?? serverUpdatedAt
            next.revision?.decision = nil
            next.applyCompletion(completion)
            next.lifecycle = next.resolvedLifecycle()
        case .generate(let run, let replacing):
            switch lifecycle {
            case .empty, .unavailable: break
            case .draft, .ready, .filming, .decided:
                guard replacing else { throw DayTransitionError.illegalMove }
            case .generating(let existing):
                guard existing.generationID == nil && run.generationID != nil || existing.requestID == run.requestID || existing.generationID == run.generationID && run.generationID != nil else {
                    throw DayTransitionError.illegalMove
                }
            }
            next.lastKnownLifecycle = lifecycle
            next.lifecycle = .generating(run)
        case .generated(let content):
            guard case .generating = lifecycle else { throw DayTransitionError.illegalMove }
            try next.install(content)
            next.lifecycle = .draft
        case .generationFailed:
            guard case .generating = lifecycle else { throw DayTransitionError.illegalMove }
            if next.revision != nil {
                next.revision?.content.status = "archived"
                next.lifecycle = .unavailable
            } else {
                next.lifecycle = .empty
            }
        case .retain(let content, let completion):
            guard content.scheduledDate == identity.scheduledDate, revision?.id != content.id else {
                throw DayTransitionError.mismatchedRevision
            }
            var retained = Day(identity: identity)
            try retained.transition(.reconcile(content, completion, nil))
            if let saved = retained.revision, !next.previousRevisions.contains(where: { $0.id == saved.id }) {
                next.previousRevisions.append(saved)
            }
        case .makeReady:
            guard lifecycle == .draft, next.revision != nil else { throw DayTransitionError.illegalMove }
            next.revision?.content.status = "published"
            next.revision?.decision = nil
            next.lifecycle = next.resolvedLifecycle()
        case .returnToDraft:
            guard lifecycle.exposesReadyPackage else { throw DayTransitionError.illegalMove }
            next.revision?.content.status = "draft"
            next.revision?.decision = nil
            next.lifecycle = .draft
        case .markShots(let ids):
            guard lifecycle == .ready || { if case .filming = lifecycle { return true }; return false }(), var revision,
                  revision.decision?.completionState != .posted,
                  ids.isSubset(of: Set(revision.content.sceneList.map(\.id))),
                  ids.isSuperset(of: revision.filmingProgress.shotSceneIDs) else {
                throw DayTransitionError.illegalMove
            }
            revision.filmingProgress.shotSceneIDs = ids
            revision.filmingProgress.isComplete = !revision.content.sceneList.isEmpty
                && ids.count == revision.content.sceneList.count
            next.revision = revision
            next.lifecycle = next.resolvedLifecycle()
        case .decide(let decision):
            guard lifecycle.exposesReadyPackage, let revision else { throw DayTransitionError.illegalMove }
            if case .decided(let outcome) = lifecycle {
                let isUndo = outcome == .posted && decision.completionState == .shot
                guard isUndo || revision.decision?.completionState == decision.completionState else {
                    throw DayTransitionError.illegalMove
                }
            }
            switch decision.completionState {
            case .posted:
                guard revision.filmingProgress.isComplete || revision.dailyCard.isNonFilmingPost else {
                    throw DayTransitionError.illegalMove
                }
            case .shot:
                guard revision.filmingProgress.isComplete || revision.dailyCard.isNonFilmingPost else {
                    throw DayTransitionError.illegalMove
                }
                if case .decided(let outcome) = lifecycle, outcome != .posted {
                    throw DayTransitionError.illegalMove
                }
            case .usedBackup, .skippedIntentionally, .savedForTomorrow:
                guard revision.decision?.completionState != .posted,
                      !revision.filmingProgress.isComplete else { throw DayTransitionError.illegalMove }
            }
            next.revision?.decision = decision
            next.lifecycle = next.resolvedLifecycle()
        case .edit(let content):
            guard revision?.id == content.id, lifecycle == .draft || lifecycle.exposesReadyPackage else {
                throw DayTransitionError.mismatchedRevision
            }
            try next.install(content)
            let updatedLifecycle = next.resolvedLifecycle()
            switch (lifecycle, updatedLifecycle) {
            case (.draft, .draft), (.ready, .ready), (.filming, .filming): break
            case (.decided(let previous), .decided(let updated)) where previous == updated: break
            default: throw DayTransitionError.illegalMove
            }
            next.lifecycle = updatedLifecycle
        case .missingReady:
            if case .generating = lifecycle { return }
            if next.revision != nil {
                next.revision?.content.status = "draft"
                next.revision?.decision = nil
                next.lifecycle = .draft
            } else {
                next.lifecycle = .empty
            }
        case .removed:
            if let revision { next.previousRevisions.append(revision) }
            next.revision = nil
            next.lifecycle = .empty
        case .unavailable:
            if lifecycle != .unavailable { next.lastKnownLifecycle = lifecycle }
            next.lifecycle = .unavailable
        }
        self = next
    }

    private mutating func install(_ content: GeneratedDailyCardDraft) throws {
        guard content.scheduledDate == identity.scheduledDate else { throw DayTransitionError.mismatchedRevision }
        guard content.title.nilIfBlank != nil,
              !["Checking today's plan", "No ready package"].contains(content.title),
              !content.sceneList.isEmpty || content.script.nilIfBlank != nil || content.caption.nilIfBlank != nil else {
            throw DayTransitionError.incompletePackage
        }
        if revision?.id != content.id {
            if let revision { previousRevisions.append(revision) }
            revision = previousRevisions.last { $0.id == content.id } ?? DayRevision(content: content)
            previousRevisions.removeAll { $0.id == content.id }
        }
        guard var current = revision else { throw DayTransitionError.mismatchedRevision }
        let ids = Set(content.sceneList.map(\.id))
        for scene in current.content.sceneList where current.filmingProgress.shotSceneIDs.contains(scene.id) && !ids.contains(scene.id) {
            let matches = content.sceneList.filter {
                $0.number == scene.number && $0.id == ShotScene.stableID(revisionID: content.id, number: scene.number)
            }
            if matches.count == 1 { current.filmingProgress.shotSceneIDs.insert(matches[0].id) }
        }
        current.content = content
        current.filmingProgress.shotSceneIDs.formIntersection(ids)
        current.filmingProgress.isComplete = !ids.isEmpty && current.filmingProgress.shotSceneIDs == ids
        if current.decision?.completionState == .shot, !current.filmingProgress.isComplete {
            current.decision = nil
        }
        revision = current
    }

    private mutating func applyCompletion(_ completion: CompletionState?) {
        guard let completion else { return }
        revision?.decision = DailyDecision(completionState: completion)
        if completion == .shot || completion == .posted, let revision {
            self.revision?.filmingProgress.shotSceneIDs = Set(revision.content.sceneList.map(\.id))
            self.revision?.filmingProgress.isComplete = !revision.content.sceneList.isEmpty
        }
    }

    private static func timestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func resolvedLifecycle() -> DayLifecycle {
        guard let revision else { return .empty }
        if revision.content.status.lowercased() == "archived" { return .unavailable }
        if ["draft", "open", "ready", "backup"].contains(revision.content.status.lowercased()) {
            return .draft
        }
        switch revision.decision?.completionState {
        case .posted: return .decided(.posted)
        case .usedBackup: return .decided(.backup)
        case .skippedIntentionally, .savedForTomorrow: return .decided(.skipped)
        default:
            return revision.filmingProgress.shotSceneIDs.isEmpty
                ? .ready : .filming(revision.filmingProgress)
        }
    }
}
