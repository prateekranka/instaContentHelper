# Layers Surface: Creator Content OS V2 First TestFlight MVP

Source inputs:

- V2 PRD draft: `/tmp/codex-remote-attachments/019e91d6-f797-7072-bc8c-b5db7482e6cf/D4864C26-EC4C-4E92-BC1D-B275F97C5DE7/1-creator-content-os-v2-prd.md`
- Conceptual model: `docs/layers-conceptual-model-creator-content-os-v2.md`
- Interaction flows: `docs/layers-interaction-flow-creator-content-os-v2.md`

This is a surface decision inventory for the first TestFlight MVP slice, not the full V2 intelligence system.

## Surface Frame

Medium: native iPhone SwiftUI app.

Primary emotional job:

- Creator should feel prepared, not managed.
- Manager should feel in control of the weekly system, not buried in a SaaS dashboard.

Visual register:

- Premium editorial fitness journal.
- Calm, warm, precise, personal.
- Avoid generic AI assistant, analytics dashboard, growth-hack app, or dense content-calendar look.

First TestFlight MVP surface should prove:

- Creator can use one Daily Card each morning.
- Manager can prepare and publish a week.
- Manager can add a small number of References and use them in generation.
- Creator can decide, copy, request an alternative, and complete the day.
- Archive records the week.

## MVP Slice

### Include Now

- Pairing / role setup
- Creator Daily Mode
- Today surface for one Daily Card
- Package detail: Scenes, Script, Caption, Audio, Post
- Decision sheet and completion states
- Lightweight feedback tags
- Card Alternative preview and "Use this"
- Manager Setup Mode
- Weekly Setup Draft
- Weekly Plan Review
- Daily Card Review
- Publish Confirmation
- Trend + Inspiration Inbox, reduced to References
- Add Reference
- Reference Review
- Archive
- Basic Creator Profile editor or read/edit structured profile sections
- Local/offline Today states

### Defer From Surface MVP

- Dedicated Watchlist screen
- Full top-500 influencer management UI
- Benchmark Creator detail screen
- Trend clustering dashboard
- Pattern library screen
- Collab Lead pipeline
- Full Collabs & Events workspace
- Learning Summary screen beyond simple archive notes
- Performance snapshots beyond optional final post link
- Scout-specific UI
- Provider/API settings
- Analytics dashboard
- iPad layout

### Minimal Handling For Deferred Objects

- Watchlist/Benchmark Creator: seed or import behind a simple admin utility, not a polished user-facing screen.
- Pattern/Trend/Audio Option: show as "Inspiration used" inside card/source surfaces, not as independent libraries.
- Brand Brief/Key Moment: allow lightweight entry during Weekly Setup, not a separate full workflow.

## Audit Findings

There is no existing product surface to audit, so findings are against the PRD's proposed surface language and flow.

### Vocabulary Findings

Surface fix: avoid exposing backend/schema terms.

- Do not show `trend_observation`, `trend_cluster`, `content_pattern`, `audio_candidate`, `daily_card_reference`, or `source_list_member`.
- Use the product terms from the conceptual model: Reference, Trend, Pattern, Audio Option, Idea, Daily Card, Brand Brief, Key Moment.

Surface fix: use softer Creator-facing labels where the model term is too internal, while preserving the model underneath.

- Model term: Daily Card. Creator-facing label: `Today`.
- Model term: Package Detail. Creator-facing labels: `Scenes`, `Script`, `Caption`, `Audio`, `Post`.
- Model term: Card Alternative. Creator-facing label: `Option`.
- Model term: Feedback. Creator-facing label: `Tell us what to adjust`.

Deeper-layer risk: `Can shoot today` remains unresolved as an intent signal. Surface should avoid making it look like completion.

Decision:

- In MVP, `Can shoot today` should open the decision sheet and not mark the day complete by itself.

### Object Consistency

Potential shapeshifter: Daily Card.

- It appears as Today, a day row in Weekly Plan, Daily Card Review, Archive entry, and Alternative Preview.
- Surface treatment must keep a consistent core: title, date, shootability, status, package availability.

Potential masked objects: Reference vs Trend vs Pattern.

- Raw links/screenshots and approved planning inputs can look similar in admin lists.
- MVP must visually separate `References to review` from `Ready for planning`.

Potential masked objects: Brand Brief vs Key Moment.

- Both can appear as flags on a Weekly Plan.
- Surface should distinguish commercial obligations from life/context moments.

Surface decision:

- Use distinct labels: `Brand` for Brand Brief, `Moment` for Key Moment.
- Brand surfaces must include disclosure/approval state. Moment surfaces should not.

### Completeness Findings

Breadboard affordances required in MVP:

- Prepare next week
- Generate week
- Review day
- Publish week
- Add Reference
- Analyze Reference
- Confirm extraction
- Use source this week
- Copy script/caption/audio notes
- Need easier option
- Use this alternative
- Mark shot
- Mark posted
- Save for tomorrow
- Skip intentionally
- Add feedback

Surface gap to avoid:

- A pretty Today card without visible completion affordances would fail the flow.
- An admin Weekly Plan calendar without publish/review states would fail the flow.
- A Trend Inbox that jumps straight from screenshot to "Trend" would violate the conceptual model.

### Emotional Register

Creator-facing tone:

- Reassuring, direct, warm.
- Avoid pressure, streak language, "growth hacking," or "content machine" phrasing.
- The app should make skipped days feel handled, not failed.

Manager-facing tone:

- Precise and operational.
- Show constraints, warnings, source provenance, and generation status without visual clutter.

Bad surface language to avoid:

- "Optimize today's content."
- "Engagement opportunity."
- "Viral trend detected."
- "Failed to complete."
- "No content available."

Better language:

- "Today's idea is ready."
- "Use the easier version."
- "This audio needs checking in Instagram."
- "No card has been published for today."
- "Saved. We will sync this when you're back online."

## Screen Surface Decisions

### Pairing

Primary user need:

- Get the right phone into the right role without feeling like a login system.

Content hierarchy:

1. App name / private workspace cue
2. Pairing code entry
3. Role confirmation after valid code
4. Continue

Copy:

- Title: `Pair this phone`
- Helper: `Enter the code Manager created for this workspace.`
- Success: `This phone is paired as Creator.`
- Failure: `That code did not work. It may be expired or already used. Check the code and try again.`

Accessibility:

- Numeric/text code field must support paste.
- Clear error text, not colour-only indication.

### Today

Primary user need:

- Creator immediately knows what to shoot today and how hard it will be.

Most prominent:

1. Daily Card title
2. Why today
3. Shootability and estimated time
4. Primary action: `See what to shoot`
5. Secondary action: `Need easier option`

Content required:

- Date/day context
- Title
- Why today
- Shootability
- Estimated shoot time
- Energy required if useful
- Brand/Moment flag if relevant
- Audio verification flag if relevant
- Completion state if already decided

Creator-facing labels:

- `Today`
- `Why this fits today`
- `Easy`, `Medium`, `Hard`
- `Need easier option`
- `Mark shot`
- `Mark posted`
- `Save for tomorrow`
- `Skip today`

Surface decision:

- Do not make Trends, Patterns, or source intelligence visually dominant on Today. Show a small "Inspired by..." note only when useful.

Loading:

- If cached: show immediately.
- If syncing: show card with a small `Checking for updates...` state.
- If no card: `No card has been published for today. Ask Manager to publish this week.`

Offline:

- `You're offline. Today's card is saved on this phone. Decisions will sync later.`

### Package Detail

Primary user need:

- Copy or follow the exact production package without hunting.

MVP sections:

- Scenes
- Script
- Caption
- Audio
- Post
- Brand only if relevant

Hierarchy:

- Section switcher
- Section content
- Copy/open action near the relevant content
- Warnings inline, not as generic banners

Copy labels:

- `Copy script`
- `Copy caption`
- `Open audio in Instagram`
- `Copy post checklist`
- `Use fallback audio`

Audio warning:

- `Check this audio inside Instagram before posting. If it is unavailable, use the fallback below.`

Brand warning:

- `Brand note: include the required tag and disclosure.`

### Decision Sheet

Primary user need:

- Complete the day through a real decision, not guilt.

Options:

- `I shot it`
- `I posted it`
- `Use backup story`
- `Caption-only today`
- `Save for tomorrow`
- `Skip today`

Surface decision:

- Use first-person labels for Creator-facing completion actions where they feel natural.
- Avoid `Complete day` because it hides meaningful differences.

Post-action:

- Show confirmation with undo.
- Offer optional feedback.

Copy:

- `Saved for today. Want to tell us what to adjust next time?`

### Alternative Preview

Primary user need:

- Safely choose a lower-effort or better-voice version without losing the original.

Hierarchy:

1. Reason for alternative: `Easier version`, `More Hinglish`, `Shorter caption`, etc.
2. What changed
3. Preview of changed fields
4. Primary: `Use this`
5. Secondary: `Keep original`

Critical surface rule:

- Never replace the original silently.

Failure:

- `Could not create that option. The connection failed before we could save anything. Try again or use the backup already on today's card.`

### Weekly Setup Home

Primary user need:

- Manager sees what needs to be prepared next and whether Creator already has a published week.

Most prominent:

1. Current/published week status
2. Next week preparation action
3. Warnings or missing setup items
4. Last week completion summary

Labels:

- `Prepare next week`
- `Current published week`
- `Draft week`
- `Needs review`
- `Published to Creator`

Surface decision:

- This can be more operational than Today, but should still avoid generic dashboard density.

### Weekly Setup Draft

Primary user need:

- Manager can enter enough context to generate a useful week.

MVP sections:

- Week
- Location
- Routine changes
- Key moments
- Brand notes
- References to use
- No-go topics

Progress:

- Show setup completeness as a checklist, not a percentage.

Generation disabled copy:

- `Add a week start date and routine/context before generating.`

### Weekly Plan Review

Primary user need:

- Manager can trust and approve the 7 days before Creator sees them.

Day row/card content:

- Day/date
- Daily Card title
- Workout/context
- Shootability
- Source flag: Brand, Moment, Trend, Pattern, Evergreen
- Audio confidence
- Warning count
- Review state

Primary actions:

- `Open day`
- `Publish week`
- `Save draft`

Warning labels:

- `Audio needs checking`
- `Brand requirement missing`
- `Too hard after previous hard day`
- `Source not approved`

Surface decision:

- Publish should be visually prominent only when all blocking warnings are resolved.

### Daily Card Review

Primary user need:

- Manager edits and approves exactly what Creator will see.

Must show:

- Creator preview
- Editable fields
- Source explanation
- Brand/event constraints
- Warning list
- Revision marker

Actions:

- `Edit`
- `Create option`
- `Use this`
- `Approve day`
- `Back to week`

Surface decision:

- "Creator preview" should be the default view. Advanced fields can be secondary.

### Trend + Inspiration Inbox MVP

Primary user need:

- Manager can add and confirm raw source material.

MVP grouping:

- `Needs review` - References added or analyzed but not confirmed
- `Ready for planning` - approved Trends, Patterns, Audio Options, Ideas
- `Dismissed` - optional hidden filter

Primary action:

- `Add screenshot or link`

Copy:

- `References are raw material. Confirm what the system found before using them in a week.`

Surface decision:

- Avoid presenting this as a social feed. It is an intake/review surface.

### Add Reference

Fields:

- Link
- Screenshot/video upload
- Note
- Tags

Actions:

- `Analyze now`
- `Save without analysis`
- `Cancel`

Failure copy:

- Invalid link: `This link does not look like a reel or audio link. Save it as a note, or check the link and try again.`
- Upload failed: `The upload did not finish. Your note is still here. Try the upload again.`

### Reference Review

Hierarchy:

1. Raw source preview
2. Extracted findings
3. Fit for Creator
4. What to adapt
5. What to avoid
6. Confirm/approve actions

Actions:

- `Confirm extraction`
- `Approve as Trend`
- `Approve as Pattern`
- `Save as Idea`
- `Approve audio`
- `Dismiss`

Surface decision:

- Make `Confirm extraction` and `Approve for planning` visibly distinct.

### Archive MVP

Primary user need:

- Manager and Creator can see what happened during the week without analytics pressure.

Entry content:

- Date
- Daily Card title
- Completion state
- Caption/script used
- Feedback tags
- Optional post link

Labels:

- `Shot`
- `Posted`
- `Used backup`
- `Saved for tomorrow`
- `Skipped`

Do not show:

- Likes/views/comments in MVP primary archive
- Charts
- Streaks

## Feedback And Error Decisions

### Action Success

- Pairing success: confirm role and workspace.
- Reference saved: show it in `Needs review`.
- Reference analyzed: show extracted findings and next required action.
- Week generated: route to Weekly Plan Review.
- Week published: show "Published to Creator" and sync status.
- Daily decision saved: show completion state and undo.
- Copy action: show short copied confirmation.

### In Progress

- Analysis: show specific stages.
- Weekly generation: show specific stages.
- Sync: use quiet status text unless it blocks the user.
- Alternative generation: show what is being changed.

### Errors

Every error must diagnose, explain, and recover.

Network during Today:

- `You're offline. Today's card is saved on this phone. Decisions will sync later.`

No published card:

- `No card has been published for today. Ask Manager to publish this week.`

Generation failed:

- `The week was not generated. The system could not validate the cards it created. Your setup is saved; try again or adjust the inputs.`

Reference analysis failed:

- `This reference could not be analyzed. The screenshot may be unclear or the link may not be accessible. Save it as a note or try another source.`

Audio uncertainty:

- `This audio may not be available on Creator's account. Check it in Instagram before posting.`

Brand blocking warning:

- `This card is missing a required brand detail. Add the disclosure/tag before publishing.`

## Hierarchy Decisions

### Overall Navigation

Recommended MVP navigation:

- Creator role: Today as home, Archive and Settings secondary.
- Manager role: Setup as home, Today preview, References, Archive, Profile.

Surface decision:

- Do not use the same tab bar for Creator and Manager if it makes Creator see admin machinery. Role-based home is acceptable for TestFlight.

### Today Hierarchy

Primary:

- Title and shootability/action.

Secondary:

- Package tabs and copy actions.

Tertiary:

- Source explanation, warnings, feedback.

### Setup Hierarchy

Primary:

- Publishable week status.

Secondary:

- Missing setup items and warnings.

Tertiary:

- Source provenance and advanced generation notes.

## Accessibility Decisions

Screen UI requirements:

- Minimum 44pt touch targets for all completion/copy actions.
- Dynamic Type support at least through large accessibility sizes for Today and Package Detail.
- High contrast text; do not rely on muted editorial greys for critical warnings.
- Colour cannot be the only indicator for shootability, warning state, or completion state.
- Buttons need explicit labels: `Copy caption`, not icon-only copy.
- Images/screenshots in Reference Review need accessible labels or can be marked decorative if not essential.
- Focus should move to the generated result after analysis/generation completes.
- Completion confirmation and errors should be announced to VoiceOver.
- External Instagram links should be labelled as leaving the app.

Creator-specific accessibility:

- Avoid tiny dense admin controls in Daily Mode.
- Keep line lengths short for scripts/captions.
- Copy affordances must sit close to the content they copy.

## Consistency Decisions

Object treatments:

- Daily Card: title + date + shootability + status in every context.
- Reference: source preview + extraction status + provenance.
- Trend/Pattern/Audio Option: fit score + source provenance + use status.
- Brand Brief: brand name + due/review date + disclosure/approval state.
- Key Moment: name + date + kind + content angle.

Action treatments:

- Safe primary: filled button.
- Secondary: plain/text or bordered.
- Destructive/dismissive: visually quiet but clearly labelled.
- AI generation: button label must name outcome, not "AI" or "regenerate."

Examples:

- Good: `Make easier`, `Shorter caption`, `More Hinglish`
- Avoid: `Regenerate`, `Optimize`, `Use AI`

## Cross-Layer Issues To Resolve

1. `Can shoot today` needs final model/flow decision. MVP recommendation: intent action only, not completion.
2. `Save for tomorrow` needs final behavior. MVP recommendation: mark current day Saved for tomorrow and create an Idea for rescheduling; do not automatically move tomorrow's card.
3. Audio verification policy needs product decision. MVP recommendation: verification warning plus fallback is enough; do not block publishing unless brand/collab requires exact audio.
4. Watchlist import scope needs MVP decision. MVP recommendation: seed/import minimal list for generation, but defer dedicated Watchlist surface.
5. Brand approval needs split. MVP recommendation: one simple `Approval needed` field in Brand Brief; separate Manager vs brand approval later.

## Surface Decisions To Make Now

Priority 1:

- Final MVP navigation for Creator vs Manager roles.
- Final Today card content order.
- Final Daily Card completion labels.
- Final copy for offline/no-card/generation failure states.
- Final treatment for unverified audio.

Priority 2:

- Whether Package Detail uses segmented control, sections, or vertical scroll.
- Whether Reference Review shows extracted objects as separate cards or checklist rows.
- How warnings appear in Weekly Plan Review.
- How "Published to Creator" and sync status appear after publish.

Priority 3:

- App name lockup.
- Icon direction.
- Paper/editorial texture level.
- Photo/context visual treatment.

## Deferred Surface Decisions

- Full Watchlist management.
- Benchmark Creator detail.
- Pattern library.
- Trend cluster detail.
- Learning Summary presentation.
- Collab Lead pipeline.
- Performance data presentation.
- Scout-only experience.
- Provider/API setup screens.

## What's Working

- The product has a strong emotional surface direction: prepared personal brief, not content dashboard.
- The Today surface has a clear primary job and should be the first screen Creator sees.
- The conceptual vocabulary now prevents source-intelligence objects from being masked.
- The breadboards already protect important surface feedback: no silent overwrites, no blank offline Today, no changing completed days, no unconfirmed source material.
- The MVP can be screenshot-worthy without needing the full V2 intelligence system.

## Next Step

Before implementation, translate this surface inventory into a concrete first-build screen spec and visual direction. The strongest next practical skill is `imagegen-frontend-mobile` or `build-ios-apps:swiftui-ui-patterns`, depending on whether you want visual concepts first or to scaffold the SwiftUI app first.

The surface is the layer users encounter. Everything decided below either gets honoured here or undermined here. Revisit this skill after any significant change to the conceptual model or interaction structure.

