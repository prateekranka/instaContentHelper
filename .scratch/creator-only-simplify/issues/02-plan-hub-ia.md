# Plan hub information architecture

Type: grilling
Status: resolved
Blocked by: 01

## Question

How is the buried Plan hub structured so day-at-a-time prep (brief → generate → light edit → available on Today), Creator Profile settings, and References / intelligence / import coexist in one hub without becoming a second primary mode?

Depends on [Primary shell without Manager mode](01-primary-shell.md) for how Plan is entered (Profile, empty-Today CTA, Today `⋯`).

**Constraints from shell decision:**
- Plan is one hub reached from those three entries — not a tab and not a mode switch
- Daily generation prompt text box is first
- Creator Profile editor and References are **collapsible accordion sections below** that prompt
- Detail what else sits on the Plan screen (date, generate, edit, available-on-Today control, import entry points inside References accordion, etc.)

## Answer

**Single Plan hub** (not a tab/mode). Vertical order:

1. Title **Plan**
2. **Calendar date control** + **legend** (replaces Today/Tomorrow chips + picker)
3. **Daily generation prompt** (brief text box)
4. **Generate** (primary action)
5. **Result / light edit** for the selected date’s card (inline on Plan; not a Weekly day screen)
6. **Available on Today** control (makes the ready package for that date)
7. Accordion **Creator Profile** (default **collapsed**) — existing profile fields relocated, not redesigned
8. Accordion **References** (default **collapsed**) — existing Intelligence home surfaces (Import, Needs your call, growth/library); import/detail push from Plan

**Calendar dots + legend:**
- **Green** = ready package for that date (available on Today / ready for the Creator loop)
- **Yellow** = draft only (generated in Plan, not yet a ready package)
- **No dot** = nothing for that date
- **New draft for the same day overwrites the previous draft**

**Edit after ready:** Ready does **not** lock the card. Editing happens in Plan. **Edit** buttons on the **Today hero card** and **Shoot Folio** navigate to Plan with that card’s date selected.

**After Available on Today succeeds:** navigate to **Today** showing that card; stay on Plan only on failure.

**Entry into Plan** (from shell): Profile → Plan; empty Today CTA; Today `⋯` → Plan; plus Edit from Today/Shoot Folio as above.
