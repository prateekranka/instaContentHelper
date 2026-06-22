import Foundation

struct DailyCard: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var context: String
    var effortLabel: String
    var whyToday: String
    var sourceNote: String?
    var scheduledDate: String?
    var scenes: [ShotScene]
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

    init(
        id: UUID = UUID(),
        title: String,
        context: String,
        effortLabel: String,
        whyToday: String,
        sourceNote: String? = nil,
        scheduledDate: String? = nil,
        scenes: [ShotScene],
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
        assumptions: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.context = context
        self.effortLabel = effortLabel
        self.whyToday = whyToday
        self.sourceNote = sourceNote
        self.scheduledDate = scheduledDate
        self.scenes = scenes
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
    }
}

struct ShotScene: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let number: Int
    let title: String
    let duration: String
    let symbol: String

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
        title = decodedTitle ?? decodedVideoPortion ?? decodedPlacement ?? decodedText ?? ""
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
            ?? container.decodeIfPresent(String.self, forKey: .body)
            ?? decodedVoiceover
            ?? decodedOnScreenText
            ?? decodedShot
            ?? (decodedTitle == nil ? "" : decodedText ?? "")
        shot = decodedShot
        videoPortion = decodedVideoPortion
        voiceover = decodedVoiceover
        onScreenText = decodedOnScreenText
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

struct ArchiveEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let dailyCardID: UUID?
    let day: String
    let date: String
    let cardTitle: String
    var decision: CompletionState
    let outputLine: String
    let hasPostThumbnail: Bool

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
    case post = "Post"

    var id: String { rawValue }
}

enum CreatorTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case today = "Today"
    case profile = "Profile"

    var id: String { rawValue }
}

enum CreatorRoute: Hashable, Sendable {
    case shootFolio
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

enum GenerateWeekMode: String, Codable, Hashable, Sendable {
    case generateDraft = "generate_draft"
    case regenerateDraft = "regenerate_draft"
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

struct GeneratedDailyCardDraft: Identifiable, Hashable, Sendable {
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
        sourceNote: String
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
            sourceNote: sourceNote.nilIfBlank ?? contentPillar,
            scheduledDate: scheduledDate,
            scenes: sceneList,
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
            assumptions: assumptions
        )
    }
}

struct IntelligenceHome: Identifiable, Hashable, Sendable {
    let id: UUID
    var sourcePulse: SourcePulseSummary
    var readyForThisWeek: [IntelligenceItem]
    var needsReview: [IntelligenceItem]
    var ideaCandidates: [IntelligenceItem]
    var recentlyUsed: [IntelligenceItem]
    var librarySections: [IntelligenceLibrarySection]

    init(
        id: UUID = UUID(),
        sourcePulse: SourcePulseSummary,
        readyForThisWeek: [IntelligenceItem],
        needsReview: [IntelligenceItem],
        ideaCandidates: [IntelligenceItem],
        recentlyUsed: [IntelligenceItem],
        librarySections: [IntelligenceLibrarySection]
    ) {
        self.id = id
        self.sourcePulse = sourcePulse
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
