import Foundation

struct SupabaseGenerateWeekRequest: Encodable, Sendable {
    var creatorID: UUID
    var weekStartDate: String
    var weeklySetupID: UUID?
    var mode: GenerateWeekMode
    var preserveManualEdits: Bool
    var mock: Bool?

    enum CodingKeys: String, CodingKey {
        case creatorID = "creator_id"
        case weekStartDate = "week_start_date"
        case weeklySetupID = "weekly_setup_id"
        case mode
        case preserveManualEdits = "preserve_manual_edits"
        case mock
    }
}

struct SupabaseGenerateWeekResponse: Decodable, Hashable, Sendable {
    var generationID: UUID
    var weeklyPlanID: UUID
    var status: String
    var strategySummary: String
    var warnings: [String]
    var assumptions: [String]
    var dailyCards: [SupabaseGeneratedDailyCardDTO]
    var ideaBank: [SupabaseIdeaRow]
    var sourceSummary: String
    var generatedAt: String

    enum CodingKeys: String, CodingKey {
        case generationID = "generation_id"
        case weeklyPlanID = "weekly_plan_id"
        case status
        case strategySummary = "strategy_summary"
        case warnings
        case assumptions
        case dailyCards = "daily_cards"
        case ideaBank = "idea_bank"
        case sourceSummary = "source_summary"
        case generatedAt = "generated_at"
    }

    func domainDraft() -> GeneratedWeekDraft {
        GeneratedWeekDraft(
            id: generationID,
            weeklyPlanID: weeklyPlanID,
            status: status,
            strategySummary: strategySummary,
            warnings: warnings,
            assumptions: assumptions,
            dailyCards: dailyCards.map(\.domainCard),
            ideaBank: ideaBank.map { $0.domainIdea() },
            sourceSummary: sourceSummary,
            generatedAt: generatedAt
        )
    }
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
    var sceneList: [SupabaseShotSceneDTO]
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
    var audioOptionNotes: String
    var mamtaFitScore: Double
    var riskNotes: [String]
    var assumptions: [String]
    var sourceNote: String

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
        case audioOptionNotes = "audio_option_notes"
        case mamtaFitScore = "mamta_fit_score"
        case riskNotes = "risk_notes"
        case assumptions
        case sourceNote = "source_note"
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
            sceneList: sceneList.enumerated().map { index, scene in
                scene.domainScene(fallbackNumber: index + 1)
            },
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
            mamtaFitScore: mamtaFitScore,
            riskNotes: riskNotes,
            assumptions: assumptions,
            sourceNote: sourceNote
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
    var sceneList: [SupabasePublishSceneRequest]
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
    var mamtaFitScore: Double
    var riskNotes: [String]
    var assumptions: [String]
    var sourceNote: String

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
        case mamtaFitScore = "mamta_fit_score"
        case riskNotes = "risk_notes"
        case assumptions
        case sourceNote = "source_note"
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
        sceneList = card.sceneList.map { scene in
            SupabasePublishSceneRequest(
                number: scene.number,
                title: scene.title,
                duration: scene.duration,
                symbol: scene.symbol
            )
        }
        script = card.script
        noVoiceoverVersion = card.noVoiceoverVersion
        onScreenText = card.onScreenText
        caption = card.caption
        cta = card.cta
        hashtags = card.hashtags
        coverText = card.coverText
        postInstructions = .object([
            "line": .string(card.postInstructions),
            "audio_option_notes": .string(card.audioOptionNotes)
        ])
        brandEventNotes = card.brandEventNotes
        backupStory = .object(["line": .string(card.backupStory)])
        backupCaptionOnly = .object(["line": .string(card.backupCaptionOnly)])
        mamtaFitScore = card.mamtaFitScore
        riskNotes = card.riskNotes
        assumptions = card.assumptions
        sourceNote = card.sourceNote
    }
}
