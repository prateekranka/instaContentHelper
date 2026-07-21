# Empty Today one-action prototype

Type: prototype
Status: resolved
Blocked by: 01

## Question

What should the single empty-state action on Today look and feel like when nothing is available — copy, hierarchy, and the jump into Plan — such that it stays one job, not a mini Manager surface?

Depends on [Primary shell without Manager mode](01-primary-shell.md) and [Plan hub information architecture](02-plan-hub-ia.md).

Use `/prototype` for a cheap throwaway artifact; keep the answer, not the code, unless Notes change.

## Answer

**Winner: Variant B — Journal card**

Prototype: [assets/07-empty-today-prototype.html](../assets/07-empty-today-prototype.html) (`?variant=B`)

**Empty Today structure:**
- Keep the Today header (title + date)
- One **journal-style card** in the content area (not centered hero, not bottom command-bar only)
- Card contains: small visual cue, headline, one short supporting sentence, single primary CTA
- **No `⋯`**, no Weekly/Manager, no second actions

**Copy (locked from prototype B):**
- Headline: **Nothing ready for today**
- Body: **There’s no ready package for this date yet. Open Plan to generate one and make it available on Today.**
- CTA: **Plan today’s content** → navigates into Plan (same hub as Profile → Plan)

**Rejected:**
- A — Calm center (too sparse / poster-like for this app’s journal density)
- C — Command-bar CTA (separates message from action more than needed)

Throwaway HTML may stay under `assets/` as the primary source for this decision; do not promote into the app target as-is — rewrite properly at build time.
