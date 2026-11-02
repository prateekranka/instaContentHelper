import Foundation

/// Client-side Instagram Business Login configuration + helpers.
///
/// The app only ever holds the PUBLIC Instagram app id and the redirect URI
/// (surfaced from the build config via Info.plist). The app secret and the
/// code→token exchange stay server-side in the `instagram-connect` edge function.
enum InstagramOAuth {
    static let callbackScheme = "creatorcontenthelper"
    static let scopes = "instagram_business_basic,instagram_business_manage_insights"

    static var appID: String? {
        infoValue("INSTAGRAM_APP_ID")
    }

    static var redirectURI: String? {
        infoValue("INSTAGRAM_REDIRECT_URI")
    }

    static var isConfigured: Bool {
        appID != nil && redirectURI != nil
    }

    /// Builds the authorization URL opened in the web-auth sheet, or nil when the
    /// app isn't configured with an Instagram app id / redirect yet.
    static func authorizeURL(state: String = UUID().uuidString) -> URL? {
        guard let appID, let redirectURI else { return nil }
        var components = URLComponents(string: "https://www.instagram.com/oauth/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: appID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
        ]
        return components?.url
    }

    /// Extracts the `code` query item from the OAuth callback URL.
    static func authorizationCode(from callbackURL: URL) -> String? {
        URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value?
            .nilIfBlank
    }

    private static func infoValue(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }
}
