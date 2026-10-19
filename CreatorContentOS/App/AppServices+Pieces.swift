import Foundation

enum PieceDraftCreationError: LocalizedError, Equatable {
    case dateHasAIDraft
    case pastDate
    case voiceRequired
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .dateHasAIDraft:
            "This date already has an AI draft. For now AI can create one draft per date. You can write this one yourself."
        case .pastDate:
            "AI drafts are available for today and later dates. You can write this one yourself."
        case .voiceRequired:
            "Set up your voice in You before creating AI drafts. You can write this one yourself."
        case .generationFailed(let message):
            message
        }
    }
}

extension PieceContent {
    init(package card: GeneratedDailyCardDraft) {
        let rows = GeneratedStoryboardBreakdown.rows(for: card)
        let count = max(card.sceneList.count, rows.count)
        let shots: [PieceShot] = (0..<count).map { index in
            let scene = card.sceneList[safe: index]
            let row = rows[safe: index]
            let title = scene?.title.nilIfBlank ?? row?.visualShot.nilIfBlank ?? "Shot \(index + 1)"
            let direction = PieceContent.meaningful(row?.whatToShow, excluding: [title, "Show the main action clearly."])
            let line = PieceContent.meaningful(row?.audioDialogue, excluding: ["No voiceover specified."])
            return PieceShot(
                id: scene?.id ?? UUID(),
                title: title,
                direction: direction,
                line: line,
                durationSeconds: PieceContent.seconds(from: scene?.duration),
                previewURL: row?.thumbnailURL
            )
        }
        let hashtags = card.hashtags
            .compactMap(\.nilIfBlank)
            .map { $0.hasPrefix("#") ? $0 : "#\($0)" }
            .joined(separator: " ")
        self.init(
            title: card.title,
            format: PieceFormat(legacyFormat: card.format, hasScenes: !card.sceneList.isEmpty),
            durationSeconds: card.durationSeconds,
            minutesToFilm: card.estimatedShootMinutes > 0 ? card.estimatedShootMinutes : nil,
            script: card.script,
            shots: shots,
            instagramCaption: card.caption,
            tiktokCaption: "",
            hashtags: hashtags,
            accessibilityNote: "",
            notes: card.postInstructions
        )
    }

    private static func meaningful(_ value: String?, excluding: [String]) -> String {
        guard let value = value?.nilIfBlank, !excluding.contains(value) else { return "" }
        return value
    }

    private static func seconds(from duration: String?) -> Int? {
        guard let duration else { return nil }
        let digits = duration.prefix { $0.isNumber }
        return Int(digits)
    }
}

extension AppServices {
    func syncPiecesWithDayPackages() {
        if case .ready = todayContentState, isImportableTodayCard {
            importDayPackage(
                GeneratedDailyCardDraft(fromPublishedCard: todayShootFolioCard),
                approved: true,
                legacyShotSceneIDs: shotSceneIDs,
                legacyCompletion: todayCard.completionState
            )
        }
        for package in dayBriefGeneratedCards.values {
            importDayPackage(
                package,
                approved: DayPackageLifecycleStatus.requiresOverwriteConfirmation(package.status)
            )
        }
    }

    func syncPiecesWithDayPackage(on date: String) {
        guard let package = dayPackage(for: date) else { return }
        importDayPackage(package, approved: DayPackageLifecycleStatus.requiresOverwriteConfirmation(package.status))
    }

    private var isImportableTodayCard: Bool {
        let title = todayCard.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != "Checking today's plan" else { return false }
        return !todayCard.scenes.isEmpty || todayCard.isNonFilmingPost || todayCard.script?.nilIfBlank != nil
    }

    @discardableResult
    private func importDayPackage(
        _ package: GeneratedDailyCardDraft,
        approved: Bool,
        legacyShotSceneIDs: Set<UUID> = [],
        legacyCompletion: CompletionState? = nil
    ) -> ContentPiece? {
        if let existing = pieceStore.piece(linkedTo: package.id) {
            if approved && !existing.isApproved && existing.versions.count == 1 {
                pieceStore.update { library, now in
                    library.markReviewed(existing.id, now: now)
                    library.approve([existing.id], now: now)
                }
            }
            return pieceStore.piece(existing.id)
        }
        let date = package.scheduledDate.nilIfBlank ?? currentTodayDateString
        let content = PieceContent(package: package)
        let replaceable = pieceStore.pieces(on: date).first { piece in
            piece.linkedDailyCardID != nil
                && piece.versions.count == 1
                && piece.captures.isEmpty
                && piece.postings.isEmpty
                && piece.markedShotAt == nil
                && piece.currentVersion.origin == .imported
        }
        let pieceID: UUID
        if let replaceable {
            pieceID = replaceable.id
            pieceStore.update { library, now in
                try library.replaceUntouchedContent(
                    replaceable.id,
                    with: content,
                    linkedDailyCardID: package.id,
                    approved: approved,
                    now: now
                )
            }
        } else {
            pieceID = pieceStore.addPiece(
                date: date,
                content: content,
                origin: .imported,
                approved: approved,
                linkedDailyCardID: package.id
            ).id
        }
        let capturedIDs = content.shots.map(\.id).filter { legacyShotSceneIDs.contains($0) }
        pieceStore.update { library, now in
            for shotID in capturedIDs {
                try library.markCaptured(pieceID, shotID: shotID, now: now)
            }
            if legacyCompletion == .shot || legacyCompletion == .posted {
                try? library.markShot(pieceID, now: now)
            }
            if legacyCompletion == .posted {
                try library.recordUnspecifiedPostedMark(pieceID, now: now)
            }
        }
        return pieceStore.piece(pieceID)
    }

    func createAIPiece(
        date: String,
        topic: String,
        format: PieceFormat,
        minutesToFilm: Int,
        keepItSimple: Bool
    ) async throws -> ContentPiece {
        guard !SupabaseDateFormatting.isDatePast(date, todayString: currentTodayDateString) else {
            throw PieceDraftCreationError.pastDate
        }
        guard dayPackage(for: date) == nil else {
            throw PieceDraftCreationError.dateHasAIDraft
        }
        guard canGenerateContent else {
            throw PieceDraftCreationError.voiceRequired
        }
        var brief = "\(topic). Format: \(format.title). Time to film: about \(minutesToFilm) minutes."
        if keepItSimple {
            brief += " Keep it easy to film with what is at hand."
        }
        let package: GeneratedDailyCardDraft
        do {
            package = try await generateDayCard(scheduledDate: date, dayBrief: brief)
        } catch {
            let message = dayBriefGenerationErrors[date]?.nilIfBlank
                ?? error.localizedDescription.nilIfBlank
                ?? "We could not create a draft."
            throw PieceDraftCreationError.generationFailed(message)
        }
        guard let piece = importDayPackage(package, approved: false) else {
            throw PieceDraftCreationError.generationFailed("We could not create a draft.")
        }
        pieceStore.update { library, now in
            guard let index = library.pieces.firstIndex(where: { $0.id == piece.id }) else { return }
            library.pieces[index].topic = topic
            if let versionIndex = library.pieces[index].versions.indices.first {
                library.pieces[index].versions[versionIndex].content.format = format
                library.pieces[index].versions[versionIndex].origin = .generated
                if library.pieces[index].versions[versionIndex].content.minutesToFilm == nil {
                    library.pieces[index].versions[versionIndex].content.minutesToFilm = minutesToFilm
                }
            }
        }
        return pieceStore.piece(piece.id) ?? piece
    }

    func approvePieces(_ ids: [UUID]) {
        pieceStore.update { library, now in
            library.approve(ids, now: now)
        }
        let linkedDraftDates = ids.compactMap { id -> String? in
            guard let piece = pieceStore.piece(id),
                  let cardID = piece.linkedDailyCardID,
                  let package = dayPackage(for: piece.date),
                  package.id == cardID,
                  DayPackageLifecycleStatus.isDraftPackage(package.status),
                  !SupabaseDateFormatting.isDatePast(piece.date, todayString: currentTodayDateString)
            else { return nil }
            return piece.date
        }
        let count = ids.count
        lastActionMessage = count == 1 ? "Approved. A version is saved." : "\(count) pieces approved."
        guard !linkedDraftDates.isEmpty else { return }
        Task { @MainActor in
            for date in Set(linkedDraftDates) {
                _ = try? await makeDayAvailable(scheduledDate: date)
            }
        }
    }

    func markPieceShot(_ id: UUID) -> Bool {
        let succeeded = pieceStore.update { library, now in
            try library.markShot(id, now: now)
        }
        if succeeded, isLinkedToTodayCard(id), todayCard.completionState == nil {
            completeToday(with: DailyDecision.shot)
        }
        return succeeded
    }

    func recordPiecePosting(_ id: UUID, platform: PiecePlatform, link: String?) {
        pieceStore.update { library, now in
            try library.recordPosting(id, platform: platform, state: .markedByYou, link: link, now: now)
        }
        if isLinkedToTodayCard(id), todayCard.completionState != .posted {
            completeToday(with: DailyDecision.posted)
        }
    }

    private func isLinkedToTodayCard(_ id: UUID) -> Bool {
        guard let linked = pieceStore.piece(id)?.linkedDailyCardID else { return false }
        return linked == todayCard.id
    }
}
