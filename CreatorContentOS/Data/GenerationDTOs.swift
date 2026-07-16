import Foundation

/// Safe, non-sensitive client-side context encoded into generation requests
/// for hosted log correlation. Only carries values useful for tracing which
/// app surface and action produced a request — never tokens, auth headers,
/// emails, API keys, or private profile text. Optional fields are omitted from
/// the encoded payload when nil so requests stay backward-compatible.
struct SupabaseGenerationClientContext: Encodable, Sendable, Equatable {
    var uiSurface: String
    var action: String
    var selectedWeekStart: String?
    var scheduledDate: String?
    var dayGuidancePresent: Bool?
    var dayGuidanceChars: Int?

    enum CodingKeys: String, CodingKey {
        case uiSurface = "ui_surface"
        case action
        case selectedWeekStart = "selected_week_start"
        case scheduledDate = "scheduled_date"
        case dayGuidancePresent = "day_guidance_present"
        case dayGuidanceChars = "day_guidance_chars"
    }
}

enum GenerationResponseMode: String, Encodable, Sendable {
    case sync
    case async
}

struct SupabaseRegenerateDayRequest: Encodable, Sendable {
    var creatorID: UUID
    var weeklyPlanID: UUID
    var scheduledDate: String
    var preserveManualEdits: Bool
    var responseMode: GenerationResponseMode = .sync
    var mock: Bool?
    var action = "regenerate_day"
    var dayGuidance: String?
    var clientContext: SupabaseGenerationClientContext? = nil

    enum CodingKeys: String, CodingKey {
        case creatorID = "creator_id"
        case weeklyPlanID = "weekly_plan_id"
        case scheduledDate = "scheduled_date"
        case preserveManualEdits = "preserve_manual_edits"
        case responseMode = "response_mode"
        case mock
        case action
        case dayGuidance = "day_guidance"
        case clientContext = "client_context"
    }
}

/// Day-at-a-time generation: one card for an explicit target date driven by a
/// free-text day brief. The server assembles the creator profile and
/// references, uses the day brief as the only brief, and returns the same
/// storyboard + caption card payload as regenerate_day.
struct SupabaseDailyGenerationRequest: Encodable, Sendable {
    var creatorID: UUID
    var scheduledDate: String
    var dayBrief: String
    var responseMode: GenerationResponseMode = .sync
    var mock: Bool?
    var action = "generate_day"
    var clientContext: SupabaseGenerationClientContext? = nil

    enum CodingKeys: String, CodingKey {
        case creatorID = "creator_id"
        case scheduledDate = "scheduled_date"
        case dayBrief = "day_brief"
        case responseMode = "response_mode"
        case mock
        case action
        case clientContext = "client_context"
    }
}

typealias SupabaseGenerateDayRequest = SupabaseDailyGenerationRequest

struct SupabaseDailyGenerationResponse: Decodable, Hashable, Sendable {
    var generationID: UUID
    var weeklyPlanID: UUID
    var status: String
    var targetScheduledDate: String
    var dailyCard: SupabaseGeneratedDailyCardDTO
    var warnings: [String]
    var assumptions: [String]
    var sourceSummary: String
    var generatedAt: String

    enum CodingKeys: String, CodingKey {
        case generationID = "generation_id"
        case weeklyPlanID = "weekly_plan_id"
        case status
        case targetScheduledDate = "target_scheduled_date"
        case dailyCard = "daily_card"
        case warnings
        case assumptions
        case sourceSummary = "source_summary"
        case generatedAt = "generated_at"
    }

    var domainResult: DailyGenerationResult {
        DailyGenerationResult(
            generationID: generationID,
            weeklyPlanID: weeklyPlanID,
            status: status,
            targetScheduledDate: targetScheduledDate,
            dailyCard: dailyCard.domainCard,
            warnings: warnings,
            assumptions: assumptions,
            sourceSummary: sourceSummary,
            generatedAt: generatedAt
        )
    }
}

typealias SupabaseRegenerateDayResponse = SupabaseDailyGenerationResponse

struct DailyGenerationResult: Hashable, Sendable {
    var generationID: UUID
    var weeklyPlanID: UUID
    var status: String
    var targetScheduledDate: String
    var dailyCard: GeneratedDailyCardDraft
    var warnings: [String]
    var assumptions: [String]
    var sourceSummary: String
    var generatedAt: String
}

typealias RegeneratedDayResult = DailyGenerationResult

struct SupabaseGenerateStoryboardThumbnailRequest: Encodable, Hashable, Sendable {
    var creatorID: UUID
    var dailyCardID: UUID
    var rowIndexes: [Int]?
    var force: Bool
    var revisionInstructions: String?

    enum CodingKeys: String, CodingKey {
        case creatorID = "creator_id"
        case dailyCardID = "daily_card_id"
        case rowIndexes = "row_indexes"
        case force
        case revisionInstructions = "revision_instructions"
    }
}

struct SupabaseGenerateStoryboardThumbnailResponse: Decodable, Hashable, Sendable {
    var dailyCardID: UUID
    var assets: [StoryboardThumbnailAsset]
    var generatedCount: Int
    var cachedCount: Int
    var model: String
    var promptVersion: String

    enum CodingKeys: String, CodingKey {
        case dailyCardID = "daily_card_id"
        case assets
        case generatedCount = "generated_count"
        case cachedCount = "cached_count"
        case model
        case promptVersion = "prompt_version"
    }
}

extension GeneratedWeekDraft {
    @discardableResult
    mutating func replaceDailyCard(_ regeneratedCard: GeneratedDailyCardDraft) -> Bool {
        if let index = dailyCards.firstIndex(where: {
            $0.id == regeneratedCard.id || $0.scheduledDate == regeneratedCard.scheduledDate
        }) {
            dailyCards[index] = regeneratedCard
            return true
        }

        dailyCards.append(regeneratedCard)
        dailyCards.sort { $0.scheduledDate < $1.scheduledDate }
        return true
    }
}

struct SupabaseGenerationStatusRequest: Encodable, Sendable {
    var generationID: UUID
    var creatorID: UUID
    var action = "status"

    enum CodingKeys: String, CodingKey {
        case generationID = "generation_id"
        case creatorID = "creator_id"
        case action
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(generationID.uuidString.lowercased(), forKey: .generationID)
        try container.encode(creatorID.uuidString.lowercased(), forKey: .creatorID)
        try container.encode(action, forKey: .action)
    }
}

struct SupabaseGenerationStatusResponse: Decodable, Hashable, Sendable {
    var generationID: UUID
    var status: String
    var weeklyPlanID: UUID?
    var message: String?
    var targetScheduledDate: String?
    var pollAfterSeconds: Int?
    var error: String?

    enum CodingKeys: String, CodingKey {
        case generationID = "generation_id"
        case status
        case weeklyPlanID = "weekly_plan_id"
        case message
        case targetScheduledDate = "target_scheduled_date"
        case pollAfterSeconds = "poll_after_seconds"
        case error
    }
}

enum SupabaseDailyGenerationInvocation: Sendable {
    case completed(SupabaseDailyGenerationResponse)
    case running(SupabaseGenerationStatusResponse)
    case failed(SupabaseGenerationStatusResponse)

    static func decode(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> SupabaseDailyGenerationInvocation {
        let probe = try decoder.decode(SupabaseGenerationStatusProbe.self, from: data)
        if probe.status == "draft" || probe.status == "completed" {
            return .completed(try decoder.decode(SupabaseDailyGenerationResponse.self, from: data))
        }

        var status = try decoder.decode(SupabaseGenerationStatusResponse.self, from: data)
        switch status.status {
        case "failed":
            return .failed(status)
        case "cancelled":
            if status.error?.nilIfBlank == nil {
                status.error = "generation_cancelled"
            }
            return .failed(status)
        case "pending", "queued", "retrying", "running":
            return .running(status)
        default:
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "Unexpected regenerate-day status: \(status.status)"
                )
            )
        }
    }
}

typealias SupabaseRegenerateDayInvocation = SupabaseDailyGenerationInvocation

private struct SupabaseGenerationStatusProbe: Decodable {
    let status: String?
}

struct SupabaseGeneratedDailyCardDTO: Codable, Hashable, Sendable {
    var id: UUID?
    var scheduledDate: String
    var status: String?
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
    var sceneList: [SupabaseShotSceneDTO]
    var shotTimeline: [ProductionTimelineItem]?
    var voiceoverTimeline: [ProductionTimelineItem]?
    var onScreenTextTimeline: [ProductionTimelineItem]?
    var silentVersionTimeline: [ProductionTimelineItem]?
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
    var backupStoryDetail: [ProductionTimelineItem]?
    var captionBackupDetail: String?
    var audioOptionNotes: String
    var creatorFitScore: Double
    var riskNotes: [String]
    var assumptions: [String]
    var sourceNote: String
    var reviewState: String?
    var storyboardThumbnailAssets: [StoryboardThumbnailAsset]?

    enum CodingKeys: String, CodingKey {
        case id
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
        case format
        case primarySurface = "primary_surface"
        case durationSeconds = "duration_seconds"
        case hook
        case saveShareReason = "save_share_reason"
        case sceneList = "scene_list"
        case shotTimeline = "shot_timeline"
        case voiceoverTimeline = "voiceover_timeline"
        case onScreenTextTimeline = "on_screen_text_timeline"
        case silentVersionTimeline = "silent_version_timeline"
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
        case backupStoryDetail = "backup_story_detail"
        case captionBackupDetail = "caption_backup_detail"
        case audioOptionNotes = "audio_option_notes"
        case creatorFitScore = "creator_fit_score"
        case riskNotes = "risk_notes"
        case assumptions
        case sourceNote = "source_note"
        case reviewState = "review_state"
        case storyboardThumbnailAssets = "storyboard_thumbnail_assets"
    }

    var domainCard: GeneratedDailyCardDraft {
        GeneratedDailyCardDraft(
            id: id ?? UUID(),
            scheduledDate: scheduledDate,
            status: status ?? "draft",
            title: title,
            whyToday: whyToday,
            growthJob: growthJob,
            contentPillar: contentPillar,
            shootability: shootability,
            estimatedShootMinutes: estimatedShootMinutes,
            energyRequired: energyRequired,
            languageMode: languageMode,
            format: format,
            primarySurface: primarySurface,
            durationSeconds: durationSeconds,
            hook: hook,
            saveShareReason: saveShareReason,
            sceneList: sceneList.enumerated().map { index, scene in
                scene.domainScene(fallbackNumber: index + 1)
            },
            shotTimeline: shotTimeline ?? [],
            voiceoverTimeline: voiceoverTimeline ?? [],
            onScreenTextTimeline: onScreenTextTimeline ?? [],
            silentVersionTimeline: silentVersionTimeline ?? [],
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
            backupStoryDetail: backupStoryDetail ?? [],
            captionBackupDetail: captionBackupDetail,
            audioOptionNotes: audioOptionNotes,
            creatorFitScore: creatorFitScore,
            riskNotes: riskNotes,
            assumptions: assumptions,
            sourceNote: sourceNote,
            storyboardThumbnailAssets: storyboardThumbnailAssets ?? []
        )
    }
}

struct SupabaseDraftDailyCardPublishRequest: Encodable, Sendable {
    var id: UUID
    var scheduledDate: String
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
    var sceneList: [SupabasePublishSceneRequest]
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
    var postInstructions: SupabaseJSONValue
    var brandEventNotes: String
    var backupStory: SupabaseJSONValue
    var backupCaptionOnly: SupabaseJSONValue
    var backupStoryDetail: [ProductionTimelineItem]
    var captionBackupDetail: String?
    var creatorFitScore: Double
    var riskNotes: [String]
    var assumptions: [String]
    var sourceNote: String
    var reviewState: String
    var storyboardThumbnailAssets: [StoryboardThumbnailAsset]

    enum CodingKeys: String, CodingKey {
        case id
        case scheduledDate = "scheduled_date"
        case title
        case whyToday = "why_today"
        case growthJob = "growth_job"
        case contentPillar = "content_pillar"
        case shootability
        case estimatedShootMinutes = "estimated_shoot_minutes"
        case energyRequired = "energy_required"
        case languageMode = "language_mode"
        case format
        case primarySurface = "primary_surface"
        case durationSeconds = "duration_seconds"
        case hook
        case saveShareReason = "save_share_reason"
        case sceneList = "scene_list"
        case shotTimeline = "shot_timeline"
        case voiceoverTimeline = "voiceover_timeline"
        case onScreenTextTimeline = "on_screen_text_timeline"
        case silentVersionTimeline = "silent_version_timeline"
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
        case backupStoryDetail = "backup_story_detail"
        case captionBackupDetail = "caption_backup_detail"
        case creatorFitScore = "creator_fit_score"
        case riskNotes = "risk_notes"
        case assumptions
        case sourceNote = "source_note"
        case reviewState = "review_state"
        case storyboardThumbnailAssets = "storyboard_thumbnail_assets"
    }

    init(card: GeneratedDailyCardDraft) {
        id = card.id
        scheduledDate = card.scheduledDate
        title = card.title
        whyToday = card.whyToday
        growthJob = card.growthJob
        contentPillar = card.contentPillar
        shootability = card.shootability
        estimatedShootMinutes = card.estimatedShootMinutes
        energyRequired = card.energyRequired
        languageMode = card.languageMode
        format = card.format
        primarySurface = card.primarySurface
        durationSeconds = card.durationSeconds
        hook = card.hook
        saveShareReason = card.saveShareReason
        sceneList = card.sceneList.map { scene in
            SupabasePublishSceneRequest(
                number: scene.number,
                title: scene.title,
                duration: scene.duration,
                symbol: scene.symbol
            )
        }
        shotTimeline = card.shotTimeline
        voiceoverTimeline = card.voiceoverTimeline
        onScreenTextTimeline = card.onScreenTextTimeline
        silentVersionTimeline = card.silentVersionTimeline
        script = card.script
        noVoiceoverVersion = card.noVoiceoverVersion
        onScreenText = card.onScreenText
        caption = card.caption
        cta = card.cta
        hashtags = card.hashtags
        coverText = card.coverText
        postInstructions = .object([
            "line": .string(card.postInstructions),
            "instructions": .string(card.postInstructions),
            "audio_option_notes": .string(card.audioOptionNotes),
            "format": .string(card.format ?? ""),
            "primary_surface": .string(card.primarySurface ?? ""),
            "duration_seconds": .number(Double(card.durationSeconds ?? 0)),
            "hook": .string(card.hook ?? ""),
            "save_share_reason": .string(card.saveShareReason ?? ""),
            "shot_timeline": .array(card.shotTimeline.map(\.supabaseJSONValue)),
            "voiceover_timeline": .array(card.voiceoverTimeline.map(\.supabaseJSONValue)),
            "silent_version_timeline": .array(card.silentVersionTimeline.map(\.supabaseJSONValue)),
            "on_screen_text_timeline": .array(card.onScreenTextTimeline.map(\.supabaseJSONValue)),
            "caption_backup_detail": .string(card.captionBackupDetail ?? "")
        ])
        brandEventNotes = card.brandEventNotes
        backupStory = .object([
            "line": .string(card.backupStory),
            "detail": .array(card.backupStoryDetail.map(\.supabaseJSONValue))
        ])
        backupCaptionOnly = .object([
            "line": .string(card.backupCaptionOnly),
            "detail": .string(card.captionBackupDetail ?? "")
        ])
        backupStoryDetail = card.backupStoryDetail
        captionBackupDetail = card.captionBackupDetail
        creatorFitScore = card.creatorFitScore
        riskNotes = card.riskNotes
        assumptions = card.assumptions
        sourceNote = card.sourceNote
        reviewState = card.status.lowercased() == "ready" ? "ready"
            : card.status.lowercased() == "backup" ? "backup"
            : "open"
        storyboardThumbnailAssets = card.storyboardThumbnailAssets
    }
}

private extension ProductionTimelineItem {
    var supabaseJSONValue: SupabaseJSONValue {
        var object: [String: SupabaseJSONValue] = [
            "timestamp": .string(timestamp),
            "title": .string(title),
            "detail": .string(detail)
        ]
        if let shot {
            object["shot"] = .string(shot)
        }
        if let videoPortion {
            object["video_portion"] = .string(videoPortion)
        }
        if let voiceover {
            object["voiceover"] = .string(voiceover)
        }
        if let onScreenText {
            object["on_screen_text"] = .string(onScreenText)
            object["text"] = .string(onScreenText)
        }
        if let placement {
            object["placement"] = .string(placement)
        }
        if let durationSeconds {
            object["duration_seconds"] = .number(Double(durationSeconds))
        }
        return .object(object)
    }
}
