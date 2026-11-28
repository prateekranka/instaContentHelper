import Foundation

enum AIConsentCopy {
    static let errorCode = "ai_consent_required"

    static let sheetTitle = "Use AI to write your ideas?"

    static let purposeAndDestinations = """
    Mira shares your creator profile, briefs, scripts, and shot notes with DeepSeek, OpenAI, and Google Gemini. They help write ideas and make pictures.
    """

    static let allowTitle = "Allow"
    static let notNowTitle = "Not now"

    static let accountHeader = sheetTitle
    static let accountAllowTitle = allowTitle
    static let accountRetryTitle = allowTitle
    static let statusAllowed = "Allowed"
    static let statusDeclined = "Not allowed yet"
    static let statusUnknown = "Not decided yet"
}
