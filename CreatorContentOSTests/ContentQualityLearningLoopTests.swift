import XCTest
@testable import CreatorContentOS

final class ContentQualityLearningLoopTests: XCTestCase {
    func testPrePublishScoringUsesVersionedWeightsAndWeakestCategories() {
        let score = PrePublishQualityScorer().score(
            categoryEvidence: [
                .openingAttention: .init(score: 90, explanation: "Clear first frame."),
                .retentionArchitecture: .init(score: 80, explanation: "Good pacing."),
                .creatorVoiceSpecificity: .init(score: 100, explanation: "Sounds like the creator."),
                .audienceGoalFit: .init(
                    score: 70,
                    explanation: "Audience is a little broad.",
                    suggestedImprovements: ["Name the target viewer."]
                ),
                .saveShareTrigger: .init(
                    score: 60,
                    explanation: "Save reason is weak.",
                    suggestedImprovements: ["Add a real save/send reason."]
                ),
                .accessibilityComprehension: .init(score: 100, explanation: "Works silent."),
                .formatProductionFit: .init(score: 80, explanation: "Shootable.")
            ]
        )

        XCTAssertEqual(score.qualityVersion, LearningLoopVersion.prePublishQuality)
        XCTAssertEqual(score.overallScore, 82.5, accuracy: 0.001)
        XCTAssertEqual(score.publishRecommendation, .improveWeakestSection)
        XCTAssertEqual(score.label, .good)
        XCTAssertEqual(score.weakestCategories.first, .saveShareTrigger)
        XCTAssertTrue(score.suggestedImprovements.contains("Add a real save/send reason."))
    }

    func testBlockingHardGateOverridesHighWeightedScore() {
        let blockingGate = HardGateResult(
            version: LearningLoopVersion.hardGates,
            checks: [
                HardGateCheck(
                    gate: .noThirdPartyWatermark,
                    passed: false,
                    severity: .blocking,
                    explanation: "Third-party watermark is present.",
                    suggestedFix: "Export without the watermark."
                )
            ]
        )

        let score = PrePublishQualityScorer().score(
            categoryEvidence: perfectQualityEvidence(),
            hardGateResult: blockingGate
        )

        XCTAssertEqual(score.overallScore, 100, accuracy: 0.001)
        XCTAssertEqual(score.publishRecommendation, .doNotPublish)
        XCTAssertEqual(score.label, .blocked)
        XCTAssertTrue(score.hardGateResult.blocksPublishing)
        XCTAssertEqual(score.hardGateResult.failedBlockingGates.map(\.gate), [.noThirdPartyWatermark])
    }

    func testWarningHardGateDoesNotBlockPublishingRecommendation() {
        let warningGate = HardGateResult(
            version: LearningLoopVersion.hardGates,
            checks: [
                HardGateCheck(
                    gate: .recommendationEligible,
                    passed: false,
                    severity: .warning,
                    explanation: "Discovery reel may run over 90 seconds.",
                    suggestedFix: "Cut a shorter discovery edit.",
                    blocksPublishing: false
                )
            ]
        )

        let score = PrePublishQualityScorer().score(
            categoryEvidence: perfectQualityEvidence(),
            hardGateResult: warningGate
        )

        XCTAssertFalse(score.hardGateResult.blocksPublishing)
        XCTAssertEqual(score.publishRecommendation, .recommendPublish)
    }

    func testDerivedMetricsCalculateFormulasAndPreserveMetricQuality() {
        let raw = PostPublishRawMetrics(
            contentID: UUID(),
            creatorID: UUID(),
            format: .reel,
            collectedAt: Date(timeIntervalSince1970: 0),
            window: .twentyFourHours,
            followersAtPublish: 500,
            durationSec: 24,
            primaryMetricGoal: .reach,
            metricSource: .manual,
            dataQuality: .partial,
            views: 1_300,
            reach: 1_000,
            nonFollowerReach: 700,
            likes: 40,
            comments: 10,
            saves: 5,
            shares: 4,
            sends: 10,
            totalInteractions: 100,
            follows: 2,
            profileVisits: 20,
            profileLinkTaps: 5,
            websiteTaps: 3,
            reelWatchTime: 12_000,
            reelAverageWatchTime: 12,
            storyReach: 500,
            storyReplies: 10,
            storyExits: 50,
            storyStickerTaps: 25,
            firstFrameReach: 500,
            finalFrameReach: 400,
            commentQualityScore: 4.2,
            meaningfulCommentCount: 5,
            questionCommentCount: 2,
            negativeCommentCount: 1,
            commentSentiment: .positive,
            audienceFitScore: 4.5,
            brandFitScore: 4
        )

        let metrics = DerivedMetricsCalculator().calculate(raw: raw)

        XCTAssertEqual(metrics.version, LearningLoopVersion.derivedMetrics)
        XCTAssertEqual(metrics.metricSource, MetricSource.manual)
        XCTAssertEqual(metrics.dataQuality, MetricDataQuality.partial)
        assertOptionalEqual(metrics.distribution.reachMultiplier, 2)
        assertOptionalEqual(metrics.distribution.nonFollowerReachRate, 0.7)
        assertOptionalEqual(metrics.distribution.viewFrequency, 1.3)
        XCTAssertEqual(metrics.distribution.inferredReplays, 300)
        assertOptionalEqual(metrics.distribution.inferredReplayRate, 0.3)
        assertOptionalEqual(metrics.retention.avgWatchPct, 0.5)
        assertOptionalEqual(metrics.retention.watchTimePerReachedUser, 12)
        assertOptionalEqual(metrics.engagement.engagementRateByReach, 0.1)
        assertOptionalEqual(metrics.engagement.weightedInteractions, 153)
        assertOptionalEqual(metrics.engagement.weightedEngagementRate, 0.153)
        assertOptionalEqual(metrics.durableValue.saveRateByReach, 0.005)
        assertOptionalEqual(metrics.socialSpread.sendRateByReach, 0.01)
        assertOptionalEqual(metrics.socialSpread.shareRateByReach, 0.004)
        assertOptionalEqual(metrics.socialSpread.socialSpreadRate, 0.014)
        assertOptionalEqual(metrics.conversion.profileVisitRateByReach, 0.02)
        assertOptionalEqual(metrics.conversion.followRateByReach, 0.002)
        assertOptionalEqual(metrics.conversion.profileToFollowRate, 0.1)
        assertOptionalEqual(metrics.conversion.linkTapRateByProfileVisit, 0.25)
        assertOptionalEqual(metrics.stories.storyCompletionRate, 0.8)
        assertOptionalEqual(metrics.quality.meaningfulCommentRate, 0.5)
        XCTAssertEqual(metrics.quality.commentSentiment, .positive)
    }

    func testDerivedMetricsReturnNilForNullZeroAndMissingSplits() {
        let raw = PostPublishRawMetrics(
            contentID: UUID(),
            creatorID: UUID(),
            format: .reel,
            window: .twentyFourHours,
            followersAtPublish: 0,
            durationSec: 0,
            primaryMetricGoal: .reach,
            metricSource: .screenshot,
            dataQuality: .estimated,
            reach: 0,
            comments: 0,
            shares: 5
        )

        let metrics = DerivedMetricsCalculator().calculate(raw: raw)

        XCTAssertNil(metrics.distribution.reachMultiplier)
        XCTAssertNil(metrics.distribution.viewFrequency)
        XCTAssertNil(metrics.retention.avgWatchPct)
        XCTAssertNil(metrics.socialSpread.sendRateByReach)
        XCTAssertNil(metrics.socialSpread.socialSpreadRate)
        XCTAssertNil(metrics.engagement.weightedEngagementRate)
        XCTAssertNil(metrics.quality.meaningfulCommentRate)
        XCTAssertNil(metrics.socialSpread.shareRateByReach)
        XCTAssertEqual(metrics.metricSource, MetricSource.screenshot)
        XCTAssertEqual(metrics.dataQuality, MetricDataQuality.estimated)
    }

    func testGoalSpecificPerformanceScoringUsesConfiguredVersionedFormulas() {
        let derived = derivedAtStrongThresholds()
        let scorer = PostPublishPerformanceScorer()

        for goal in [MetricGoal.reach, .saves, .trust, .brandCollab, .community, .linkTaps, .comments] {
            let score = scorer.score(derived: derived, primaryGoal: goal)
            XCTAssertEqual(score.weightsVersion, LearningLoopVersion.goalPerformanceWeights)
            assertOptionalEqual(score.performanceScore, 100, "Goal \(goal.rawValue) should score all strong threshold signals as 100.")
            XCTAssertEqual(score.goalFitResult, .strong)
            XCTAssertFalse(score.strongestSignals.isEmpty)
        }
    }

    func testPerformanceScoringNormalizesAcrossAvailableSignals() {
        let derived = makeDerived(
            reachMultiplier: nil,
            nonFollowerReachRate: nil,
            viewFrequency: nil,
            avgWatchPct: 0.25,
            saveRateByReach: nil,
            sendRateByReach: nil,
            shareRateByReach: nil,
            socialSpreadRate: nil,
            followRateByReach: nil,
            profileVisitRateByReach: nil,
            profileToFollowRate: nil,
            linkTapRateByProfileVisit: nil,
            websiteTapRateByReach: nil,
            meaningfulCommentRate: nil,
            commentQualityScore: nil,
            audienceFitScore: nil,
            brandFitScore: nil
        )

        let score = PostPublishPerformanceScorer().score(derived: derived, primaryGoal: .reach)

        assertOptionalEqual(score.performanceScore, 50)
        XCTAssertEqual(score.goalFitResult, .mixed)
        XCTAssertEqual(score.weakestSignals.first?.key, .avgWatchPct)
    }

    func testBaselineCalculatesMediansTopThresholdsLiftsAndExcludesPaidByDefault() {
        let service = CreatorBaselineService()
        var samples: [PostPublishLearningSample] = []
        for index in 1...6 {
            let value = Double(index)
            let sample = learningSample(
                sendRateByReach: value / 1_000,
                saveRateByReach: value / 2_000,
                followRateByReach: value / 10_000,
                avgWatchPct: value / 10,
                profileVisitRateByReach: value / 1_000,
                reachMultiplier: value,
                paidOrBoosted: false
            )
            samples.append(sample)
        }
        samples.append(
            learningSample(
                sendRateByReach: 1,
                saveRateByReach: 1,
                followRateByReach: 1,
                avgWatchPct: 1,
                profileVisitRateByReach: 1,
                reachMultiplier: 100,
                paidOrBoosted: true
            )
        )

        let baseline = service.computeBaseline(samples: samples, filter: .init(format: .reel))
        let current = makeDerived(
            reachMultiplier: 4,
            avgWatchPct: 0.7,
            saveRateByReach: 0.0035,
            sendRateByReach: 0.007,
            followRateByReach: 0.0007,
            profileVisitRateByReach: 0.007
        )
        let lifts = service.computeLifts(current: current, baseline: baseline)

        XCTAssertEqual(baseline.version, LearningLoopVersion.baseline)
        XCTAssertEqual(baseline.sampleCount, 6)
        XCTAssertEqual(baseline.confidence, BaselineConfidence.partial)
        assertOptionalEqual(baseline.median.sendRateByReach, 0.0035, accuracy: 0.000001)
        assertOptionalEqual(baseline.top25Percent.sendRateByReach, 0.005, accuracy: 0.000001)
        assertOptionalEqual(baseline.top10Percent.sendRateByReach, 0.006, accuracy: 0.000001)
        assertOptionalEqual(lifts.sendRateLift, 2)
        assertOptionalEqual(lifts.saveRateLift, 2)

        let insufficient = service.computeBaseline(samples: Array(samples.prefix(4)))
        XCTAssertEqual(insufficient.confidence, BaselineConfidence.insufficient)

        let none = service.computeBaseline(samples: [])
        XCTAssertEqual(none.confidence, BaselineConfidence.none)
        XCTAssertNil(none.median.sendRateByReach)
    }

    func testLearningLoopClassifiesReachAndQualityQuadrants() {
        let analyzer = LearningLoopAnalyzer()

        XCTAssertEqual(
            analyzer.classifyOutcome(derived: makeClassificationDerived(highReach: true, highQuality: true)).category,
            .highReachHighQuality
        )
        XCTAssertEqual(
            analyzer.classifyOutcome(derived: makeClassificationDerived(highReach: true, highQuality: false)).category,
            .highReachLowQuality
        )
        XCTAssertEqual(
            analyzer.classifyOutcome(derived: makeClassificationDerived(highReach: false, highQuality: true)).category,
            .lowReachHighQuality
        )
        XCTAssertEqual(
            analyzer.classifyOutcome(derived: makeClassificationDerived(highReach: false, highQuality: false)).category,
            .lowReachLowQuality
        )
    }

    func testStoryFrameMetricsPreserveTapForwardWithoutPenalizingIt() throws {
        let sequenceID = UUID()
        let frames = [
            StoryFrameRawMetrics(
                storySequenceID: sequenceID,
                frameIndex: 0,
                frameType: .poll,
                frameGoal: .tap,
                reach: 100,
                exits: 10,
                tapsForward: 80,
                replies: 5,
                stickerTaps: 20
            ),
            StoryFrameRawMetrics(
                storySequenceID: sequenceID,
                frameIndex: 1,
                frameType: .link,
                frameGoal: .link,
                reach: 60,
                exits: 6,
                tapsForward: 20,
                replies: 3,
                stickerTaps: 12,
                linkTaps: 9
            )
        ]

        let calculator = StoryMetricsCalculator()
        let frameMetrics = calculator.calculateFrameMetrics(frames: frames)
        let sequenceMetrics = try XCTUnwrap(calculator.calculateSequenceMetrics(frames: frames))

        assertOptionalEqual(frameMetrics[0].storyFrameExitRate, 0.10)
        assertOptionalEqual(frameMetrics[0].storyFrameReplyRate, 0.05)
        assertOptionalEqual(frameMetrics[0].storyFrameStickerTapRate, 0.20)
        XCTAssertEqual(frameMetrics[0].tapsForward, 80)
        assertOptionalEqual(frameMetrics[1].storyFrameLinkTapRate, 0.15)
        assertOptionalEqual(sequenceMetrics.storySequenceCompletionRate, 0.60)
    }

    private func assertOptionalEqual(
        _ actual: Double?,
        _ expected: Double,
        _ message: String = "",
        accuracy: Double = 0.001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected \(expected), got nil. \(message)", file: file, line: line)
            return
        }
        XCTAssertEqual(actual, expected, accuracy: accuracy, message, file: file, line: line)
    }

    private func perfectQualityEvidence() -> [PrePublishQualityCategory: QualityCategoryEvidence] {
        Dictionary(uniqueKeysWithValues: PrePublishQualityCategory.allCases.map {
            ($0, QualityCategoryEvidence(score: 100, explanation: "Strong."))
        })
    }

    private func derivedAtStrongThresholds() -> DerivedMetrics {
        makeDerived(
            reachMultiplier: 3,
            nonFollowerReachRate: 0.60,
            viewFrequency: 1.50,
            avgWatchPct: 0.50,
            saveRateByReach: 0.005,
            sendRateByReach: 0.010,
            shareRateByReach: 0.005,
            socialSpreadRate: 0.015,
            followRateByReach: 0.002,
            profileVisitRateByReach: 0.020,
            profileToFollowRate: 0.20,
            linkTapRateByProfileVisit: 0.20,
            websiteTapRateByReach: 0.010,
            meaningfulCommentRate: 0.40,
            commentQualityScore: 4,
            commentSentiment: .positive,
            audienceFitScore: 4,
            brandFitScore: 4,
            storyCompletionRate: nil,
            storyReplyRate: nil
        )
    }

    private func makeClassificationDerived(
        highReach: Bool,
        highQuality: Bool
    ) -> DerivedMetrics {
        makeDerived(
            reachMultiplier: highReach ? 3.1 : 1.2,
            nonFollowerReachRate: highReach ? 0.65 : 0.20,
            avgWatchPct: highQuality ? 0.55 : 0.20,
            saveRateByReach: highQuality ? 0.006 : 0.001,
            sendRateByReach: highQuality ? 0.011 : 0.001,
            followRateByReach: highQuality ? 0.003 : 0.0003,
            profileToFollowRate: highQuality ? 0.25 : 0.05,
            commentQualityScore: highQuality ? 4.2 : 2.0,
            audienceFitScore: highQuality ? 4.3 : 2.0,
            brandFitScore: highQuality ? 4.0 : 2.0
        )
    }

    private func learningSample(
        sendRateByReach: Double,
        saveRateByReach: Double,
        followRateByReach: Double,
        avgWatchPct: Double,
        profileVisitRateByReach: Double,
        reachMultiplier: Double,
        paidOrBoosted: Bool
    ) -> PostPublishLearningSample {
        PostPublishLearningSample(
            format: .reel,
            contentPillar: "education",
            hookType: "identity",
            durationBand: .fifteenTo30,
            paidOrBoosted: paidOrBoosted,
            derived: makeDerived(
                reachMultiplier: reachMultiplier,
                avgWatchPct: avgWatchPct,
                saveRateByReach: saveRateByReach,
                sendRateByReach: sendRateByReach,
                followRateByReach: followRateByReach,
                profileVisitRateByReach: profileVisitRateByReach
            )
        )
    }

    private func makeDerived(
        reachMultiplier: Double? = nil,
        nonFollowerReachRate: Double? = nil,
        viewFrequency: Double? = nil,
        avgWatchPct: Double? = nil,
        saveRateByReach: Double? = nil,
        sendRateByReach: Double? = nil,
        shareRateByReach: Double? = nil,
        socialSpreadRate: Double? = nil,
        followRateByReach: Double? = nil,
        profileVisitRateByReach: Double? = nil,
        profileToFollowRate: Double? = nil,
        linkTapRateByProfileVisit: Double? = nil,
        websiteTapRateByReach: Double? = nil,
        meaningfulCommentRate: Double? = nil,
        commentQualityScore: Double? = nil,
        commentSentiment: CommentSentiment = .unknown,
        audienceFitScore: Double? = nil,
        brandFitScore: Double? = nil,
        storyCompletionRate: Double? = nil,
        storyReplyRate: Double? = nil
    ) -> DerivedMetrics {
        DerivedMetrics(
            version: LearningLoopVersion.derivedMetrics,
            metricSource: .manual,
            dataQuality: .partial,
            paidOrBoosted: false,
            weightedEngagementWeightsVersion: LearningLoopVersion.weightedEngagement,
            distribution: .init(
                reachMultiplier: reachMultiplier,
                nonFollowerReachRate: nonFollowerReachRate,
                viewFrequency: viewFrequency,
                inferredReplays: nil,
                inferredReplayRate: nil
            ),
            retention: .init(
                avgWatchPct: avgWatchPct,
                watchTimePerReachedUser: nil,
                completionProxy: avgWatchPct,
                skipRate: nil
            ),
            engagement: .init(
                engagementRateByReach: nil,
                weightedInteractions: nil,
                weightedEngagementRate: nil,
                likeRateByReach: nil,
                commentRateByReach: nil
            ),
            durableValue: .init(saveRateByReach: saveRateByReach),
            socialSpread: .init(
                sendRateByReach: sendRateByReach,
                shareRateByReach: shareRateByReach,
                socialSpreadRate: socialSpreadRate
            ),
            conversion: .init(
                profileVisitRateByReach: profileVisitRateByReach,
                followRateByReach: followRateByReach,
                profileToFollowRate: profileToFollowRate,
                linkTapRateByProfileVisit: linkTapRateByProfileVisit,
                websiteTapRateByReach: websiteTapRateByReach
            ),
            stories: .init(
                storyExitRate: nil,
                storyReplyRate: storyReplyRate,
                storyStickerTapRate: nil,
                storyCompletionRate: storyCompletionRate
            ),
            quality: .init(
                commentQualityScore: commentQualityScore,
                meaningfulCommentRate: meaningfulCommentRate,
                questionRate: nil,
                negativeCommentRate: nil,
                commentSentiment: commentSentiment,
                audienceFitScore: audienceFitScore,
                brandFitScore: brandFitScore
            )
        )
    }
}
