import Foundation

/// One selectable day idea shown in Plan. `dayBrief` is sent verbatim to `generateDayCard`.
struct PlanDayIdeaCandidate: Equatable, Sendable, Identifiable {
    var id: String { title }
    let title: String
    let summary: String
    let dayBrief: String
}

/// Saved creator setup used to personalize deterministic on-device idea copy.
struct PlanDaySetupSummary: Equatable, Sendable {
    var contentPillars: [String]
    var voiceIsConfigured: Bool
    var confirmedReferenceCount: Int
    var totalReferenceCount: Int

    static func from(
        profile: CreatorProfileSummary,
        intelligenceHome: IntelligenceHome
    ) -> PlanDaySetupSummary {
        let references = intelligenceHome.sourcePulse.references
        let confirmed = references.filter { $0.state != .needsReview }.count
        let positioning = profile.positioning.trimmingCharacters(in: .whitespacesAndNewlines)
        let voiceConfigured = !positioning.isEmpty && !profile.voiceRules.isEmpty
        return PlanDaySetupSummary(
            contentPillars: profile.contentPillars,
            voiceIsConfigured: voiceConfigured,
            confirmedReferenceCount: confirmed,
            totalReferenceCount: references.count
        )
    }
}

enum PlanDayDateFormatting {
    struct FormattedPlanDate: Equatable, Sendable {
        let weekday: String
        let label: String
        let shortLabel: String
    }

    static func formattedDate(for scheduledDate: String) -> FormattedPlanDate? {
        guard let date = parseLocalDate(scheduledDate) else { return nil }
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "en_GB")
        weekdayFormatter.dateFormat = "EEEE"

        let labelFormatter = DateFormatter()
        labelFormatter.locale = Locale(identifier: "en_GB")
        labelFormatter.dateFormat = "d MMMM yyyy"

        let shortFormatter = DateFormatter()
        shortFormatter.locale = Locale(identifier: "en_GB")
        shortFormatter.dateFormat = "EEE d MMM"

        return FormattedPlanDate(
            weekday: weekdayFormatter.string(from: date),
            label: labelFormatter.string(from: date),
            shortLabel: shortFormatter.string(from: date)
        )
    }

    static func parseLocalDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
}

enum PlanDayIdeaBuilder {
    static func buildIdeas(
        scheduledDate: String,
        setup: PlanDaySetupSummary
    ) -> [PlanDayIdeaCandidate] {
        guard let formatted = PlanDayDateFormatting.formattedDate(for: scheduledDate) else {
            return []
        }

        let voiceHint = setup.voiceIsConfigured ? "your voice" : "your positioning"
        let refsHint: String
        if setup.confirmedReferenceCount > 0 {
            let noun = setup.confirmedReferenceCount == 1 ? "reference" : "references"
            refsHint = "\(setup.confirmedReferenceCount) \(noun)"
        } else {
            refsHint = "what you save"
        }

        let labelParts = formatted.label.split(separator: " ")
        let dayNumber = labelParts.first.map(String.init) ?? formatted.label
        let monthName = labelParts.dropFirst().first.map(String.init) ?? formatted.label

        let templates: [(String, String)] = [
            (
                "Behind the routine",
                "What \(formatted.weekday) actually looks like — one honest moment, no polish."
            ),
            (
                "Small win, said plainly",
                "One thing that went right before \(dayNumber) \(monthName) — quick hook, simple payoff."
            ),
            (
                "Process over outcome",
                "Show the prep, not the result — \(voiceHint) leads, camera follows."
            ),
            (
                "Question you keep getting",
                "Answer the DM you would have ignored — framed for \(formatted.weekday)'s audience."
            ),
            (
                "Contrast reel",
                "Two beats: expectation vs reality. \(refsHint) can set the pacing."
            ),
        ]

        return templates.map { title, summary in
            PlanDayIdeaCandidate(
                title: title,
                summary: summary,
                dayBrief: "\(title). \(summary)"
            )
        }
    }
}
