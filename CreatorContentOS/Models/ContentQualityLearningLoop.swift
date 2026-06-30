import Foundation

enum LearningLoopVersion {
    static let prePublishQuality = "creator_pre_publish_quality_v1"
    static let hardGates = "creator_hard_gates_v1"
    static let derivedMetrics = "creator_derived_metrics_v1"
    static let weightedEngagement = "creator_weighted_engagement_v1"
    static let goalPerformanceWeights = "creator_goal_performance_weights_v1"
    static let baseline = "creator_baseline_v1"
    static let classification = "creator_learning_loop_classification_v1"
}

enum ContentFormat: String, Codable, CaseIterable, Hashable, Sendable {
    case reel
    case story
    case post
    case carousel
}

enum MetricGoal: String, Codable, CaseIterable, Hashable, Sendable {
    case reach
    case saves
    case sends
    case shares
    case follows
    case comments
    case linkTaps = "link_taps"
    case trust
    case brandCollab = "brand_collab"
    case community
}

enum AudioType: String, Codable, CaseIterable, Hashable, Sendable {
    case original
    case trending
    case licensed
    case silent
    case voiceover
    case unknown
}

enum PostPublishMetricWindow: String, Codable, CaseIterable, Hashable, Sendable {
    case oneHour = "1h"
    case sixHours = "6h"
    case twentyFourHours = "24h"
    case seventyTwoHours = "72h"
    case sevenDays = "7d"
    case thirtyDays = "30d"
}

enum MetricSource: String, Codable, CaseIterable, Hashable, Sendable {
    case api
    case manual
    case screenshot
    case mixed
}

enum MetricDataQuality: String, Codable, CaseIterable, Hashable, Sendable {
    case complete
    case partial
    case estimated
}

enum CommentSentiment: String, Codable, CaseIterable, Hashable, Sendable {
    case positive
    case mixed
    case negative
    case unknown
}

enum CommentCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case genericPositive = "generic_positive"
    case meaningfulReaction = "meaningful_reaction"
    case question
    case targetAudienceSignal = "target_audience_signal"
    case negativeOrConfused = "negative_or_confused"
    case offTopic = "off_topic"
    case spam
}

struct CreatorProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var creatorID: UUID
    var displayName: String
    var niche: String?
    var contentPillars: [String]
    var targetAudience: [String]
    var voiceTraits: [String]
    var creatorBeliefs: [String]
    var allowedPhrases: [String]
    var bannedPhrases: [String]
    var tonePreferences: [String]
    var offBrandPatterns: [String]
    var shootableContexts: [String]
    var availableLocations: [String]
    var recurringFormats: [String]
    var weeklyRoutine: [String]
    var brandGoals: [String]
    var monetizationGoals: [String]
    var safetyConstraints: [String]
    var strongPastPostExamples: [String]
    var weakPastPostExamples: [String]
    var dislikedStyles: [String]
    var competitorInspiration: [String]
    var creatorNotes: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        creatorID: UUID,
        displayName: String,
        niche: String? = nil,
        contentPillars: [String] = [],
        targetAudience: [String] = [],
        voiceTraits: [String] = [],
        creatorBeliefs: [String] = [],
        allowedPhrases: [String] = [],
        bannedPhrases: [String] = [],
        tonePreferences: [String] = [],
        offBrandPatterns: [String] = [],
        shootableContexts: [String] = [],
        availableLocations: [String] = [],
        recurringFormats: [String] = [],
        weeklyRoutine: [String] = [],
        brandGoals: [String] = [],
        monetizationGoals: [String] = [],
        safetyConstraints: [String] = [],
        strongPastPostExamples: [String] = [],
        weakPastPostExamples: [String] = [],
        dislikedStyles: [String] = [],
        competitorInspiration: [String] = [],
        creatorNotes: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.creatorID = creatorID
        self.displayName = displayName
        self.niche = niche
        self.contentPillars = contentPillars
        self.targetAudience = targetAudience
        self.voiceTraits = voiceTraits
        self.creatorBeliefs = creatorBeliefs
        self.allowedPhrases = allowedPhrases
        self.bannedPhrases = bannedPhrases
        self.tonePreferences = tonePreferences
        self.offBrandPatterns = offBrandPatterns
        self.shootableContexts = shootableContexts
        self.availableLocations = availableLocations
        self.recurringFormats = recurringFormats
        self.weeklyRoutine = weeklyRoutine
        self.brandGoals = brandGoals
        self.monetizationGoals = monetizationGoals
        self.safetyConstraints = safetyConstraints
        self.strongPastPostExamples = strongPastPostExamples
        self.weakPastPostExamples = weakPastPostExamples
        self.dislikedStyles = dislikedStyles
        self.competitorInspiration = competitorInspiration
        self.creatorNotes = creatorNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ContentCard: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var dailyCardID: UUID?
    var creatorID: UUID
    var title: String
    var format: ContentFormat
    var contentPillar: String?
    var hookType: String?
    var ctaType: String?
    var primaryMetricGoal: MetricGoal
    var secondaryMetricGoal: MetricGoal?
    var scriptOrCaption: String?
    var voiceoverScript: String?
    var shotList: [String]
    var textOverlays: [String]
    var captionOptions: [String]
    var audioStrategy: String?
    var durationSec: Double?
    var sceneCount: Int?
    var hasVoiceover: Bool?
    var hasFace: Bool?
    var hasCaptions: Bool?
    var targetAudience: [String]
    var trendSourceID: UUID?
    var inspirationContentID: UUID?
    var brandCollabID: UUID?
    var generatedQualityScore: Double?
    var qualityVersion: String?
    var promptVersion: String?
    var hardGateResult: HardGateResult?
    var recommendationStatus: PublishRecommendation?
    var whyThisShouldWork: String?
    var creatorVoiceNotes: String?
    var audienceFitNotes: String?
    var riskFlags: [String]
    var improvementNotes: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        dailyCardID: UUID? = nil,
        creatorID: UUID,
        title: String,
        format: ContentFormat,
        contentPillar: String? = nil,
        hookType: String? = nil,
        ctaType: String? = nil,
        primaryMetricGoal: MetricGoal,
        secondaryMetricGoal: MetricGoal? = nil,
        scriptOrCaption: String? = nil,
        voiceoverScript: String? = nil,
        shotList: [String] = [],
        textOverlays: [String] = [],
        captionOptions: [String] = [],
        audioStrategy: String? = nil,
        durationSec: Double? = nil,
        sceneCount: Int? = nil,
        hasVoiceover: Bool? = nil,
        hasFace: Bool? = nil,
        hasCaptions: Bool? = nil,
        targetAudience: [String] = [],
        trendSourceID: UUID? = nil,
        inspirationContentID: UUID? = nil,
        brandCollabID: UUID? = nil,
        generatedQualityScore: Double? = nil,
        qualityVersion: String? = nil,
        promptVersion: String? = nil,
        hardGateResult: HardGateResult? = nil,
        recommendationStatus: PublishRecommendation? = nil,
        whyThisShouldWork: String? = nil,
        creatorVoiceNotes: String? = nil,
        audienceFitNotes: String? = nil,
        riskFlags: [String] = [],
        improvementNotes: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.dailyCardID = dailyCardID
        self.creatorID = creatorID
        self.title = title
        self.format = format
        self.contentPillar = contentPillar
        self.hookType = hookType
        self.ctaType = ctaType
        self.primaryMetricGoal = primaryMetricGoal
        self.secondaryMetricGoal = secondaryMetricGoal
        self.scriptOrCaption = scriptOrCaption
        self.voiceoverScript = voiceoverScript
        self.shotList = shotList
        self.textOverlays = textOverlays
        self.captionOptions = captionOptions
        self.audioStrategy = audioStrategy
        self.durationSec = durationSec
        self.sceneCount = sceneCount
        self.hasVoiceover = hasVoiceover
        self.hasFace = hasFace
        self.hasCaptions = hasCaptions
        self.targetAudience = targetAudience
        self.trendSourceID = trendSourceID
        self.inspirationContentID = inspirationContentID
        self.brandCollabID = brandCollabID
        self.generatedQualityScore = generatedQualityScore
        self.qualityVersion = qualityVersion
        self.promptVersion = promptVersion
        self.hardGateResult = hardGateResult
        self.recommendationStatus = recommendationStatus
        self.whyThisShouldWork = whyThisShouldWork
        self.creatorVoiceNotes = creatorVoiceNotes
        self.audienceFitNotes = audienceFitNotes
        self.riskFlags = riskFlags
        self.improvementNotes = improvementNotes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum PrePublishQualityCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case openingAttention = "opening_attention"
    case retentionArchitecture = "retention_architecture"
    case creatorVoiceSpecificity = "creator_voice_specificity"
    case audienceGoalFit = "audience_goal_fit"
    case saveShareTrigger = "save_share_trigger"
    case accessibilityComprehension = "accessibility_comprehension"
    case formatProductionFit = "format_production_fit"
}

struct QualityCategoryEvidence: Codable, Hashable, Sendable {
    var score: Double
    var explanation: String
    var checks: [String: Bool]
    var suggestedImprovements: [String]

    init(
        score: Double,
        explanation: String,
        checks: [String: Bool] = [:],
        suggestedImprovements: [String] = []
    ) {
        self.score = score
        self.explanation = explanation
        self.checks = checks
        self.suggestedImprovements = suggestedImprovements
    }
}

struct QualityCategoryScore: Codable, Hashable, Sendable {
    var category: PrePublishQualityCategory
    var score: Double
    var weight: Double
    var weightedPoints: Double
    var explanation: String
    var checks: [String: Bool]
    var suggestedImprovements: [String]
}

enum PublishRecommendation: String, Codable, CaseIterable, Hashable, Sendable {
    case recommendPublish = "recommend_publish"
    case improveWeakestSection = "improve_weakest_section"
    case rewriteBeforeShooting = "rewrite_before_shooting"
    case doNotPublish = "do_not_publish"
}

enum PrePublishScoreLabel: String, Codable, CaseIterable, Hashable, Sendable {
    case strong
    case good
    case rewrite
    case weak
    case blocked
}

struct PrePublishQualityScoringConfig: Codable, Hashable, Sendable {
    var version: String
    var categoryWeights: [PrePublishQualityCategory: Double]
    var weakCategoryLimit: Int

    static let creatorQualityV1 = PrePublishQualityScoringConfig(
        version: LearningLoopVersion.prePublishQuality,
        categoryWeights: [
            .openingAttention: 0.20,
            .retentionArchitecture: 0.15,
            .creatorVoiceSpecificity: 0.15,
            .audienceGoalFit: 0.15,
            .saveShareTrigger: 0.15,
            .accessibilityComprehension: 0.10,
            .formatProductionFit: 0.10
        ],
        weakCategoryLimit: 3
    )
}

enum HardGateIdentifier: String, Codable, CaseIterable, Hashable, Sendable {
    case platformPolicySafe = "platform_policy_safe"
    case recommendationEligible = "recommendation_eligible"
    case originalOrTransformative = "original_or_transformative"
    case noThirdPartyWatermark = "no_third_party_watermark"
    case noEngagementBait = "no_engagement_bait"
    case brandSafe = "brand_safe"
    case creatorVoiceNotViolated = "creator_voice_not_violated"
    case factualClaimsSupported = "factual_claims_supported"
    case rightsClear = "rights_clear"
}

enum HardGateSeverity: String, Codable, CaseIterable, Hashable, Sendable {
    case info
    case warning
    case blocking
}

struct HardGateCheck: Codable, Hashable, Sendable {
    var gate: HardGateIdentifier
    var passed: Bool
    var severity: HardGateSeverity
    var explanation: String
    var suggestedFix: String?
    var blocksPublishing: Bool

    init(
        gate: HardGateIdentifier,
        passed: Bool,
        severity: HardGateSeverity,
        explanation: String,
        suggestedFix: String? = nil,
        blocksPublishing: Bool? = nil
    ) {
        self.gate = gate
        self.passed = passed
        self.severity = severity
        self.explanation = explanation
        self.suggestedFix = suggestedFix
        self.blocksPublishing = blocksPublishing ?? (!passed && severity == .blocking)
    }
}

struct HardGateResult: Codable, Hashable, Sendable {
    var version: String
    var checks: [HardGateCheck]

    var blocksPublishing: Bool {
        checks.contains { !$0.passed && $0.blocksPublishing }
    }

    var failedBlockingGates: [HardGateCheck] {
        checks.filter { !$0.passed && $0.blocksPublishing }
    }

    static let passing = HardGateResult(
        version: LearningLoopVersion.hardGates,
        checks: HardGateIdentifier.allCases.map {
            HardGateCheck(
                gate: $0,
                passed: true,
                severity: .info,
                explanation: "No issue detected.",
                blocksPublishing: false
            )
        }
    )
}

struct PrePublishQualityScore: Codable, Hashable, Sendable {
    var overallScore: Double
    var categoryScores: [QualityCategoryScore]
    var weakestCategories: [PrePublishQualityCategory]
    var suggestedImprovements: [String]
    var publishRecommendation: PublishRecommendation
    var label: PrePublishScoreLabel
    var qualityVersion: String
    var hardGateResult: HardGateResult
    var createdAt: Date
    var updatedAt: Date
}

struct PrePublishQualityScorer {
    var config: PrePublishQualityScoringConfig

    init(config: PrePublishQualityScoringConfig = .creatorQualityV1) {
        self.config = config
    }

    func score(
        categoryEvidence: [PrePublishQualityCategory: QualityCategoryEvidence],
        hardGateResult: HardGateResult = .passing,
        now: Date = Date()
    ) -> PrePublishQualityScore {
        let categoryScores = PrePublishQualityCategory.allCases.map { category in
            let evidence = categoryEvidence[category] ?? QualityCategoryEvidence(
                score: 0,
                explanation: "No scoring evidence supplied.",
                suggestedImprovements: ["Add evidence for \(category.rawValue)."]
            )
            let weight = config.categoryWeights[category] ?? 0
            let clampedScore = Self.clamp(evidence.score, lower: 0, upper: 100)
            return QualityCategoryScore(
                category: category,
                score: clampedScore,
                weight: weight,
                weightedPoints: clampedScore * weight,
                explanation: evidence.explanation,
                checks: evidence.checks,
                suggestedImprovements: evidence.suggestedImprovements
            )
        }

        let overallScore = Self.round2(categoryScores.reduce(0) { $0 + $1.weightedPoints })
        let weakest = categoryScores
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.category.rawValue < rhs.category.rawValue
                }
                return lhs.score < rhs.score
            }
            .prefix(config.weakCategoryLimit)
            .map(\.category)
        let suggestions = categoryScores
            .filter { weakest.contains($0.category) || $0.score < 75 }
            .flatMap(\.suggestedImprovements)
        let label = Self.label(for: overallScore, hardGateResult: hardGateResult)

        return PrePublishQualityScore(
            overallScore: overallScore,
            categoryScores: categoryScores,
            weakestCategories: weakest,
            suggestedImprovements: Array(NSOrderedSet(array: suggestions)) as? [String] ?? suggestions,
            publishRecommendation: Self.recommendation(for: overallScore, hardGateResult: hardGateResult),
            label: label,
            qualityVersion: config.version,
            hardGateResult: hardGateResult,
            createdAt: now,
            updatedAt: now
        )
    }

    static func recommendation(
        for score: Double,
        hardGateResult: HardGateResult
    ) -> PublishRecommendation {
        guard !hardGateResult.blocksPublishing else { return .doNotPublish }
        switch score {
        case 85...:
            return .recommendPublish
        case 75..<85:
            return .improveWeakestSection
        case 60..<75:
            return .rewriteBeforeShooting
        default:
            return .doNotPublish
        }
    }

    static func label(
        for score: Double,
        hardGateResult: HardGateResult
    ) -> PrePublishScoreLabel {
        guard !hardGateResult.blocksPublishing else { return .blocked }
        switch score {
        case 85...:
            return .strong
        case 75..<85:
            return .good
        case 60..<75:
            return .rewrite
        default:
            return .weak
        }
    }

    static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    static func round2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}

struct PostPublishRawMetrics: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var contentID: UUID
    var dailyCardID: UUID?
    var creatorID: UUID
    var accountID: String?
    var instagramMediaID: String?
    var format: ContentFormat
    var contentPillar: String?
    var hookType: String?
    var ctaType: String?
    var generatedQualityScore: Double?
    var promptVersion: String?
    var qualityVersion: String?
    var publishedAt: Date?
    var collectedAt: Date
    var window: PostPublishMetricWindow
    var followersAtPublish: Int?
    var followersAtCollection: Int?
    var durationSec: Double?
    var sceneCount: Int?
    var hasVoiceover: Bool?
    var hasFace: Bool?
    var hasCaptions: Bool?
    var audioType: AudioType
    var audioID: String?
    var primaryMetricGoal: MetricGoal
    var secondaryMetricGoal: MetricGoal?
    var paidOrBoosted: Bool
    var metricSource: MetricSource
    var dataQuality: MetricDataQuality
    var views: Int?
    var reach: Int?
    var followerReach: Int?
    var nonFollowerReach: Int?
    var replays: Int?
    var impressions: Int?
    var likes: Int?
    var comments: Int?
    var saves: Int?
    var shares: Int?
    var sends: Int?
    var totalInteractions: Int?
    var follows: Int?
    var profileVisits: Int?
    var profileLinkTaps: Int?
    var websiteTaps: Int?
    var reelWatchTime: Double?
    var reelAverageWatchTime: Double?
    var reelSkipRate: Double?
    var storyReach: Int?
    var storyReplies: Int?
    var storyExits: Int?
    var storyTapsForward: Int?
    var storyTapsBack: Int?
    var storyStickerTaps: Int?
    var storyCompletionRate: Double?
    var firstFrameReach: Int?
    var finalFrameReach: Int?
    var commentQualityScore: Double?
    var meaningfulCommentCount: Int?
    var questionCommentCount: Int?
    var targetAudienceCommentCount: Int?
    var negativeCommentCount: Int?
    var commentSentiment: CommentSentiment
    var audienceFitScore: Double?
    var brandFitScore: Double?
    var notes: String?

    init(
        id: UUID = UUID(),
        contentID: UUID,
        dailyCardID: UUID? = nil,
        creatorID: UUID,
        accountID: String? = nil,
        instagramMediaID: String? = nil,
        format: ContentFormat,
        contentPillar: String? = nil,
        hookType: String? = nil,
        ctaType: String? = nil,
        generatedQualityScore: Double? = nil,
        promptVersion: String? = nil,
        qualityVersion: String? = nil,
        publishedAt: Date? = nil,
        collectedAt: Date = Date(),
        window: PostPublishMetricWindow,
        followersAtPublish: Int? = nil,
        followersAtCollection: Int? = nil,
        durationSec: Double? = nil,
        sceneCount: Int? = nil,
        hasVoiceover: Bool? = nil,
        hasFace: Bool? = nil,
        hasCaptions: Bool? = nil,
        audioType: AudioType = .unknown,
        audioID: String? = nil,
        primaryMetricGoal: MetricGoal,
        secondaryMetricGoal: MetricGoal? = nil,
        paidOrBoosted: Bool = false,
        metricSource: MetricSource,
        dataQuality: MetricDataQuality,
        views: Int? = nil,
        reach: Int? = nil,
        followerReach: Int? = nil,
        nonFollowerReach: Int? = nil,
        replays: Int? = nil,
        impressions: Int? = nil,
        likes: Int? = nil,
        comments: Int? = nil,
        saves: Int? = nil,
        shares: Int? = nil,
        sends: Int? = nil,
        totalInteractions: Int? = nil,
        follows: Int? = nil,
        profileVisits: Int? = nil,
        profileLinkTaps: Int? = nil,
        websiteTaps: Int? = nil,
        reelWatchTime: Double? = nil,
        reelAverageWatchTime: Double? = nil,
        reelSkipRate: Double? = nil,
        storyReach: Int? = nil,
        storyReplies: Int? = nil,
        storyExits: Int? = nil,
        storyTapsForward: Int? = nil,
        storyTapsBack: Int? = nil,
        storyStickerTaps: Int? = nil,
        storyCompletionRate: Double? = nil,
        firstFrameReach: Int? = nil,
        finalFrameReach: Int? = nil,
        commentQualityScore: Double? = nil,
        meaningfulCommentCount: Int? = nil,
        questionCommentCount: Int? = nil,
        targetAudienceCommentCount: Int? = nil,
        negativeCommentCount: Int? = nil,
        commentSentiment: CommentSentiment = .unknown,
        audienceFitScore: Double? = nil,
        brandFitScore: Double? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.contentID = contentID
        self.dailyCardID = dailyCardID
        self.creatorID = creatorID
        self.accountID = accountID
        self.instagramMediaID = instagramMediaID
        self.format = format
        self.contentPillar = contentPillar
        self.hookType = hookType
        self.ctaType = ctaType
        self.generatedQualityScore = generatedQualityScore
        self.promptVersion = promptVersion
        self.qualityVersion = qualityVersion
        self.publishedAt = publishedAt
        self.collectedAt = collectedAt
        self.window = window
        self.followersAtPublish = followersAtPublish
        self.followersAtCollection = followersAtCollection
        self.durationSec = durationSec
        self.sceneCount = sceneCount
        self.hasVoiceover = hasVoiceover
        self.hasFace = hasFace
        self.hasCaptions = hasCaptions
        self.audioType = audioType
        self.audioID = audioID
        self.primaryMetricGoal = primaryMetricGoal
        self.secondaryMetricGoal = secondaryMetricGoal
        self.paidOrBoosted = paidOrBoosted
        self.metricSource = metricSource
        self.dataQuality = dataQuality
        self.views = views
        self.reach = reach
        self.followerReach = followerReach
        self.nonFollowerReach = nonFollowerReach
        self.replays = replays
        self.impressions = impressions
        self.likes = likes
        self.comments = comments
        self.saves = saves
        self.shares = shares
        self.sends = sends
        self.totalInteractions = totalInteractions
        self.follows = follows
        self.profileVisits = profileVisits
        self.profileLinkTaps = profileLinkTaps
        self.websiteTaps = websiteTaps
        self.reelWatchTime = reelWatchTime
        self.reelAverageWatchTime = reelAverageWatchTime
        self.reelSkipRate = reelSkipRate
        self.storyReach = storyReach
        self.storyReplies = storyReplies
        self.storyExits = storyExits
        self.storyTapsForward = storyTapsForward
        self.storyTapsBack = storyTapsBack
        self.storyStickerTaps = storyStickerTaps
        self.storyCompletionRate = storyCompletionRate
        self.firstFrameReach = firstFrameReach
        self.finalFrameReach = finalFrameReach
        self.commentQualityScore = commentQualityScore
        self.meaningfulCommentCount = meaningfulCommentCount
        self.questionCommentCount = questionCommentCount
        self.targetAudienceCommentCount = targetAudienceCommentCount
        self.negativeCommentCount = negativeCommentCount
        self.commentSentiment = commentSentiment
        self.audienceFitScore = audienceFitScore
        self.brandFitScore = brandFitScore
        self.notes = notes
    }
}

struct WeightedEngagementWeights: Codable, Hashable, Sendable {
    var version: String
    var like: Double
    var comment: Double
    var save: Double
    var share: Double
    var send: Double
    var follow: Double

    static let v1 = WeightedEngagementWeights(
        version: LearningLoopVersion.weightedEngagement,
        like: 1,
        comment: 2,
        save: 3,
        share: 4,
        send: 5,
        follow: 6
    )
}

struct DerivedMetrics: Codable, Hashable, Sendable {
    var version: String
    var metricSource: MetricSource
    var dataQuality: MetricDataQuality
    var paidOrBoosted: Bool
    var weightedEngagementWeightsVersion: String
    var distribution: DistributionMetrics
    var retention: RetentionMetrics
    var engagement: EngagementMetrics
    var durableValue: DurableValueMetrics
    var socialSpread: SocialSpreadMetrics
    var conversion: ConversionMetrics
    var stories: StoryMetrics
    var quality: QualityMetrics

    struct DistributionMetrics: Codable, Hashable, Sendable {
        var reachMultiplier: Double?
        var nonFollowerReachRate: Double?
        var viewFrequency: Double?
        var inferredReplays: Int?
        var inferredReplayRate: Double?
    }

    struct RetentionMetrics: Codable, Hashable, Sendable {
        var avgWatchPct: Double?
        var watchTimePerReachedUser: Double?
        var completionProxy: Double?
        var skipRate: Double?
    }

    struct EngagementMetrics: Codable, Hashable, Sendable {
        var engagementRateByReach: Double?
        var weightedInteractions: Double?
        var weightedEngagementRate: Double?
        var likeRateByReach: Double?
        var commentRateByReach: Double?
    }

    struct DurableValueMetrics: Codable, Hashable, Sendable {
        var saveRateByReach: Double?
    }

    struct SocialSpreadMetrics: Codable, Hashable, Sendable {
        var sendRateByReach: Double?
        var shareRateByReach: Double?
        var socialSpreadRate: Double?
    }

    struct ConversionMetrics: Codable, Hashable, Sendable {
        var profileVisitRateByReach: Double?
        var followRateByReach: Double?
        var profileToFollowRate: Double?
        var linkTapRateByProfileVisit: Double?
        var websiteTapRateByReach: Double?
    }

    struct StoryMetrics: Codable, Hashable, Sendable {
        var storyExitRate: Double?
        var storyReplyRate: Double?
        var storyStickerTapRate: Double?
        var storyCompletionRate: Double?
    }

    struct QualityMetrics: Codable, Hashable, Sendable {
        var commentQualityScore: Double?
        var meaningfulCommentRate: Double?
        var questionRate: Double?
        var negativeCommentRate: Double?
        var commentSentiment: CommentSentiment
        var audienceFitScore: Double?
        var brandFitScore: Double?
    }
}

struct DerivedMetricsCalculator {
    var engagementWeights: WeightedEngagementWeights

    init(engagementWeights: WeightedEngagementWeights = .v1) {
        self.engagementWeights = engagementWeights
    }

    func calculate(raw: PostPublishRawMetrics) -> DerivedMetrics {
        let reach = Self.double(raw.reach)
        let followersAtPublish = Self.double(raw.followersAtPublish)
        let views = Self.double(raw.views)
        let inferredReplays = Self.inferredReplays(views: raw.views, reach: raw.reach)
        let storyCompletion = raw.storyCompletionRate
            ?? Self.safeDivide(Self.double(raw.finalFrameReach), Self.double(raw.firstFrameReach))
        let weightedInteractions = self.weightedInteractions(raw: raw)

        return DerivedMetrics(
            version: LearningLoopVersion.derivedMetrics,
            metricSource: raw.metricSource,
            dataQuality: raw.dataQuality,
            paidOrBoosted: raw.paidOrBoosted,
            weightedEngagementWeightsVersion: engagementWeights.version,
            distribution: .init(
                reachMultiplier: Self.safeDivide(reach, followersAtPublish),
                nonFollowerReachRate: Self.safeDivide(Self.double(raw.nonFollowerReach), reach),
                viewFrequency: Self.safeDivide(views, reach),
                inferredReplays: inferredReplays,
                inferredReplayRate: Self.safeDivide(Self.double(inferredReplays), reach)
            ),
            retention: .init(
                avgWatchPct: Self.safeDivide(raw.reelAverageWatchTime, raw.durationSec),
                watchTimePerReachedUser: Self.safeDivide(raw.reelWatchTime, reach),
                completionProxy: Self.safeDivide(raw.reelAverageWatchTime, raw.durationSec),
                skipRate: raw.reelSkipRate
            ),
            engagement: .init(
                engagementRateByReach: Self.safeDivide(Self.double(raw.totalInteractions), reach),
                weightedInteractions: weightedInteractions,
                weightedEngagementRate: Self.safeDivide(weightedInteractions, reach),
                likeRateByReach: Self.safeDivide(Self.double(raw.likes), reach),
                commentRateByReach: Self.safeDivide(Self.double(raw.comments), reach)
            ),
            durableValue: .init(
                saveRateByReach: Self.safeDivide(Self.double(raw.saves), reach)
            ),
            socialSpread: .init(
                sendRateByReach: Self.safeDivide(Self.double(raw.sends), reach),
                shareRateByReach: Self.safeDivide(Self.double(raw.shares), reach),
                socialSpreadRate: Self.safeDivide(Self.sumIfAllPresent(raw.sends, raw.shares), reach)
            ),
            conversion: .init(
                profileVisitRateByReach: Self.safeDivide(Self.double(raw.profileVisits), reach),
                followRateByReach: Self.safeDivide(Self.double(raw.follows), reach),
                profileToFollowRate: Self.safeDivide(Self.double(raw.follows), Self.double(raw.profileVisits)),
                linkTapRateByProfileVisit: Self.safeDivide(Self.double(raw.profileLinkTaps), Self.double(raw.profileVisits)),
                websiteTapRateByReach: Self.safeDivide(Self.double(raw.websiteTaps), reach)
            ),
            stories: .init(
                storyExitRate: Self.safeDivide(Self.double(raw.storyExits), Self.double(raw.storyReach)),
                storyReplyRate: Self.safeDivide(Self.double(raw.storyReplies), Self.double(raw.storyReach)),
                storyStickerTapRate: Self.safeDivide(Self.double(raw.storyStickerTaps), Self.double(raw.storyReach)),
                storyCompletionRate: storyCompletion
            ),
            quality: .init(
                commentQualityScore: raw.commentQualityScore,
                meaningfulCommentRate: Self.safeDivide(Self.double(raw.meaningfulCommentCount), Self.double(raw.comments)),
                questionRate: Self.safeDivide(Self.double(raw.questionCommentCount), Self.double(raw.comments)),
                negativeCommentRate: Self.safeDivide(Self.double(raw.negativeCommentCount), Self.double(raw.comments)),
                commentSentiment: raw.commentSentiment,
                audienceFitScore: raw.audienceFitScore,
                brandFitScore: raw.brandFitScore
            )
        )
    }

    static func safeDivide(_ numerator: Double?, _ denominator: Double?) -> Double? {
        guard let numerator, let denominator, denominator != 0 else {
            return nil
        }
        return numerator / denominator
    }

    static func double(_ value: Int?) -> Double? {
        value.map(Double.init)
    }

    static func inferredReplays(views: Int?, reach: Int?) -> Int? {
        guard let views, let reach else { return nil }
        return max(views - reach, 0)
    }

    static func sumIfAllPresent(_ lhs: Int?, _ rhs: Int?) -> Double? {
        guard let lhs, let rhs else { return nil }
        return Double(lhs + rhs)
    }

    private func weightedInteractions(raw: PostPublishRawMetrics) -> Double? {
        guard
            let likes = raw.likes,
            let comments = raw.comments,
            let saves = raw.saves,
            let shares = raw.shares,
            let sends = raw.sends,
            let follows = raw.follows
        else {
            return nil
        }

        return Double(likes) * engagementWeights.like
            + Double(comments) * engagementWeights.comment
            + Double(saves) * engagementWeights.save
            + Double(shares) * engagementWeights.share
            + Double(sends) * engagementWeights.send
            + Double(follows) * engagementWeights.follow
    }
}

enum PerformanceSignalKey: String, Codable, CaseIterable, Hashable, Sendable {
    case socialSpreadRate = "social_spread_rate"
    case avgWatchPct = "avg_watch_pct"
    case nonFollowerReachRate = "non_follower_reach_rate"
    case followRateByReach = "follow_rate_by_reach"
    case viewFrequency = "view_frequency"
    case saveRateByReach = "save_rate_by_reach"
    case meaningfulCommentRate = "meaningful_comment_rate"
    case completionOrAvgWatch = "completion_or_avg_watch"
    case meaningfulConversationRate = "meaningful_conversation_rate"
    case profileVisitRateByReach = "profile_visit_rate_by_reach"
    case saveOrShareRate = "save_or_share_rate"
    case profileOrLinkActionRate = "profile_or_link_action_rate"
    case brandFitScore = "brand_fit_score"
    case commentSentiment = "comment_sentiment"
    case linkTapEfficiency = "link_tap_efficiency"
    case followOrCommentQuality = "follow_or_comment_quality"
}

struct WeightedPerformanceSignal: Codable, Hashable, Sendable {
    var key: PerformanceSignalKey
    var weight: Double
}

struct GoalPerformanceScoringConfig: Codable, Hashable, Sendable {
    var version: String
    var formulas: [MetricGoal: [WeightedPerformanceSignal]]

    static let v1 = GoalPerformanceScoringConfig(
        version: LearningLoopVersion.goalPerformanceWeights,
        formulas: [
            .reach: [
                .init(key: .socialSpreadRate, weight: 0.35),
                .init(key: .avgWatchPct, weight: 0.25),
                .init(key: .nonFollowerReachRate, weight: 0.20),
                .init(key: .followRateByReach, weight: 0.10),
                .init(key: .viewFrequency, weight: 0.10)
            ],
            .sends: [
                .init(key: .socialSpreadRate, weight: 0.35),
                .init(key: .avgWatchPct, weight: 0.25),
                .init(key: .nonFollowerReachRate, weight: 0.20),
                .init(key: .followRateByReach, weight: 0.10),
                .init(key: .viewFrequency, weight: 0.10)
            ],
            .shares: [
                .init(key: .socialSpreadRate, weight: 0.35),
                .init(key: .avgWatchPct, weight: 0.25),
                .init(key: .nonFollowerReachRate, weight: 0.20),
                .init(key: .followRateByReach, weight: 0.10),
                .init(key: .viewFrequency, weight: 0.10)
            ],
            .saves: [
                .init(key: .saveRateByReach, weight: 0.35),
                .init(key: .avgWatchPct, weight: 0.20),
                .init(key: .socialSpreadRate, weight: 0.15),
                .init(key: .followRateByReach, weight: 0.15),
                .init(key: .meaningfulCommentRate, weight: 0.15)
            ],
            .follows: [
                .init(key: .saveRateByReach, weight: 0.35),
                .init(key: .avgWatchPct, weight: 0.20),
                .init(key: .socialSpreadRate, weight: 0.15),
                .init(key: .followRateByReach, weight: 0.15),
                .init(key: .meaningfulCommentRate, weight: 0.15)
            ],
            .trust: [
                .init(key: .completionOrAvgWatch, weight: 0.25),
                .init(key: .meaningfulConversationRate, weight: 0.25),
                .init(key: .profileVisitRateByReach, weight: 0.20),
                .init(key: .followRateByReach, weight: 0.20),
                .init(key: .saveOrShareRate, weight: 0.10)
            ],
            .brandCollab: [
                .init(key: .completionOrAvgWatch, weight: 0.25),
                .init(key: .saveOrShareRate, weight: 0.20),
                .init(key: .profileOrLinkActionRate, weight: 0.20),
                .init(key: .brandFitScore, weight: 0.20),
                .init(key: .commentSentiment, weight: 0.15)
            ],
            .community: [
                .init(key: .meaningfulConversationRate, weight: 0.30),
                .init(key: .socialSpreadRate, weight: 0.20),
                .init(key: .completionOrAvgWatch, weight: 0.20),
                .init(key: .profileVisitRateByReach, weight: 0.15),
                .init(key: .followRateByReach, weight: 0.15)
            ],
            .linkTaps: [
                .init(key: .linkTapEfficiency, weight: 0.30),
                .init(key: .profileVisitRateByReach, weight: 0.20),
                .init(key: .completionOrAvgWatch, weight: 0.20),
                .init(key: .saveOrShareRate, weight: 0.15),
                .init(key: .followOrCommentQuality, weight: 0.15)
            ],
            .comments: [
                .init(key: .meaningfulConversationRate, weight: 0.30),
                .init(key: .socialSpreadRate, weight: 0.20),
                .init(key: .completionOrAvgWatch, weight: 0.20),
                .init(key: .profileVisitRateByReach, weight: 0.15),
                .init(key: .followRateByReach, weight: 0.15)
            ]
        ]
    )
}

enum GoalFitResult: String, Codable, CaseIterable, Hashable, Sendable {
    case strong
    case aligned
    case mixed
    case weak
    case insufficientData = "insufficient_data"
}

struct PerformanceSignalContribution: Codable, Hashable, Sendable {
    var key: PerformanceSignalKey
    var rawValue: Double
    var normalizedScore: Double
    var weight: Double
}

struct PostPublishPerformanceScore: Codable, Hashable, Sendable {
    var performanceScore: Double?
    var goalFitResult: GoalFitResult
    var strongestSignals: [PerformanceSignalContribution]
    var weakestSignals: [PerformanceSignalContribution]
    var diagnosis: String
    var recommendedNextAction: String
    var weightsVersion: String
}

struct PostPublishPerformanceScorer {
    var config: GoalPerformanceScoringConfig

    init(config: GoalPerformanceScoringConfig = .v1) {
        self.config = config
    }

    func score(
        derived: DerivedMetrics,
        primaryGoal: MetricGoal
    ) -> PostPublishPerformanceScore {
        let formula = config.formulas[primaryGoal] ?? config.formulas[.reach] ?? []
        let contributions = formula.compactMap { signal -> PerformanceSignalContribution? in
            guard let rawValue = rawSignalValue(signal.key, derived: derived) else {
                return nil
            }
            return PerformanceSignalContribution(
                key: signal.key,
                rawValue: rawValue,
                normalizedScore: normalizedScore(signal.key, rawValue: rawValue),
                weight: signal.weight
            )
        }

        guard !contributions.isEmpty else {
            return PostPublishPerformanceScore(
                performanceScore: nil,
                goalFitResult: .insufficientData,
                strongestSignals: [],
                weakestSignals: [],
                diagnosis: "Not enough post-publish metrics to evaluate the goal.",
                recommendedNextAction: "Collect more metrics before changing the content strategy.",
                weightsVersion: config.version
            )
        }

        let availableWeight = contributions.reduce(0) { $0 + $1.weight }
        let weightedScore = contributions.reduce(0) { $0 + ($1.normalizedScore * $1.weight) } / availableWeight
        let roundedScore = PrePublishQualityScorer.round2(weightedScore)
        let strongest = contributions.sorted { $0.normalizedScore > $1.normalizedScore }.prefix(2)
        let weakest = contributions.sorted { $0.normalizedScore < $1.normalizedScore }.prefix(2)

        return PostPublishPerformanceScore(
            performanceScore: roundedScore,
            goalFitResult: Self.result(for: roundedScore),
            strongestSignals: Array(strongest),
            weakestSignals: Array(weakest),
            diagnosis: Self.diagnosis(for: roundedScore, weakest: Array(weakest)),
            recommendedNextAction: Self.nextAction(for: roundedScore, weakest: Array(weakest)),
            weightsVersion: config.version
        )
    }

    private func rawSignalValue(
        _ key: PerformanceSignalKey,
        derived: DerivedMetrics
    ) -> Double? {
        switch key {
        case .socialSpreadRate:
            return derived.socialSpread.socialSpreadRate
        case .avgWatchPct:
            return derived.retention.avgWatchPct
        case .nonFollowerReachRate:
            return derived.distribution.nonFollowerReachRate
        case .followRateByReach:
            return derived.conversion.followRateByReach
        case .viewFrequency:
            return derived.distribution.viewFrequency
        case .saveRateByReach:
            return derived.durableValue.saveRateByReach
        case .meaningfulCommentRate:
            return derived.quality.meaningfulCommentRate
        case .completionOrAvgWatch:
            return derived.stories.storyCompletionRate
                ?? derived.retention.completionProxy
                ?? derived.retention.avgWatchPct
        case .meaningfulConversationRate:
            return derived.quality.meaningfulCommentRate
                ?? derived.stories.storyReplyRate
        case .profileVisitRateByReach:
            return derived.conversion.profileVisitRateByReach
        case .saveOrShareRate:
            return Self.sumIfAnyPresent(
                derived.durableValue.saveRateByReach,
                derived.socialSpread.socialSpreadRate
            )
        case .profileOrLinkActionRate:
            return Self.maxPresent(
                derived.conversion.profileVisitRateByReach,
                derived.conversion.linkTapRateByProfileVisit,
                derived.conversion.websiteTapRateByReach
            )
        case .brandFitScore:
            return derived.quality.brandFitScore
        case .commentSentiment:
            switch derived.quality.commentSentiment {
            case .positive:
                return 1
            case .mixed:
                return 0.5
            case .negative:
                return 0
            case .unknown:
                return nil
            }
        case .linkTapEfficiency:
            return derived.conversion.linkTapRateByProfileVisit
                ?? derived.conversion.websiteTapRateByReach
        case .followOrCommentQuality:
            guard
                let followRate = derived.conversion.followRateByReach,
                let commentQuality = derived.quality.commentQualityScore
            else {
                return derived.conversion.followRateByReach ?? derived.quality.commentQualityScore
            }
            return max(
                normalizedScore(.followRateByReach, rawValue: followRate),
                normalizedScore(.brandFitScore, rawValue: commentQuality)
            ) / 100
        }
    }

    private func normalizedScore(_ key: PerformanceSignalKey, rawValue: Double) -> Double {
        switch key {
        case .socialSpreadRate:
            return thresholdScore(rawValue, target: 0.015)
        case .avgWatchPct, .completionOrAvgWatch:
            return thresholdScore(rawValue, target: 0.50)
        case .nonFollowerReachRate:
            return thresholdScore(rawValue, target: 0.60)
        case .followRateByReach:
            return thresholdScore(rawValue, target: 0.002)
        case .viewFrequency:
            return thresholdScore(rawValue, target: 1.50)
        case .saveRateByReach:
            return thresholdScore(rawValue, target: 0.005)
        case .meaningfulCommentRate:
            return thresholdScore(rawValue, target: 0.40)
        case .meaningfulConversationRate:
            return rawValue <= 0.05
                ? thresholdScore(rawValue, target: 0.01)
                : thresholdScore(rawValue, target: 0.40)
        case .profileVisitRateByReach:
            return thresholdScore(rawValue, target: 0.02)
        case .saveOrShareRate:
            return thresholdScore(rawValue, target: 0.015)
        case .profileOrLinkActionRate:
            return rawValue <= 0.05
                ? thresholdScore(rawValue, target: 0.02)
                : thresholdScore(rawValue, target: 0.20)
        case .brandFitScore:
            return thresholdScore(rawValue, target: 4)
        case .commentSentiment:
            return thresholdScore(rawValue, target: 1)
        case .linkTapEfficiency:
            return rawValue <= 0.05
                ? thresholdScore(rawValue, target: 0.01)
                : thresholdScore(rawValue, target: 0.20)
        case .followOrCommentQuality:
            return rawValue <= 1 ? thresholdScore(rawValue, target: 1) : thresholdScore(rawValue, target: 4)
        }
    }

    private func thresholdScore(_ rawValue: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return PrePublishQualityScorer.clamp((rawValue / target) * 100, lower: 0, upper: 100)
    }

    private static func result(for score: Double) -> GoalFitResult {
        switch score {
        case 85...:
            return .strong
        case 70..<85:
            return .aligned
        case 50..<70:
            return .mixed
        default:
            return .weak
        }
    }

    private static func diagnosis(
        for score: Double,
        weakest: [PerformanceSignalContribution]
    ) -> String {
        guard score < 70, let weakestSignal = weakest.first else {
            return "The post matched its metric goal well enough to reuse the structure with fresh packaging."
        }
        return "The post underperformed mainly on \(weakestSignal.key.rawValue)."
    }

    private static func nextAction(
        for score: Double,
        weakest: [PerformanceSignalContribution]
    ) -> String {
        guard score < 70, let weakestSignal = weakest.first else {
            return "Repeat the format and keep tracking quality signals against this goal."
        }
        switch weakestSignal.key {
        case .avgWatchPct, .completionOrAvgWatch:
            return "Rewrite the hook and tighten the first half of the piece before reposting the idea."
        case .socialSpreadRate, .saveOrShareRate:
            return "Add a clearer save/send reason without using engagement bait."
        case .followRateByReach, .profileVisitRateByReach, .profileOrLinkActionRate, .linkTapEfficiency, .followOrCommentQuality:
            return "Clarify the profile or conversion reason tied to the content promise."
        default:
            return "Revise the weakest signal and compare against the next matching post."
        }
    }

    private static func sumIfAnyPresent(_ values: Double?...) -> Double? {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return present.reduce(0, +)
    }

    private static func maxPresent(_ values: Double?...) -> Double? {
        values.compactMap { $0 }.max()
    }
}

enum BaselineConfidence: String, Codable, CaseIterable, Hashable, Sendable {
    case none
    case insufficient
    case partial
    case reliable
}

enum DurationBand: String, Codable, CaseIterable, Hashable, Sendable {
    case under15 = "under_15"
    case fifteenTo30 = "15_30"
    case thirtyTo60 = "30_60"
    case sixtyTo90 = "60_90"
    case over90 = "over_90"
    case unknown

    init(durationSec: Double?) {
        guard let durationSec else {
            self = .unknown
            return
        }
        switch durationSec {
        case ..<15:
            self = .under15
        case 15..<30:
            self = .fifteenTo30
        case 30..<60:
            self = .thirtyTo60
        case 60..<90:
            self = .sixtyTo90
        default:
            self = .over90
        }
    }
}

struct BaselineMetricSet: Codable, Hashable, Sendable {
    var reachMultiplier: Double?
    var nonFollowerReachRate: Double?
    var saveRateByReach: Double?
    var sendRateByReach: Double?
    var followRateByReach: Double?
    var avgWatchPct: Double?
    var profileVisitRateByReach: Double?
}

struct CreatorBaseline: Codable, Hashable, Sendable {
    var version: String
    var sampleCount: Int
    var confidence: BaselineConfidence
    var median: BaselineMetricSet
    var top25Percent: BaselineMetricSet
    var top10Percent: BaselineMetricSet
    var includesPaid: Bool
}

struct BaselineLiftMetrics: Codable, Hashable, Sendable {
    var saveRateLift: Double?
    var sendRateLift: Double?
    var followRateLift: Double?
    var avgWatchLift: Double?
    var profileVisitLift: Double?
}

struct BaselineFilter: Codable, Hashable, Sendable {
    var format: ContentFormat?
    var contentPillar: String?
    var hookType: String?
    var durationBand: DurationBand?

    init(
        format: ContentFormat? = nil,
        contentPillar: String? = nil,
        hookType: String? = nil,
        durationBand: DurationBand? = nil
    ) {
        self.format = format
        self.contentPillar = contentPillar
        self.hookType = hookType
        self.durationBand = durationBand
    }
}

struct PostPublishLearningSample: Codable, Hashable, Sendable {
    var id: UUID
    var format: ContentFormat
    var contentPillar: String?
    var hookType: String?
    var durationBand: DurationBand
    var paidOrBoosted: Bool
    var derived: DerivedMetrics

    init(
        id: UUID = UUID(),
        format: ContentFormat,
        contentPillar: String? = nil,
        hookType: String? = nil,
        durationBand: DurationBand,
        paidOrBoosted: Bool,
        derived: DerivedMetrics
    ) {
        self.id = id
        self.format = format
        self.contentPillar = contentPillar
        self.hookType = hookType
        self.durationBand = durationBand
        self.paidOrBoosted = paidOrBoosted
        self.derived = derived
    }
}

struct CreatorBaselineService {
    func computeBaseline(
        samples: [PostPublishLearningSample],
        filter: BaselineFilter = BaselineFilter(),
        includePaid: Bool = false
    ) -> CreatorBaseline {
        let comparable = samples.filter { sample in
            (includePaid || !sample.paidOrBoosted)
                && (filter.format == nil || sample.format == filter.format)
                && (filter.contentPillar == nil || sample.contentPillar == filter.contentPillar)
                && (filter.hookType == nil || sample.hookType == filter.hookType)
                && (filter.durationBand == nil || sample.durationBand == filter.durationBand)
        }

        return CreatorBaseline(
            version: LearningLoopVersion.baseline,
            sampleCount: comparable.count,
            confidence: Self.confidence(for: comparable.count),
            median: metricSet(samples: comparable, reducer: Self.median),
            top25Percent: metricSet(samples: comparable) { Self.percentile($0, percentile: 0.75) },
            top10Percent: metricSet(samples: comparable) { Self.percentile($0, percentile: 0.90) },
            includesPaid: includePaid
        )
    }

    func computeLifts(
        current: DerivedMetrics,
        baseline: CreatorBaseline
    ) -> BaselineLiftMetrics {
        BaselineLiftMetrics(
            saveRateLift: DerivedMetricsCalculator.safeDivide(
                current.durableValue.saveRateByReach,
                baseline.median.saveRateByReach
            ),
            sendRateLift: DerivedMetricsCalculator.safeDivide(
                current.socialSpread.sendRateByReach,
                baseline.median.sendRateByReach
            ),
            followRateLift: DerivedMetricsCalculator.safeDivide(
                current.conversion.followRateByReach,
                baseline.median.followRateByReach
            ),
            avgWatchLift: DerivedMetricsCalculator.safeDivide(
                current.retention.avgWatchPct,
                baseline.median.avgWatchPct
            ),
            profileVisitLift: DerivedMetricsCalculator.safeDivide(
                current.conversion.profileVisitRateByReach,
                baseline.median.profileVisitRateByReach
            )
        )
    }

    private func metricSet(
        samples: [PostPublishLearningSample],
        reducer: ([Double]) -> Double?
    ) -> BaselineMetricSet {
        BaselineMetricSet(
            reachMultiplier: reducer(samples.compactMap(\.derived.distribution.reachMultiplier)),
            nonFollowerReachRate: reducer(samples.compactMap(\.derived.distribution.nonFollowerReachRate)),
            saveRateByReach: reducer(samples.compactMap(\.derived.durableValue.saveRateByReach)),
            sendRateByReach: reducer(samples.compactMap(\.derived.socialSpread.sendRateByReach)),
            followRateByReach: reducer(samples.compactMap(\.derived.conversion.followRateByReach)),
            avgWatchPct: reducer(samples.compactMap(\.derived.retention.avgWatchPct)),
            profileVisitRateByReach: reducer(samples.compactMap(\.derived.conversion.profileVisitRateByReach))
        )
    }

    static func confidence(for sampleCount: Int) -> BaselineConfidence {
        switch sampleCount {
        case 0:
            return .none
        case 1..<5:
            return .insufficient
        case 5..<20:
            return .partial
        default:
            return .reliable
        }
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    static func percentile(_ values: [Double], percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let clamped = PrePublishQualityScorer.clamp(percentile, lower: 0, upper: 1)
        let rank = max(Int(ceil(clamped * Double(sorted.count))), 1)
        return sorted[min(rank - 1, sorted.count - 1)]
    }
}

enum LearningLoopOutcomeCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case highReachHighQuality = "high_reach_high_quality"
    case highReachLowQuality = "high_reach_low_quality"
    case lowReachHighQuality = "low_reach_high_quality"
    case lowReachLowQuality = "low_reach_low_quality"
}

struct LearningLoopDiagnosis: Codable, Hashable, Sendable {
    var version: String
    var category: LearningLoopOutcomeCategory
    var meaning: String
    var nextAction: String
    var usedBaselineConfidence: BaselineConfidence?
}

struct LearningLoopAnalyzer {
    func classifyOutcome(
        derived: DerivedMetrics,
        performanceScore: PostPublishPerformanceScore? = nil,
        baseline: CreatorBaseline? = nil
    ) -> LearningLoopDiagnosis {
        let highReach = isHighReach(derived: derived, baseline: baseline)
        let highQuality = isHighQuality(derived: derived, performanceScore: performanceScore)

        let category: LearningLoopOutcomeCategory
        switch (highReach, highQuality) {
        case (true, true):
            category = .highReachHighQuality
        case (true, false):
            category = .highReachLowQuality
        case (false, true):
            category = .lowReachHighQuality
        case (false, false):
            category = .lowReachLowQuality
        }

        return LearningLoopDiagnosis(
            version: LearningLoopVersion.classification,
            category: category,
            meaning: Self.meaning(for: category),
            nextAction: Self.nextAction(for: category),
            usedBaselineConfidence: baseline?.confidence
        )
    }

    private func isHighReach(
        derived: DerivedMetrics,
        baseline: CreatorBaseline?
    ) -> Bool {
        if let baseline, baseline.confidence == .partial || baseline.confidence == .reliable {
            if let lift = DerivedMetricsCalculator.safeDivide(
                derived.distribution.reachMultiplier,
                baseline.median.reachMultiplier
            ), lift >= 1.25 {
                return true
            }
        }

        return (derived.distribution.reachMultiplier ?? 0) >= 3.0
            || (derived.distribution.nonFollowerReachRate ?? 0) >= 0.60
    }

    private func isHighQuality(
        derived: DerivedMetrics,
        performanceScore: PostPublishPerformanceScore?
    ) -> Bool {
        if let score = performanceScore?.performanceScore, score >= 75 {
            return true
        }

        let checks = [
            (derived.retention.avgWatchPct ?? derived.retention.completionProxy ?? 0) >= 0.50,
            (derived.socialSpread.sendRateByReach ?? 0) >= 0.01,
            (derived.durableValue.saveRateByReach ?? 0) >= 0.005,
            (derived.conversion.followRateByReach ?? 0) >= 0.002,
            (derived.conversion.profileToFollowRate ?? 0) >= 0.20,
            (derived.quality.commentQualityScore ?? 0) >= 4,
            (derived.quality.audienceFitScore ?? 0) >= 4,
            (derived.quality.brandFitScore ?? 0) >= 4
        ]

        return checks.filter { $0 }.count >= 3
    }

    private static func meaning(for category: LearningLoopOutcomeCategory) -> String {
        switch category {
        case .highReachHighQuality:
            return "Winning format. Repeat the structure."
        case .highReachLowQuality:
            return "Empty virality. Do not copy blindly."
        case .lowReachHighQuality:
            return "Good idea, weak packaging or distribution."
        case .lowReachLowQuality:
            return "Weak idea or weak execution."
        }
    }

    private static func nextAction(for category: LearningLoopOutcomeCategory) -> String {
        switch category {
        case .highReachHighQuality:
            return "Repeat the format with a fresh creator-specific angle."
        case .highReachLowQuality:
            return "Keep the distribution lesson but rewrite for audience fit, saves, sends, or follows."
        case .lowReachHighQuality:
            return "Rewrite the hook, first frame, edit, or distribution packaging and try again."
        case .lowReachLowQuality:
            return "Drop or rethink the idea before investing more production time."
        }
    }
}

enum StoryFrameType: String, Codable, CaseIterable, Hashable, Sendable {
    case photo
    case video
    case poll
    case question
    case link
    case repost
    case unknown
}

enum StoryFrameGoal: String, Codable, CaseIterable, Hashable, Sendable {
    case reply
    case tap
    case `continue`
    case link
    case trust
    case unknown
}

struct StoryFrameRawMetrics: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var storySequenceID: UUID
    var storyFrameID: UUID
    var frameIndex: Int
    var frameType: StoryFrameType
    var frameGoal: StoryFrameGoal
    var reach: Int?
    var exits: Int?
    var tapsForward: Int?
    var tapsBack: Int?
    var replies: Int?
    var stickerTaps: Int?
    var linkTaps: Int?

    init(
        id: UUID = UUID(),
        storySequenceID: UUID,
        storyFrameID: UUID = UUID(),
        frameIndex: Int,
        frameType: StoryFrameType,
        frameGoal: StoryFrameGoal,
        reach: Int? = nil,
        exits: Int? = nil,
        tapsForward: Int? = nil,
        tapsBack: Int? = nil,
        replies: Int? = nil,
        stickerTaps: Int? = nil,
        linkTaps: Int? = nil
    ) {
        self.id = id
        self.storySequenceID = storySequenceID
        self.storyFrameID = storyFrameID
        self.frameIndex = frameIndex
        self.frameType = frameType
        self.frameGoal = frameGoal
        self.reach = reach
        self.exits = exits
        self.tapsForward = tapsForward
        self.tapsBack = tapsBack
        self.replies = replies
        self.stickerTaps = stickerTaps
        self.linkTaps = linkTaps
    }
}

struct StoryFrameDerivedMetrics: Codable, Hashable, Sendable {
    var storySequenceID: UUID
    var storyFrameID: UUID
    var frameIndex: Int
    var storyFrameExitRate: Double?
    var storyFrameReplyRate: Double?
    var storyFrameStickerTapRate: Double?
    var storyFrameLinkTapRate: Double?
    var tapsForward: Int?
}

struct StorySequenceMetrics: Codable, Hashable, Sendable {
    var storySequenceID: UUID
    var frameCount: Int
    var storySequenceCompletionRate: Double?
}

struct StoryMetricsCalculator {
    func calculateFrameMetrics(
        frames: [StoryFrameRawMetrics]
    ) -> [StoryFrameDerivedMetrics] {
        frames.map { frame in
            let reach = DerivedMetricsCalculator.double(frame.reach)
            return StoryFrameDerivedMetrics(
                storySequenceID: frame.storySequenceID,
                storyFrameID: frame.storyFrameID,
                frameIndex: frame.frameIndex,
                storyFrameExitRate: DerivedMetricsCalculator.safeDivide(
                    DerivedMetricsCalculator.double(frame.exits),
                    reach
                ),
                storyFrameReplyRate: DerivedMetricsCalculator.safeDivide(
                    DerivedMetricsCalculator.double(frame.replies),
                    reach
                ),
                storyFrameStickerTapRate: DerivedMetricsCalculator.safeDivide(
                    DerivedMetricsCalculator.double(frame.stickerTaps),
                    reach
                ),
                storyFrameLinkTapRate: DerivedMetricsCalculator.safeDivide(
                    DerivedMetricsCalculator.double(frame.linkTaps),
                    reach
                ),
                tapsForward: frame.tapsForward
            )
        }
    }

    func calculateSequenceMetrics(
        frames: [StoryFrameRawMetrics]
    ) -> StorySequenceMetrics? {
        guard
            let first = frames.min(by: { $0.frameIndex < $1.frameIndex }),
            let last = frames.max(by: { $0.frameIndex < $1.frameIndex })
        else {
            return nil
        }

        return StorySequenceMetrics(
            storySequenceID: first.storySequenceID,
            frameCount: frames.count,
            storySequenceCompletionRate: DerivedMetricsCalculator.safeDivide(
                DerivedMetricsCalculator.double(last.reach),
                DerivedMetricsCalculator.double(first.reach)
            )
        )
    }
}

enum TrendSourceType: String, Codable, CaseIterable, Hashable, Sendable {
    case instagramReelLink = "instagram_reel_link"
    case competitorPost = "competitor_post"
    case trendingAudioNote = "trending_audio_note"
    case screenshot
    case caption
    case brandBrief = "brand_brief"
    case contentNote = "content_note"
}

enum TrendLabel: String, Codable, CaseIterable, Hashable, Sendable {
    case useNow = "use_now"
    case adaptCarefully = "adapt_carefully"
    case ignore
    case saveForLater = "save_for_later"
}

struct TrendSource: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var creatorID: UUID
    var sourceType: TrendSourceType
    var sourceURL: String?
    var observedPattern: String?
    var whyItWorked: String?
    var creatorFitScore: Double?
    var audienceFitScore: Double?
    var adaptationRisk: String?
    var suggestedCreatorAngle: String?
    var ignoreReason: String?
    var label: TrendLabel
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        creatorID: UUID,
        sourceType: TrendSourceType,
        sourceURL: String? = nil,
        observedPattern: String? = nil,
        whyItWorked: String? = nil,
        creatorFitScore: Double? = nil,
        audienceFitScore: Double? = nil,
        adaptationRisk: String? = nil,
        suggestedCreatorAngle: String? = nil,
        ignoreReason: String? = nil,
        label: TrendLabel,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.creatorID = creatorID
        self.sourceType = sourceType
        self.sourceURL = sourceURL
        self.observedPattern = observedPattern
        self.whyItWorked = whyItWorked
        self.creatorFitScore = creatorFitScore
        self.audienceFitScore = audienceFitScore
        self.adaptationRisk = adaptationRisk
        self.suggestedCreatorAngle = suggestedCreatorAngle
        self.ignoreReason = ignoreReason
        self.label = label
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
