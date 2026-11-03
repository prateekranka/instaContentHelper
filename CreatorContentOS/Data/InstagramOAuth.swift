import Foundation

/// Client-side Instagram API with Unified login (Facebook Login for Business)
/// configuration + helpers. The creator logs in with Instagram or Facebook and
/// shares their Instagram professional account; no Facebook Page is needed.
///
/// The app only ever holds the PUBLIC Meta app id, the login configuration id and
/// the redirect URI (surfaced from the build config via Info.plist). The app
/// secret and the code→token exchange stay server-side in `instagram-connect`.
enum InstagramOAuth {
    static let callbackScheme = "creatorcontenthelper"
    /// Used only when no login configuration id is set; Facebook Login for
    /// Business takes its permissions from the configuration instead.
    static let scopes = "instagram_basic,instagram_manage_insights"

    static var appID: String? {
        infoValue("INSTAGRAM_APP_ID")
    }

    static var redirectURI: String? {
        infoValue("INSTAGRAM_REDIRECT_URI")
    }

    /// Facebook Login for Business configuration (User access token type).
    static var loginConfigID: String? {
        infoValue("INSTAGRAM_LOGIN_CONFIG_ID")
    }

    static var isConfigured: Bool {
        appID != nil && redirectURI != nil
    }

    /// Builds the authorization URL opened in the web-auth sheet, or nil when the
    /// app isn't configured with a Meta app id / redirect yet.
    static func authorizeURL(state: String) -> URL? {
        guard let appID, let redirectURI else { return nil }
        var components = URLComponents(string: "https://www.facebook.com/dialog/oauth")
        var items = [
            URLQueryItem(name: "client_id", value: appID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "override_default_response_type", value: "true"),
        ]
        if let loginConfigID {
            items.append(URLQueryItem(name: "config_id", value: loginConfigID))
        } else {
            items.append(URLQueryItem(name: "scope", value: scopes))
        }
        components?.queryItems = items
        return components?.url
    }

    /// Extracts the `code` query item from the OAuth callback URL.
    static func authorizationCode(from callbackURL: URL) -> String? {
        queryValue("code", in: callbackURL)
    }

    /// Extracts the `state` query item, which must match the one sent in `authorizeURL`.
    static func state(from callbackURL: URL) -> String? {
        queryValue("state", in: callbackURL)
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value?
            .nilIfBlank
    }

    private static func infoValue(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfBlank
    }
}
