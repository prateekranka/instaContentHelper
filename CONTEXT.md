# ContentHelper

Creator-only Instagram daily content OS: prepared day cards for shooting and posting, with prep tools buried under Plan.

## Language

**Creator**:
The only targeted user of the app. The person who opens ContentHelper daily to get Instagram content ready.
_Avoid_: Manager, admin, operator, dual-role user

**Today**:
The primary surface showing the day card currently available for the Creator to shoot, or an empty state with one action into Plan.
_Avoid_: feed, home dashboard, calendar

**Shoot Folio**:
The package for today’s card — Scenes, Script, Caption, Audio — with copy and shot/posted actions.
_Avoid_: brief, storyboard editor, post composer

**Other ideas**:
Backup choices when the Creator will not shoot today’s primary card (e.g. short story, caption-only, save, skip).
_Avoid_: regenerate, AI chat, trend inbox

**Plan**:
The buried prep hub for day-at-a-time generation, light edit, making a card available on Today, Creator Profile settings, and References.
_Avoid_: Manager mode, Admin shell, Weekly Control

**Available on Today**:
The per-day action that turns the selected date’s draft into that date’s **ready package**. Does not require a full week. On success, navigates to Today when that date is local today.
_Avoid_: publish week, soft-lock, weekly publish ceremony

**Draft**:
A generated day card in Plan that is not a ready package (calendar yellow). Regenerating a draft overwrites it. Regenerating a ready package (or after a Decision) requires warn + explicit Overwrite, then yields a new draft.
_Avoid_: published (for yellow state), soft-locked

**Ready package**:
The day card available for the Creator loop for that date (calendar green). Today shows it only on the device’s local calendar date. Light edits keep it ready; Unpublish returns it to draft.
_Avoid_: published week, locked card, soft-locked

**Unpublish**:
Explicit Plan action that demotes a ready package to draft (with confirmation). Allowed after a Decision: clears the live Decision, keeps Archive history.
_Avoid_: unlock week, soft-unlock

**Creator Profile**:
Voice, pillars, caption style, and related generation settings for the Creator — edited under Plan, not a primary daily tab.
_Avoid_: account settings, Manager profile admin as a role

**References**:
Intelligence, import, and related source material used in prep — lives under Plan, not in the primary UI.
_Avoid_: Trend Inbox as a primary tab, Manager References mode

**Decision**:
The Creator’s recorded outcome for a day (e.g. posted, shot, backup, skipped), kept in Archive.
_Avoid_: analytics event, engagement metric

**Sign in with Apple**:
The only sign-in front door. After Apple Auth succeeds, the app still runs Auth session → exchange → device token. First sign-in auto-provisions a Creator; there is no allowlist gate.
_Avoid_: email OTP, approved tester email, pairing code as sign-in

**Archive**:
The Creator’s history of day decisions; a primary tab in the shell (order: Today · Archive · Profile), not nested under Profile.
_Avoid_: Profile subsection, analytics timeline

**Profile**:
Account tab for identity, sign out, one entry into Plan, and light Supabase/Gemini status — not prep editing.
_Avoid_: Manager tools, nested Archive, Creator Profile editor on this tab
