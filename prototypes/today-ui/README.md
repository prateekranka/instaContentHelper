# PROTOTYPE — Pocket Sheet shell

Throwaway. **Do not ship.**

Chosen direction: **Pocket Sheet** (monochrome) across the Creator shell.

## Screens

| Tab | What's prototyped |
| --- | --- |
| Today | Pocket Sheet shoot list + inline execution package (caption, VO script, deep BG audio), empty CTAs → Plan, mark posted → Archive under You, easier-ideas sheet |
| Plan (center) | Selected-day hub + execution package preview, calendar sheet, inline 5-idea generate + optional steer, Approve/Regenerate, **Content categories** (editable toggle chips, 1–3), Voice + References (soft gate; voice deferred after onboarding; unlimited refs), generated-days list when ≥1 day has content |
| You | Account row → compact Apple sheet (health only); Archive section → flat chronological list; Sign out on page |
| First-run | 3-screen onboarding: categories → refs (reel+profile min) → confirm + Generate; soft skip resumes next launch |

## Run

```bash
open "prototypes/today-ui/index.html?empty=1"
# First-run onboarding: ?first=1 (or ?empty=1&first=1)
# Resume test: soft-skip during onboarding, reload without ?first=1
# Plan hub empty: ?tab=plan&nocontent=1
# Plan hub: ?tab=plan
# You + Archive: ?tab=you or ?tab=archive (legacy alias)
# Ready Today (default): prototypes/today-ui/index.html
# Audio previews: play BG on Today or Plan; Swap opens ranked alternatives
# Tabs: ?tab=today|plan|you · keys 1/2/3 · E empty · F first-run
```

## Preview URLs

| State | URL |
| --- | --- |
| Ready Today | `prototypes/today-ui/index.html` |
| Empty Today | `prototypes/today-ui/index.html?empty=1` |
| First-run onboarding | `prototypes/today-ui/index.html?first=1` |
| Onboarding step 2 (refs) | `prototypes/today-ui/index.html?first=1` — pick categories, continue |
| Post-onboarding Plan | Complete onboarding → lands on Plan (Generate, not auto-daygen) |
| Plan empty (no generated days) | `prototypes/today-ui/index.html?tab=plan&nocontent=1` |
| Plan hub | `prototypes/today-ui/index.html?tab=plan` |
| References | Unlimited confirmed references; add/import never opens a paywall |
| Needs review + dedup | `?tab=plan` — expand References; paste duplicate URL for preview sheet |
| You + account sheet | `prototypes/today-ui/index.html?tab=you` — tap Account row |
| Archive (under You) | `prototypes/today-ui/index.html?tab=archive` |
