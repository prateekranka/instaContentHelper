# Per-day available-on-Today semantics

Type: grilling
Status: resolved
Blocked by: 03

## Question

What exact product rules define when a day card is a **draft** vs a **ready package** (available on Today) — edits after ready, replacing a day’s card, calendar green/yellow meaning, and what happens to the old week soft-lock concept in product language?

**Constraints already locked (from Plan hub IA):**
- Green = ready package for that date; yellow = draft only; no dot = none
- New draft for the same day overwrites the previous draft
- Ready does not lock editing (edit in Plan; Edit from Today/Shoot Folio opens Plan)
- Available on Today success navigates to Today

Depends on [Publish and soft-lock data model (research)](03-publish-data-model-research.md).

## Answer

### States (per calendar date)

| State | Calendar | Meaning |
| --- | --- | --- |
| None | no dot | Nothing generated for that date |
| **Draft** | yellow | Generated in Plan; not on Creator Today |
| **Ready package** | green | Made available for that date; Today shows it **only when that date is the device’s local today** |

### Available on Today

- Operates on **one day only** (the Plan-selected date’s current draft → ready package).
- Does **not** require a full week of cards.
- No week soft-lock / publish-week ceremony in product language (retired for Creators).
- On success: navigate to **Today** showing that card (when the date is today).

### Unpublish

- Explicit **Unpublish** control on Plan for a green day (confirm once).
- Effect: ready → **draft** (yellow). If that date is today, Today goes empty (CTA).
- **Allowed after a Decision.** Clears the live Decision for that date; **keeps Archive history** of the prior Decision.

### Edit vs regenerate

- **Light edit** of a ready package in Plan: **stays ready (green)**; updates the same package in place (Today refreshes to the updated content when that date is current).
- **Generate again** when a ready package exists (or after a Decision): **warn + explicit Overwrite** confirmation → replaces with a **new draft (yellow)**; must Available on Today again to become ready. If a Decision existed, clear the live Decision; keep Archive history (same as Unpublish).
- Draft-only regenerate (yellow → yellow overwrite): already allowed; no ready-overwrite warning required.

### Today tab

- Shows **only** the ready package for **today’s local calendar date**.
- Future ready packages remain green on the Plan calendar but do not appear on Today until that date.
- No ready package for today → empty Today CTA into Plan.

### Product language

- Creators use: draft, ready package, Available on Today, Unpublish, Overwrite.
- Avoid: soft-lock, publish week, Manager publish ceremony.
- Week containers may remain as storage under the hood until a later migration decision.
