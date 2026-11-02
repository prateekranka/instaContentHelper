import Foundation

enum AIConsentCopy {
    static let errorCode = "ai_consent_required"

    static let sheetTitle = "Use AI to write your ideas?"

    static let purposeAndDestinations = """
    Shares your creator profile, day briefs, scripts, and storyboard notes with DeepSeek, OpenAI, and Google Gemini to write ideas and create images.
    """

    static let allowTitle = "Allow"
    static let notNowTitle = "Not now"

    static let blockedMessage =
        "Allow AI to write ideas first. You can also allow this later in You → Account."

    static let accountHeader = sheetTitle
    static let accountAllowTitle = allowTitle
    static let accountRetryTitle = allowTitle
    static let statusAllowed = "Allowed"
    static let statusDeclined = "Not allowed yet"
    static let statusUnknown = "Not decided yet"
}
