# Creator-only shell: Today · Archive · Profile

Status: ready-for-agent
Blocked by: 01

Parent: [spec.md](../spec.md) · seam **Creator shell**

## What to build

Once signed in, the Creator always lands in a Creator-only shell. Root tabs are **Today · Archive · Profile** (that order). There is no Manager/Admin mode switch in the primary experience. **Archive** is a peer tab of past Decisions. **Profile** shows Apple account identity, sign out, one entry into **Plan**, and light Supabase / Gemini status — not Creator Profile editing, not References, not nested Archive, not Manager tools. Generation and prep entry are available to Creator without an owner/editor role gate. Shoot Folio structure is left alone; this ticket owns shell composition and Profile/Archive placement.

## Acceptance criteria

- [ ] Live app uses tabs Today · Archive · Profile in that order; no Manager/Admin mode as a primary product path.
- [ ] Opening the app after sign-in lands on Today as the daily job surface.
- [ ] Archive tab lists past Decisions (filters remain useful for “today” / history).
- [ ] Profile shows Apple identity, sign out, one Plan entry, and light Supabase + Gemini status.
- [ ] Profile does not host Creator Profile editor, References, nested Archive, or Manager tools.
- [ ] Creator can reach Plan/generate capabilities without an owner/editor role gate.
- [ ] UI-level coverage (or equivalent shell/navigation tests) locks tab order and Profile destinations; auth identity on Profile reflects the Apple session from ticket 01.

## Blocked by

- [Sign in with Apple activation](01-sign-in-with-apple-activation.md)

## Comments
