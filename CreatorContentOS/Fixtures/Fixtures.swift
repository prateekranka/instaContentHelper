import Foundation

#if DEBUG
/// Realistic edge cases supplied at the fixture boundary, as required by break-ui.
enum PocketUIFixtureData: String, CaseIterable, Identifiable {
    case demo, worst, empty, one, huge
    var id: String { rawValue }

    var label: String {
        switch self {
        case .demo: "Demo data"
        case .worst: "Worst case"
        case .empty: "Empty"
        case .one: "One"
        case .huge: "1,284"
        }
    }

    func applying(to original: GeneratedDailyCardDraft) -> GeneratedDailyCardDraft {
        guard self != .demo else { return original }
        var copy = original
        copy.shotTimeline = []
        copy.voiceoverTimeline = []
        copy.silentVersionTimeline = []
        copy.onScreenTextTimeline = []
        copy.storyboardThumbnailAssets = []
        switch self {
        case .demo: break
        case .worst:
            copy.title = "Đặng Thị Ngọc Hân — the small creative routine that helped me finish a difficult week without burning out"
            copy.hook = "👩🏽‍💻 One calm minute before the day starts: what would you make if it did not need to be perfect?"
            copy.whyToday = Array(repeating: "A realistic, detailed note about the moment, the audience, and why this small daily routine is worth sharing.", count: 18).joined(separator: " ")
            copy.shootability = "Moderate effort, with a quiet setup and time to repeat each take"
            copy.sourceNote = "https://example.com/workspaces/creative-routines/projects/a-small-moment-worth-sharing/notes/9f8e7d6c5b4a"
            copy.sceneList = [
                ShotScene(number: 1, title: "Aleksandra Wiśniewska-Kowalczyk opens her marked journal and finds the line that stayed", duration: "3 sec", symbol: "book.closed"),
                ShotScene(number: 2, title: "Benachrichtigungseinstellungen", duration: "4 sec", symbol: "text.bubble"),
                ShotScene(number: 3, title: "نور الهدى عبد الرحمن · One honest thought", duration: "3 sec", symbol: "person.crop.rectangle"),
                ShotScene(number: 4, title: "J", duration: "2 sec", symbol: "bookmark")
            ]
            copy.durationSeconds = 12
            copy.script = "Đặng Thị Ngọc Hân · 王秀英 · 👩🏽‍💻 Priya\nA short note can carry a full thought.\n<script>alert(1)</script> &amp; **bold** are literal text here."
            copy.caption = "Small moments count.\n\nA slow morning. A marked page. One honest line, with enough space to read it.\n\nWhat is one small thing you are glad you did today?"
            copy.onScreenText = ["Đặng Thị Ngọc Hân", "王秀英", "👩🏽‍💻 Priya", "J"]
            copy.hashtags = ["creative-routines-and-small-moments-worth-sharing", "SmallMoments"]
        case .empty:
            copy.title = "A thought for today"
            copy.format = "Post"
            copy.durationSeconds = nil
            copy.sceneList = []
            copy.hook = nil
            copy.script = ""
            copy.sourceNote = ""
            copy.onScreenText = []
            copy.hashtags = []
            copy.caption = "You do not need a big update to have something worth sharing."
        case .one:
            copy.title = "One small moment"
            copy.format = "Story"
            copy.durationSeconds = 10
            copy.sceneList = [ShotScene(number: 1, title: "One small moment", duration: "10 sec", symbol: "camera")]
            copy.hook = nil
            copy.onScreenText = ["One small moment"]
        case .huge:
            copy.title = "An imported archive of daily moments"
            copy.durationSeconds = 3_852
            copy.sceneList = (1...1_284).map { number in
                ShotScene(number: number, title: "Daily moment \(number)", duration: "3 sec", symbol: "camera")
            }
            copy.onScreenText = []
        }
        return copy
    }
}

extension GeneratedDailyCardDraft {
    /// Returns the real storyboard fixture with deliberately long copy for
    /// Dynamic Type and narrow-screen e2e checks.
    var withLongContent: GeneratedDailyCardDraft {
        var copy = self
        copy.title = "The biggest lie women are told after 40 is that getting stronger is no longer for them"
        copy.whyToday = "This deliberately long fixture explains the idea, the creator fit, and the reason to publish today in enough detail to exercise wrapping and scrolling."
        copy.growthJob = "Build trust through a clear, personal strength story that stays useful when the viewer saves it for a later training day."
        copy.contentPillar = "Strength, confidence, and practical training after 40"
        copy.shootability = "Moderate, with ten simple shots and clear substitutions"
        copy.energyRequired = "Medium energy with a calm pace and short recovery between takes"
        copy.hook = "The biggest lie women are told after 40? That getting stronger is not for them anymore."
        copy.saveShareReason = "Save this when you need a direct reminder that strength training remains available, useful, and worth starting at any age."
        copy.sceneList = copy.sceneList.map { scene in
            var scene = scene
            scene.title += " — show the detail clearly before moving to the next part"
            scene.duration = "3 sec, with a steady pause for the viewer to follow"
            return scene
        }
        copy.shotTimeline = copy.shotTimeline.map { item in
            var item = item
            item.detail += " Keep the frame stable, leave space around the subject, and repeat the take if the action is hard to read."
            item.videoPortion = (item.videoPortion ?? "") + " Use a clean background and keep the movement easy to understand."
            return item
        }
        copy.voiceoverTimeline = copy.voiceoverTimeline.map { item in
            var item = item
            item.voiceover = (item.voiceover ?? "") + " Take one calm breath before the next line so the message remains clear."
            return item
        }
        copy.onScreenTextTimeline = copy.onScreenTextTimeline.map { item in
            var item = item
            item.onScreenText = (item.onScreenText ?? "") + " — strength is still available to you"
            return item
        }
        copy.script = copy.script
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { "\($0) Keep the language direct, personal, and easy to follow." }
            .joined(separator: "\n")
        copy.noVoiceoverVersion = "Use the same shots with bold captions, generous timing, and enough contrast for a viewer who needs to pause and read each line."
        copy.onScreenText = copy.onScreenText.map { "\($0) — start small and stay consistent" }
        copy.caption = "Strength after 40 is not about proving anything. It is about giving your body more chances to surprise you, one practical and repeatable choice at a time."
        copy.cta = "Save this for the day you need the reminder, then send it to someone who is waiting for permission to begin."
        copy.coverText = "The biggest lie after 40: strength is not for you"
        copy.postInstructions = "Keep the delivery natural and personal. Mix present-day shots with older clips, leave enough time for captions, and choose a cover that remains readable at a small size."
        copy.backupStory = "Post one mirror selfie or gym clip with a short line about starting small, then add the longer explanation in the caption for viewers who want the full context."
        copy.backupCaptionOnly = "Your age is not the limit. The story you keep repeating might be, and you can change that story with one small action today."
        copy.audioOptionNotes = "Use a calm but driving audio bed under the voiceover, and keep it quiet enough that every spoken line remains easy to understand."
        copy.riskNotes = ["Long fixture copy is intentional. Verify scrolling, wrapping, and action visibility before using this route as a UI proof."]
        copy.assumptions = copy.assumptions + ["The e2e launch uses MCO_LONG_CONTENT=1 for accessibility stress coverage."]
        return copy
    }
}
#endif

extension DailyCard {
    /// Placeholder Today card with no scenes — used when `MCO_FORCE_EMPTY_TODAY=1`.
    static let emptyTodayPlaceholder = DailyCard(
        title: "Checking today's plan",
        context: "Today",
        effortLabel: "Loading",
        whyToday: "Your first idea will appear after onboarding.",
        scenes: []
    )

    static let raceWeekToday = DailyCard(
        title: "Race week has entered the house",
        context: "Friday, Race Week",
        effortLabel: "Easy - 12 min",
        whyToday: "Stay visible without overthinking it.",
        hook: "The tiny thing I changed this race week.",
        sourceNote: "Inspired by a race-week discipline pattern.",
        scheduledDate: "2026-06-05",
        scenes: [
            ShotScene(number: 1, title: "Shoes by the door", duration: "3 sec", symbol: "shoeprints.fill"),
            ShotScene(number: 2, title: "Open the journal", duration: "4 sec", symbol: "book.closed"),
            ShotScene(number: 3, title: "Bottle, timer, breath", duration: "3 sec", symbol: "waterbottle"),
            ShotScene(number: 4, title: "One steady stride", duration: "2 sec", symbol: "figure.run")
        ],
        shotTimeline: [
            ProductionTimelineItem(timestamp: "0-3 sec", title: "Shoes by the door", detail: "Frame the shoes ready by the door.", shot: "Wide entryway", videoPortion: "Steady wide shot of shoes waiting."),
            ProductionTimelineItem(timestamp: "3-7 sec", title: "Open the journal", detail: "Open the journal and show the page.", shot: "Hands + journal", videoPortion: "Close-up of the open page."),
            ProductionTimelineItem(timestamp: "7-10 sec", title: "Bottle, timer, breath", detail: "Set the bottle and timer, then take a breath.", shot: "Prep still life", videoPortion: "Quiet prep before leaving."),
            ProductionTimelineItem(timestamp: "10-12 sec", title: "One steady stride", detail: "Step out and hold a calm first stride.", shot: "Walking out", videoPortion: "One clean step into the day.")
        ],
        voiceoverTimeline: [
            ProductionTimelineItem(timestamp: "0-3 sec", title: "Hook", detail: "", voiceover: "Race week starts with the shoes by the door."),
            ProductionTimelineItem(timestamp: "3-7 sec", title: "Journal", detail: "", voiceover: "Then I open the journal and write one honest line."),
            ProductionTimelineItem(timestamp: "7-10 sec", title: "Prep", detail: "", voiceover: "Bottle, timer, breath. Keep it small."),
            ProductionTimelineItem(timestamp: "10-12 sec", title: "Stride", detail: "", voiceover: "One steady stride is enough for today.")
        ],
        script: """
        Race week starts with the shoes by the door.
        Then I open the journal and write one honest line.
        Bottle, timer, breath. Keep it small.
        One steady stride is enough for today.
        """
    )

    static let weekFixtures: [DailyCard] = [
        DailyCard(title: "Reset Monday", context: "Monday, Race Week", effortLabel: "Easy - 10 min", whyToday: "Start clean.", scheduledDate: "2026-06-01", scenes: []),
        DailyCard(title: "Sharpen, don't chase", context: "Tuesday, Race Week", effortLabel: "Medium - 14 min", whyToday: "Keep pace honest.", scheduledDate: "2026-06-02", scenes: []),
        DailyCard(title: "Fuel the engine", context: "Wednesday, Race Week", effortLabel: "Easy - 8 min", whyToday: "Make recovery visible.", scheduledDate: "2026-06-03", scenes: []),
        DailyCard(title: "Shakeout and mindset", context: "Thursday, Race Week", effortLabel: "Easy - 9 min", whyToday: "Low effort prep before race day.", scheduledDate: "2026-06-04", scenes: []),
        .raceWeekToday,
        DailyCard(title: "Race day. Let's go.", context: "Saturday, Race Week", effortLabel: "Backup - 8 min", whyToday: "Puma mention needs a disclosure line.", scheduledDate: "2026-06-06", scenes: []),
        DailyCard(title: "Open family moment", context: "Sunday, Race Week", effortLabel: "Open - confirm", whyToday: "Choose only if the day feels natural.", scheduledDate: "2026-06-07", scenes: [])
    ]
}

extension ArchiveEntry {
    static let fixtures: [ArchiveEntry] = [
        ArchiveEntry(day: "TUE", date: "3 JUN", cardTitle: "Race week has entered the house", decision: .posted, outputLine: "Posted", hasPostThumbnail: true),
        ArchiveEntry(day: "MON", date: "2 JUN", cardTitle: "Keep it simple", decision: .usedBackup, outputLine: "Used backup", hasPostThumbnail: false),
        ArchiveEntry(day: "SUN", date: "1 JUN", cardTitle: "Rest today", decision: .savedForTomorrow, outputLine: "Saved for tomorrow", hasPostThumbnail: false),
        ArchiveEntry(day: "SAT", date: "31 MAY", cardTitle: "Not the right day", decision: .skippedIntentionally, outputLine: "Skipped after decision", hasPostThumbnail: false)
    ]
}

extension WeeklyPlan {
    static let raceWeek = WeeklyPlan(
        title: "Generate a Week",
        eyebrow: "MANAGER WEEKLY CONTROL",
        weekRange: "1 Jun - 7 Jun",
        weekStartDate: "2026-06-01",
        weekEndDate: "2026-06-07",
        readinessLine: "5 ready, 1 backup, 1 open",
        isSoftLocked: false,
        days: [
            WeeklyDay(
                weekday: "MON",
                date: "01",
                scheduledDate: "2026-06-01",
                title: "Reset Monday",
                reason: "Routine after a full weekend.",
                source: .routine,
                state: .planned,
                isSoftLocked: false
            ),
            WeeklyDay(
                weekday: "TUE",
                date: "02",
                scheduledDate: "2026-06-02",
                title: "Sharpen, don't chase",
                reason: "Routine keeps pace honest.",
                source: .routine,
                state: .planned,
                isSoftLocked: false
            ),
            WeeklyDay(
                weekday: "WED",
                date: "03",
                scheduledDate: "2026-06-03",
                title: "Fuel the engine",
                reason: "Trend works only if the audio clears.",
                source: .trend,
                state: .backup,
                isSoftLocked: false
            ),
            WeeklyDay(
                weekday: "THU",
                date: "04",
                scheduledDate: "2026-06-04",
                title: "Shakeout and mindset",
                reason: "Low-effort prep before race day.",
                source: .routine,
                state: .planned,
                isSoftLocked: false
            ),
            WeeklyDay(
                weekday: "FRI",
                date: "05",
                scheduledDate: "2026-06-05",
                title: "Race week has entered the house",
                reason: "Pattern fits current training energy.",
                source: .pattern,
                state: .planned,
                isSoftLocked: false
            ),
            WeeklyDay(
                weekday: "SAT",
                date: "06",
                scheduledDate: "2026-06-06",
                title: "Race day. Let's go.",
                reason: "Puma mention needs a disclosure line.",
                source: .brand,
                state: .backup,
                isSoftLocked: false
            ),
            WeeklyDay(
                weekday: "SUN",
                date: "07",
                scheduledDate: "2026-06-07",
                title: "Open family moment",
                reason: "Choose only if the day feels natural.",
                source: .moment,
                state: .open,
                isSoftLocked: false
            )
        ],
        weeklyBriefText: "Mumbai race week. Early mornings are best. Keep the week practical: 3 runs, 1 gym, 1 race, family on Sunday, Puma disclosure on Saturday, and no politics, weight talk, or negativity.",
        setupSections: [
            WeeklySetupSection(systemImage: "mappin.and.ellipse", title: "Place", summary: "Mumbai, race week, early mornings.", state: "Ready"),
            WeeklySetupSection(systemImage: "dumbbell", title: "Body", summary: "3 runs, 1 gym, 1 race.", state: "Ready"),
            WeeklySetupSection(systemImage: "person.2", title: "Family", summary: "Parents in town on Sunday.", state: "Ready"),
            WeeklySetupSection(systemImage: "briefcase", title: "Obligations", summary: "Puma disclosure needed for Saturday.", state: "Needs detail"),
            WeeklySetupSection(systemImage: "waveform.path.ecg", title: "Source pulse", summary: "6 approved trends/audio options.", state: "Ready"),
            WeeklySetupSection(systemImage: "nosign", title: "Boundaries", summary: "No politics, weight talk, or negativity.", state: "Ready")
        ]
    )
}

extension WeeklyIdea {
    static let raceWeekBank: [WeeklyIdea] = [
        WeeklyIdea(
            title: "The quiet pre-race dinner",
            reason: "A real family moment without overproducing.",
            source: .moment,
            effortLabel: "Easy"
        ),
        WeeklyIdea(
            title: "What I pack before a 10K",
            reason: "Useful, simple, and brand-safe.",
            source: .routine,
            effortLabel: "Easy"
        ),
        WeeklyIdea(
            title: "One song, one steady stride",
            reason: "Audio-first reel with a fallback caption.",
            source: .audio,
            effortLabel: "Medium"
        ),
        WeeklyIdea(
            title: "Race morning non-negotiables",
            reason: "Clear prep list for followers who train.",
            source: .pattern,
            effortLabel: "Easy"
        ),
        WeeklyIdea(
            title: "How I calm nerves at sixty",
            reason: "High-trust, personal, and not preachy.",
            source: .pattern,
            effortLabel: "Medium"
        ),
        WeeklyIdea(
            title: "Shoe check, then go",
            reason: "Fast backup if the schedule slips.",
            source: .trend,
            effortLabel: "Low"
        )
    ]
}

extension IntelligenceHome {
    static let raceWeekLibrary = IntelligenceHome(
        sourcePulse: SourcePulseSummary(
            title: "Source Pulse",
            subtitle: "Manual references from this week.",
            references: [
                ReferenceSummary(
                    title: "Track screenshot",
                    sourceType: "Screenshot",
                    note: "Golden hour run, USA feed.",
                    state: .needsReview,
                    symbol: "photo"
                ),
                ReferenceSummary(
                    title: "Gym mirror format",
                    sourceType: "Reel link",
                    note: "Needs fit check for Creator.",
                    state: .needsReview,
                    symbol: "link"
                ),
                ReferenceSummary(
                    title: "Calm Drive",
                    sourceType: "Audio link",
                    note: "Verified fallback audio.",
                    state: .approved,
                    symbol: "music.note"
                )
            ]
        ),
        readyForThisWeek: [
            IntelligenceItem(
                title: "Discipline on hard days",
                subtitle: "A grounded race-week pattern.",
                kind: .pattern,
                state: .ready,
                trailingNote: "High fit",
                symbol: "sun.max"
            ),
            IntelligenceItem(
                title: "Race week truth",
                subtitle: "One honest training thought.",
                kind: .idea,
                state: .ready,
                trailingNote: "Easy",
                symbol: "lightbulb"
            ),
            IntelligenceItem(
                title: "Calm Drive",
                subtitle: "Instrumental, 96 BPM.",
                kind: .audio,
                state: .approved,
                trailingNote: "Verified",
                symbol: "music.note"
            )
        ],
        needsReview: [
            IntelligenceItem(
                id: UUID(uuidString: "2B01A874-F839-4F01-9D63-842D8D1BB701")!,
                title: "Real training highlight",
                subtitle: "USA reel structure, not the script.",
                kind: .trend,
                state: .needsReview,
                trailingNote: "Check fit",
                symbol: "sparkle.magnifyingglass",
                typeChip: .reel,
                sourceURL: "https://www.instagram.com/reel/fixture-training-highlight/",
                reviewItem: ReferenceReviewItem(
                    kind: .sourceReference,
                    id: UUID(uuidString: "D0DA7C7B-E52B-48FD-BBC4-1201B5E7B801")!
                )
            ),
            IntelligenceItem(
                id: UUID(uuidString: "6477C1F0-3DB4-4A46-B0EB-FE5A10B97C64")!,
                title: "Gym mirror format",
                subtitle: "Could feel too generic.",
                kind: .pattern,
                state: .needsReview,
                trailingNote: "Low fit",
                symbol: "rectangle.on.rectangle",
                typeChip: .unknown,
                reviewItem: ReferenceReviewItem(
                    kind: .sourceReference,
                    id: UUID(uuidString: "E0F2B681-BCF5-4B0D-93C7-BC896E09D9D8")!
                )
            )
        ],
        ideaCandidates: [
            IntelligenceItem(
                title: "Workout truth in 10 seconds",
                subtitle: "Story fallback if the reel slips.",
                kind: .idea,
                state: .ready,
                trailingNote: "10 sec",
                symbol: "lightbulb"
            ),
            IntelligenceItem(
                title: "Race morning non-negotiables",
                subtitle: "Shootable list from the weekly setup.",
                kind: .idea,
                state: .approved,
                trailingNote: "Easy",
                symbol: "checklist"
            ),
            IntelligenceItem(
                title: "Parents in town, no performance",
                subtitle: "Family moment with no forced filming.",
                kind: .idea,
                state: .needsReview,
                trailingNote: "Confirm",
                symbol: "person.2"
            )
        ],
        recentlyUsed: [
            IntelligenceItem(
                title: "Race day. Let's go.",
                subtitle: "Used for Saturday card.",
                kind: .idea,
                state: .usedThisWeek,
                trailingNote: "2 days ago",
                symbol: "figure.run"
            ),
            IntelligenceItem(
                title: "Shakeout mindset",
                subtitle: "Low-effort prep format.",
                kind: .pattern,
                state: .usedThisWeek,
                trailingNote: "4 days ago",
                symbol: "shoeprints.fill"
            )
        ],
        librarySections: [
            IntelligenceLibrarySection(title: "Watchlists", subtitle: "Creator formats to learn from.", count: 12, symbol: "bookmark"),
            IntelligenceLibrarySection(title: "Benchmark Creators", subtitle: "Reference creators, not scripts.", count: 18, symbol: "person.2"),
            IntelligenceLibrarySection(title: "Patterns", subtitle: "Reusable Creator-safe structures.", count: 24, symbol: "sun.max"),
            IntelligenceLibrarySection(title: "Trends", subtitle: "Manual USA feed observations.", count: 19, symbol: "sparkle.magnifyingglass"),
            IntelligenceLibrarySection(title: "Audio Options", subtitle: "Verified and fallback sounds.", count: 16, symbol: "music.note"),
            IntelligenceLibrarySection(title: "Ideas", subtitle: "Prepared card candidates.", count: 23, symbol: "lightbulb")
        ]
    )
}

struct FakeGenerationOutput {
    func makeResult(scheduledDate: String, dayBrief: String, revisionID: UUID = UUID()) -> DailyGenerationResult {
        let trimmedBrief = dayBrief.trimmingCharacters(in: .whitespacesAndNewlines)
        let pillar = inferredContentPillar(from: trimmedBrief)
        let title = synthesizedTitle(from: trimmedBrief, pillar: pillar)
        let script = synthesizedScript(from: trimmedBrief, pillar: pillar)
        let format = fixtureFormat(from: trimmedBrief)
        let duration = format == "Post" ? nil : requestedDuration(from: trimmedBrief) ?? (format == "Story" ? 10 : 12)
        let scenes = fixtureScenes(for: pillar, format: format, duration: duration)
        var dailyCard = GeneratedDailyCardDraft(
            id: revisionID,
            scheduledDate: scheduledDate,
            status: "draft",
            title: title,
            whyToday: trimmedBrief.isEmpty
                ? "Fixture day generation for \(scheduledDate)."
                : trimmedBrief,
            growthJob: "Consistency.",
            contentPillar: pillar,
            shootability: "easy",
            estimatedShootMinutes: format == "Reel" ? 12 : 2,
            energyRequired: "low",
            languageMode: "English",
            format: format,
            primarySurface: format == "Story" ? "instagram_stories" : format == "Post" ? "instagram_feed" : "instagram_reels",
            durationSeconds: duration,
            hook: title,
            saveShareReason: "Save this as a reminder to shoot the day as planned.",
            sceneList: scenes,
            script: script,
            noVoiceoverVersion: format == "Post" ? "Use a photo you already have. No filming needed." : "Use bold captions over the same shots.",
            onScreenText: sceneOnScreenText(for: pillar),
            caption: script,
            cta: "Save this for later.",
            hashtags: hashtags(for: pillar),
            coverText: String(title.prefix(40)),
            postInstructions: "Keep it real, natural, and personal.",
            brandEventNotes: "",
            backupStory: "Post one phone clip with the same hook.",
            backupCaptionOnly: "Same angle, shorter cut.",
            audioOptionNotes: "",
            creatorFitScore: 90,
            riskNotes: [],
            assumptions: ["Fixture UI generation — no live model call."],
            sourceNote: "Based on your idea."
        )
#if DEBUG
        if DebugLaunchFlags.longContent {
            dailyCard = dailyCard.withLongContent
            dailyCard.scheduledDate = scheduledDate
            dailyCard.status = "draft"
        }
        dailyCard = DebugLaunchFlags.uiFixtureData.applying(to: dailyCard)
#endif
        return DailyGenerationResult(
            generationID: UUID(),
            weeklyPlanID: WeeklyPlan.raceWeek.id,
            status: "draft",
            targetScheduledDate: scheduledDate,
            dailyCard: dailyCard,
            warnings: [],
            assumptions: ["Fixture UI generation — no live model call."],
            sourceSummary: "Fixture day brief only.",
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    private func fixtureFormat(from brief: String) -> String {
        let lower = brief.lowercased()
        if lower.contains("photo") || lower.contains("carousel") || lower.contains("caption-only") { return "Post" }
        if lower.range(of: #"\bstory\b"#, options: .regularExpression) != nil { return "Story" }
        return "Reel"
    }

    private func requestedDuration(from brief: String) -> Int? {
        guard let expression = try? NSRegularExpression(pattern: #"(\d+)\s*(?:[-–]\s*)?(?:seconds?|secs?|s)\b"#, options: .caseInsensitive),
              let match = expression.firstMatch(in: brief, range: NSRange(brief.startIndex..., in: brief)),
              let range = Range(match.range(at: 1), in: brief),
              let seconds = Int(brief[range]), seconds > 0 else { return nil }
        return seconds
    }

    private func fixtureScenes(for pillar: String, format: String, duration: Int?) -> [ShotScene] {
        guard let duration else { return [] }
        let original = synthesizedScenes(for: pillar)
        let count = format == "Story" ? 1 : min(original.count, duration)
        return original.prefix(count).enumerated().map { index, scene in
            let seconds = duration / count + (index < duration % count ? 1 : 0)
            return ShotScene(number: index + 1, title: scene.title, duration: "\(seconds) sec", symbol: scene.symbol)
        }
    }

    private func inferredContentPillar(from brief: String) -> String {
        let lower = brief.lowercased()
        let hasBooks = lower.contains("book")
        let hasMovies = lower.contains("movie") || lower.contains(" tv") || lower.contains("tv ")
        if hasBooks && hasMovies { return "books" }
        if hasMovies { return "movies-tv" }
        if hasBooks { return "books" }
        if lower.contains("hyrox") || lower.contains("race week") || lower.contains("fitness") || lower.contains("gym") {
            return "fitness-wellness"
        }
        return "lifestyle"
    }

    private func synthesizedTitle(from brief: String, pillar: String) -> String {
        let lower = brief.lowercased()
        if lower.contains("book") && (lower.contains("movie") || lower.contains(" tv")) {
            return "What I'm reading and watching right now"
        }
        switch pillar {
        case "books":
            return "The book on my nightstand — one honest takeaway"
        case "movies-tv":
            return "One scene from what I'm watching that stuck with me"
        case "fitness-wellness":
            return "One small training win worth sharing today"
        default:
            let titleSeed = brief.split(separator: ".").first.map(String.init) ?? brief
            let title = String(titleSeed.prefix(72))
            return title.isEmpty ? "Fixture day draft" : title
        }
    }

    private func synthesizedScript(from brief: String, pillar: String) -> String {
        switch pillar {
        case "books":
            return """
            Here is the book I cannot stop thinking about.
            One line about why it landed for me.
            What I would tell a friend who asked if it is worth it.
            """
        case "movies-tv":
            return """
            Here is what I am watching this week.
            The moment that made me pause the scroll.
            Why it fits the mood I am in right now.
            """
        default:
            if brief.localizedCaseInsensitiveContains("book") && brief.localizedCaseInsensitiveContains("movie") {
                return """
                Two things on my mind this week: a book and a show.
                One honest line about each.
                Why they pair well for the kind of content I make.
                """
            }
            return brief.isEmpty
                ? "Open with the day's angle. Show one real beat. Close with a simple ask."
                : brief
        }
    }

    private func synthesizedScenes(for pillar: String) -> [ShotScene] {
        switch pillar {
        case "books":
            return [
                ShotScene(number: 1, title: "Book on the table", duration: "3 sec", symbol: "book.closed"),
                ShotScene(number: 2, title: "Favorite page", duration: "4 sec", symbol: "text.book.closed"),
                ShotScene(number: 3, title: "Quick rating", duration: "3 sec", symbol: "star"),
                ShotScene(number: 4, title: "Save for later", duration: "2 sec", symbol: "bookmark")
            ]
        case "movies-tv":
            return [
                ShotScene(number: 1, title: "Remote and couch", duration: "3 sec", symbol: "tv"),
                ShotScene(number: 2, title: "Pause on the scene", duration: "4 sec", symbol: "film"),
                ShotScene(number: 3, title: "Reaction beat", duration: "3 sec", symbol: "face.smiling"),
                ShotScene(number: 4, title: "Soft ask", duration: "2 sec", symbol: "heart")
            ]
        default:
            return [
                ShotScene(number: 1, title: "Talking-head hook", duration: "3 sec", symbol: "person.crop.rectangle"),
                ShotScene(number: 2, title: "Process b-roll", duration: "4 sec", symbol: "film.stack"),
                ShotScene(number: 3, title: "Proof moment", duration: "3 sec", symbol: "checkmark.circle"),
                ShotScene(number: 4, title: "Soft CTA", duration: "2 sec", symbol: "heart")
            ]
        }
    }

    private func sceneOnScreenText(for pillar: String) -> [String] {
        switch pillar {
        case "books":
            return ["Currently reading", "Worth it?", "Save this"]
        case "movies-tv":
            return ["Watching now", "This scene", "Save this"]
        default:
            return ["Today", "Keep it real", "Save this"]
        }
    }

    private func hashtags(for pillar: String) -> [String] {
        switch pillar {
        case "books":
            return ["books", "currentlyreading", "fixture"]
        case "movies-tv":
            return ["movies", "whattowatch", "fixture"]
        default:
            return ["fixture", "dayplan"]
        }
    }
}
