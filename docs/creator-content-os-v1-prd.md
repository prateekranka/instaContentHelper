# Creator Content OS iPhone App V1 PRD

## Problem Statement

Creator needs a simple daily creative routine for Instagram content. The current system lives across ChatGPT, a custom GPT, screenshots, trend links, notes, and manual coordination by Manager. That works while Manager is operating the system, but it is too scattered for Creator to use independently each morning.

The app should turn a weekly setup pass by Manager into one clear daily content card for Creator. Creator should open the app, see the best reel idea for today, decide whether she can shoot it, and get the shot list, script, caption, and audio notes without needing to prompt, research, or manage a content calendar.

## Product Direction

Working product: Creator Content OS for iPhone.

V1 is bespoke for Creator. The data model should support multiple workspaces and creators later, but the interface should expose only Creator for now.

The app is a native SwiftUI iPhone-only app with a small Supabase backend for shared data, storage, sync, and AI calls. Creator's phone should cache the current week locally so daily viewing and copying works offline. Generation, uploads, trend analysis, and sync require network.

Visual direction: premium editorial fitness journal, not SaaS dashboard. The app should feel calm, personal, prepared, and screenshot-worthy.

## Product Principles

- Shootability wins over trend potential.
- Creator should not have to manage a content system.
- Daily Mode is the home screen; Setup Mode is hidden behind settings.
- AI stays behind structured buttons, not a primary chat interface.
- Weekly plans are pre-generated and soft-locked.
- Skipped days should still produce a small useful action.
- Every primary screen should be attractive enough to share, but daily usefulness comes first.

## Core Users

### Creator

Primary daily user. Opens the app from an 8 AM notification, reviews today's card, decides whether she can shoot it, copies content, gives lightweight feedback, and marks the day state.

Default UI should not expose strategy maintenance. Advanced setup editing can be available through settings if she needs it.

### Manager

Initial operator/admin. Maintains the creator profile, performs weekly setup, adds trend screenshots and links, reviews generated weekly plans, edits cards, and publishes the week to Creator.

### Future Users

The data model should allow future editors, helpers, coaches, or additional creators through workspaces, users, roles, and paired devices. V1 UI does not need generic onboarding.

## V1 Scope

### Screens

1. Today
2. Weekly Plan
3. Trend Inbox
4. Creator Profile
5. Archive

### Today Screen

One beautiful daily card:

- Hero idea title
- One-line "why today"
- Shootability: easy, medium, hard
- Estimated shoot time
- Primary action: Can shoot today
- Secondary action: Need easier option
- Package tabs: Shot List, Script, Caption, Audio
- Footer actions: Mark shot, Mark posted, Feedback
- AI fallback buttons: Make easier, Shorter caption, More Hinglish, New audio/trend version

Fallback buttons create an alternative first. The user must choose "Use this" before the current card changes.

### Weekly Plan

Manager performs a 10-minute setup pass and generates a 7-day plan:

- This week's location
- Workout and race schedule
- Family/travel moments
- Brand/collab obligations
- 5-10 trend/audio options
- No-go topics
- Key moments
- Optional photos/context visuals

The weekly generator produces:

- 7 primary daily cards
- 1 easy backup per day
- An idea bank underneath

Flow:

1. Generate week
2. Review 7 draft days
3. Edit any card
4. Publish to Creator

Published days are soft-locked. They change only when Creator chooses an easier option, Manager adds a strong trend, the schedule changes, a brand obligation appears, or an admin manually regenerates.

### Trend Inbox

No Instagram scraping in v1.

Trend intake supports:

- Upload screenshot of trending audio
- Paste reel/audio links
- Optional note from Manager
- Tags: funny, emotional, training, travel, collab
- Suggested use: use now, adapt this week, save for later

AI analyzes uploaded screenshots and links, then asks for confirmation before saving the result into the idea bank.

Trend links open externally in Instagram.

### Creator Profile

The app exports the Creator Content OS custom GPT knowledge into an editable setup profile.

Profile contains:

- Voice rules
- Content pillars
- Preferred hooks
- Caption style
- Things Creator would never say
- Family/race context
- Weekly workout rhythm
- Brand/collab tone
- No-go topics
- Language preferences
- Example scripts
- Recurring reel formats

Voice mode is stored per card:

- English
- Hinglish
- Hindi touch

### Archive

Clean history of decisions and outputs, not analytics.

Each archived day shows:

- Date
- Idea title
- State: posted, shot, backup, skipped, saved
- Caption/script used
- Feedback tags
- Optional final Instagram post link

No likes, views, comments, or performance tracking in v1.

## Completion Model

A completed day means Creator made a decision, not necessarily posted.

Valid completion states:

- Posted
- Shot, not posted yet
- Used backup story
- Saved for tomorrow
- Skipped intentionally

If Creator taps "Not today," the app immediately offers lower-effort options:

- 10-second story
- Caption-only post
- Save this for tomorrow

## Notifications

Use local scheduled notifications on Creator's phone.

Primary notification:

- 8:00 AM
- Specific to the prepared idea
- Example: "Today's reel is ready: Race week has entered the house"

Optional second reminder:

- 5:00 PM if no decision state exists
- Example: "Want the 10-second backup instead?"

No server push in v1 unless local notifications prove insufficient.

## Backend Strategy

Use Supabase for:

- Postgres data
- Storage for trend screenshots and optional context images
- Edge Functions for AI calls and secure API keys
- Shared sync between Manager's phone and Creator's phone

Avoid full email/password auth in v1. Use workspace/device pairing.

### Pairing Model

Conceptual objects:

- Workspace
- Creator
- User
- Role
- Device
- Invite

Roles:

- owner
- editor
- creator

First-launch flow:

1. User enters invite/pairing code.
2. Backend validates code, expiry, role, and max uses.
3. Device is registered under a user and workspace.
4. App stores device token and role in Keychain.
5. Future requests include the device token.

For v1, clients should use Edge Functions as an API facade instead of direct unrestricted database writes. Edge Functions validate device tokens and use server-side credentials for database operations.

## Supabase Schema Shape

All primary content tables include `workspace_id`, and creator-specific content includes `creator_id`.

### workspaces

- id
- name
- created_at

### creators

- id
- workspace_id
- display_name
- active_profile_id
- created_at

### users

- id
- workspace_id
- display_name
- role
- created_at

### devices

- id
- workspace_id
- user_id
- device_name
- role
- token_hash
- revoked_at
- last_seen_at
- created_at

### invites

- id
- workspace_id
- role
- code_hash
- expires_at
- max_uses
- used_count
- revoked_at
- created_at

### creator_profiles

- id
- workspace_id
- creator_id
- version
- voice_rules
- content_pillars
- caption_style
- preferred_hooks
- no_go_topics
- family_context
- race_context
- weekly_routine
- brand_tone
- language_preferences
- example_scripts
- recurring_formats
- created_at
- updated_at

### key_moments

- id
- workspace_id
- creator_id
- name
- date
- location
- kind: race, travel, family, collab, festival, other
- content_angle_notes
- created_at

### brand_items

- id
- workspace_id
- creator_id
- brand_name
- kind: obligation, lead
- deliverable
- due_date
- must_mention
- must_avoid
- tone
- reference_url
- status
- notes
- created_at
- updated_at

### weekly_plans

- id
- workspace_id
- creator_id
- week_start_date
- status: draft, published, archived
- setup_context
- published_at
- created_by_user_id
- created_at
- updated_at

### daily_cards

- id
- workspace_id
- creator_id
- weekly_plan_id
- date
- status: draft, published, completed
- title
- why_today
- shootability
- estimated_shoot_time_minutes
- language_mode
- shot_list
- voiceover_script
- caption
- on_screen_text
- audio_suggestion
- brand_note
- backup_story
- backup_caption_only
- source_trend_id
- completion_state
- completed_at
- created_at
- updated_at

### card_revisions

- id
- workspace_id
- daily_card_id
- revision_kind: ai_draft, admin_edit, creator_edit, alternative, completion_update
- payload
- created_by_user_id
- created_at

### idea_bank_items

- id
- workspace_id
- creator_id
- title
- summary
- tags
- source
- suggested_use
- linked_trend_id
- status: saved, used, dismissed
- created_at
- updated_at

### trend_items

- id
- workspace_id
- creator_id
- screenshot_storage_path
- reel_url
- audio_name
- creator_handle
- extracted_summary
- fit_notes
- tags
- suggested_use
- confirmed_at
- status: pending, confirmed, dismissed
- created_at
- updated_at

### feedback_events

- id
- workspace_id
- creator_id
- daily_card_id
- user_id
- tags
- note
- created_at

Allowed feedback tags:

- Too hard to shoot
- Too long
- Not my voice
- Too generic
- Loved this
- Use more like this

### sync_events

- id
- workspace_id
- entity_type
- entity_id
- operation
- changed_at

## AI Function Contracts

AI responses should be strict structured JSON, validated server-side before being saved.

### generateWeeklyPlan

Input:

- Creator profile
- Weekly setup context
- Key moments
- Brand obligations
- Confirmed trends
- Recent archive feedback
- Existing idea bank

Output:

- Weekly plan metadata
- 7 daily card drafts
- 7 backup ideas
- New idea bank items
- Warnings or assumptions

### analyzeTrend

Input:

- Screenshot image path
- Reel/audio link
- Optional note
- Creator profile summary

Output:

- Audio names detected
- Visible creator handles
- Trend pattern
- Creator fit assessment
- Suggested use: now, this week, later
- Tags
- Confidence and review notes

### createCardAlternative

Input:

- Current card
- Requested transformation: make easier, shorter caption, more Hinglish, new audio/trend version
- Creator profile
- Optional trend item

Output:

- Alternative card payload
- Explanation of what changed

### rewriteCardField

Input:

- Card field
- Rewrite instruction
- Creator profile

Output:

- Replacement field text
- Voice/style notes

## SwiftUI Architecture

Use native SwiftUI, iPhone-only.

Recommended app modules:

- App session and device pairing
- Domain models
- Local SwiftData cache
- Sync service
- Backend API client
- Notification scheduler
- AI action coordinator
- Today feature
- Weekly Plan feature
- Trend Inbox feature
- Creator Profile feature
- Archive feature
- Shared design system

Deep modules to keep testable:

- WeekPlanGeneratorClient: sends structured generation requests and validates responses
- SyncEngine: fetches changes, writes local cache, queues offline decisions
- NotificationScheduler: schedules 8 AM and optional 5 PM local notifications from published cards
- CardStateMachine: enforces draft, published, alternative, completed, archived state transitions
- TrendAnalyzerClient: uploads screenshots, analyzes trends, and requires confirmation before saving

## Local Cache

Use SwiftData for:

- Current workspace
- Current creator
- Published current week
- Daily cards
- Idea bank summaries
- Archive summaries
- Pending offline feedback/completion changes

Offline supported:

- View current week
- View today's card
- Copy script/caption/audio notes
- Mark shoot, not today, posted, skipped, or saved
- Add lightweight feedback

Network required:

- Weekly generation
- Trend upload
- AI alternatives
- Cross-phone sync
- Publishing a week

## Implementation Milestones

### Milestone 1: App Shell and Sample Data

- Create SwiftUI iPhone app
- Implement editorial visual system
- Build Today, Weekly Plan, Trend Inbox, Creator Profile, and Archive shells
- Use local sample JSON for a full week
- Verify Today opens instantly and looks screenshot-worthy

### Milestone 2: Local Domain and Cache

- Add SwiftData models
- Implement card state transitions
- Implement copy actions and feedback tags
- Implement local notifications from sample published cards

### Milestone 3: Supabase Backend

- Create schema
- Add device pairing and invite flow
- Add Edge Function API facade
- Add sync endpoints
- Store and fetch weekly plan data

### Milestone 4: AI Generation

- Implement generateWeeklyPlan
- Validate strict JSON
- Add review/edit/publish flow
- Include recent archive feedback lightly in generation

### Milestone 5: Trend Inbox

- Upload trend screenshots
- Paste trend links
- Analyze with AI
- Confirm before saving to idea bank
- Use confirmed trend in a card alternative

### Milestone 6: End-to-End TestFlight Proof

- Pair Manager device as owner/editor
- Pair Creator device as creator
- Publish one full week
- Verify local notifications
- Verify offline Today access
- Verify completion states and archive sync

## MVP Acceptance Test

For one full week:

- Manager creates and publishes a weekly plan on Sunday.
- Creator receives a specific 8 AM notification daily.
- Creator opens Today in under 3 seconds.
- Creator can decide: shoot, easier, skip, save, or posted.
- Creator can copy script, caption, and audio notes.
- At least 5 of 7 days get a decision state.
- Archive reflects the week accurately.

## Testing Plan

Test external behavior, not implementation details.

Unit tests:

- Card state transitions
- Weekly plan validation
- AI JSON validation
- Notification scheduling rules
- Pairing code state handling
- Offline queue behavior

Integration tests:

- Generate week to draft cards
- Review/edit/publish weekly plan
- Upload/analyze/confirm trend
- Create and accept an alternative card
- Sync completion state from Creator device to Manager device

UI tests:

- First launch pairing
- Today card daily decision flow
- Need easier backup flow
- Weekly setup review/publish flow
- Trend inbox confirmation flow
- Archive history view

Manual proof:

- iPhone light and dark mode screenshots
- Poor network/offline check
- Notification tap opens Today
- Copy buttons work into Instagram or Notes

## Non-Goals For V1

- In-app recording
- In-app video editing
- Instagram scraping
- Instagram analytics
- Likes/views/comments tracking
- Widgets
- Web admin
- iPad support
- Public creator onboarding
- Generic SaaS dashboard
- Primary chat interface
- Brand outreach message generation
- Full email/password authentication
- Server push notifications

## Open Decisions

- Final app name and icon direction
- Whether to start with a real Supabase project immediately or mock API first
- Whether AI functions use OpenAI Responses API directly from Supabase Edge Functions
- Whether Manager and Creator share one TestFlight build configuration or use an internal debug flag for admin tools
- Exact notification time zone behavior when Creator travels

