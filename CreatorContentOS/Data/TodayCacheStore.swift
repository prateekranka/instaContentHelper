import Foundation
import Observation

struct DayStoreSnapshot: Codable, Hashable, Sendable {
    var days: [Day] = []
    var archiveEntries: [ArchiveEntry] = []

    init(days: [Day] = [], archiveEntries: [ArchiveEntry] = []) {
        self.days = days
        self.archiveEntries = archiveEntries
    }

    enum CodingKeys: String, CodingKey {
        case days
        case archiveEntries
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        days = try values.decodeIfPresent([Day].self, forKey: .days) ?? []
        archiveEntries = try values.decodeIfPresent([ArchiveEntry].self, forKey: .archiveEntries) ?? []
    }
}

@MainActor
@Observable
final class DayStore {
    let context: WorkspaceContext
    private(set) var days: [String: Day] = [:]
    private(set) var changeVersion = 0
    private var dayVersions: [String: Int] = [:]
    private(set) var archiveEntries: [ArchiveEntry] = []
    var ideaSuggestions: [String: PlanDayIdeasCacheEntry] = [:]
    var pendingDecisionRevisionID: UUID?

    init(context: WorkspaceContext) {
        self.context = context
    }

    var snapshot: DayStoreSnapshot {
        DayStoreSnapshot(days: days.values.sorted { $0.identity.scheduledDate < $1.identity.scheduledDate }, archiveEntries: archiveEntries)
    }

    var packages: [String: GeneratedDailyCardDraft] {
        days.compactMapValues { $0.revision?.content }
    }

    var readyCards: [DailyCard] {
        days.values.filter { $0.lifecycle.exposesReadyPackage }
            .compactMap { $0.revision?.dailyCard }
            .sorted { ($0.scheduledDate ?? "") < ($1.scheduledDate ?? "") }
    }

    func day(for date: String) -> Day? { days[date] }

    func card(revisionID: UUID) -> DailyCard? {
        for day in days.values {
            if let revision = day.revision, revision.id == revisionID { return revision.dailyCard }
            if let revision = day.previousRevisions.first(where: { $0.id == revisionID }) { return revision.dailyCard }
        }
        return nil
    }

    func restore(_ snapshot: DayStoreSnapshot) {
        for day in snapshot.days where day.identity.workspaceID == context.workspaceID && day.identity.creatorID == context.creatorID {
            days[day.identity.scheduledDate] = day
            changeVersion += 1
            dayVersions[day.identity.scheduledDate] = changeVersion
        }
        archiveEntries.removeAll()
        mergeArchive(snapshot.archiveEntries)
    }

    func changed(_ date: String, since version: Int) -> Bool { (dayVersions[date] ?? 0) > version }

    func transition(_ move: DayTransition, on date: String) throws {
        var day = days[date] ?? Day(identity: DayIdentity(workspaceID: context.workspaceID, creatorID: context.creatorID, scheduledDate: date))
        try day.transition(move)
        days[date] = day
        changeVersion += 1
        dayVersions[date] = changeVersion
    }

    func receive(_ package: GeneratedDailyCardDraft, completion: CompletionState? = nil, updatedAt: String? = nil, readVersion: Int? = nil, authoritativeDecision: Bool = false) throws {
        if let readVersion, changed(package.scheduledDate, since: readVersion) { return }
        let localDecision = days[package.scheduledDate]?.revision
        let keepsDecision = localDecision?.id == package.id
            && (localDecision?.id == pendingDecisionRevisionID || !authoritativeDecision && DayPackageLifecycleStatus.requiresOverwriteConfirmation(package.status))
        let resolvedCompletion = completion ?? CompletionState(supabaseStatus: package.status)
            ?? (keepsDecision ? localDecision?.decision?.completionState : nil)
        try transition(.reconcile(package, resolvedCompletion, updatedAt), on: package.scheduledDate)
    }

    func receivePublished(_ card: DailyCard, readVersion: Int? = nil) throws {
        guard let date = card.scheduledDate else { throw DayTransitionError.mismatchedRevision }
        var package = GeneratedDailyCardDraft(fromPublishedCard: card)
        if let existing = days[date]?.revision, existing.id == card.id {
            package.growthJob = existing.content.growthJob
            package.contentPillar = existing.content.contentPillar
            package.shootability = existing.content.shootability
            package.estimatedShootMinutes = existing.content.estimatedShootMinutes
            package.energyRequired = existing.content.energyRequired
            package.languageMode = existing.content.languageMode
            package.saveShareReason = existing.content.saveShareReason
            package.silentVersionTimeline = existing.content.silentVersionTimeline
            package.backupStoryDetail = existing.content.backupStoryDetail
            package.captionBackupDetail = existing.content.captionBackupDetail
        }
        try receive(package, completion: card.completionState, readVersion: readVersion, authoritativeDecision: true)
    }

    func reconcile(_ rows: [SupabaseCreatorDayRow], today: String, readVersion: Int) throws {
        for row in rows {
            if changed(row.scheduledDate, since: readVersion) { continue }
            if let card = row.revision {
                guard card.workspaceID == context.workspaceID, card.creatorID == context.creatorID,
                      card.scheduledDate == row.scheduledDate, card.id == row.currentRevisionID else {
                    throw DayTransitionError.mismatchedRevision
                }
                try receive(card.generatedDailyCardDraft(), completion: CompletionState(supabaseStatus: card.status), updatedAt: row.updatedAt, authoritativeDecision: true)
            } else if row.currentRevisionID == nil {
                try transition(.removed, on: row.scheduledDate)
            } else {
                throw DayTransitionError.mismatchedRevision
            }
            if let run = row.generation, run.status == "running" {
                try transition(.generate(DayGenerationRun(requestID: run.generationID, generationID: run.generationID), replacing: true), on: row.scheduledDate)
            }
        }
        if !rows.contains(where: { $0.scheduledDate == today }), !changed(today, since: readVersion) {
            try transition(.removed, on: today)
        }
    }

    func retainPendingCard(_ card: DailyCard) throws {
        guard let date = card.scheduledDate else { throw DayTransitionError.mismatchedRevision }
        if let current = days[date]?.revision, current.id != card.id {
            try transition(.retain(GeneratedDailyCardDraft(fromPublishedCard: card), card.completionState), on: date)
        } else if self.card(revisionID: card.id) == nil {
            try receivePublished(card)
        }
    }

    func updatePackage(on date: String, revisionID: UUID, patch: ReadyDayPackageUpdate, title: String?, caption: String?) throws {
        guard var content = days[date]?.revision?.content, content.id == revisionID else { throw DayTransitionError.mismatchedRevision }
        if let value = title ?? patch.title { content.title = value }
        if let value = patch.whyToday { content.whyToday = value }
        if let value = caption ?? patch.caption { content.caption = value }
        if let value = patch.script { content.script = value }
        if let value = patch.backupStory { content.backupStory = value }
        if let value = patch.backupCaptionOnly { content.backupCaptionOnly = value }
        if let value = patch.shootability { content.shootability = value }
        if let value = patch.estimatedShootMinutes { content.estimatedShootMinutes = value }
        if let value = patch.sceneList { content.sceneList = value }
        try transition(.edit(content), on: date)
    }

    func updateThumbnails(_ assets: [StoryboardThumbnailAsset], revisionID: UUID) throws {
        guard let date = days.first(where: { $0.value.revision?.id == revisionID })?.key,
              var content = days[date]?.revision?.content else { throw DayTransitionError.mismatchedRevision }
        content.storyboardThumbnailAssets = assets
        try transition(.edit(content), on: date)
    }

    func mergeArchive(_ entries: [ArchiveEntry], authoritative: Bool = false) {
        for entry in entries {
            if let index = archiveEntries.firstIndex(where: { existing in
                if let revisionID = entry.dailyCardID { return existing.dailyCardID == revisionID }
                return existing.id == entry.id
            }) {
                if archiveEntries[index].decision == .posted,
                   entry.decision != .posted || !authoritative { continue }
                var mergedEntry = entry
                mergedEntry.captionSnapshot = entry.captionSnapshot ?? archiveEntries[index].captionSnapshot
                mergedEntry.scheduledDate = entry.scheduledDate ?? archiveEntries[index].scheduledDate
                mergedEntry.decisionAt = entry.decisionAt ?? archiveEntries[index].decisionAt
                archiveEntries[index] = mergedEntry
            } else {
                archiveEntries.append(entry)
            }
        }
        archiveEntries.sort { ($0.scheduledDate ?? $0.decisionAt ?? "") > ($1.scheduledDate ?? $1.decisionAt ?? "") }
    }
}

struct CachedTodaySnapshot: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 2
    var schemaVersion: Int = currentSchemaVersion
    var dayStore: DayStoreSnapshot?
    var cachedAt: Date
    var source: String
    var unsyncedDecision: UnsyncedTodayDecision?
    private var todayCard: DailyCard?
    private var weekCards: [DailyCard] = []
    private var shotSceneIDs: Set<UUID> = []

    init(dayStore: DayStoreSnapshot, cachedAt: Date, source: String, unsyncedDecision: UnsyncedTodayDecision?) {
        self.dayStore = dayStore
        self.cachedAt = cachedAt
        self.source = source
        self.unsyncedDecision = unsyncedDecision
    }

    init(todayCard: DailyCard, weekCards: [DailyCard], cachedAt: Date, source: String, shotSceneIDs: Set<UUID>? = nil, unsyncedDecision: UnsyncedTodayDecision? = nil) {
        schemaVersion = 1
        self.todayCard = todayCard
        self.weekCards = weekCards
        self.cachedAt = cachedAt
        self.source = source
        self.shotSceneIDs = shotSceneIDs ?? []
        self.unsyncedDecision = unsyncedDecision
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, dayStore, cachedAt, source, unsyncedDecision, todayCard, weekCards, shotSceneIDs
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "Unsupported DayStore cache version")
        }
        dayStore = try values.decodeIfPresent(DayStoreSnapshot.self, forKey: .dayStore)
        cachedAt = try values.decodeIfPresent(Date.self, forKey: .cachedAt) ?? .distantPast
        source = try values.decodeIfPresent(String.self, forKey: .source) ?? "legacy"
        todayCard = try values.decodeIfPresent(DailyCard.self, forKey: .todayCard)
        weekCards = try values.decodeIfPresent([DailyCard].self, forKey: .weekCards) ?? []
        shotSceneIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .shotSceneIDs) ?? []
        unsyncedDecision = try values.decodeIfPresent(UnsyncedTodayDecision.self, forKey: .unsyncedDecision)
        if unsyncedDecision?.card == nil, let id = unsyncedDecision?.cardID {
            unsyncedDecision?.card = ([todayCard].compactMap { $0 } + weekCards).first { $0.id == id }
                ?? dayStore?.days.compactMap(\.revision).first { $0.id == id }?.dailyCard
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encodeIfPresent(dayStore, forKey: .dayStore)
        try values.encode(cachedAt, forKey: .cachedAt)
        try values.encode(source, forKey: .source)
        try values.encodeIfPresent(unsyncedDecision, forKey: .unsyncedDecision)
        if dayStore == nil {
            try values.encodeIfPresent(todayCard, forKey: .todayCard)
            try values.encode(weekCards, forKey: .weekCards)
            try values.encode(shotSceneIDs, forKey: .shotSceneIDs)
        }
    }

    func migratedStore(for context: WorkspaceContext) -> DayStoreSnapshot {
        if let dayStore { return dayStore }
        var days: [String: Day] = [:]
        for card in weekCards + [todayCard].compactMap({ $0 }) {
            guard let date = card.scheduledDate else { continue }
            var day = days[date] ?? Day(identity: DayIdentity(workspaceID: context.workspaceID, creatorID: context.creatorID, scheduledDate: date))
            do {
                try day.transition(.reconcile(GeneratedDailyCardDraft(fromPublishedCard: card), card.completionState, nil))
                if card.id == todayCard?.id, !shotSceneIDs.isEmpty {
                    let ids = shotSceneIDs.intersection(Set(card.scenes.map(\.id)))
                    if card.completionState != .posted { try day.transition(.markShots(ids)) }
                }
                days[date] = day
            } catch {
                try? day.transition(.unavailable)
                days[date] = day
            }
        }
        return DayStoreSnapshot(days: Array(days.values))
    }
}

struct UnsyncedTodayDecision: Codable, Hashable, Sendable {
    var cardID: UUID
    var decision: DailyDecision
    var card: DailyCard?
}

protocol TodayCacheStoring {
    func loadSnapshot(for context: WorkspaceContext) throws -> CachedTodaySnapshot?
    func saveSnapshot(_ snapshot: CachedTodaySnapshot, for context: WorkspaceContext) throws
    func clearSnapshot(for context: WorkspaceContext) throws
}

struct FileTodayCacheStore: TodayCacheStoring {
    private let baseDirectory: URL?

    init(baseDirectory: URL? = nil) { self.baseDirectory = baseDirectory }

    func loadSnapshot(for context: WorkspaceContext) throws -> CachedTodaySnapshot? {
        let url = try fileURL(for: context)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(CachedTodaySnapshot.self, from: data)
        } catch {
            let preservedURL = url.deletingPathExtension().appendingPathExtension("unreadable-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: url, to: preservedURL)
            throw error
        }
    }

    func saveSnapshot(_ snapshot: CachedTodaySnapshot, for context: WorkspaceContext) throws {
        let directory = try directoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existingURL = try fileURL(for: context)
        if FileManager.default.fileExists(atPath: existingURL.path) {
            do { _ = try loadSnapshot(for: context) }
            catch {
                if FileManager.default.fileExists(atPath: existingURL.path) { throw error }
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL(for: context), options: .atomic)
    }

    func clearSnapshot(for context: WorkspaceContext) throws {
        let url = try fileURL(for: context)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func fileURL(for context: WorkspaceContext) throws -> URL {
        try directoryURL().appendingPathComponent("today-\(context.workspaceID.uuidString)-\(context.creatorID.uuidString).json")
    }

    private func directoryURL() throws -> URL {
        if let baseDirectory { return baseDirectory }
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return root.appendingPathComponent("CreatorContentOS", isDirectory: true).appendingPathComponent("TodayCache", isDirectory: true)
    }
}
