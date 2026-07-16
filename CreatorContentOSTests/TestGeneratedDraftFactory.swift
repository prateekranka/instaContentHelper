import Foundation
@testable import CreatorContentOS

/// Test-only deterministic draft factory. Do not inject this into app fixture runtime.
enum TestGeneratedDraftFactory {
    static func makeDraft(
        weekStartDate: String
    ) async -> GeneratedWeekDraft {
        let cards = SupabaseDateFormatting.weekDates(starting: weekStartDate).enumerated().map { index, date in
            GeneratedDailyCardDraft(
                id: UUID(),
                scheduledDate: date,
                status: "draft",
                title: [
                    "Generated Monday reset",
                    "Generated gym detail",
                    "Generated recovery check",
                    "Generated meal note",
                    "Generated calm routine note",
                    "Generated low-pressure movement",
                    "Generated caption backup"
                ][index],
                whyToday: "A test deterministic draft grounded in Creator's weekly rhythm.",
                growthJob: "Build consistency with grounded lifestyle content.",
                contentPillar: ["lifestyle", "gym", "recovery", "eating", "lifestyle", "gym", "recovery"][index],
                shootability: index == 6 ? "backup" : "easy",
                estimatedShootMinutes: index == 6 ? 6 : 12,
                energyRequired: index == 6 ? "low" : "medium",
                languageMode: "English with light Hinglish if natural",
                sceneList: [
                    ShotScene(number: 1, title: "Opening detail", duration: "3 sec", symbol: "sparkles"),
                    ShotScene(number: 2, title: "One steady movement", duration: "5 sec", symbol: "figure.run"),
                    ShotScene(number: 3, title: "Useful close", duration: "4 sec", symbol: "text.quote")
                ],
                script: "One useful detail is enough today. Keep it simple and steady.",
                noVoiceoverVersion: "Three quiet clips with simple on-screen text.",
                onScreenText: ["Simple today", "One useful detail", "Done"],
                caption: "Keeping it simple today. One useful detail, done properly.",
                cta: "Save this for a low-pressure day.",
                hashtags: ["lifestylecreator", "fitnessover60"],
                coverText: "Simple today",
                postInstructions: "Use calm audio only if it fits.",
                brandEventNotes: "",
                backupStory: "A 10-second story with one detail and one line.",
                backupCaptionOnly: "Caption-only backup for a crowded day.",
                audioOptionNotes: "Calm fallback audio, or no audio dependency.",
                creatorFitScore: 88,
                riskNotes: [],
                assumptions: ["Test helper used deterministic local context."],
                sourceNote: "Test-only deterministic weekly generation."
            )
        }

        return GeneratedWeekDraft(
            id: UUID(),
            weeklyPlanID: UUID(),
            strategySummary: "Test deterministic draft: seven shootable Creator-safe cards for review.",
            warnings: [],
            assumptions: ["Test helper does not call AI services."],
            dailyCards: cards,
            ideaBank: [
                WeeklyIdea(
                    title: "Test caption-only backup",
                    reason: "Saved from test deterministic generation.",
                    source: .pattern,
                    effortLabel: "Easy"
                )
            ],
            sourceSummary: "Test profile, setup, references, archive, and idea bank.",
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )
    }
}
