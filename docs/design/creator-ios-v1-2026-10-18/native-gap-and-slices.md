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
6. **Cloud sync and several AI drafts per date** (19 October, second change).
   - Migration `20261019120000_content_pieces_sync.sql` adds `content_pieces`. Each row stores one piece document, a revision for safe concurrent writes, and a sequence number that lets a device fetch only rows changed since its last sync. The table is reachable only through edge functions.
   - Edge function `sync-pieces` handles `pull` and `push`. It authenticates with the same device session as the other functions. A push whose base revision is out of date is rejected as a conflict and the server copy is returned.
   - The app pulls, merges, then pushes. On a conflict it merges both copies and pushes the result. Approved versions, drafts from each device, captured shots and posting records are all kept; when two devices edit the same draft, the later edit becomes a new draft version. Edits are saved on the device first, and a banner says when they are waiting to sync.
   - `generate-week` accepts `generate_piece_draft`. It runs the same generation pipeline as `generate_day` but never reads or writes the date's daily card, so a date can hold any number of AI drafts. The first AI draft for a date still uses `generate_day` and becomes that date's day package.
   - The old Shoot Folio and one-package filming screens are removed. Filming uses the piece flow only.
7. **Later, not in this change.**
   - Instagram and TikTok connections, direct posting and insights (22, 23, 30–32). These need API access, platform review and owner approval.
   - Reminders, appearance and AI-privacy preferences (37–40) beyond what already exists.

## Limits that remain

- The migration and the `sync-pieces` and `generate-week` changes are in the repository only. They have not been deployed. Until they are, live sync reports a failure and edits stay on the device.
- Attached clips and final media files stay on the device that added them. Their records sync, and other devices ask the creator to choose the file again.
- Storyboard previews for a second or later AI draft are generated, but the app keeps the copy it received when the text finished. Previews that arrive later are not fetched again.
- Clips are copied into the app from Photos. The app does not edit or render video.
- Posting results are manual marks. Nothing is sent to Instagram or TikTok.
- Fixture and e2e runs use local-only sync, so e2e cannot show sync between two devices.
