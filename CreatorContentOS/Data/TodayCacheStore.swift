import Foundation
import Observation

struct DayStoreSnapshot: Codable, Hashable, Sendable {
    var days: [Day] = []
    var archiveEntries: [ArchiveEntry] = []
    var outbox: [ContentIntent] = []

    init(days: [Day] = [], archiveEntries: [ArchiveEntry] = [], outbox: [ContentIntent] = []) {
        self.days = days
        self.archiveEntries = archiveEntries
        self.outbox = outbox
    }

    enum CodingKeys: String, CodingKey {
        case days
        case archiveEntries
        case outbox
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        days = try values.decodeIfPresent([Day].self, forKey: .days) ?? []
        archiveEntries = try values.decodeIfPresent([ArchiveEntry].self, forKey: .archiveEntries) ?? []
        outbox = try values.decodeIfPresent([ContentIntent].self, forKey: .outbox) ?? []
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
    private(set) var outbox: [ContentIntent] = []

    init(context: WorkspaceContext) {
        self.context = context
    }

    var snapshot: DayStoreSnapshot {
        DayStoreSnapshot(days: days.values.sorted { $0.identity.scheduledDate < $1.identity.scheduledDate }, archiveEntries: archiveEntries, outbox: outbox)
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
        outbox = snapshot.outbox.filter { $0.workspaceID == context.workspaceID && $0.creatorID == context.creatorID }
        archiveEntries.removeAll()
        mergeArchive(snapshot.archiveEntries)
    }

    func enqueue(_ intent: ContentIntent) {
        guard intent.workspaceID == context.workspaceID, intent.creatorID == context.creatorID,
              !outbox.contains(where: { $0.id == intent.id }) else { return }
        outbox.append(intent)
    }

    func restoreOutbox(_ intents: [ContentIntent]) {
        outbox = intents
    }

    func updateIntent(_ intent: ContentIntent) {
        guard let index = outbox.firstIndex(where: { $0.id == intent.id }) else { return }
        outbox[index] = intent
    }

    func finishIntent(_ id: String) {
        outbox.removeAll { $0.id == id }
    }

    func bindRevision(requestedID: UUID, to revisionID: UUID) {
        for index in outbox.indices where !outbox[index].isGeneration && outbox[index].revisionID == requestedID {
            outbox[index].revisionID = revisionID
        }
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
        let pending = outbox.last { $0.kind == .decide && $0.revisionID == package.id }
        let keepsDecision = localDecision?.id == package.id && !authoritativeDecision
            && DayPackageLifecycleStatus.requiresOverwriteConfirmation(package.status)
        let resolvedCompletion = pending?.decision?.completionState
            ?? (keepsDecision ? localDecision?.decision?.completionState : completion ?? CompletionState(supabaseStatus: package.status))
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
            if let run = row.generation {
                for index in outbox.indices where outbox[index].isGeneration && outbox[index].scheduledDate == row.scheduledDate {
                    if run.idempotencyKey == outbox[index].id || run.generationID == outbox[index].generationID {
                        outbox[index].generationID = run.generationID
                        if run.status == "completed" { outbox[index].generatedRevisionID = row.currentRevisionID }
                    } else if run.idempotencyKey != nil,
                              outbox[index].generationID != nil || row.currentRevisionID != nil && row.currentRevisionID != outbox[index].priorRevisionID {
                        outbox[index].supersededByServer = true
                    }
                }
                if run.status == "running" {
                    let requestID = outbox.first { $0.generationID == run.generationID }?.requestedRevisionID ?? run.generationID
                    try transition(.generate(DayGenerationRun(requestID: requestID, generationID: run.generationID), replacing: true), on: row.scheduledDate)
                }
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
        let patch = patch.owningShotLines(in: content)
        if let value = patch.script { content.script = value }
        if let value = patch.backupStory { content.backupStory = value }
        if let value = patch.backupCaptionOnly { content.backupCaptionOnly = value }
        if let value = patch.shootability { content.shootability = value }
        if let value = patch.estimatedShootMinutes { content.estimatedShootMinutes = value }
        if let value = patch.sceneList { content.sceneList = value }
        content.normalizeShotContent()
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
                if archiveEntries[index].decision == .posted, !authoritative { continue }
                var mergedEntry = entry
                if archiveEntries[index].decision == .posted {
                    mergedEntry = ArchiveEntry(
                        id: entry.id,
                        dailyCardID: entry.dailyCardID,
                        day: entry.day,
                        date: entry.date,
                        cardTitle: archiveEntries[index].cardTitle,
                        decision: entry.decision,
                        outputLine: entry.outputLine,
                        hasPostThumbnail: entry.hasPostThumbnail
                    )
                    mergedEntry.captionSnapshot = archiveEntries[index].captionSnapshot
                }
                mergedEntry.captionSnapshot = mergedEntry.captionSnapshot ?? archiveEntries[index].captionSnapshot
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
    static let currentSchemaVersion = 3
    var schemaVersion: Int = currentSchemaVersion
    var dayStore: DayStoreSnapshot?
    var cachedAt: Date
    var source: String
    private var legacyDecision: LegacyTodayDecision?
    private var todayCard: DailyCard?
    private var weekCards: [DailyCard] = []
    private var shotSceneIDs: Set<UUID> = []

    init(dayStore: DayStoreSnapshot, cachedAt: Date, source: String) {
        self.dayStore = dayStore
        self.cachedAt = cachedAt
        self.source = source
    }

    init(todayCard: DailyCard, weekCards: [DailyCard], cachedAt: Date, source: String, shotSceneIDs: Set<UUID>? = nil, unsyncedDecision: LegacyTodayDecision? = nil) {
        schemaVersion = 1
        self.todayCard = todayCard
        self.weekCards = weekCards
        self.cachedAt = cachedAt
        self.source = source
        self.shotSceneIDs = shotSceneIDs ?? []
        self.legacyDecision = unsyncedDecision
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
        legacyDecision = try values.decodeIfPresent(LegacyTodayDecision.self, forKey: .unsyncedDecision)
        if legacyDecision?.card == nil, let id = legacyDecision?.cardID {
            legacyDecision?.card = ([todayCard].compactMap { $0 } + weekCards).first { $0.id == id }
                ?? dayStore?.days.compactMap(\.revision).first { $0.id == id }?.dailyCard
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encodeIfPresent(dayStore, forKey: .dayStore)
        try values.encode(cachedAt, forKey: .cachedAt)
        try values.encode(source, forKey: .source)
        if dayStore == nil { try values.encodeIfPresent(legacyDecision, forKey: .unsyncedDecision) }
        if dayStore == nil {
            try values.encodeIfPresent(todayCard, forKey: .todayCard)
            try values.encode(weekCards, forKey: .weekCards)
            try values.encode(shotSceneIDs, forKey: .shotSceneIDs)
        }
    }

    func migratedStore(for context: WorkspaceContext) -> DayStoreSnapshot {
        if var dayStore {
            migrateDecision(into: &dayStore, context: context)
            return dayStore
        }
        var days: [String: Day] = [:]
        for card in weekCards + [todayCard].compactMap({ $0 }) {
            guard let date = card.scheduledDate else { continue }
            var day = days[date] ?? Day(identity: DayIdentity(workspaceID: context.workspaceID, creatorID: context.creatorID, scheduledDate: date))
            do {
                let package = GeneratedDailyCardDraft(fromPublishedCard: card)
                try day.transition(.reconcile(package, nil, nil))
                if card.id == todayCard?.id, !shotSceneIDs.isEmpty {
                    let ids = shotSceneIDs.intersection(Set(card.scenes.map(\.id)))
                    if card.completionState != .posted { try day.transition(.markShots(ids)) }
                }
                try day.transition(.reconcile(package, card.completionState, nil))
                days[date] = day
            } catch {
                try? day.transition(.unavailable)
                days[date] = day
            }
        }
        var snapshot = DayStoreSnapshot(days: Array(days.values))
        migrateDecision(into: &snapshot, context: context)
        return snapshot
    }
    private func migrateDecision(into snapshot: inout DayStoreSnapshot, context: WorkspaceContext) {
        guard let legacyDecision else { return }
        let card = legacyDecision.card ?? snapshot.days.compactMap(\.revision).first { $0.id == legacyDecision.cardID }?.dailyCard
        guard let card, let date = card.scheduledDate,
              !snapshot.outbox.contains(where: { $0.kind == .decide && $0.revisionID == card.id }) else { return }
        var intent = ContentIntent(kind: .decide, context: context, scheduledDate: date, revisionID: card.id)
        intent.decision = legacyDecision.decision
        intent.cardSnapshot = card
        snapshot.outbox.append(intent)
    }

}

struct LegacyTodayDecision: Codable, Hashable, Sendable {
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
