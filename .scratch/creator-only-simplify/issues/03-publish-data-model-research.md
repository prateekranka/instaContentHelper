# Publish and soft-lock data model (research)

Type: research
Status: resolved

## Question

How do the current week soft-lock, `publish-week`, and Today-read paths work in schema and Edge Functions, and what facts must later tickets know to replace week publish with per-day “available on Today”?

Deliverable: a short cited markdown summary linked from this ticket (schema, Edge Functions, client call sites).

## Answer

Full cited research: [assets/03-publish-data-model-research.md](../assets/03-publish-data-model-research.md)

**Facts for later tickets:**

1. **Soft-lock is week-scoped** — only `weekly_plans.is_soft_locked` (+ plan `status = published`). `daily_cards` has no soft-lock column; client derives day lock from `status != draft`.
2. **`publish_week_atomic` / `publish-week` require all 7 days**, set the whole week soft-locked, and flip cards to `published` (or replace the prior published week).
3. **Creator Today** reads via `read-content` `today` by `scheduled_date` + published-lifecycle statuses only — **drafts never appear**; soft-lock is not checked on that read path.
4. **Regenerate and Manager package edits are blocked** once the week is soft-locked/published; there is no write path to edit published package content today.
5. **`review_state` is Manager draft review only** (open/ready/backup) — it is **not** Today availability. Product draft (yellow) vs ready package (green) is not encoded as that column alone; Today visibility is `daily_cards.status`.
6. **Coupling to remove/replace for per-day available-on-Today:** 7-day publish gate, week `is_soft_locked`, card `status = published` as the only Today gate, and post-publish edit/regen blocks.
