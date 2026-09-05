import Foundation

enum OnboardingReferenceParseError: Error, Equatable {
    case empty
    case malformed
    case nonInstagram
    case unsupportedStory
    case unsupportedAudio
    case invalidHandle

    var userMessage: String {
        switch self {
        case .empty:
            "Paste a reel URL or @handle"
        case .malformed:
            "That doesn't look like a reel or profile — try instagram.com/reel/… or @handle"
        case .nonInstagram:
            "Paste an Instagram link — instagram.com/reel/… or instagram.com/handle"
        case .unsupportedStory:
            "Story links can't be used as references."
        case .unsupportedAudio:
            "Audio links aren't supported — paste a reel or profile."
        case .invalidHandle:
            "Enter a valid @handle — letters, numbers, dots, underscores (2–30 chars)."
        }
    }
}

struct OnboardingReferenceParseResult: Hashable, Sendable {
    var reference: OnboardingReference
    var needsProfileVerification: Bool
    var handle: String?
}

enum OnboardingReferenceParser {
    private static let instagramHosts: Set<String> = [
        "instagram.com", "www.instagram.com", "m.instagram.com",
    ]

    private static let reservedHandles: Set<String> = [
        "about", "accounts", "audio", "developer", "direct", "explore",
        "p", "reel", "reels", "stories", "tv", "music",
    ]

    static func parse(_ rawText: String) -> Result<OnboardingReferenceParseResult, OnboardingReferenceParseError> {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let looksLikeURL = trimmed.range(
            of: #"instagram\.com|https?://"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil

        if looksLikeURL {
            return parseURL(trimmed)
        }

        return parsePlainHandle(trimmed)
    }

    /// A full reel/post URL is complete enough to add on paste or when typing finishes.
    static func shouldAutoAddCompleteReelOrPost(previous: String, current: String) -> Bool {
        guard looksLikeCompleteReelOrPostURL(current) else { return false }
        let inserted = current.count - previous.count
        if inserted >= 12 { return true }
        return reelOrPostURLLooksTerminated(current)
    }

    static func looksLikeCompleteReelOrPostURL(_ rawText: String) -> Bool {
        guard case .success(let parsed) = parse(rawText), parsed.reference.isReel else {
            return false
        }
        return true
    }

    static func looksLikeURLAttempt(_ rawText: String) -> Bool {
        rawText.range(
            of: #"instagram\.com|https?://"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func reelOrPostURLLooksTerminated(_ rawText: String) -> Bool {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let delimited = trimmed.range(
            of: #"(?i)instagram\.com/(?:reel|reels|p)/[A-Za-z0-9_-]{5,}(/|\?)"#,
            options: .regularExpression
        ) != nil
        if delimited { return true }
        return trimmed.range(
            of: #"(?i)instagram\.com/(?:reel|reels|p)/[A-Za-z0-9_-]{11,}\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func parseURL(
        _ value: String
    ) -> Result<OnboardingReferenceParseResult, OnboardingReferenceParseError> {
        guard let classification = classifyInstagramURL(value) else {
            return .failure(.malformed)
        }

        switch classification.kind {
        case .nonInstagram:
            return .failure(.nonInstagram)
        case .story:
            return .failure(.unsupportedStory)
        case .audio:
            return .failure(.unsupportedAudio)
        case .malformed:
            return .failure(.malformed)
        case .reel, .post:
            return .success(
                OnboardingReferenceParseResult(
                    reference: buildReelRef(classification: classification),
                    needsProfileVerification: false,
                    handle: nil
                )
            )
        case .profile(let handle):
            let url = instagramProfileURL(handle: handle)
            return .success(
                OnboardingReferenceParseResult(
                    reference: buildProfileRef(handle: handle, url: url),
                    needsProfileVerification: true,
                    handle: handle
                )
            )
        }
    }

    private static func parsePlainHandle(
        _ value: String
    ) -> Result<OnboardingReferenceParseResult, OnboardingReferenceParseError> {
        if let handle = normalizePlainHandle(value) {
            let url = instagramProfileURL(handle: handle)
            return .success(
                OnboardingReferenceParseResult(
                    reference: buildProfileRef(handle: handle, url: url),
                    needsProfileVerification: true,
                    handle: handle
                )
            )
        }

        let looksLikeHandleAttempt = value.hasPrefix("@")
            || value.range(of: #"^[A-Za-z0-9._]+$"#, options: .regularExpression) != nil
        return .failure(looksLikeHandleAttempt ? .invalidHandle : .malformed)
    }

    private enum URLKind {
        case nonInstagram
        case story
        case audio
        case malformed
        case reel
        case post
        case profile(String)
    }

    private struct URLClassification {
        var kind: URLKind
        var url: String
        var key: String
    }

    private static func classifyInstagramURL(_ value: String) -> URLClassification? {
        guard let normalized = normalizeInstagramURL(value),
              let url = URL(string: normalized)
        else {
            return URLClassification(kind: .malformed, url: value, key: value)
        }

        let host = url.host?.lowercased() ?? ""
        guard instagramHosts.contains(host) else {
            return URLClassification(kind: .nonInstagram, url: normalized, key: normalized)
        }

        let segments = instagramPathSegments(url)
        guard !segments.isEmpty else {
            return URLClassification(kind: .malformed, url: normalized, key: normalized)
        }

        if segments.first?.lowercased() == "stories" {
            return URLClassification(kind: .story, url: normalized, key: normalized)
        }

        if segments.contains(where: { $0.lowercased() == "audio" || $0.lowercased() == "music" }) {
            return URLClassification(kind: .audio, url: normalized, key: normalized)
        }

        for index in 0 ..< segments.count - 1 {
            let segment = segments[index].lowercased()
            if segment == "reel" || segment == "reels" || segment == "p" {
                let shortcode = segments[index + 1]
                if shortcode.isEmpty || reservedHandles.contains(shortcode.lowercased()) {
                    return URLClassification(kind: .malformed, url: normalized, key: normalized)
                }
                let mediaKind: URLKind = segment == "p" ? .post : .reel
                let key = "instagram:\(segment == "p" ? "post" : "reel"):\(shortcode)"
                return URLClassification(kind: mediaKind, url: normalized, key: key)
            }
        }

        if segments.count == 1, let handle = normalizePlainHandle(segments[0]) {
            return URLClassification(
                kind: .profile(handle),
                url: instagramProfileURL(handle: handle),
                key: "handle:\(handle)"
            )
        }

        return URLClassification(kind: .malformed, url: normalized, key: normalized)
    }

    private static func normalizeInstagramURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var urlString = trimmed
        if !urlString.lowercased().hasPrefix("http") {
            urlString = "https://\(urlString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        }

        guard var components = URLComponents(string: urlString) else { return nil }
        components.host = components.host?.lowercased()
        components.fragment = nil

        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { item in
                let lower = item.name.lowercased()
                return !(lower == "igshid" || lower == "fbclid" || lower.hasPrefix("utm_"))
            }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        components.path = path

        guard let url = components.url else { return nil }
        return url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .replacingOccurrences(of: "/?", with: "?")
    }

    private static func instagramPathSegments(_ url: URL) -> [String] {
        url.path
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { segment in
                segment.removingPercentEncoding ?? String(segment)
            }
    }

    static func normalizePlainHandle(_ value: String) -> String? {
        var handle = value.trimmingCharacters(in: .whitespacesAndNewlines)
        handle = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@/"))
        handle = handle.lowercased()

        guard handle.count >= 2, handle.count <= 30 else { return nil }
        guard handle.range(of: #"^[a-z0-9._]+$"#, options: .regularExpression) != nil else { return nil }
        guard handle.range(of: #"[a-z]"#, options: .regularExpression) != nil else { return nil }
        guard !reservedHandles.contains(handle) else { return nil }
        return handle
    }

    static func instagramProfileURL(handle: String) -> String {
        "https://www.instagram.com/\(handle)/"
    }

    private static func buildReelRef(classification: URLClassification) -> OnboardingReference {
        let short = classification.url.replacingOccurrences(
            of: #"^https?://(www\.)?"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let label: String
        if short.count > 46 {
            label = String(short.prefix(43)) + "…"
        } else {
            label = short
        }
        return OnboardingReference(
            id: UUID().uuidString,
            kind: .reel,
            label: label,
            key: classification.key,
            url: classification.url
        )
    }

    private static func buildProfileRef(handle: String, url: String) -> OnboardingReference {
        OnboardingReference(
            id: UUID().uuidString,
            kind: .profile,
            label: "@\(handle) · profile",
            key: "handle:\(handle)",
            url: url
        )
    }
}
