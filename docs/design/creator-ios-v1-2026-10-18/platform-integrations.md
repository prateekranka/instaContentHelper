# ContentHelper: social integration design

Research checked 18 October 2026. This is a proposed capability map. No accounts were connected and no posting capability was implemented or approved for this app.

## Recommended product scope

Start with a complete creator workflow that works with manual posting. Add account-aware direct publishing where approved. Ask for publishing access at posting time and insights access when the creator opens results. Keep a usable export route when an account, region, format or permission is unsupported.

| Integration | Proposed experience | Conditions and fallback |
|---|---|---|
| Instagram account | Connect a professional account and show its handle at review | Meta's Instagram Login route does not require a linked Facebook Page. Personal accounts use manual export. [Meta's official collection](https://www.postman.com/meta/workspace/instagram/documentation/23987686-9386f468-7714-490f-9bfc-9442db5c8f00) |
| Instagram Reel | Preview final media, edit caption/cover, publish, show result | Requires supported account, format, permissions and platform review. [Meta Reel publishing request](https://www.postman.com/meta/instagram/request/gabnx7r/publish-reel) |
| Instagram photos/carousels | Keep format-aware media order, caption and accessibility fields | Validate the selected login route and current media restrictions before exposing controls. Export remains available. |
| Instagram Stories | Finish in Instagram when direct posting is not eligible | Meta's Facebook Login documentation limits Story publishing to business accounts. Do not promise direct Stories for every creator. [Meta account limitations](https://www.postman.com/meta/instagram/folder/u4g5a2a/instagram-api-with-facebook-login) |
| TikTok direct post | Show creator nickname, preview, editable caption and explicit post settings | Needs user authorization and an audited client for public posting. Unaudited clients are restricted. [TikTok Direct Post](https://developers.tiktok.com/docs/en/content-posting-api-get-started) |
| TikTok draft upload | Send final media, then offer Finish in TikTok | Delivery to the inbox is not publication. [TikTok Upload](https://developers.tiktok.com/docs/en/content-posting-api-reference-upload-video) |
| TikTok app handoff | Share selected media through Share Kit and handle cancel/failure | App registration and media access are required. A saved draft is different from a published result. [TikTok Share Kit for iOS](https://developers.tiktok.com/docs/en/share-kit-ios-quickstart-v2) |
| TikTok photo post | Review ordered images and photo-specific settings | Use supported photo endpoint and its distinct metadata; disclose generated output when applicable. [TikTok Photo API](https://developers.tiktok.com/docs/en/content-posting-api-reference-photo-post) |
| TikTok post verification | Keep Uploading, Processing, Posted and Failed separate | Poll or consume status events; only mark verified after a completed result. [TikTok post status](https://developers.tiktok.com/docs/en/content-posting-api-reference-get-video-status) |
| Authorized TikTok library | Let creator link their own public posts to saved work | Display API exposes authorized public-video metadata, not a raw-media download or an unrestricted saved-post library. [Display API](https://developers.tiktok.com/docs/en/display-api-overview) |
| Results | Show available per-post metrics, fetch time and creator notes | TikTok video metadata includes views, likes, comments and shares. Instagram metrics depend on approved access and current definitions. [TikTok video object](https://developers.tiktok.com/docs/en/tiktok-api-v2-video-object), [Meta collection overview](https://www.postman.com/meta/instagram/collection/6yqw8pt/instagram-api) |

The direct Instagram developer pages could not be retrieved in this session. Meta's verified official Postman workspace supplied the primary evidence. Fine-grained Instagram scopes, field availability, current insights names, scheduling constraints and format rules must be rechecked in the selected API version before implementation. The designs do not claim that one login route grants every capability.

## TikTok final-review contract

Use the latest account information. Require the creator to choose an audience from the returned options; do not preset it. Comments, Duet and Stitch start unchecked and respect account restrictions. Photo posts omit Duet/Stitch. Provide commercial-content disclosure and the applicable music/policy declaration. Preview the media, keep captions editable, and send only after explicit consent. No ContentHelper promotional watermark. See [TikTok's required sharing UX](https://developers.tiktok.com/docs/en/content-sharing-guidelines).

The screen board shows the initial audience-unselected state. Selecting an audience enables the next valid action; the app must still validate all current requirements. Commercial selections reveal further controls in a scrolling form. A generated planning thumbnail is not automatically included in the final post; AI disclosure follows the actual outgoing media.

## What to add next

| Priority | Capability | Why it helps |
|---|---|---|
| First | Final-media picker, copy caption, save/export, platform app handoff, manual Posted mark | Completes the day even without API access |
| Next | Approved Instagram publishing plus status and account recovery | Removes repeated export work for eligible creators |
| Next | TikTok Share Kit, draft upload and audited Direct Post | Supports both native finishing and direct publishing where available |
| Next | Link creator's own posts, available metrics and private notes | Lets a creator learn from a piece and make a follow-up |
| Later | Scheduling against a reviewed immutable upload snapshot | Requires background service, timezone handling, account checks and a clear reviewed consent model |
| Later | Contextual reminders, share extension, App Shortcuts and a Today widget | Helps capture ideas and resume the next piece with less navigation |
| Later | YouTube Shorts, Facebook Reels and Threads | Reuse the platform adapter model after separate API and market checks; not verified in this research pass |

Keep trend references lightweight: saved links and creator notes first. Do not promise arbitrary Instagram/TikTok downloading, access to private saved collections, licensed trending music, or unrestricted trend APIs. Platform-app completion can provide platform editing tools without pretending those tools exist inside ContentHelper.

Because the research pilot is India-based, prioritize Instagram for that pilot and gate other platforms by actual regional/account availability. The TikTok boards describe a supported-market flow; this session did not establish TikTok availability for an Indian account or device.

## Reliability rules

- Content approval and upload consent are separate. Approving a day never posts it automatically.
- Review each platform with its account and final media visible. Do not reuse a TikTok audience choice as implicit consent for later posts.
- Preserve separate captions, target states and attempts. One platform's failure cannot undo another's successful result.
- Reconcile unknown attempts before retrying; retain request identity to avoid duplicate posts.
- Local edits never silently change a published social post. Preserve the original record and create a new publishing revision when requested.
- Disconnecting stops future access and keeps local drafts/history. Already published posts remain on the platform.
