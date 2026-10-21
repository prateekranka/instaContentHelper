import Foundation
import Observation

struct DayStoreSnapshot: Codable, Hashable, Sendable {
    var pieces: [Piece] = []
    var archiveEntries: [ArchiveEntry] = []
    var outbox: [ContentIntent] = []

    init(pieces: [Piece] = [], archiveEntries: [ArchiveEntry] = [], outbox: [ContentIntent] = []) {
        self.pieces = pieces
        self.archiveEntries = archiveEntries
        self.outbox = outbox
    }

    enum CodingKeys: String, CodingKey {
        case pieces, days, archiveEntries, outbox
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pieces = try values.decodeIfPresent([Piece].self, forKey: .pieces)
            ?? values.decodeIfPresent([Piece].self, forKey: .days) ?? []
        archiveEntries = try values.decodeIfPresent([ArchiveEntry].self, forKey: .archiveEntries) ?? []
        outbox = try values.decodeIfPresent([ContentIntent].self, forKey: .outbox) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(pieces, forKey: .pieces)
        try values.encode(archiveEntries, forKey: .archiveEntries)
        try values.encode(outbox, forKey: .outbox)
    }

    mutating func migrateIntentPieces(for context: WorkspaceContext) {
        for index in outbox.indices where outbox[index].workspaceID == context.workspaceID && outbox[index].creatorID == context.creatorID && outbox[index].pieceID == nil {
            let intent = outbox[index]
            let revisions = Set([intent.revisionID, intent.requestedRevisionID] + [intent.priorRevisionID, intent.generatedRevisionID].compactMap { $0 })
            let matching = pieces.first {
                $0.identity.workspaceID == context.workspaceID && $0.identity.creatorID == context.creatorID
                    && ($0.revision.map { revisions.contains($0.id) } == true || $0.previousRevisions.contains { revisions.contains($0.id) })
            } ?? pieces.first {
                $0.identity.workspaceID == context.workspaceID && $0.identity.creatorID == context.creatorID
                    && $0.scheduledDate == intent.scheduledDate && $0.position == 0
            }
            let pieceID: UUID
            if let matching {
                pieceID = matching.identity.pieceID
            } else {
                pieceID = UUID()
                pieces.append(Piece(identity: PieceIdentity(workspaceID: context.workspaceID, creatorID: context.creatorID, pieceID: pieceID), scheduledDate: intent.scheduledDate, requiresServerBinding: true))
            }
            outbox[index].pieceID = pieceID
            outbox[index].usesLegacyPieceTarget = true
            if intent.isGeneration { outbox[index].usesLegacyGenerationIdentity = true }
        }
    }
}

struct DayCardProjection {
    let card: DailyCard
    let shotSceneCount: Int
    let unshotSceneCount: Int
    let areAllScenesShot: Bool

    init(revision: DayRevision) {
        card = revision.dailyCard
        let shotIDs = revision.filmingProgress.shotSceneIDs
        shotSceneCount = card.scenes.count { shotIDs.contains($0.id) }
        unshotSceneCount = max(card.scenes.count - shotSceneCount, 0)
        areAllScenesShot = !card.scenes.isEmpty && unshotSceneCount == 0
    }
}

@MainActor
@Observable
final class DayStore {
    let context: WorkspaceContext
    private(set) var pieces: [UUID: Piece] = [:]
    private(set) var pieceIDsByDate: [String: [UUID]] = [:]
    private(set) var changeVersion = 0
    private var pieceVersions: [UUID: Int] = [:]
    @ObservationIgnored private var cardProjections: [UUID: [UUID: DayCardProjection]] = [:]
    private(set) var archiveEntries: [ArchiveEntry] = []
    var ideaSuggestions: [String: PlanDayIdeasCacheEntry] = [:]
    private(set) var outbox: [ContentIntent] = []

    init(context: WorkspaceContext) {
        self.context = context
    }

    var snapshot: DayStoreSnapshot {
        DayStoreSnapshot(pieces: pieces.values.sorted {
            ($0.scheduledDate, $0.position, $0.identity.pieceID.uuidString) < ($1.scheduledDate, $1.position, $1.identity.pieceID.uuidString)
        }, archiveEntries: archiveEntries, outbox: outbox)
    }

    var packages: [String: GeneratedDailyCardDraft] {
        pieceIDsByDate.compactMapValues { ids in
            ids.compactMap { pieces[$0] }.first { $0.position == 0 }?.revision?.content
        }
    }

    var readyCards: [DailyCard] {
        pieceIDsByDate.keys.sorted().compactMap { date in
            guard day(for: date)?.lifecycle.exposesReadyPackage == true else { return nil }
            return projection(for: date)?.card
        }
    }

    func piece(for pieceID: UUID) -> Piece? { pieces[pieceID] }

    func piece(revisionID: UUID) -> Piece? {
        pieces.values.first { $0.revision?.id == revisionID || $0.previousRevisions.contains { $0.id == revisionID } }
    }

    func piece(for intent: ContentIntent) -> Piece? {
        if let pieceID = intent.pieceID { return pieces[pieceID] }
        guard let piece = piece(revisionID: intent.revisionID), piece.scheduledDate == intent.scheduledDate else { return nil }
        return piece
    }

    func day(for date: String) -> Piece? {
        pieceIDsByDate[date]?.compactMap { pieces[$0] }.first { $0.position == 0 }
    }

    @discardableResult
    func ensurePiece(on date: String, pieceID: UUID? = nil, position: Int? = nil, requiresServerBinding: Bool = false) -> UUID {
        if let pieceID, pieces[pieceID] != nil { return pieceID }
        if pieceID == nil, let existing = day(for: date) { return existing.identity.pieceID }
        let id = pieceID ?? UUID()
        let nextPosition = (pieceIDsByDate[date]?.compactMap { pieces[$0]?.position }.max() ?? -1) + 1
        pieces[id] = Piece(identity: PieceIdentity(workspaceID: context.workspaceID, creatorID: context.creatorID, pieceID: id), scheduledDate: date, position: position ?? nextPosition, requiresServerBinding: requiresServerBinding)
        rebuildDateIndex()
        return id
    }

    private func rebuildDateIndex() {
        pieceIDsByDate = Dictionary(grouping: pieces.values, by: \.scheduledDate).mapValues {
            $0.sorted { ($0.position, $0.requiresServerBinding ? 1 : 0, $0.identity.pieceID.uuidString) < ($1.position, $1.requiresServerBinding ? 1 : 0, $1.identity.pieceID.uuidString) }.map { $0.identity.pieceID }
        }
    }

    func projection(for date: String, revisionID: UUID? = nil) -> DayCardProjection? {
        guard let pieceID = day(for: date)?.identity.pieceID else { return nil }
        return projection(pieceID: pieceID, revisionID: revisionID)
    }

    func projection(pieceID: UUID, revisionID: UUID? = nil) -> DayCardProjection? {
        guard let piece = pieces[pieceID], let id = revisionID ?? piece.revision?.id else { return nil }
        if let cached = cardProjections[pieceID]?[id] { return cached }
        guard let revision = piece.revision.flatMap({ $0.id == id ? $0 : nil })
            ?? piece.previousRevisions.first(where: { $0.id == id }) else { return nil }
        let projection = DayCardProjection(revision: revision)
        cardProjections[pieceID, default: [:]][id] = projection
        return projection
    }

    func card(revisionID: UUID) -> DailyCard? {
        guard let piece = piece(revisionID: revisionID) else { return nil }
        return projection(pieceID: piece.identity.pieceID, revisionID: revisionID)?.card
    }

    func restore(_ snapshot: DayStoreSnapshot) {
        var snapshot = snapshot
        snapshot.migrateIntentPieces(for: context)
        for saved in snapshot.pieces where saved.identity.workspaceID == context.workspaceID && saved.identity.creatorID == context.creatorID {
            for existing in pieces.values where existing.scheduledDate == saved.scheduledDate && existing.position == saved.position && existing.identity.pieceID != saved.identity.pieceID {
                pieces[existing.identity.pieceID] = nil
                cardProjections[existing.identity.pieceID] = nil
                pieceVersions[existing.identity.pieceID] = nil
            }
        }
        for piece in snapshot.pieces where piece.identity.workspaceID == context.workspaceID && piece.identity.creatorID == context.creatorID {
            cardProjections[piece.identity.pieceID] = nil
            pieces[piece.identity.pieceID] = piece
            changeVersion += 1
            pieceVersions[piece.identity.pieceID] = changeVersion
        }
        rebuildDateIndex()
        outbox = snapshot.outbox.filter { $0.workspaceID == context.workspaceID && $0.creatorID == context.creatorID }
        archiveEntries.removeAll()
        mergeArchive(snapshot.archiveEntries)
    }

    func enqueue(_ intent: ContentIntent) {
        guard intent.workspaceID == context.workspaceID, intent.creatorID == context.creatorID,
              !outbox.contains(where: { $0.id == intent.id }) else { return }
        var intent = intent
        intent.pieceID = intent.pieceID ?? piece(revisionID: intent.revisionID)?.identity.pieceID ?? ensurePiece(on: intent.scheduledDate)
        outbox.append(intent)
    }

    func restoreIntent(_ intent: ContentIntent, at index: Int) {
        guard !outbox.contains(where: { $0.id == intent.id }) else { return }
        var intent = intent
        if intent.pieceID.flatMap({ pieces[$0] }) == nil, let matching = piece(revisionID: intent.revisionID) {
            intent.pieceID = matching.identity.pieceID
        }
        outbox.insert(intent, at: min(index, outbox.count))
    }

    func updateIntent(_ intent: ContentIntent) {
        guard let index = outbox.firstIndex(where: { $0.id == intent.id }) else { return }
        outbox[index] = intent
    }

    func finishIntent(_ id: String) {
        outbox.removeAll { $0.id == id }
    }

    func bindRevision(requestedID: UUID, to revisionID: UUID, pieceID: UUID?) {
        for index in outbox.indices where !outbox[index].isGeneration && outbox[index].revisionID == requestedID && outbox[index].pieceID == pieceID {
            outbox[index].revisionID = revisionID
        }
    }

    func changed(_ date: String, since version: Int) -> Bool {
        guard let pieceID = day(for: date)?.identity.pieceID else { return false }
        return changed(pieceID: pieceID, since: version)
    }

    func changed(pieceID: UUID, since version: Int) -> Bool { (pieceVersions[pieceID] ?? 0) > version }

    func transition(_ move: DayTransition, on date: String) throws {
        try transition(move, pieceID: ensurePiece(on: date))
    }

    func transition(_ move: DayTransition, pieceID: UUID) throws {
        guard var piece = pieces[pieceID] else { throw DayTransitionError.mismatchedRevision }
        try piece.transition(move)
        cardProjections[pieceID] = nil
        pieces[pieceID] = piece
        changeVersion += 1
        pieceVersions[pieceID] = changeVersion
    }

    func transition(_ move: DayTransition, for intent: ContentIntent) throws {
        guard let piece = piece(for: intent) else { throw DayTransitionError.mismatchedRevision }
        try transition(move, pieceID: piece.identity.pieceID)
    }

    func bindServerPieces(_ rows: [SupabaseCreatorDayRow]) throws {
        for row in rows {
            if let card = row.revision {
                guard card.workspaceID == context.workspaceID, card.creatorID == context.creatorID,
                      card.scheduledDate == row.scheduledDate, card.id == row.currentRevisionID else { throw DayTransitionError.mismatchedRevision }
            }
            guard let id = row.pieceID ?? row.revision?.pieceID ?? row.generation?.pieceID else { continue }
            try bindServerPiece(id, revisionID: row.currentRevisionID, scheduledDate: row.scheduledDate, position: row.position, generationID: row.generation?.generationID)
        }
    }

    @discardableResult
    func bindServerPiece(_ pieceID: UUID, revisionID: UUID?, scheduledDate: String, position: Int? = nil, generationID: UUID? = nil) throws -> UUID {
        let matching = revisionID.flatMap { id in
            pieces.values.first { $0.requiresServerBinding && ($0.revision?.id == id || $0.previousRevisions.contains { $0.id == id }) }
                ?? piece(revisionID: id)
        } ?? generationID.flatMap { id in
                outbox.first { $0.generationID == id }.flatMap { piece(for: $0) }
            }
        if let matching, matching.identity.pieceID != pieceID {
            guard matching.requiresServerBinding, matching.scheduledDate == scheduledDate else { throw DayTransitionError.mismatchedRevision }
            let localID = matching.identity.pieceID
            let serverRevisionID = pieces[pieceID]?.revision?.id
            var bound = pieces[pieceID] ?? matching
            guard bound.scheduledDate == scheduledDate else { throw DayTransitionError.mismatchedRevision }
            if pieces[pieceID] != nil { bound.mergeSavedWork(from: matching) }
            bound.bind(to: pieceID, position: position ?? bound.position)
            pieces[localID] = nil
            pieces[pieceID] = bound
            cardProjections[localID] = nil
            cardProjections[pieceID] = nil
            pieceVersions[pieceID] = max(pieceVersions[pieceID] ?? 0, pieceVersions.removeValue(forKey: localID) ?? 0)
            for index in outbox.indices where outbox[index].pieceID == localID {
                outbox[index].pieceID = pieceID
                if outbox[index].isGeneration, let current = serverRevisionID,
                   current != outbox[index].priorRevisionID, current != outbox[index].generatedRevisionID,
                   current != outbox[index].revisionID {
                    outbox[index].supersededByServer = true
                }
                outbox[index].cardSnapshot?.pieceID = pieceID
                outbox[index].archiveSnapshot?.pieceID = pieceID
            }
            for index in archiveEntries.indices where archiveEntries[index].pieceID == localID {
                archiveEntries[index].pieceID = pieceID
            }
            rebuildDateIndex()
        }
        let id = ensurePiece(on: scheduledDate, pieceID: pieceID, position: position)
        guard var piece = pieces[id], piece.scheduledDate == scheduledDate else { throw DayTransitionError.mismatchedRevision }
        piece.bind(to: id, position: position ?? piece.position)
        pieces[id] = piece
        cardProjections[id] = nil
        rebuildDateIndex()
        return id
    }

    private func incomingPieceID(_ package: GeneratedDailyCardDraft, pieceID: UUID?, position: Int? = nil) throws -> UUID {
        if let pieceID = pieceID ?? package.pieceID {
            guard package.pieceID == nil || package.pieceID == pieceID else { throw DayTransitionError.mismatchedRevision }
            if package.pieceID == nil, let existing = pieces[pieceID] {
                guard existing.scheduledDate == package.scheduledDate else { throw DayTransitionError.mismatchedRevision }
                return pieceID
            }
            return try bindServerPiece(pieceID, revisionID: package.id, scheduledDate: package.scheduledDate, position: position)
        }
        if let existing = piece(revisionID: package.id) { return existing.identity.pieceID }
        let id = ensurePiece(on: package.scheduledDate, requiresServerBinding: true)
        if pieces[id]?.revision == nil { pieces[id]?.requireServerBinding() }
        return id
    }

    func receive(_ package: GeneratedDailyCardDraft, pieceID: UUID? = nil, completion: CompletionState? = nil, updatedAt: String? = nil, readVersion: Int? = nil, authoritativeDecision: Bool = false) throws {
        let id = try incomingPieceID(package, pieceID: pieceID)
        if let readVersion, changed(pieceID: id, since: readVersion) { return }
        let localDecision = pieces[id]?.revision
        let pending = outbox.last { $0.kind == .decide && $0.revisionID == package.id && $0.pieceID == id }
        let keepsDecision = localDecision?.id == package.id && !authoritativeDecision
            && DayPackageLifecycleStatus.requiresOverwriteConfirmation(package.status)
        let resolvedCompletion = pending?.decision?.completionState
            ?? (keepsDecision ? localDecision?.decision?.completionState : completion ?? CompletionState(supabaseStatus: package.status))
        try transition(.reconcile(package, resolvedCompletion, updatedAt), pieceID: id)
    }

    func receivePublished(_ card: DailyCard, readVersion: Int? = nil) throws {
        guard card.scheduledDate != nil else { throw DayTransitionError.mismatchedRevision }
        var package = GeneratedDailyCardDraft(fromPublishedCard: card)
        let id = try incomingPieceID(package, pieceID: card.pieceID)
        if let existing = pieces[id]?.revision, existing.id == card.id {
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
        try receive(package, pieceID: id, completion: card.completionState, readVersion: readVersion, authoritativeDecision: true)
    }

    func reconcile(_ rows: [SupabaseCreatorDayRow], today: String, readVersion: Int, removeMissingToday: Bool = true) throws {
        for row in rows {
            if let card = row.revision {
                guard card.workspaceID == context.workspaceID, card.creatorID == context.creatorID,
                      card.scheduledDate == row.scheduledDate, card.id == row.currentRevisionID else { throw DayTransitionError.mismatchedRevision }
            }
            let serverID = row.pieceID ?? row.revision?.pieceID ?? row.generation?.pieceID
            let id: UUID
            if let serverID {
                guard row.revision?.pieceID == nil || row.revision?.pieceID == serverID,
                      row.generation?.pieceID == nil || row.generation?.pieceID == serverID else { throw DayTransitionError.mismatchedRevision }
                id = try bindServerPiece(serverID, revisionID: row.currentRevisionID, scheduledDate: row.scheduledDate, position: row.position, generationID: row.generation?.generationID)
            } else {
                id = ensurePiece(on: row.scheduledDate, requiresServerBinding: true)
            }
            if changed(pieceID: id, since: readVersion) { continue }
            if let card = row.revision {
                guard card.workspaceID == context.workspaceID, card.creatorID == context.creatorID,
                      card.scheduledDate == row.scheduledDate, card.id == row.currentRevisionID else {
                    throw DayTransitionError.mismatchedRevision
                }
                try receive(card.generatedDailyCardDraft(), pieceID: id, completion: CompletionState(supabaseStatus: card.status), updatedAt: row.updatedAt, authoritativeDecision: true)
            } else if row.currentRevisionID == nil {
                try transition(.removed, pieceID: id)
            } else {
                throw DayTransitionError.mismatchedRevision
            }
            if let run = row.generation {
                for index in outbox.indices where outbox[index].isGeneration {
                    let intent = outbox[index]
                    let matches = intent.pieceID.map { $0 == id }
                        ?? (intent.scheduledDate == row.scheduledDate && row.currentRevisionID.map { revisionID in
                            ([intent.revisionID] + [intent.priorRevisionID, intent.generatedRevisionID].compactMap { $0 }).contains(revisionID)
                        } == true)
                    guard matches else { continue }
                    if run.idempotencyKey == intent.id || run.generationID == intent.generationID {
                        outbox[index].generationID = run.generationID
                        if run.status == "completed" { outbox[index].generatedRevisionID = row.currentRevisionID }
                    } else if run.idempotencyKey != nil,
                              intent.generationID != nil || row.currentRevisionID != nil && row.currentRevisionID != intent.priorRevisionID {
                        outbox[index].supersededByServer = true
                    }
                }
                if run.status == "running" {
                    let requestID = outbox.first { $0.pieceID == id && $0.generationID == run.generationID }?.requestedRevisionID ?? run.generationID
                    try transition(.generate(DayGenerationRun(requestID: requestID, generationID: run.generationID), replacing: true), pieceID: id)
                }
            }
        }
        if removeMissingToday, !rows.contains(where: { $0.scheduledDate == today && ($0.position ?? 0) == 0 }), !changed(today, since: readVersion) {
            try transition(.removed, on: today)
        }
    }

    func retainPendingCard(_ card: DailyCard, pieceID: UUID? = nil) throws {
        guard let date = card.scheduledDate else { throw DayTransitionError.mismatchedRevision }
        let id = pieceID ?? piece(revisionID: card.id)?.identity.pieceID ?? ensurePiece(on: date, requiresServerBinding: true)
        if let current = pieces[id]?.revision, current.id != card.id {
            try transition(.retain(GeneratedDailyCardDraft(fromPublishedCard: card), card.completionState), pieceID: id)
        } else if self.card(revisionID: card.id) == nil {
            try receive(GeneratedDailyCardDraft(fromPublishedCard: card), pieceID: id, completion: card.completionState)
        }
    }

    func updatePackage(on date: String, revisionID: UUID, patch: ReadyDayPackageUpdate, title: String?, caption: String?) throws {
        guard let piece = piece(revisionID: revisionID), piece.scheduledDate == date,
              var content = piece.revision?.content, content.id == revisionID else { throw DayTransitionError.mismatchedRevision }
        if let value = title ?? patch.title { content.title = value }
        if let value = patch.whyToday { content.whyToday = value }
        if let value = caption ?? patch.caption { content.caption = value }
        let patch = patch.owningShotLines(in: content)
        if let value = patch.script { content.script = value }
        if let value = patch.backupStory { content.backupStory = value }
        if let value = patch.backupCaptionOnly { content.backupCaptionOnly = value }
        if let value = patch.shootability { content.shootability = value }
        if let value = patch.estimatedShootMinutes { content.estimatedShootMinutes = value }
        if let value = patch.sceneList {
            content.sceneList = value
            content.shotContentOwned = true
        }
        content.normalizeShotContent()
        try transition(.edit(content), pieceID: piece.identity.pieceID)
    }

    func updateThumbnails(_ assets: [StoryboardThumbnailAsset], revisionID: UUID) throws {
        guard let piece = piece(revisionID: revisionID), var content = piece.revision?.content, content.id == revisionID else { throw DayTransitionError.mismatchedRevision }
        content.storyboardThumbnailAssets = assets
        try transition(.edit(content), pieceID: piece.identity.pieceID)
    }

    func mergeArchive(_ entries: [ArchiveEntry], authoritative: Bool = false) {
        for incoming in entries {
            if let pieceID = incoming.pieceID, let revisionID = incoming.dailyCardID,
               let local = piece(revisionID: revisionID), local.requiresServerBinding {
                _ = try? bindServerPiece(pieceID, revisionID: revisionID, scheduledDate: local.scheduledDate)
            }
            var entry = incoming
            if let pending = outbox.last(where: { $0.kind == .decide && $0.revisionID == entry.dailyCardID }),
               let snapshot = pending.archiveSnapshot, entry.decision != snapshot.decision {
                entry = ArchiveEntry(
                    id: incoming.id, dailyCardID: incoming.dailyCardID, day: incoming.day, date: incoming.date,
                    cardTitle: incoming.cardTitle, decision: snapshot.decision,
                    outputLine: snapshot.outputLine, hasPostThumbnail: snapshot.hasPostThumbnail
                )
                entry.pieceID = incoming.pieceID
                entry.captionSnapshot = incoming.captionSnapshot
                entry.scheduledDate = incoming.scheduledDate
                entry.decisionAt = snapshot.decisionAt
            }
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
                mergedEntry.pieceID = entry.pieceID ?? archiveEntries[index].pieceID
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
    static let currentSchemaVersion = 4
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
                ?? dayStore?.pieces.compactMap(\.revision).first { $0.id == id }?.dailyCard
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
            dayStore.migrateIntentPieces(for: context)
            return dayStore
        }
        var days: [String: Piece] = [:]
        for card in weekCards + [todayCard].compactMap({ $0 }) {
            guard let date = card.scheduledDate else { continue }
            var day = days[date] ?? Piece(identity: PieceIdentity(workspaceID: context.workspaceID, creatorID: context.creatorID, pieceID: card.pieceID ?? UUID()), scheduledDate: date, requiresServerBinding: card.pieceID == nil)
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
        var snapshot = DayStoreSnapshot(pieces: Array(days.values))
        migrateDecision(into: &snapshot, context: context)
        snapshot.migrateIntentPieces(for: context)
        return snapshot
    }
    private func migrateDecision(into snapshot: inout DayStoreSnapshot, context: WorkspaceContext) {
        guard let legacyDecision else { return }
        let card = legacyDecision.card ?? snapshot.pieces.compactMap(\.revision).first { $0.id == legacyDecision.cardID }?.dailyCard
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
    func clearSnapshot(for context: WorkspaceContext) throws
    @MainActor func saveSnapshotInBackground(_ snapshot: CachedTodaySnapshot, for context: WorkspaceContext) async throws
}

struct FileTodayCacheStore: TodayCacheStoring, Sendable {
    private static let fileQueue = DispatchQueue(label: "contenthelper.today-cache", qos: .userInitiated)
    private let baseDirectory: URL?

    init(baseDirectory: URL? = nil) { self.baseDirectory = baseDirectory }

    func loadSnapshot(for context: WorkspaceContext) throws -> CachedTodaySnapshot? {
        try Self.fileQueue.sync { try loadSnapshotOnFileQueue(for: context) }
    }

    private func loadSnapshotOnFileQueue(for context: WorkspaceContext) throws -> CachedTodaySnapshot? {
        let url = try fileURL(for: context)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot: CachedTodaySnapshot
        do {
            snapshot = try decoder.decode(CachedTodaySnapshot.self, from: data)
        } catch {
            let preservedURL = url.deletingPathExtension().appendingPathExtension("unreadable-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: url, to: preservedURL)
            throw error
        }
        if snapshot.schemaVersion < CachedTodaySnapshot.currentSchemaVersion {
            let recoveryURL = url.deletingPathExtension().appendingPathExtension("migration-recovery.json")
            if !FileManager.default.fileExists(atPath: recoveryURL.path) {
                try FileManager.default.copyItem(at: url, to: recoveryURL)
            }
        }
        return snapshot
    }

    @MainActor
    func saveSnapshotInBackground(_ snapshot: CachedTodaySnapshot, for context: WorkspaceContext) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Self.fileQueue.async {
                do {
                    try saveSnapshotOnFileQueue(snapshot, for: context)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func saveSnapshot(_ snapshot: CachedTodaySnapshot, for context: WorkspaceContext) throws {
        try Self.fileQueue.sync { try saveSnapshotOnFileQueue(snapshot, for: context) }
    }

    private func saveSnapshotOnFileQueue(_ snapshot: CachedTodaySnapshot, for context: WorkspaceContext) throws {
        let directory = try directoryURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existingURL = try fileURL(for: context)
        if FileManager.default.fileExists(atPath: existingURL.path) {
            do { _ = try loadSnapshotOnFileQueue(for: context) }
            catch {
                if FileManager.default.fileExists(atPath: existingURL.path) { throw error }
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: existingURL, options: .atomic)
        if snapshot.schemaVersion == CachedTodaySnapshot.currentSchemaVersion {
            let recoveryURL = existingURL.deletingPathExtension().appendingPathExtension("migration-recovery.json")
            if FileManager.default.fileExists(atPath: recoveryURL.path) {
                try? FileManager.default.removeItem(at: recoveryURL)
            }
        }
    }

    func clearSnapshot(for context: WorkspaceContext) throws {
        try Self.fileQueue.sync { try clearSnapshotOnFileQueue(for: context) }
    }

    private func clearSnapshotOnFileQueue(for context: WorkspaceContext) throws {
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
