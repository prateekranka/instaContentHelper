# Mira implementation plan and single-agent handoff

## Launch contract

- Requested implementation model: GPT-6.1 Sol (`gpt-6.1-sol`).
- Requested reasoning effort: `xhigh`.
- Work as one agent. Do not spawn subagents or delegate implementation.
- Repository: https://github.com/prateekranka/instaContentHelper
- Worktree: `/workspace/mira-ios-mvp`.
- Branch: `codex/mira-ios-mvp`.
- Base commit: `1580a82` (existing creator app and design handover).
- The user now requests implementation in a new thread with this complete plan.
- First deliverable after environment inspection: a public workflow tracker.
- Do not publish to TestFlight or submit to the App Store as an incidental build step.

This document consolidates the agreed app implementation plan and tracker addendum. No app implementation or tracker deployment was performed while preparing this handoff.

### Existing repository reconciliation

The repository already contains a SwiftUI app (`CreatorContentOS`), Supabase backend, tests, and previous design work. Read the README, applicable AGENTS.md instructions, `docs/project-state-2026-10-18.md`, and `docs/claude-handover.md` first. Read global instructions at `/workspace/.agent-instructions/de88d12fa8c7/AGENTS.md` when available. Resolve its relative references from that directory.

The latest user scope and design decisions in this document supersede older product directions. Inspect and reuse existing code where appropriate. Do not blindly scaffold over the existing app, replace its backend, downgrade its current iOS 26 deployment target, or delete earlier work. The greenfield choices below are proposed defaults; document necessary adaptations to the existing repository. Use the requested Linux Apple toolchain with an adapter for the existing Xcode project where feasible. Keep all changes inside this worktree.

## 1. Implementation instructions

Implement Mira, a native iPhone app that helps creators decide what to post, write it in their own voice, and prepare to film independently. Complete milestones sequentially. Build and check meaningful increments.

Use https://github.com/joshuaswarren/omarchy-apple-dev for the Apple development toolchain. Build the app with native SwiftUI.

First release:

- #5 Quick ideas: “What should I post today?”
- #8 Ideas and scripts: hooks, spoken scripts, and captions in the creator’s voice.
- #9 Detailed storyboard: clear instructions for filming each shot independently.

Primary example user: Mamta, an older creator interested in training after 60, healthy Indian eating, and mindset. Her age informs accessibility and her own positioning. Do not patronise her or make every idea mention age.

The implementing model and runtime AI model are separate decisions. Do not assume “GPT-6.1 Sol xhigh” is a runtime API model identifier.

## 2. Product scope and completion boundary

Core promise: “Tell Mira what you have time for. Get an idea that feels like you, words you can comfortably say, and a plan you can film yourself.”

Complete journey:

1. Mamta opens Mira.
2. She says: “Aaj 15 minutes hain. Ghar pe kuch simple shoot karna hai.”
3. Mira shows three distinct ideas suited to filming at home within her available time.
4. She chooses one.
5. Mira drafts a hook, script, and caption.
6. She says: “Less motivational. Make it sound more like me.”
7. She reviews the revision and chooses Make shot list.
8. Mira produces a feasible filming plan.
9. She checks off shots while filming outside the app.
10. She closes Mira and resumes at the same place later.

Start with short vertical Reels: talking to camera, voiceover with supporting footage, or a simple combination.

Include a lightweight creator profile, saved projects, voice input, and optional pasted brand requirements. Exclude Instagram connection, performance analytics, trend discovery, calendars, reminders, video upload/editing, publishing, brand messaging, payments, and deal tracking. Do not add inactive tabs or placeholder controls for them.

End at a ready-to-film plan and filming progress, not a finished or published Reel.

## 3. Toolchain and environment

Use omarchy-apple-dev full mode. It extracts the Apple SDK from an Xcode archive. Experimental no-xcode mode lacks the SwiftUI support required here, including documented NavigationStack and binding limitations.

Read:

- https://github.com/joshuaswarren/omarchy-apple-dev/blob/main/README.md
- https://github.com/joshuaswarren/omarchy-apple-dev/blob/main/GETTING-STARTED.md
- https://github.com/joshuaswarren/omarchy-apple-dev/blob/main/docs/DISTROS.md

Sequence:

1. Inspect workspace, source, instructions, host distribution, CPU, disk, Swift, and device access.
2. Clone tooling separately from app source. Pin a specific commit and record versions.
3. Follow full-mode installation for the actual host. Use the documented user-only route when appropriate.
4. Obtain the matching Xcode archive through the user’s Apple account if unavailable. Never bypass authentication.
5. Confirm `swift sdk list` includes `darwin`.
6. For a new project use `xtool new Mira`; for this existing project inspect `tools/xcodeproj2xtool.py` and use an adapter without overwriting source.
7. Build with `xtool dev build`.
8. Install and launch a minimal/native increment on an iPhone using the documented `device-run.sh` workflow.

Original greenfield proposal: iOS 17 minimum with newer APIs gated. This repository currently targets iOS 26; preserve it initially and evaluate any broader compatibility separately.

At planning time the toolchain documented Swift 6.4.x/Xcode 27 combinations. Recent changes were not all verified through the entire device-debug loop. Establish a working combination early and pin it.

Linux compilation does not prove UI or device correctness. Do not claim iOS Simulator, Xcode previews, or XCTest UI execution on Linux. Use real-device verification. A separately available Mac can supplement testing.

If SDK or device access is blocked, continue independent domain/backend/tracker work. Record precise unverified checks.

## 4. Visual direction

Mira should feel like a carefully typeset creative notebook: warm, quiet, useful, and legible.

| Element | Direction |
|---|---|
| Light background | Warm off-white, approximately #F7F5EF |
| Text | Deep charcoal, approximately #242724 |
| Accent | Muted dark olive, approximately #465643 |
| Secondary surfaces | Subtle tonal separation and purposeful borders |
| Typography | System text; restrained system serif for large editorial headings |
| Body size | About 18 pt at default Dynamic Type |
| Spacing | Consistent 8-point rhythm with generous section spacing |
| Controls | Native behaviour and clear labels; primary controls about 52 pt tall |
| Icons | Purposeful SF Symbols; text labels where needed |
| Animation | Brief state transitions; honour Reduce Motion |

Verify contrast in light/dark and increased contrast. Provide a real dark palette, not mechanical inversion. For Hindi and mixed scripts, prefer reliable glyphs and legibility over serif styling.

Use typography and spacing for hierarchy. Cards must group meaningful objects. Avoid nested cards, decorative gradients/glass, glowing borders, sparkle icons, AI avatars, floating orbs, excessive shadows, animated typing theatrics, and pills for every option. Native system surfaces may use their native styling.

No invented engagement scores, viral potential, unsupported trend labels, or “Unlock your creativity” copy. No filler stock/generated imagery. Keep text alongside any storyboard diagram.

Acceptance: the app remains recognisable and polished without decorative illustrations.

## 5. Navigation and screens

Two native tabs: Today and Projects. Profile opens from a labelled toolbar control. Each tab owns its navigation stack. A project contains idea, script, storyboard, and progress.

### Today

Short greeting; prominent “What should I post today?” action; most relevant unfinished project and its next action; restrained Ask Mira entry with microphone/text.

Example: “Your breakfast Reel — Script ready · Next: make your shot list — Continue”. No fabricated metrics or dashboard grid.

### Quick-idea input

Voice/text first. Optional constraints:

- Time to prepare and film: 10, 20, 45 minutes, or custom.
- Location: home, gym, outside, or custom.
- Style: talking, voiceover, or either.

Use saved preferences. Natural language can populate constraints, but display them for correction. Distinguish filming time from final Reel duration. Ask one concise follow-up when essential; otherwise expose editable assumptions.

### Idea results

Three genuinely distinct concepts in a vertical list; modest emphasis on the recommendation. Each includes title, hook, what viewers see, why it fits, filming-time estimate, and setup.

Example: “What I eat after training — Show one breakfast you actually make, and explain why it works for your routine. About 15 minutes · Kitchen · Three simple shots.”

Use this idea, Adjust, and More ideas must work. Preserve saved ideas when requesting alternatives.

### Script

Editable document: hook, spoken script, caption, estimated runtime, language. Separate spoken words from production instructions. Contextual revisions: Shorter, More conversational, Change language, and freeform voice/text.

Make shot list confirms the current script revision as storyboard input.

### Shot list

Overview: final duration estimate, shot count, locations/props, separate voiceover needs. Numbered readable rows with expandable details.

Each shot includes purpose; target edited duration; suggested recording duration; framing/phone placement; action; spoken words or voiceover; on-screen text; and a simpler alternative when useful.

Start filming opens focused shooting mode.

### Shooting

One shot at a time, large text, Mark filmed, Previous/Next, Make this easier, and clear progress. “Filmed” is user-reported, not proof that Mira captured or analysed media.

### Projects

Drafts/plans and next actions. Rename, archive, delete, resume. Every visible control works.

## 6. Creator profile and personalisation

Short, skippable supporting setup: name, themes, audience, preferred English/Hindi/Hinglish, Devanagari/Romanised preference, tone and things they would not say, solo filming preference, optional real captions/spoken samples.

Mamta is an explicitly selected demo fixture, not seeded personal data for every installation. Do not claim Instagram analysis.

Corrections apply to the project by default. Offer to remember reusable preferences, e.g. “Remember ‘less motivational, more everyday’ for future scripts?” Persist only after acceptance.

Keep Hinglish natural. Do not mechanically alternate languages or translate every English phrase.

## 7. Optional brand requirements

Secondary Add brand requirements action in creation/settings. Pasted text and manual editing only. Defer PDFs, OCR, WhatsApp forwarding, and email integrations.

Extract proposed brand/product, required mentions/visuals, duration, tags/disclosures supplied in the brief, code if supplied, prohibited content, deadline if supplied, and unresolved questions. Preserve original text and source excerpts. Creator confirms before generation uses it.

Never invent missing codes, deadlines, benefits, or approval. Map requirements to planned passages/shots. Say Included in the plan, not Brief passed. Finished-video checking is outside scope.

Explain conflicts with filming constraints and offer choices instead of silently removing requirements.

## 8. State, revisions, persistence

User stages: Choosing an idea → Writing the script → Planning shots → Ready to film → Filming → Filming complete.

Generation states separately: Idle, Working, Failed, Cancelled.

Persist profile; constraints/input; ideas/selection; script revisions/approval; storyboard revisions/source script revision; brand requirements; filming progress; last meaningful position; pending job IDs.

Rules:

- Manual edits autosave. AI revisions remain proposals until applied. Preserve undo.
- Script or requirement edits mark existing storyboards out of date without deleting them.
- Offer Update shot list. Never overwrite newer edits with late responses.
- Preserve filmed status only for unchanged shots. Flag changed shots for review.

Greenfield persistence: versioned Codable documents in Application Support behind a repository abstraction. Implement atomic writes, serialised access, migrations, corrupt-document recovery, immediate important-transition saves, and briefly debounced typing. Reuse suitable existing persistence instead of replacing it gratuitously.

Read/edit existing work offline. New generation needs connectivity.

## 9. Native architecture

SwiftUI, Swift concurrency, Observation @Observable, typed NavigationStack routes, explicit dependency injection, URLSession, and native text share sheets. Domain logic must remain independent of SwiftUI/Apple-only frameworks for Linux tests.

Suggested feature boundaries (adapt to existing repository):

```
MiraApp/
  App/
  DesignSystem/
  Features/{Today,Ideas,Script,Storyboard,Shooting,Projects,Profile}/
  Services/{Networking,Persistence,Speech}/
  Resources/
MiraCore/{Models,Workflow,Validation}/
Tests/MiraCoreTests/
server/src/{routes,generation,schemas,jobs}/
server/tests/
fixtures/
docs/
```

Abstractions: ProjectRepository, GenerationService, SpeechInputService, CreatorProfileRepository. Provide deterministic fixtures plus real implementations. Global dependencies at root, transient state local. Avoid view models for every component and business logic in view bodies.

Use Bundle.module for SwiftPM resources appropriately. Check development and shipping resource layouts.

## 10. AI backend and contracts

Greenfield: small TypeScript Fastify/Zod backend. Existing equivalent infrastructure takes precedence after inspection; this repository has Supabase Edge Functions and migrations. Keep provider credentials server-side.

Operations:

| Operation | Input | Output |
|---|---|---|
| Generate ideas | Profile, constraints, optional requirements, recent summaries | Three distinct ideas |
| Generate script | Selected idea, profile, constraints, requirements | Hook, spoken text, caption, duration estimate |
| Generate storyboard | Approved script revision, constraints, requirements | Ordered shots and mappings |
| Revise artifact | Artifact, requested change, source revision | Proposed replacement |
| Extract requirements | Pasted brief | Checklist, excerpts, unresolved fields |

Use schema-constrained responses where supported. Validate server-side. Treat briefs, samples, and transcripts as data, not instructions overriding application behaviour.

Respect time/location/equipment/solo constraints. Do not invent history, metrics, trends, testimonials, or product claims. Avoid repetitive motivational hooks and age-centred assumptions. Keep scripts speakable, captions concise, and selected language/script consistent. Durations must be positive, plausible, and fit the target. Speech must plausibly fit. Label estimates. Give concrete phone placement. Report unresolved conflicts.

No agent framework, multi-agent runtime, vector database, or autonomous tools are needed.

### Job lifecycle

Create durable jobs with idempotency keys/input revisions. Return IDs, allow status/result fetch and cancellation, and reconcile after app relaunch. A single-instance SQLite store suffices for a new service; reuse suitable existing durable infrastructure. Define interrupted-worker recovery.

Bound transient retries. Avoid repeat charges after lost connectivity; do not promise exactly-once provider execution without support. Apply results only to matching input revisions; otherwise keep a recoverable proposal.

For a private pilot use individually provisioned, revocable device credentials in Keychain, ownership checks, and rate limiting, or existing equivalent authentication. No embedded shared secret. Public account/recovery design is a separate decision.

Select an available runtime model by quality, latency, multilingual behaviour, and cost. Keep it configurable. Follow current credential/consent instructions; never print secrets.

## 11. Voice

Tap microphone → unmistakable recording state/timer → stop → editable transcript → submit through typed-input workflow. Ask permissions at point of use.

Evaluate real-device Apple Hindi/English recognition. Do not assume one locale accurately recognises Hinglish. Use a backend transcription implementation behind the same interface where needed. Explain when audio leaves the device.

Handle denial, unavailable recognition, silence, incoming-call/audio interruptions, backgrounding, lost connectivity, empty/failed transcripts. Bound recording (e.g. 60 seconds). Always offer text. Delete temporary audio after transcription/cancellation; no default raw-audio retention.

Defer full-duplex voice, wake words, background listening, synthetic replies.

## 12. Contextual Ask Mira

Today: “Give me an idea I can shoot in the kitchen.” Script: “Make this shorter and less formal.” Shot: “I don’t have a tripod.” Storyboard: “Can I do all of this at home?”

Use a focused sheet with project context, input, and proposed change. Do not replace navigation with general chat. Typed intents: generate ideas, revise script, revise shot, revise storyboard, explain plan. Validate targets/revisions server-side.

Show proposal and Apply before replacement. Provide undo. Explain out-of-scope requests briefly without losing the task.

## 13. Quality and testing

Deterministic state/persistence/contract/error tests; separate generative-content rubric rather than exact-string assertions. Follow repository testing gates for supported UI/flow targets.

Automate workflow transitions; save/reload/migration; corrupt recovery; stale storyboard marking; late responses; retries/cancellation/duplicate submission/interrupted jobs; malformed AI output; missing codes; valid mappings; invalid durations/contradictions; auth and ownership.

Content scenarios:

| Scenario | Expected |
|---|---|
| Ten minutes at home alone | Minimal feasible setup |
| Hindi input, explicit English output preference | Honour output preference |
| Hinglish, less motivational | Natural conversational revision |
| No tripod | Stable realistic alternative |
| Cannot film in gym | Coherent revised locations/concept |
| Required code missing | Flag gap |
| Unsupported brand health claim | Flag for correction, invent no evidence |
| Sparse profile | Useful output with explicit assumptions |
| Script changed after two filmed shots | Preserve history, identify affected shots |

Device checks: small screen; large Dynamic Type; VoiceOver order/labels; light/dark; Reduce Motion; Hindi/Romanised Hinglish; keyboard/microphone; long content; relaunch during edits/generation; offline reopen; quiet-room and ordinary-noise speech.

Capture real screenshots of Today, ideas, script, shot list, shooting. Inspect clipping, hierarchy, contrast, bottom controls, density. Never call compilation runtime proof.

When Mamta is available, run a usability session: can she choose, revise, and explain filming the first shot without coaching? Record as human validation, not simulated success.

## 14. Sequential milestones (updated to include tracker)

1. Inspect environment and existing repository.
2. Deploy public tracker and update CLI. Seed actual tasks. This is the first deliverable, before substantial iOS work. Proceed independently if native setup is blocked.
3. Prove toolchain: pin SDK/tooling, compile native increment, install/launch or record exact blocker.
4. Foundation: design tokens/navigation/models/persistence/fixtures. Projects survive relaunch.
5. Complete deterministic ideas → script → storyboard → filming journey.
6. Live generation: contracts, durable jobs, real inputs, no lost edits.
7. Revisions: contextual requests, Apply, undo, stale artifacts/history.
8. Voice/language: permissions/transcript review/multilingual device checks.
9. Optional briefs: paste/extract/confirm/map; gaps remain visible.
10. Device refinement: accessibility/screenshots/offline/errors/layout.
11. Handoff: repeatable build instructions, test evidence, configuration, limitations.

Build after meaningful native edits. Fix compiler errors before proceeding. Keep deterministic fixtures for testing; never silently return fixtures after live generation fails. Do not incidentally distribute to TestFlight/App Store.

## 15. Definition of done

- Practical ideas from short voice/text requests.
- Script edits respect creator language/preferences.
- Understandable, independently shootable storyboards.
- Revisions preserve work and dependencies.
- Relaunch resumes work.
- Brief context affects plans without invented details.
- Existing content works offline.
- Loading/failure/cancel/retry states work.
- Restrained, legible real-iPhone interface.
- Real generation works; fixtures are explicit.
- Build/device evidence and unverified checks reported separately.
- Public tracker accurately shows status. Completed code tasks link pushed commits and verification; unfinished tasks remain visible.

Handoff includes source, pinned tooling, setup, tests, real-device screenshots, limitations, and public tracker URL.

## 16. Public implementation tracker

Build and deploy a small web workflow tracker so the user’s brother can inspect progress without development-environment access. Stable public HTTPS URL, no login to view. Authenticated editing only.

Exactly three columns: Planned, Working, Done. Answer what is planned, active, finished, and which code proves it. No fictional progress, completion percentages, or hashes.

### Design

Mira’s warm background, readable typography, quiet borders/status labels. Desktop: side-by-side columns. Mobile: labelled column selector with counts and one column at a time; no forced horizontal card reading.

Header: “Mira — Build progress”, current focus sentence, last project activity, refresh/connection state. Refresh about every 30 seconds. Keep the last successful view during failures and label stale data. Distinguish last fetched from last project activity.

### Cards

Stable ID (MIRA-012), concrete outcome title, plain description, status, milestone, acceptance criteria, created/started/updated/completed timestamps, relevant pushed commits, verification result, optional blocker/next action.

Compact cards open full details with criteria, notes, links, and activity history. Store UTC ISO 8601; display local timezone with visible timezone and exact times alongside relative wording.

### Status rules

- Planned: not started.
- Working: implementation/integration/required verification underway.
- Done: acceptance criteria passed and evidence recorded.
- Normally one Working task for the single agent. Explain exceptions for blocked or externally waiting tasks.
- Blocked stays in its current column with a visible label/reason/next step. No fourth column.
- Reopen Done tasks to Working when necessary, preserving completion history.
- Never mark device testing done based on compilation.

### GitHub evidence

For completed code tasks: create focused commit → push to configured GitHub repository → attach full real commit URL → record verification → mark Done.

URL format: `https://github.com/<owner>/<repository>/commit/<full-sha>`.

Allow multiple and follow-up commits. Link pushed branch commits before merge. A push alone does not mean done. Never link local-only or invented hashes. Label private repository links; brother needs repository permission to inspect them. Board descriptions remain understandable without code access.

Non-code tasks attach evidence such as build results or a committed verification note.

### Tracker architecture

Small responsive web frontend, TypeScript/Fastify, durable SQLite. Deploy as a separate service so app backend changes do not interrupt it. If existing hosting requires equivalent durable storage, document adaptation rather than using ephemeral files.

- Public board/detail reads, authenticated writes.
- Agent CLI to create/update tasks, attach commits, record verification.
- Transactional task/activity writes and idempotent mutations.
- Server-generated timestamps, persistent storage, backup/restore documentation.
- Health endpoint and deployment-restart checks.
- Public host supporting durable storage; no temporary tunnel or ephemeral preview as permanent URL.
- Credentials in environment secret storage, never public frontend or Git.
- Publish only safe project information. Exclude secrets, raw private briefs, recordings, device IDs, sensitive logs.

### Agent operating procedure

Before a task, move it to Working and record intended outcome. After meaningful progress, update notes and attach pushed commits. Before Done, verify criteria and record results. Record blockers and next steps immediately. At session end, reconcile board and repository.

No separate tracker agent. On failed updates, retain pending mutations locally and retry. Do not claim the public board is current until writes succeed.

### Initial tasks

- Toolchain and native build proof.
- Tracker deployment and update CLI.
- Visual tokens/navigation.
- Models/persistence.
- Quick-idea input/results.
- Editable scripts.
- Detailed storyboards.
- Shooting checklist/resume.
- AI backend/contracts.
- Durable generation/recovery.
- Contextual revisions/undo.
- Voice/multilingual behaviour.
- Optional pasted brief requirements.
- Accessibility/physical-device validation.
- Final build documentation/handoff.

Split independently verifiable outcomes. Avoid one giant “Build the app” card. Seed honest statuses reflecting work already performed.

### Tracker acceptance

- Public HTTPS works from another device without login.
- Three columns/task details work.
- Unauthenticated writes rejected; authenticated changes appear after refresh.
- Accurate timestamps/history and real pushed commit links.
- Data survives redeploy/restart.
- Failed refresh shows stale-data state.
- Readable mobile/desktop layouts.

Deploy immediately after initial inspection, before substantial iOS work. Use the board to expose toolchain blockers. Final handoff includes the URL and accurate final state.
