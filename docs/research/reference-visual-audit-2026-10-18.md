# ContentHelper reference-screen visual audit

18 October 2026. This follows the [creator-first flow proposal](creator-first-flows-2026-10-18.md).

## Outcome

Visual review is possible through the rendered public pages in Brave. Mobbin's public flow carousels display actual phone previews. Official Buffer, Adobe Express, and Captions pages also display useful interface images. These sources were viewed as pixels and captured for this audit.

The earlier report used text indexes only. This follow-up adds direct visual evidence for the sources listed below. It does not claim that the reference apps were installed, that their current live behavior was tested, or that the proposed ContentHelper screens already exist.

## Access and coverage

| Reference | What was visually reviewed | Evidence and limits |
|---|---|---|
| [Spotify onboarding on Mobbin](https://mobbin.com/explore/flows/d162ef83-02c1-45d9-be0f-6d03633ac095) | Account fields; notification explanation and native sheet; artist and podcast selection; loading; terms/tracking interruptions; personalized Home | Eight saved page captures. Selected readable states from the 29-screen library flow; not a guarantee that every distinct frame is fully readable. Capture date/version was not established. |
| [Placify onboarding on Mobbin](https://mobbin.com/explore/flows/e7c01786-65e4-4739-903b-8bfbe339e7c6) | Introductory screens; example search prompts; search results; selection; saved place; optional photo prompt; populated map/list | Three page captures from the 12-screen preview. This is a reference recording, not current live-app proof. |
| [Walmart Sparky on Mobbin](https://mobbin.com/explore/flows/0447ed53-fb99-4aff-9350-78944e8395fe) | Suggested questions; typed follow-up; loading dots; error followed by a repeated question; answer sources/feedback; product cards | Two page captures from the seven-screen flow. This demonstrates the captured UI states, not the AI's reliability. |
| [Saturn Calendar on Mobbin](https://mobbin.com/explore/flows/dab581d3-d756-4772-a3e1-46838624aecc) | Text alternative; microphone cue; recording waveform/cancel/confirmation; interpreted text; event card; optional follow-up choices | One capture showing the four public previews. It does not prove transcription accuracy or voice permissions. |
| [Buffer AI Assistant](https://buffer.com/ai-assistant) | Composer with media and channel context; separate original/suggestion areas; Retry/Replace; specific editing actions | Two captures of official marketing interface illustrations. Useful for visual patterns, not proof of a running editor or mobile layout. |
| [Adobe Express version history](https://helpx.adobe.com/express/web/arrange-layers-and-pages/version-history.html) | File-menu entry; history panel; timestamped versions; restore/copy/bookmark icons | Two captures of official help screenshots. These do not show selected-text AI editing. |
| [Captions camera](https://captions.ai/help/docs/project/camera) | Home/menu/camera sequence; camera preview; record button; Continue; secondary controls | One capture of a three-phone help illustration. Teleprompter text and scene-by-scene progress are not visible in that image. |
| [Busuu on Page Flows](https://pageflows.com/post/ios/onboarding/busuu/) | Public App Store, splash, and language screens; brief recording preview; account gate | The page explicitly labels this version January 2020. Playback stopped at about 20 seconds. Selecting a later chapter reached an account gate. Later plan screens remain index evidence only. |
| Clubhouse and Bear on Page Flows | Not part of this visual pass | Retain their earlier status as text-index references. |

Public Mobbin phone previews are about 234 × 548 pixels; Saturn previews are 233 × 546. They support layout and sequence findings. They do not support exact font, spacing, contrast-ratio, or touch-target compliance claims.

## Findings that change the design detail

### 1. Show clear selections, then carry them into the result

Spotify's artist and podcast screens combine recognizable examples, search, and visible selected-item checkmarks. Its completion screens retain selected artwork before processing. This makes the relationship between a choice and the result visible.

For ContentHelper, use a small set of topic or format examples on the existing short setup screen. Show selected topic and language while the plan is prepared. Keep those choices visible on the first package. Do not add another required preference-selection stage.

Spotify's captured account sequence also includes birth date, gender, name, and later terms/tracking screens. Their presence is evidence of extra steps, not a recommendation to copy them. ContentHelper should reach the first useful plan after the required account and AI-consent steps.

Evidence: [selection](../../work/evidence/reference-visual-audit/20261018T143748Z.AiNyf5/spotify-public-preview-04.jpg), [processing](../../work/evidence/reference-visual-audit/20261018T143748Z.AiNyf5/spotify-public-preview-05.jpg), [final sequence](../../work/evidence/reference-visual-audit/20261018T143748Z.AiNyf5/spotify-public-preview-final.jpg).

### 2. Teach through the first saved object

Placify moves from an introductory sequence to finding a real place, selecting it, and seeing it on the map. The optional photo prompt appears beside the saved place. The task itself gives the app context for explaining the next feature.

For ContentHelper, the first saved package should become the teaching surface. Explain script editing beside the script and filming progress beside the first shot. Ask for an optional reference or style example when it would improve that package. A separate feature-tour sequence would add more work before creation.

The captured Placify hint text and some secondary labels are visually faint. This is a legibility concern from the preview, not a measured contrast failure. ContentHelper should keep task instructions prominent and test them at supported text sizes later.

Evidence: [first task](../../work/evidence/reference-visual-audit/20261018T143748Z.AiNyf5/placify-public-preview-02.jpg), [saved place and optional photo](../../work/evidence/reference-visual-audit/20261018T143748Z.AiNyf5/placify-public-preview-03.jpg).

### 3. Put named editing actions beside a replacement preview

Buffer's official editing illustration visibly separates the short original text from the proposed replacement. Retry and Replace are separate actions. Rephrase, Shorten, Expand, More casual, and More formal are named choices.

For ContentHelper, use this structure in a sheet attached to the selected hook, script section, shot, or caption. Show the section name, current text, suggestion, and explicit Apply/Keep original actions. Offer Retry without losing the current text. Keep the first few actions specific to the task: Shorter, Easier to say, Change language, or Less filming.

The desktop-style illustration should inform the interaction, not dictate the phone layout. On an iPhone, stack the current and proposed text with clear labels.

![Official Buffer page showing an original, proposed text, Retry and Replace, and named editing actions](../../work/evidence/reference-visual-audit/20261018T143748Z.AiNyf5/buffer-official-ai-editing.jpg)

### 4. Make retry a direct action

The Walmart capture shows a failed answer, then the same question entered again. The conversation remains visible. Later answers expose sources and feedback controls. Product cards turn a long answer into identifiable objects.

For ContentHelper, keep the failed brief or edit request and offer a visible Retry action. The creator should not need to type the request again. Present generated work as a package with named sections, rather than an unstructured conversation. Source controls are useful for a recommendation based on a current reference, but they do not establish that its claims are correct.

Evidence: [error, repeated question, sources, and cards](../../work/evidence/reference-visual-audit/20261018T143748Z.AiNyf5/walmart-ai-public-preview-02.jpg).

### 5. Keep voice input correctable before it changes work

Saturn shows a text entry option, a microphone cue, a recording state, interpreted text, and a resulting event card. Optional follow-up choices appear after the core request.

If ContentHelper later adds spoken idea capture, keep a text alternative. Let the creator correct the interpreted brief before generation. Add optional audience or cadence detail after the idea has become a useful object. Voice remains an optional feature; this reference does not establish that Mamta prefers it.

![Saturn public previews showing text, recording, interpreted text, and a result card](../../work/evidence/reference-visual-audit/20261018T143748Z.AiNyf5/saturn-voice-public-preview.jpg)

### 6. Keep recovery discoverable and separate from deletion

Adobe's help screenshots place version history in the File menu and group saved versions by time. Restore, copy, and bookmark actions sit beside a timestamp. That is a useful recovery structure, although the small action icons need explanation in a phone interface.

For ContentHelper, put Versions in the package's visible menu and use named actions: Restore this version, Make a variant, and Keep this version. Show a preview before restoration. Do not make recovery depend on recognizing three unlabeled icons.

Evidence: [history entry](../../work/evidence/reference-visual-audit/20261018T143748Z.AiNyf5/adobe-official-history-entry.jpg), [timestamped actions](../../work/evidence/reference-visual-audit/20261018T143748Z.AiNyf5/adobe-official-history-actions.jpg).

### 7. Keep the filming action dominant

The Captions help illustration gives the camera preview most of the phone area and makes the record control visually distinct. Camera options remain secondary. It also shows that users may pass through a menu to reach filming.

For ContentHelper's first release, keep the current shot, spoken line, and Mark captured action dominant in Shoot Folio. Put optional settings behind the task. If a built-in camera is added later, Start filming should enter it directly from the accepted package.

The image does not show readable teleprompter text, a shot checklist, or interruption recovery. Those remain proposed ContentHelper requirements, not visually verified Captions features.

Evidence: [official camera illustration](../../work/evidence/reference-visual-audit/20261018T143748Z.AiNyf5/captions-official-camera.jpg).

## Changes to the earlier research interpretation

- Visual evidence is now available for the selected Mobbin and official interface images above. The earlier blanket statement that no reference screenshots were reviewed applies only to the initial research pass.
- Busuu's referenced Page Flows recording is historical: January 2020. Later screens are still gated. Do not describe that recording as a current 2026 onboarding audit.
- Meta's [Edits launch article and its December 2025 update](https://about.fb.com/news/2025/04/introducing-edits-streamlined-video-creation-app/) explicitly describe storyboards connecting scripts, teleprompter cues, clips, and notes. Edits must remain a close comparison. Do not claim that storyboard organization alone differentiates ContentHelper. This correction is from official documentation, not a visual audit of Edits.

The proposed navigation and six flow maps remain appropriate. The visual review adds detail to selection feedback, generation context, refinement previews, retry, and version recovery. It does not validate demand or prove that the proposed complete workflow is usable.

## Repeatable audit method

1. Open the exact reference flow or official guide in the normal browser.
2. Record the source URL, visible version/date, and access level.
3. Use the site's normal carousel or public recording controls. Stop when an account or payment gate appears.
4. Check that images loaded before interpreting a blank frame. Retain the surrounding page context in a capture.
5. Save page screenshots and label the states that are actually readable. Keep the source controls distinct from the product interface.
6. Write each finding as observed detail → effect on the task → proposed ContentHelper change.
7. Keep layout observations separate from behavior, performance, and accessibility tests.

Mobbin's blue interaction outlines and translucent blue highlights belong to the reference annotation layer. Its Save/Copy overlays, carousel arrows, and page header are not controls in the recorded apps. Adobe's orange outlines and Buffer's promotional framing also belong to the source presentation.

Original Mobbin image-file downloads were rejected by the browser permission gate. A retry after the user said permission should work returned the same rejection. No alternate downloader was used. Read-only page viewing and screenshot capture worked, so this audit did not depend on downloading the source image files. Page Flows did not have an authenticated session in this browser. No account, trial, or subscription was created.

Evidence lives in [the capture manifest](../../work/evidence/reference-visual-audit/20261018T143748Z.AiNyf5/capture-manifest.json) and the linked original page screenshots. The shared evidence root was unavailable, so a task-local evidence directory was used. App source was not changed. No ContentHelper app behavior tests were run; this was reference research.
