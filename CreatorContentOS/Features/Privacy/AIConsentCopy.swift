import Foundation

enum AIConsentCopy {
    static let errorCode = "ai_consent_required"

    static let sheetTitle = "Allow AI partners"

    static let purposeAndDestinations = """
    ContentHelper sends your creator profile, day briefs, scripts, and storyboard notes to AI partners (DeepSeek, OpenAI, Google Gemini) to make scripts, captions, plan ideas, and storyboard images. Nothing is posted for you.
    """

    static let allowTitle = "Allow"
    static let notNowTitle = "Not now"

    static let blockedMessage =
        "Allow AI partners first. You can also allow this later in You → Account."

    static let accountHeader = "AI partners"
    static let accountAllowTitle = "Allow AI partners"
    static let accountRetryTitle = "Allow AI partners"
    static let statusAllowed = "Allowed"
    static let statusDeclined = "Not allowed yet"
    static let statusUnknown = "Not decided yet"
}
