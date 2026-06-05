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

    init(
        id: UUID = UUID(),
        title: String,
        context: String,
        effortLabel: String,
        whyToday: String,
        sourceNote: String? = nil,
        scheduledDate: String? = nil,
        scenes: [ShotScene],
        completionState: CompletionState? = nil
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

enum MamtaTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case today = "Today"
    case shootFolio = "Shoot Folio"
    case archive = "Archive"
    case profile = "Profile"

    var id: String { rawValue }
}

enum MamtaRoute: Hashable, Sendable {
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
    var readinessLine: String
    var isSoftLocked: Bool
    var days: [WeeklyDay]
    var setupSections: [WeeklySetupSection]

    init(
        id: UUID = UUID(),
        title: String,
        eyebrow: String,
        weekRange: String,
        weekStartDate: String? = nil,
        readinessLine: String,
        isSoftLocked: Bool,
        days: [WeeklyDay],
        setupSections: [WeeklySetupSection]
    ) {
        self.id = id
        self.title = title
        self.eyebrow = eyebrow
        self.weekRange = weekRange
        self.weekStartDate = weekStartDate
        self.readinessLine = readinessLine
        self.isSoftLocked = isSoftLocked
        self.days = days
        self.setupSections = setupSections
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

    init(
        id: UUID = UUID(),
        title: String,
        sourceType: String,
        note: String,
        state: IntelligenceReviewState,
        symbol: String
    ) {
        self.id = id
        self.title = title
        self.sourceType = sourceType
        self.note = note
        self.state = state
        self.symbol = symbol
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

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        kind: IntelligenceKind,
        state: IntelligenceReviewState,
        trailingNote: String,
        symbol: String
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
        self.state = state
        self.trailingNote = trailingNote
        self.symbol = symbol
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
