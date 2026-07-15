import Foundation

extension DailyCard {
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
        ]
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
