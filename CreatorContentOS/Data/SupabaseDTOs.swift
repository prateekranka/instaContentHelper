import Foundation

enum SupabaseJSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: SupabaseJSONValue])
    case array([SupabaseJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SupabaseJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: SupabaseJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var displayText: String? {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value):
            value ? "Yes" : "No"
        case .object(let value):
            ["title", "name", "summary", "note", "value", "line", "instructions", "audio_option_notes"].compactMap { key in
                value[key]?.displayText
            }.first
        case .array(let value):
            value.compactMap(\.displayText).prefix(3).joined(separator: ", ")
        case .null:
            nil
        }
    }

    var audioOptionNotes: String? {
        if case .object(let value) = self {
            return value["audio_option_notes"]?.displayText
                ?? value["audio"]?.displayText
        }
        return nil
    }
}

struct SupabaseShotSceneDTO: Codable, Hashable, Sendable {
    var number: Int?
    var title: String?
    var duration: String?
    var symbol: String?

    func domainScene(fallbackNumber: Int) -> ShotScene {
        ShotScene(
            number: number ?? fallbackNumber,
            title: title ?? "Shot \(fallbackNumber)",
            duration: duration ?? "3 sec",
            symbol: symbol ?? "circle"
        )
    }
}

struct SupabaseDailyCardRow: Codable, Hashable, Sendable {
    var id: UUID
    var workspaceID: UUID
    var creatorID: UUID
    var weeklyPlanID: UUID
    var originIdeaID: UUID?
    var brandBriefID: UUID?
    var keyMomentID: UUID?
    var scheduledDate: String
    var status: String
    var title: String
    var whyToday: String?
    var growthJob: String?
    var contentPillar: String?
    var shootability: String?
    var estimatedShootMinutes: Int?
    var energyRequired: String?
    var languageMode: String?
    var sceneList: [SupabaseShotSceneDTO]
    var script: String?
    var noVoiceoverVersion: String?
    var onScreenText: [SupabaseJSONValue]?
    var caption: String?
    var cta: String?
    var hashtags: [String]
    var coverText: String?
    var postInstructions: SupabaseJSONValue?
    var brandEventNotes: String?
    var backupStory: SupabaseJSONValue?
    var backupCaptionOnly: SupabaseJSONValue?
    var audioOptionID: UUID?
    var audioFallbackID: UUID?
    var creatorFitScore: Double?
    var riskNotes: [SupabaseJSONValue]?
    var assumptions: [SupabaseJSONValue]?
    var sourceNote: String?
    var decisionAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case creatorID = "creator_id"
        case weeklyPlanID = "weekly_plan_id"
        case originIdeaID = "origin_idea_id"
        case brandBriefID = "brand_brief_id"
        case keyMomentID = "key_moment_id"
        case scheduledDate = "scheduled_date"
        case status
        case title
        case whyToday = "why_today"
        case growthJob = "growth_job"
        case contentPillar = "content_pillar"
        case shootability
        case estimatedShootMinutes = "estimated_shoot_minutes"
        case energyRequired = "energy_required"
        case languageMode = "language_mode"
        case sceneList = "scene_list"
        case script
        case noVoiceoverVersion = "no_voiceover_version"
        case onScreenText = "on_screen_text"
        case caption
        case cta
        case hashtags
        case coverText = "cover_text"
        case postInstructions = "post_instructions"
        case brandEventNotes = "brand_event_notes"
        case backupStory = "backup_story"
        case backupCaptionOnly = "backup_caption_only"
        case audioOptionID = "audio_option_id"
        case audioFallbackID = "audio_fallback_id"
        case creatorFitScore = "creator_fit_score"
        case riskNotes = "risk_notes"
        case assumptions
        case sourceNote = "source_note"
        case decisionAt = "decision_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workspaceID = try container.decode(UUID.self, forKey: .workspaceID)
        creatorID = try container.decode(UUID.self, forKey: .creatorID)
        weeklyPlanID = try container.decode(UUID.self, forKey: .weeklyPlanID)
        originIdeaID = try container.decodeIfPresent(UUID.self, forKey: .originIdeaID)
        brandBriefID = try container.decodeIfPresent(UUID.self, forKey: .brandBriefID)
        keyMomentID = try container.decodeIfPresent(UUID.self, forKey: .keyMomentID)
        scheduledDate = try container.decode(String.self, forKey: .scheduledDate)
        status = try container.decode(String.self, forKey: .status)
        title = try container.decode(String.self, forKey: .title)
        whyToday = try container.decodeIfPresent(String.self, forKey: .whyToday)
        growthJob = try container.decodeIfPresent(String.self, forKey: .growthJob)
        contentPillar = try container.decodeIfPresent(String.self, forKey: .contentPillar)
        shootability = try container.decodeIfPresent(String.self, forKey: .shootability)
        estimatedShootMinutes = try container.decodeIfPresent(Int.self, forKey: .estimatedShootMinutes)
        energyRequired = try container.decodeIfPresent(String.self, forKey: .energyRequired)
        languageMode = try container.decodeIfPresent(String.self, forKey: .languageMode)
        sceneList = (try? container.decode([SupabaseShotSceneDTO].self, forKey: .sceneList)) ?? []
        script = try container.decodeIfPresent(String.self, forKey: .script)
        noVoiceoverVersion = try container.decodeIfPresent(String.self, forKey: .noVoiceoverVersion)
        onScreenText = try container.decodeIfPresent([SupabaseJSONValue].self, forKey: .onScreenText)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        cta = try container.decodeIfPresent(String.self, forKey: .cta)
        hashtags = (try? container.decode([String].self, forKey: .hashtags)) ?? []
        coverText = try container.decodeIfPresent(String.self, forKey: .coverText)
        postInstructions = try container.decodeIfPresent(SupabaseJSONValue.self, forKey: .postInstructions)
        brandEventNotes = try container.decodeIfPresent(String.self, forKey: .brandEventNotes)
        backupStory = try container.decodeIfPresent(SupabaseJSONValue.self, forKey: .backupStory)
        backupCaptionOnly = try container.decodeIfPresent(SupabaseJSONValue.self, forKey: .backupCaptionOnly)
        audioOptionID = try container.decodeIfPresent(UUID.self, forKey: .audioOptionID)
        audioFallbackID = try container.decodeIfPresent(UUID.self, forKey: .audioFallbackID)
        creatorFitScore = try container.decodeIfPresent(Double.self, forKey: .creatorFitScore)
        riskNotes = try container.decodeIfPresent([SupabaseJSONValue].self, forKey: .riskNotes)
        assumptions = try container.decodeIfPresent([SupabaseJSONValue].self, forKey: .assumptions)
        sourceNote = try container.decodeIfPresent(String.self, forKey: .sourceNote)
        decisionAt = try container.decodeIfPresent(String.self, forKey: .decisionAt)
    }

    func domainCard() -> DailyCard {
        DailyCard(
            id: id,
            title: title,
            context: SupabaseDateFormatting.contextLine(for: scheduledDate),
            effortLabel: SupabaseDateFormatting.effortLabel(
                shootability: shootability,
                minutes: estimatedShootMinutes
            ),
            whyToday: whyToday ?? growthJob ?? "Prepared for today.",
            sourceNote: sourceNote ?? contentPillar,
            scheduledDate: scheduledDate,
            scenes: sceneList.enumerated().map { index, scene in
                scene.domainScene(fallbackNumber: index + 1)
            },
            completionState: CompletionState(supabaseStatus: status),
            script: script,
            noVoiceoverVersion: noVoiceoverVersion,
            onScreenText: onScreenText?.compactMap(\.displayText),
            caption: caption,
            cta: cta,
            hashtags: hashtags,
            coverText: coverText,
            postInstructions: postInstructions?.displayText,
            brandEventNotes: brandEventNotes,
            backupStory: backupStory?.displayText,
            backupCaptionOnly: backupCaptionOnly?.displayText,
            audioOptionNotes: postInstructions?.audioOptionNotes,
            creatorFitScore: creatorFitScore,
            riskNotes: riskNotes?.compactMap(\.displayText),
            assumptions: assumptions?.compactMap(\.displayText)
        )
    }

    func weeklyDay() -> WeeklyDay {
        WeeklyDay(
            weekday: SupabaseDateFormatting.weekdayAbbreviation(for: scheduledDate),
            date: SupabaseDateFormatting.dayNumber(for: scheduledDate),
            scheduledDate: scheduledDate,
            title: title,
            reason: whyToday ?? sourceNote ?? "Prepared for this day.",
            source: WeeklySourceReason(sourceNote: sourceNote, contentPillar: contentPillar),
            state: WeeklyDayState(dailyCardStatus: status),
            isSoftLocked: status != "draft"
        )
    }
}

struct SupabaseWeeklyPlanRow: Codable, Hashable, Sendable {
    var id: UUID
    var workspaceID: UUID
    var creatorID: UUID
    var weeklySetupID: UUID?
    var creatorProfileID: UUID?
    var weekStartDate: String
    var status: String
    var strategySummary: String?
    var warnings: [SupabaseJSONValue]
    var assumptions: [SupabaseJSONValue]
    var isSoftLocked: Bool
    var publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case workspaceID = "workspace_id"
        case creatorID = "creator_id"
        case weeklySetupID = "weekly_setup_id"
        case creatorProfileID = "creator_profile_id"
        case weekStartDate = "week_start_date"
        case status
        case strategySummary = "strategy_summary"
        case warnings
        case assumptions
        case isSoftLocked = "is_soft_locked"
        case publishedAt = "published_at"
    }
}

struct SupabaseWeeklySetupRow: Codable, Hashable, Sendable {
    var id: UUID
    var location: String?
    var workoutRaceSchedule: [SupabaseJSONValue]
    var familyTravelMoments: [SupabaseJSONValue]
    var energyConstraints: [SupabaseJSONValue]
    var shootingConstraints: [SupabaseJSONValue]
    var noGoTopics: [SupabaseJSONValue]
    var selectedSources: [SupabaseJSONValue]
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case location
        case workoutRaceSchedule = "workout_race_schedule"
        case familyTravelMoments = "family_travel_moments"
        case energyConstraints = "energy_constraints"
        case shootingConstraints = "shooting_constraints"
        case noGoTopics = "no_go_topics"
        case selectedSources = "selected_sources"
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        workoutRaceSchedule = (try? container.decode([SupabaseJSONValue].self, forKey: .workoutRaceSchedule)) ?? []
        familyTravelMoments = (try? container.decode([SupabaseJSONValue].self, forKey: .familyTravelMoments)) ?? []
        energyConstraints = (try? container.decode([SupabaseJSONValue].self, forKey: .energyConstraints)) ?? []
        shootingConstraints = (try? container.decode([SupabaseJSONValue].self, forKey: .shootingConstraints)) ?? []
        noGoTopics = (try? container.decode([SupabaseJSONValue].self, forKey: .noGoTopics)) ?? []
        selectedSources = (try? container.decode([SupabaseJSONValue].self, forKey: .selectedSources)) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    var setupSections: [WeeklySetupSection] {
        [
            WeeklySetupSection(systemImage: "mappin.and.ellipse", title: "Place", summary: location ?? "No location set.", state: location == nil ? "Needs detail" : "Ready"),
            WeeklySetupSection(systemImage: "dumbbell", title: "Body", summary: SupabaseDateFormatting.summaryText(workoutRaceSchedule, fallback: "No workout schedule set."), state: workoutRaceSchedule.isEmpty ? "Needs detail" : "Ready"),
            WeeklySetupSection(systemImage: "person.2", title: "Family", summary: SupabaseDateFormatting.summaryText(familyTravelMoments, fallback: "No family or travel moments set."), state: familyTravelMoments.isEmpty ? "Open" : "Ready"),
            WeeklySetupSection(systemImage: "bolt.heart", title: "Constraints", summary: SupabaseDateFormatting.summaryText(energyConstraints + shootingConstraints, fallback: "No special constraints."), state: "Ready"),
            WeeklySetupSection(systemImage: "waveform.path.ecg", title: "Source pulse", summary: SupabaseDateFormatting.summaryText(selectedSources, fallback: "No trends/audio selected."), state: selectedSources.isEmpty ? "Needs detail" : "Ready"),
            WeeklySetupSection(systemImage: "nosign", title: "Boundaries", summary: SupabaseDateFormatting.summaryText(noGoTopics, fallback: "No extra no-go topics."), state: "Ready")
        ]
    }
}

struct SupabaseIdeaRow: Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var summary: String?
    var suggestedUse: String?
    var shootability: String?
    var status: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case suggestedUse = "suggested_use"
        case shootability
        case status
    }

    func domainIdea() -> WeeklyIdea {
        WeeklyIdea(
            id: id,
            title: title,
            reason: summary ?? suggestedUse ?? "Saved for future use.",
            source: .pattern,
            effortLabel: shootability ?? "Easy",
            selectedDay: status == "scheduled" ? "Set" : nil
        )
    }
}

struct SupabaseSourceReferenceRow: Codable, Hashable, Sendable {
    var id: UUID
    var sourceType: String
    var sourceURL: String?
    var storagePath: String?
    var manualNotes: String?
    var status: String
    var analysisConfidence: Double?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sourceType = "source_type"
        case sourceURL = "source_url"
        case storagePath = "storage_path"
        case manualNotes = "manual_notes"
        case status
        case analysisConfidence = "analysis_confidence"
        case createdAt = "created_at"
    }

    func referenceSummary() -> ReferenceSummary {
        ReferenceSummary(
            id: id,
            title: manualNotes?.nilIfBlank ?? sourceURL?.nilIfBlank ?? sourceType.displayTitle,
            sourceType: sourceType.displayTitle,
            note: status.displayTitle,
            state: IntelligenceReviewState(referenceStatus: status),
            symbol: sourceType.referenceSymbol,
            sourceURL: sourceURL
        )
    }

    func reviewItem() -> IntelligenceItem {
        IntelligenceItem(
            id: id,
            title: manualNotes?.nilIfBlank ?? sourceURL?.nilIfBlank ?? "Imported reference",
            subtitle: sourceURL?.nilIfBlank ?? "Imported row needs a decision.",
            kind: .watchlist,
            state: IntelligenceReviewState(referenceStatus: status),
            trailingNote: ReferenceImportTypeChip(sourceType: sourceType).rawValue,
            symbol: sourceType.referenceSymbol,
            typeChip: ReferenceImportTypeChip(sourceType: sourceType),
            sourceURL: sourceURL,
            reviewItem: ReferenceReviewItem(kind: .sourceReference, id: id),
            sortKey: createdAt
        )
    }
}

struct SupabaseBenchmarkCreatorRow: Codable, Hashable, Sendable {
    var id: UUID
    var handle: String?
    var displayName: String?
    var platform: String?
    var region: String?
    var relevanceNotes: String?
    var status: String
    var normalizedHandle: String?
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
        case platform
        case region
        case relevanceNotes = "relevance_notes"
        case status
        case normalizedHandle = "normalized_handle"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func reviewItem() -> IntelligenceItem {
        let displayHandle = handle?.nilIfBlank
            ?? normalizedHandle.map { "@\($0)" }
            ?? displayName?.nilIfBlank
            ?? "Reference creator"

        return IntelligenceItem(
            id: id,
            title: displayName?.nilIfBlank ?? displayHandle,
            subtitle: relevanceNotes?.nilIfBlank ?? region?.nilIfBlank ?? "Candidate inspiration account.",
            kind: .watchlist,
            state: IntelligenceReviewState(benchmarkCreatorStatus: status),
            trailingNote: "Account",
            symbol: "at",
            typeChip: .account,
            sourceURL: normalizedHandle.map { "https://www.instagram.com/\($0)" },
            reviewItem: ReferenceReviewItem(kind: .benchmarkCreator, id: id),
            sortKey: updatedAt ?? createdAt
        )
    }
}

struct SupabasePatternRow: Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var patternType: String?
    var summary: String?
    var status: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case patternType = "pattern_type"
        case summary
        case status
    }

    func intelligenceItem() -> IntelligenceItem {
        IntelligenceItem(
            id: id,
            title: title,
            subtitle: summary ?? patternType ?? "Pattern",
            kind: .pattern,
            state: IntelligenceReviewState(sourceStatus: status),
            trailingNote: patternType ?? status.displayTitle,
            symbol: "sun.max"
        )
    }
}

struct SupabaseTrendRow: Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var summary: String?
    var status: String
    var timingRecommendation: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case status
        case timingRecommendation = "timing_recommendation"
    }

    func intelligenceItem() -> IntelligenceItem {
        IntelligenceItem(
            id: id,
            title: title,
            subtitle: summary ?? "Trend",
            kind: .trend,
            state: IntelligenceReviewState(sourceStatus: status),
            trailingNote: timingRecommendation ?? status.displayTitle,
            symbol: "sparkle.magnifyingglass"
        )
    }
}

struct SupabaseAudioOptionRow: Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var artistOrCreator: String?
    var availabilityConfidence: String?
    var verificationNote: String?
    var status: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case artistOrCreator = "artist_or_creator"
        case availabilityConfidence = "availability_confidence"
        case verificationNote = "verification_note"
        case status
    }

    func intelligenceItem() -> IntelligenceItem {
        IntelligenceItem(
            id: id,
            title: title,
            subtitle: artistOrCreator ?? verificationNote ?? "Audio",
            kind: .audio,
            state: IntelligenceReviewState(sourceStatus: status),
            trailingNote: availabilityConfidence?.displayTitle ?? status.displayTitle,
            symbol: "music.note"
        )
    }
}

struct SupabaseCreatorProfileRow: Codable, Hashable, Sendable {
    var displayName: String?
    var positioning: String?
    var voiceRules: [SupabaseJSONValue]
    var neverSay: [SupabaseJSONValue]

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case positioning
        case voiceRules = "voice_rules"
        case neverSay = "never_say"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        positioning = try container.decodeIfPresent(String.self, forKey: .positioning)
        voiceRules = (try? container.decode([SupabaseJSONValue].self, forKey: .voiceRules)) ?? []
        neverSay = (try? container.decode([SupabaseJSONValue].self, forKey: .neverSay)) ?? []
    }

    func summary() -> CreatorProfileSummary {
        CreatorProfileSummary(
            displayName: displayName ?? "Creator",
            positioning: positioning ?? "Creator profile active.",
            voiceLine: SupabaseDateFormatting.summaryText(voiceRules, fallback: "Voice rules are ready."),
            noGoTopics: neverSay.compactMap(\.displayText)
        )
    }
}

struct SupabaseArchiveEntryRow: Codable, Hashable, Sendable {
    struct DailyCardSummary: Codable, Hashable, Sendable {
        var title: String?
    }

    var id: UUID
    var dailyCardID: UUID?
    var archiveDate: String
    var decision: String
    var outputLine: String?
    var hasPostThumbnail: Bool
    var dailyCard: DailyCardSummary?

    enum CodingKeys: String, CodingKey {
        case id
        case dailyCardID = "daily_card_id"
        case archiveDate = "archive_date"
        case decision
        case outputLine = "output_line"
        case hasPostThumbnail = "has_post_thumbnail"
        case dailyCard = "daily_cards"
    }

    func domainEntry() -> ArchiveEntry {
        ArchiveEntry(
            id: id,
            dailyCardID: dailyCardID,
            day: SupabaseDateFormatting.weekdayAbbreviation(for: archiveDate),
            date: SupabaseDateFormatting.shortDate(for: archiveDate),
            cardTitle: dailyCard?.title ?? "Daily card",
            decision: CompletionState(supabaseStatus: decision) ?? .skippedIntentionally,
            outputLine: outputLine ?? decision.displayTitle,
            hasPostThumbnail: hasPostThumbnail
        )
    }
}

struct SupabaseDailyCardDecisionUpdate: Encodable, Sendable {
    var status: String
    var decisionAt: String
    var completedByMemberID: UUID

    enum CodingKeys: String, CodingKey {
        case status
        case decisionAt = "decision_at"
        case completedByMemberID = "completed_by_member_id"
    }
}

struct SupabaseArchiveEntryUpsert: Encodable, Sendable {
    var workspaceID: UUID
    var creatorID: UUID
    var dailyCardID: UUID
    var archiveDate: String
    var decision: String
    var outputLine: String
    var hasPostThumbnail: Bool

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case creatorID = "creator_id"
        case dailyCardID = "daily_card_id"
        case archiveDate = "archive_date"
        case decision
        case outputLine = "output_line"
        case hasPostThumbnail = "has_post_thumbnail"
    }
}

struct SupabasePublishWeekRequest: Encodable, Sendable {
    var creatorID: UUID
    var memberID: UUID
    var weeklyPlanID: UUID
    var weekStartDate: String
    var strategySummary: String
    var days: [SupabasePublishWeekDayRequest]?
    var draftDailyCards: [SupabaseDraftDailyCardPublishRequest]?

    enum CodingKeys: String, CodingKey {
        case creatorID = "creator_id"
        case memberID = "member_id"
        case weeklyPlanID = "weekly_plan_id"
        case weekStartDate = "week_start_date"
        case strategySummary = "strategy_summary"
        case days
        case draftDailyCards = "draft_daily_cards"
    }

    init(plan: WeeklyPlan, generatedDraft: GeneratedWeekDraft?, context: WorkspaceContext) {
        creatorID = context.creatorID
        memberID = context.memberID
        weeklyPlanID = plan.id
        weekStartDate = plan.weekStartDate
            ?? plan.days.compactMap(\.scheduledDate).first
            ?? SupabaseDateFormatting.todayDateString()
        strategySummary = generatedDraft?.strategySummary ?? plan.readinessSummary

        if let generatedDraft, generatedDraft.weeklyPlanID == plan.id {
            days = nil
            draftDailyCards = generatedDraft.dailyCards.map {
                SupabaseDraftDailyCardPublishRequest(card: $0)
            }
        } else {
            days = plan.days.map { SupabasePublishWeekDayRequest(day: $0) }
            draftDailyCards = nil
        }
    }
}

struct SupabasePublishWeekDayRequest: Encodable, Sendable {
    var id: UUID
    var scheduledDate: String
    var title: String
    var whyToday: String
    var source: String
    var state: String
    var shootability: String
    var estimatedShootMinutes: Int
    var sceneList: [SupabasePublishSceneRequest]

    enum CodingKeys: String, CodingKey {
        case id
        case scheduledDate = "scheduled_date"
        case title
        case whyToday = "why_today"
        case source
        case state
        case shootability
        case estimatedShootMinutes = "estimated_shoot_minutes"
        case sceneList = "scene_list"
    }

    init(day: WeeklyDay) {
        id = day.id
        scheduledDate = day.scheduledDate ?? SupabaseDateFormatting.todayDateString()
        title = day.title
        whyToday = day.reason
        source = day.source.rawValue.lowercased()
        state = day.state.rawValue
        shootability = switch day.state {
        case .planned: "easy"
        case .backup: "backup"
        case .open: "open"
        }
        estimatedShootMinutes = switch day.state {
        case .planned: 12
        case .backup: 8
        case .open: 0
        }
        sceneList = [
            SupabasePublishSceneRequest(number: 1, title: "Opening detail", duration: "3 sec", symbol: "sparkles"),
            SupabasePublishSceneRequest(number: 2, title: day.title, duration: "5 sec", symbol: "figure.run"),
            SupabasePublishSceneRequest(number: 3, title: "One useful takeaway", duration: "4 sec", symbol: "text.quote")
        ]
    }
}

struct SupabasePublishSceneRequest: Encodable, Sendable {
    var number: Int
    var title: String
    var duration: String
    var symbol: String
}

struct SupabasePublishWeekResponse: Decodable, Hashable, Sendable {
    var weeklyPlanID: UUID
    var dailyCardCount: Int
    var isSoftLocked: Bool
    var publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case weeklyPlanID = "weekly_plan_id"
        case dailyCardCount = "daily_card_count"
        case isSoftLocked = "is_soft_locked"
        case publishedAt = "published_at"
    }
}

enum SupabaseDateFormatting {
    static func contextLine(for rawDate: String) -> String {
        guard let date = parseDate(rawDate) else { return rawDate }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func weekdayAbbreviation(for rawDate: String) -> String {
        guard let date = parseDate(rawDate) else { return "DAY" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    static func dayNumber(for rawDate: String) -> String {
        guard let date = parseDate(rawDate) else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd"
        return formatter.string(from: date)
    }

    static func shortDate(for rawDate: String) -> String {
        guard let date = parseDate(rawDate) else { return rawDate }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date).uppercased()
    }

    static func weekRange(starting rawDate: String) -> String {
        dateRange(starting: rawDate, ending: weekEndDate(starting: rawDate))
    }

    static func dateRange(starting rawStartDate: String, ending rawEndDate: String) -> String {
        guard
            let start = parseDate(rawStartDate),
            let end = parseDate(rawEndDate)
        else {
            return "\(rawStartDate) - \(rawEndDate)"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d MMM"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    static func weekEndDate(starting rawDate: String) -> String {
        guard
            let start = parseDate(rawDate),
            let end = Calendar(identifier: .gregorian).date(byAdding: .day, value: 6, to: start)
        else {
            return rawDate
        }

        return dateString(from: end)
    }

    static func constrainedWeekEndDate(starting rawStartDate: String, requestedEndDate rawEndDate: String) -> String {
        guard
            let start = parseDate(rawStartDate),
            let requestedEnd = parseDate(rawEndDate),
            let maxEnd = Calendar(identifier: .gregorian).date(byAdding: .day, value: 6, to: start)
        else {
            return weekEndDate(starting: rawStartDate)
        }

        if requestedEnd < start {
            return rawStartDate
        }

        if requestedEnd > maxEnd {
            return dateString(from: maxEnd)
        }

        return dateString(from: requestedEnd)
    }

    static func dateOptions(around rawDate: String, daysBefore: Int, daysAfter: Int) -> [String] {
        guard let date = parseDate(rawDate) else {
            return [rawDate]
        }

        return (-daysBefore...daysAfter).compactMap { offset in
            Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: offset, to: date)
                .map { dateString(from: $0) }
        }
    }

    static func dateOptions(starting rawDate: String, dayCount: Int) -> [String] {
        guard let start = parseDate(rawDate), dayCount > 0 else {
            return [rawDate]
        }

        return (0..<dayCount).compactMap { offset in
            Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: offset, to: start)
                .map { dateString(from: $0) }
        }
    }

    static func displayDate(for rawDate: String) -> String {
        guard let date = parseDate(rawDate) else { return rawDate }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    static func weekDates(starting rawDate: String) -> [String] {
        guard let start = parseDate(rawDate) else {
            return []
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return (0..<7).compactMap { offset in
            Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: offset, to: start)
                .map { formatter.string(from: $0) }
        }
    }

    static func todayDateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    static func isoTimestampString() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    static func effortLabel(shootability: String?, minutes: Int?) -> String {
        switch (shootability?.nilIfBlank, minutes) {
        case (.some(let shootability), .some(let minutes)):
            "\(shootability.displayTitle) - \(minutes) min"
        case (.some(let shootability), .none):
            shootability.displayTitle
        case (.none, .some(let minutes)):
            "Ready - \(minutes) min"
        case (.none, .none):
            "Ready"
        }
    }

    static func summaryText(_ values: [SupabaseJSONValue], fallback: String) -> String {
        let text = values.compactMap(\.displayText).filter { !$0.isEmpty }.prefix(3).joined(separator: ", ")
        return text.isEmpty ? fallback : text
    }

    private static func parseDate(_ rawDate: String) -> Date? {
        let trimmedDate = String(rawDate.prefix(10))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: trimmedDate)
    }

    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

extension CompletionState {
    init?(supabaseStatus: String) {
        switch supabaseStatus {
        case "shot":
            self = .shot
        case "posted":
            self = .posted
        case "used_backup":
            self = .usedBackup
        case "saved_for_tomorrow":
            self = .savedForTomorrow
        case "skipped_intentionally":
            self = .skippedIntentionally
        default:
            return nil
        }
    }

    var supabaseStatus: String {
        switch self {
        case .shot:
            "shot"
        case .posted:
            "posted"
        case .usedBackup:
            "used_backup"
        case .savedForTomorrow:
            "saved_for_tomorrow"
        case .skippedIntentionally:
            "skipped_intentionally"
        }
    }
}

extension WeeklyDayState {
    init(dailyCardStatus: String) {
        switch dailyCardStatus {
        case "draft":
            self = .open
        case "used_backup":
            self = .backup
        default:
            self = .planned
        }
    }
}

extension WeeklySourceReason {
    init(sourceNote: String?, contentPillar: String?) {
        let text = [sourceNote, contentPillar]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if text.contains("trend") {
            self = .trend
        } else if text.contains("brand") {
            self = .brand
        } else if text.contains("audio") {
            self = .audio
        } else if text.contains("family") || text.contains("moment") {
            self = .moment
        } else if text.contains("routine") {
            self = .routine
        } else if text.isEmpty {
            self = .open
        } else {
            self = .pattern
        }
    }
}

extension IntelligenceReviewState {
    init(sourceStatus: String) {
        switch sourceStatus {
        case "approved", "verified_available":
            self = .approved
        case "used":
            self = .usedThisWeek
        case "candidate", "analyzed", "added", "analyzing":
            self = .needsReview
        default:
            self = .ready
        }
    }

    init(referenceStatus: String) {
        switch referenceStatus {
        case "confirmed":
            self = .approved
        case "needs_review", "analyzed", "added", "analyzing":
            self = .needsReview
        default:
            self = .ready
        }
    }

    init(benchmarkCreatorStatus: String) {
        switch benchmarkCreatorStatus {
        case "active":
            self = .approved
        case "candidate":
            self = .needsReview
        default:
            self = .ready
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var displayTitle: String {
        split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var referenceSymbol: String {
        switch self {
        case "screenshot", "screen_recording":
            "photo"
        case "audio_link":
            "music.note"
        case "reel_link", "benchmark_post":
            "link"
        default:
            "note.text"
        }
    }
}
