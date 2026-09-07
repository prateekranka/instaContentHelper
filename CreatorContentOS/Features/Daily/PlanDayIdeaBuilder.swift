import Foundation

/// One selectable day idea shown in Plan. `dayBrief` is sent verbatim to `generateDayCard`.
struct PlanDayIdeaCandidate: Equatable, Sendable, Identifiable {
    var id: String { title }
    let title: String
    let summary: String
    let dayBrief: String
}

/// Truncation / payload caps for `generate-plan-ideas` (keep prompts small for <60s p95).
enum PlanDayIdeaPayloadLimits {
    static let positioningMaxChars = 400
    static let voiceRulesMaxChars = 400
    static let captionStyleMaxChars = 200
    static let noGoTopicsMaxChars = 200
    static let maxReferenceLabels = 10
    static let referenceLabelMaxChars = 80
    /// Client-side deadline before falling back to `PlanDayIdeaBuilder`.
    static let clientTimeoutSeconds: TimeInterval = 50
}

/// Saved creator setup used to personalize idea copy (on-device + live DeepSeek).
struct PlanDaySetupSummary: Equatable, Sendable {
    var contentPillars: [String]
    var voiceIsConfigured: Bool
    var confirmedReferenceCount: Int
    var totalReferenceCount: Int
    /// Truncated voice fields sent to `generate-plan-ideas`.
    var positioning: String = ""
    var voiceRulesText: String = ""
    var captionStyle: String = ""
    var noGoTopicsText: String = ""
    /// Confirmed reference display labels (capped), for pacing personalization.
    var confirmedReferenceLabels: [String] = []

    /// Cache key fragment so voice/ref edits invalidate Plan idea cache.
    var cacheFingerprint: String {
        [
            contentPillars.joined(separator: ","),
            voiceIsConfigured ? "voice" : "no-voice",
            "refs:\(confirmedReferenceCount)",
            positioning,
            voiceRulesText,
            captionStyle,
            noGoTopicsText,
            confirmedReferenceLabels.joined(separator: ","),
        ].joined(separator: "|")
    }

    static func from(
        profile: CreatorProfileSummary,
        intelligenceHome: IntelligenceHome
    ) -> PlanDaySetupSummary {
        let references = intelligenceHome.sourcePulse.references
        let confirmedRefs = references.filter { $0.state != .needsReview }
        let positioning = Self.collapse(
            profile.positioning,
            maxChars: PlanDayIdeaPayloadLimits.positioningMaxChars
        )
        let voiceRulesText = Self.collapse(
            profile.voiceRules.joined(separator: "; "),
            maxChars: PlanDayIdeaPayloadLimits.voiceRulesMaxChars
        )
        let captionStyle = Self.collapse(
            profile.captionStyle ?? "",
            maxChars: PlanDayIdeaPayloadLimits.captionStyleMaxChars
        )
        let noGoTopicsText = Self.collapse(
            profile.noGoTopics.joined(separator: "; "),
            maxChars: PlanDayIdeaPayloadLimits.noGoTopicsMaxChars
        )
        let labels = confirmedRefs
            .prefix(PlanDayIdeaPayloadLimits.maxReferenceLabels)
            .map { Self.collapse($0.title, maxChars: PlanDayIdeaPayloadLimits.referenceLabelMaxChars) }
            .filter { !$0.isEmpty }
        let voiceConfigured = !positioning.isEmpty && !profile.voiceRules.isEmpty
        return PlanDaySetupSummary(
            contentPillars: profile.contentPillars,
            voiceIsConfigured: voiceConfigured,
            confirmedReferenceCount: confirmedRefs.count,
            totalReferenceCount: references.count,
            positioning: positioning,
            voiceRulesText: voiceRulesText,
            captionStyle: captionStyle,
            noGoTopicsText: noGoTopicsText,
            confirmedReferenceLabels: labels
        )
    }

    private static func collapse(_ value: String, maxChars: Int) -> String {
        let collapsed = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "" }
        return String(collapsed.prefix(maxChars))
    }
}

/// Cached Plan idea rows keyed by scheduled date + setup fingerprint.
struct PlanDayIdeasCacheEntry: Equatable, Sendable {
    var setupFingerprint: String
    var ideas: [PlanDayIdeaCandidate]
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

/// Maps edge-function / LLM idea payloads onto Plan launcher candidates.
enum PlanDayIdeaMapping {
    /// Builds candidates from decoded idea rows. Pads/truncates to
    /// `PlanDayIdeaBuilder.ideaCount` using the on-device builder when needed.
    static func candidates(
        from remoteIdeas: [PlanDayIdeaRemoteIdea],
        scheduledDate: String,
        setup: PlanDaySetupSummary
    ) -> [PlanDayIdeaCandidate] {
        var unique: [PlanDayIdeaCandidate] = []
        var seenTitles = Set<String>()

        for remote in remoteIdeas {
            guard let candidate = candidate(from: remote) else { continue }
            let key = candidate.title.lowercased()
            guard !seenTitles.contains(key) else { continue }
            seenTitles.insert(key)
            unique.append(candidate)
            if unique.count == PlanDayIdeaBuilder.ideaCount { break }
        }

        if unique.count == PlanDayIdeaBuilder.ideaCount {
            return unique
        }

        for fallback in PlanDayIdeaBuilder.buildIdeas(scheduledDate: scheduledDate, setup: setup) {
            let key = fallback.title.lowercased()
            guard !seenTitles.contains(key) else { continue }
            seenTitles.insert(key)
            unique.append(fallback)
            if unique.count == PlanDayIdeaBuilder.ideaCount { break }
        }
        return Array(unique.prefix(PlanDayIdeaBuilder.ideaCount))
    }

    static func candidate(from remote: PlanDayIdeaRemoteIdea) -> PlanDayIdeaCandidate? {
        let title = collapseOneLiner(remote.title)
        guard let title, !title.isEmpty else { return nil }
        let dayBrief = collapseOneLiner(remote.dayBrief) ?? title
        return PlanDayIdeaCandidate(
            title: title,
            summary: "",
            dayBrief: dayBrief
        )
    }

    static func collapseOneLiner(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(120))
    }
}

/// Wire-format idea row returned by `generate-plan-ideas`.
struct PlanDayIdeaRemoteIdea: Equatable, Sendable, Decodable {
    var title: String
    var dayBrief: String

    enum CodingKeys: String, CodingKey {
        case title
        case dayBrief = "day_brief"
    }

    init(title: String, dayBrief: String) {
        self.title = title
        self.dayBrief = dayBrief
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        dayBrief = try container.decodeIfPresent(String.self, forKey: .dayBrief) ?? title
    }
}

struct PlanDayIdeasResponse: Equatable, Sendable, Decodable {
    var scheduledDate: String?
    var source: String?
    var model: String?
    var ideas: [PlanDayIdeaRemoteIdea]

    enum CodingKeys: String, CodingKey {
        case scheduledDate = "scheduled_date"
        case source
        case model
        case ideas
    }
}

enum PlanDayIdeaBuilder {
    /// Count of selectable idea bubbles on Plan empty days.
    static let ideaCount = 5

    /// On-device Instagram-format trend templates (not a live Instagram scrape).
    /// Framing mirrors current Reel/carousel patterns; copy is personalized with
    /// the creator's content pillars and seeded from the selected date + setup.
    /// Placeholders: `{pillar}`, `{weekday}`.
    /// Used for fixture UI and as offline / error fallback when DeepSeek is unavailable.
    private static let trendTemplates: [(formatTag: String, titlePattern: String)] = [
        ("POV Reel", "POV: what a real {pillar} day looks like on {weekday}"),
        ("GRWM Reel", "GRWM while I talk through my {pillar} plan for {weekday}"),
        ("Listicle Reel", "3 mistakes beginners still make with {pillar}"),
        ("Stop doing this", "Stop doing this in your {pillar} routine"),
        ("Myth vs reality", "Myth vs reality: {pillar} advice that sounds good"),
        ("Day in the life", "Day in the life: soft {pillar} storytelling for {weekday}"),
        ("Wish I knew", "Things I wish I knew before taking {pillar} seriously"),
        ("Before / after", "Before/after: one honest week of {pillar}"),
        ("Voiceover story", "Voiceover: the quiet truth about my {pillar} habit"),
        ("Carousel myths", "Carousel: {pillar} myths people still believe"),
        ("Soft life Reel", "Soft life morning built around {pillar} on {weekday}"),
        ("Hot take Reel", "Hot take: the unpopular opinion I have about {pillar}"),
        ("Busy-day Reel", "What I actually do for {pillar} on a busy {weekday}"),
        ("Tell me without telling me", "Tell me you're into {pillar} without telling me"),
        ("Ranking Reel", "Ranking my {pillar} essentials from skip to keep"),
    ]

    static func buildIdeas(
        scheduledDate: String,
        setup: PlanDaySetupSummary
    ) -> [PlanDayIdeaCandidate] {
        guard let formatted = PlanDayDateFormatting.formattedDate(for: scheduledDate) else {
            return []
        }

        let pillars = normalizedPillars(from: setup.contentPillars)
        let seed = stableSeed(
            scheduledDate: scheduledDate,
            pillars: pillars,
            setup: setup
        )
        let startIndex = seed % trendTemplates.count
        let formatHint = formatSummaryHint(setup: setup)

        return (0..<ideaCount).map { offset in
            let template = trendTemplates[(startIndex + offset) % trendTemplates.count]
            let pillar = pillars[offset % pillars.count]
            let title = renderTitle(
                template.titlePattern,
                pillar: pillar,
                weekday: formatted.weekday
            )
            let summary = formatHint.map { "\(template.formatTag) · \($0)" } ?? template.formatTag
            return PlanDayIdeaCandidate(
                title: title,
                summary: summary,
                dayBrief: "\(title). \(summary)"
            )
        }
    }

    private static func renderTitle(
        _ pattern: String,
        pillar: String,
        weekday: String
    ) -> String {
        pattern
            .replacingOccurrences(of: "{pillar}", with: pillar)
            .replacingOccurrences(of: "{weekday}", with: weekday)
    }

    private static func normalizedPillars(from raw: [String]) -> [String] {
        let cleaned = raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        return cleaned.isEmpty ? ["your niche"] : cleaned
    }

    private static func formatSummaryHint(setup: PlanDaySetupSummary) -> String? {
        var bits: [String] = []
        if setup.voiceIsConfigured {
            bits.append("in your voice")
        }
        if let label = setup.confirmedReferenceLabels.first, !label.isEmpty {
            bits.append("paced like \(label)")
        } else if setup.confirmedReferenceCount > 0 {
            let noun = setup.confirmedReferenceCount == 1 ? "reference" : "references"
            bits.append("paced like your \(setup.confirmedReferenceCount) \(noun)")
        }
        guard !bits.isEmpty else { return nil }
        return bits.joined(separator: ", ")
    }

    /// Stable across process launches (unlike `Hasher`).
    private static func stableSeed(
        scheduledDate: String,
        pillars: [String],
        setup: PlanDaySetupSummary
    ) -> Int {
        let material = [
            scheduledDate,
            pillars.joined(separator: ","),
            setup.voiceIsConfigured ? "voice" : "no-voice",
            "refs:\(setup.confirmedReferenceCount)",
            String(setup.positioning.prefix(40)),
            setup.confirmedReferenceLabels.prefix(3).joined(separator: ","),
        ].joined(separator: "|")
        let hashed = material.utf8.reduce(into: 0) { partial, byte in
            partial = ((partial &* 31) &+ Int(byte)) & 0x7fff_ffff
        }
        return hashed
    }
}
