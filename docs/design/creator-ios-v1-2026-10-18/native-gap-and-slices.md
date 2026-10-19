# Native app compared with the 40-screen proposal

19 October 2026. Source comparison of `main` at `1580a82` with the screen boards and [flow specification](flow-and-state-spec.md). This is a source reading, not a runtime check. No build or e2e run was possible in the Linux session that wrote it.

## What the app had

| Area | Native app before this change | Proposal |
|---|---|---|
| Unit of work | One `DailyCard` per date. Backend `daily_cards` is unique on `(weekly_plan_id, scheduled_date)` | Several independent pieces per date |
| Status | One `CompletionState` per card: shot, posted, used backup, saved for tomorrow, skipped | Draft → Approved → Shot → Posted per piece, with filming and per-platform posting details |
| Approval | Plan "Make available on Today" for the whole day | Approve one reviewed piece or a reviewed group; approval saves a version |
| Versions | None. Edits overwrite the package | Approved versions stay; edits create a draft revision; restore makes a new draft |
| Shots | `ShotScene` with UUIDs, progress keyed by scene ID plus number/title fallback | Stable shot identity, captured state and attached clip per shot, survives reorder |
| Media | Generated storyboard thumbnails only | Generated previews labelled as such, attached clips, selected final media |
| Posting | Local "Mark as posted" for the day | Separate record per platform: Posted, Processing, Finish in app, Failed, Result unknown, Marked posted by you |
| Today | One package with Start/Continue filming and "Need something easier?" | List of pieces with states, Add content, Review day, next useful action |
| Plan | Seven-day selector, AI idea launcher and one package per date | Calendar, selected day's pieces, add piece, move piece |
| You | Voice, categories, references, account, Archive | Your content with search and filters, preferences, connections |
| Colour | Monochrome Pocket palette; secondary text #737373 | Monochrome; secondary text at least #666666 on white |

Reused as is: Pocket design tokens and components, Today / Plan / You shell, onboarding and AI-consent flow, Apple sign-in, AI day generation, storyboard thumbnails, fixture launch flags and the TesterArmy e2e harness.

## Implementation slices

1. **Piece model and store.** `ContentPiece` with versions, stable shots, captured shots, media references and posting records. Kept on the device as JSON, separated by workspace and by e2e fixture session. Existing day packages are imported as pieces, keeping shot progress and the posted mark. Approved packages become an approved version 1.
2. **Shared UI.** Reserved safe-area footer for the primary and secondary actions, status labels with text plus icon, media thumbnails with "Shot preview · generated", piece rows. Secondary-text token set to #666666.
3. **Day and piece screens.** Today (05, 34, 04), Review day (33), New content (06), Review draft and Approved (07, 08, 11), Edit script, shots and caption (13–15), Versions (16), Move content (12), and the selected day's pieces in Plan (09, 10).
4. **Filming and final media.** Continue filming with Previous and Pause (17), Attach clip from Photos (18), All shots captured and Mark as shot (19), and Ready to post with final media selection (20). Photo and carousel pieces use Prepare media and Mark ready.
5. **Manual posting and history.** Post options with copy caption, share/export and Finish in Instagram or TikTok (21). Each platform gets "Marked posted by you" with an optional link and its own result (24). Your content with search and filters (25), a posted piece (26), and edit-posted options that keep the original record (28). Reapproval with filming impact (27).
6. **Later, not in this change.**
   - Backend migration to store pieces and versions on the server, so several AI drafts per date and multi-device sync become possible. Today the backend allows one AI package per date, and pieces stay on the device.
   - Instagram and TikTok connections, direct posting and insights (22, 23, 30–32). These need API access, platform review and owner approval.
   - Reminders, appearance and AI-privacy preferences (37–40) beyond what already exists.
   - Offline sync indicator (36) once a server copy exists.

## Limits that remain after slices 1–5

- Pieces live on one device. Deleting the app removes local pieces and their versions. Server day packages and the archive are unaffected.
- AI "Create draft" can only be used for a date without an AI package. Other dates offer Write it myself and keep the topic for a later attempt.
- Clips are referenced through the Photos library identifier. The app does not copy or render video.
- Posting results are manual marks. Nothing is sent to Instagram or TikTok.
