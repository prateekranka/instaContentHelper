# Publish / soft-lock / Today-read research (ticket 03)

**Question:** How do week soft-lock, `publish-week`, and Today-read paths work today, and what facts constrain replacing week publish with per-day “available on Today”?

**Scope:** Schema, Edge Functions, client call sites, concrete coupling gaps. No redesign.

**Confidence:** High for schema + Edge Function write/read contracts (primary SQL + TS). Medium-high for client soft-lock UX mapping (derived flags, not DB columns). See §5.

---

## 1. Schema

### 1.1 `weekly_plans` — week container + soft-lock home

Defined in `supabase/migrations/20260605000000_initial_content_os_schema.sql`:

| Column | Role |
| --- | --- |
| `status` | `draft` \| `reviewed` \| `published` \| `archived` \| `replaced` ([498–499](supabase/migrations/20260605000000_initial_content_os_schema.sql#L498)) |
| `is_soft_locked` | `boolean not null default false` — **only soft-lock flag in Postgres** ([503](supabase/migrations/20260605000000_initial_content_os_schema.sql#L503)) |
| `published_at` | set on publish ([504](supabase/migrations/20260605000000_initial_content_os_schema.sql#L504)) |
| `replaced_by_weekly_plan_id` | when a newer publish replaces this week ([505](supabase/migrations/20260605000000_initial_content_os_schema.sql#L505)) |
| `week_start_date` | Monday-anchored week key ([497](supabase/migrations/20260605000000_initial_content_os_schema.sql#L497)) |

**One published week per creator+Monday:**

```795:797:supabase/migrations/20260605000000_initial_content_os_schema.sql
create unique index weekly_plans_one_published_week_idx
  on public.weekly_plans(creator_id, week_start_date)
  where status = 'published';
```

Schema doc query path: Manager Weekly Control loads `weekly_plans` by `creator_id + week_start_date + status`, then cards by `weekly_plan_id` ([54–55](docs/supabase-schema-creator-content-os-v2.md#L54)).

Day-at-a-time product note: `weekly_plans` is a thin Monday-anchored **storage/publishing container**, not the generation unit ([22–23](docs/day-at-a-time-pivot-brief.md#L22)).

### 1.2 `daily_cards` — Today sync contract; no soft-lock column

| Column / constraint | Role |
| --- | --- |
| `weekly_plan_id` | FK to week container; cascade delete ([520](supabase/migrations/20260605000000_initial_content_os_schema.sql#L520), [557–558](supabase/migrations/20260605000000_initial_content_os_schema.sql#L557)) |
| `scheduled_date` | day identity within plan; unique with `weekly_plan_id` ([524](supabase/migrations/20260605000000_initial_content_os_schema.sql#L524), [569](supabase/migrations/20260605000000_initial_content_os_schema.sql#L569)) |
| `status` | `draft` \| `published` \| decision/terminal statuses (`in_decision`, `shot`, `posted`, `used_backup`, `saved_for_tomorrow`, `skipped_intentionally`, `archived`) ([525–526](supabase/migrations/20260605000000_initial_content_os_schema.sql#L525)) |
| `review_state` | `open` \| `ready` \| `backup` — **Manager draft review only**, added later ([9–23](supabase/migrations/20260630143000_durable_review_state_atomic_publish.sql#L9)) |

**There is no `daily_cards.is_soft_locked` column.** Product doc language that publish “marks all seven weekly day rows as soft-locked” ([11–12](docs/weekly-publish-soft-lock-creator-content-os-v2.md#L11)) is implemented as:

- DB: set each card `status = 'published'` (atomic RPC [239](supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql#L239), [302–307](supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql#L302))
- Client: derive `WeeklyDay.isSoftLocked = (status != "draft")` ([423](CreatorContentOS/Data/SupabaseDTOs.swift#L423)) and set all days locked after publish in memory ([3–12](CreatorContentOS/Data/WeeklyPublishingModels.swift#L3))

**Today lookup index** (published + post-decision statuses, not draft):

```798:800:supabase/migrations/20260605000000_initial_content_os_schema.sql
create index daily_cards_today_lookup_idx
  on public.daily_cards(creator_id, scheduled_date)
  where status in ('published', 'in_decision', 'shot', 'posted', 'used_backup', 'saved_for_tomorrow', 'skipped_intentionally');
```

Table comment: “Published Daily Cards are the sync contract for Creator Today and offline cache” ([1142–1143](supabase/migrations/20260605000000_initial_content_os_schema.sql#L1142)). Schema doc: Creator Today = `daily_cards` by `creator_id + scheduled_date` where published or completed ([54](docs/supabase-schema-creator-content-os-v2.md#L54)).

### 1.3 `review_state` vs product “ready package”

Column comment: authoritative for **draft** cards; published/terminal cards are mapped by **status** ([22–23](supabase/migrations/20260630143000_durable_review_state_atomic_publish.sql#L22)).

So today:

| Concept | Current encoding |
| --- | --- |
| Manager draft yellow/green (open/ready/backup) | `daily_cards.review_state` while `status = 'draft'` |
| Visible on Creator Today | `daily_cards.status ∈` published lifecycle set |
| Week locked against regen/edit/publish again | `weekly_plans.is_soft_locked` and/or `status = 'published'` |

Product language “draft (yellow) vs ready package (green) available on Today” is **not** the same as `review_state` alone — Today ignores draft cards entirely.

### 1.4 Atomic publish RPC (current)

Latest definition: `public.publish_week_atomic(payload jsonb)` in `supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql`.

Behavior (cited):

1. Load plan; 404 if missing ([55–64](supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql#L55))
2. If already `status = 'published'`, idempotent summary with `is_soft_locked: true` ([70–82](supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql#L70))
3. Else require `is_soft_locked = false` and status `draft`/`reviewed`; else 409 `existing_published_week_locked` ([85–87](supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql#L85))
4. Require **exactly 7** `draft_daily_cards` covering the Monday week dates ([89–112](supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql#L89))
5. If another published plan exists for same week, mark it `replaced`, clear its soft-lock, archive its active cards ([114–135](supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql#L114))
6. Upsert all seven cards as `status = 'published'` ([226–281](supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql#L226))
7. Set plan `status = 'published'`, `is_soft_locked = true`, `published_at = now()` ([284–300](supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql#L284))
8. Force any remaining draft cards on that plan to `published` ([302–307](supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql#L302))

---

## 2. Edge Functions

### 2.1 `publish-week`

File: `supabase/functions/publish-week/index.ts`. Contract overview also in [docs/weekly-publish-soft-lock-creator-content-os-v2.md](docs/weekly-publish-soft-lock-creator-content-os-v2.md).

**Auth:** device token; roles `owner` | `editor` ([136–139](supabase/functions/publish-week/index.ts#L136)).

**Two publish paths:**

| Path | When | Writes |
| --- | --- | --- |
| Existing draft | `weekly_plan_id` present and no legacy 7-day `days` payload ([166–168](supabase/functions/publish-week/index.ts#L166)) | Calls `publish_week_atomic` RPC ([253–257](supabase/functions/publish-week/index.ts#L253)) |
| Legacy caller-supplied days | else ([170–176](supabase/functions/publish-week/index.ts#L170)) | Direct plan upsert with `status: "published"`, `is_soft_locked: true` ([324–335](supabase/functions/publish-week/index.ts#L324)); upsert cards; `open` days stay `draft`, others `published` ([361–381](supabase/functions/publish-week/index.ts#L361)) |

**Soft-lock gates (existing-draft path):**

- Already published → idempotent summarize ([228–230](supabase/functions/publish-week/index.ts#L228), [577–598](supabase/functions/publish-week/index.ts#L577))
- Soft-locked or not draft/reviewed → 409 `existing_published_week_locked` ([231–236](supabase/functions/publish-week/index.ts#L231))
- Payload must include **7** `draft_daily_cards` ([238–243](supabase/functions/publish-week/index.ts#L238))

**Replace behavior:** prior published plan for same creator/week → `status = 'replaced'`, `is_soft_locked = false`, cards in active statuses → `archived` ([527–571](supabase/functions/publish-week/index.ts#L527)).

**Returns:** `weekly_plan_id`, `daily_card_count`, `is_soft_locked: true`, `published_at` ([279–285](supabase/functions/publish-week/index.ts#L279)).

### 2.2 `generate-week` day actions (`generate_day` / `regenerate_day`)

Supported product surface uses day actions on this function ([18–23](docs/day-at-a-time-pivot-brief.md#L18)).

**`generate_day`:**

1. `ensureDayPlanContainer` — latest **draft** plan for that Monday, or insert thin draft with `is_soft_locked: false` ([545–594](supabase/functions/generate-week/index.ts#L545))
2. Soft-locked existing draft container → 409 `existing_published_week_locked` ([566–569](supabase/functions/generate-week/index.ts#L566))
3. Rewrites into `regenerate_day` prep ([499–515](supabase/functions/generate-week/index.ts#L499))

**`prepareDayGeneration` / regenerate locks:**

- Plan `status === "published"` **or** `is_soft_locked` → 409 ([702–705](supabase/functions/generate-week/index.ts#L702))
- Plan must be `draft` else 409 `weekly_plan_not_found` ([707–710](supabase/functions/generate-week/index.ts#L707))
- Existing card for date must be `status === "draft"`; non-draft → 404 `daily_card_not_found` ([727–733](supabase/functions/generate-week/index.ts#L727))

**Persist regenerate** (`persistRegeneratedDay`): same published/soft-lock 409 ([251–257](supabase/functions/generate-week/generation-persistence.ts#L251)); updates only rows with `status = 'draft'` ([210–224](supabase/functions/generate-week/generation-persistence.ts#L210)). Generated card values always persist as `status: "draft"` ([96](supabase/functions/generate-week/generation-persistence.ts#L96)).

**Full-week legacy path** still checks `hasPublishedWeek` (any published plan for that Monday) → 409 ([964–976](supabase/functions/generate-week/index.ts#L964), [2042–2061](supabase/functions/generate-week/index.ts#L2042)). Day `generate_day` does **not** call `hasPublishedWeek`; it can create a **new draft container** beside an already-published week for the same Monday (unique index only constrains published rows). That draft still cannot reach Today until published.

**Week draft upsert** (`upsertDraftWeeklyPlan`): rejects soft-locked draft/reviewed rows ([405–408](supabase/functions/generate-week/generation-persistence.ts#L405)); writes `is_soft_locked: false`, `status: "draft"` ([420–433](supabase/functions/generate-week/generation-persistence.ts#L420)).

### 2.3 `read-content` Today path

Action `"today"` ([106–112](supabase/functions/read-content/index.ts#L106)).

**Read (not write):**

```148:188:supabase/functions/read-content/index.ts
async function readToday(...) {
  // today_card: one row for scheduled_date in PUBLISHED_DAILY_STATUSES
  // week_cards: up to 14 published-lifecycle cards ordered by scheduled_date
  // today_status: "published" | "missing_published_card"
}
```

`PUBLISHED_DAILY_STATUSES` = published + decision statuses ([42–50](supabase/functions/read-content/index.ts#L42)). **Does not filter on `weekly_plans.is_soft_locked`.** Draft cards never appear.

Roles: all device roles may call `today` ([28–29](supabase/functions/read-content/index.ts#L28), [72–76](supabase/functions/read-content/index.ts#L72)); `weekly`/`intelligence` are admin-only ([29](supabase/functions/read-content/index.ts#L29)).

**`readWeekly`:** returns working draft plan (via `pickWorkingPlan`) **and** separate `published_weekly_plan` / `published_daily_cards` ([214–306](supabase/functions/read-content/index.ts#L214)). Soft-lock is selected on plans (`WEEKLY_PLAN_SELECT` includes `is_soft_locked` [33–34](supabase/functions/read-content/index.ts#L33)) but Today eligibility remains card `status`.

### 2.4 `write_content` — review_state gated by week soft-lock

`update_daily_card_review_state` joins card → plan; if `wp.is_soft_locked` or plan not draft/reviewed → 409 `published_week_locked` ([638–656](supabase/migrations/20260630143000_durable_review_state_atomic_publish.sql#L638)). Update only succeeds for `status = 'draft'` ([658–663](supabase/migrations/20260630143000_durable_review_state_atomic_publish.sql#L658)).

`complete_today` updates card decision status without checking soft-lock ([24–39](supabase/migrations/20260605150000_write_content_boundary.sql#L24)) — Creator decisions after publish are allowed.

No `write_content` action mutates published card package fields (script/caption/scenes) for “edit after ready.”

---

## 3. Client call sites

### 3.1 Creator Today load

| Step | Location |
| --- | --- |
| Launch: cache then network | `CreatorContentOSApp` `.task`: `loadTodayFromCache()` then `refreshFromRepositoriesImmediately()` ([19–25](CreatorContentOS/App/CreatorContentOSApp.swift#L19)) |
| Cache apply | `AppServices.loadTodayFromCache` → `apply(snapshot:)` sets `todayCard` + `weekCards` ([1241–1248](CreatorContentOS/App/AppServices.swift#L1241), [1547–1550](CreatorContentOS/App/AppServices.swift#L1547)) |
| Live fetch | `SupabaseTodayCardRepository.todayCard` → `read-content` action `.today`; missing row → `RepositoryError.noPublishedTodayCard` ([7–17](CreatorContentOS/Data/SupabaseRepositories.swift#L7)) |
| Refresh | `refreshFromRepositoriesImmediately` assigns `todayCard`, saves snapshot `source: "repository-refresh"`; on network failure falls back to cache ([1262–1274](CreatorContentOS/App/AppServices.swift#L1262)); missing published → `.missingPublishedCard` ([1267–1269](CreatorContentOS/App/AppServices.swift#L1267), [1334–1337](CreatorContentOS/App/AppServices.swift#L1334)) |
| UI | `TodayView` / `ShootFolioView` / `NotTodaySheet` read `services.todayCard` |

Offline cache contract: [docs/offline-today-cache-creator-content-os-v2.md](docs/offline-today-cache-creator-content-os-v2.md).

### 3.2 `TodayCacheStore` implications

`FileTodayCacheStore` ([16–78](CreatorContentOS/Data/TodayCacheStore.swift#L16)):

- Snapshot: `todayCard`, `weekCards`, `cachedAt`, `source` ([3–7](CreatorContentOS/Data/TodayCacheStore.swift#L3))
- Path: `Application Support/CreatorContentOS/TodayCache/today-{workspaceID}-{creatorID}.json` ([58–77](CreatorContentOS/Data/TodayCacheStore.swift#L58))
- Written after successful Today refresh (`repository-refresh`), week publish (`week-publish`), and Creator decisions ([1265](CreatorContentOS/App/AppServices.swift#L1265), [1022](CreatorContentOS/App/AppServices.swift#L1022), [278](CreatorContentOS/App/AppServices.swift#L278))
- **Caches published/available cards only.** A draft day never enters this store via the Today repository. Stale published snapshot remains if refresh fails ([32–33](docs/offline-today-cache-creator-content-os-v2.md#L32)). Per-day unpublish / replace would need explicit cache invalidation or overwrite on next successful Today read.

### 3.3 Manager publish

| Step | Location |
| --- | --- |
| UI | `WeeklyControlView.publishWeekPageAction` → `services.publishCurrentWeek()` ([132–144](CreatorContentOS/Features/Weekly/WeeklyControlView.swift#L132)); disabled unless `canPublishCurrentWeek` ([143](CreatorContentOS/Features/Weekly/WeeklyControlView.swift#L143)) |
| Gate | `canPublishCurrentWeek`: owner/editor, not soft-locked, **exactly 7 days**, no open days, complete generated draft matching dates ([346–369](CreatorContentOS/App/AppServices.swift#L346)) |
| Invoke | `SupabaseWeeklyPlanRepository.publishWeek` → Edge Function `publish-week` with `draft_daily_cards` when generated draft matches plan ([141–156](CreatorContentOS/Data/SupabaseRepositories.swift#L141), [912–925](CreatorContentOS/Data/SupabaseDTOs.swift#L912)) |
| Local reflect | `.softLockedForPublish` marks plan + all days locked ([3–12](CreatorContentOS/Data/WeeklyPublishingModels.swift#L3)); `todayCard = bestTodayCard(from: cards)` ([172–176](CreatorContentOS/Data/SupabaseRepositories.swift#L172)) |
| Post-publish | `AppServices.publishCurrentWeekImmediately` updates state, `refreshPublishedContentAfterPublishImmediately()`, `saveTodaySnapshot(source: "week-publish")` ([1001–1022](CreatorContentOS/App/AppServices.swift#L1001)) |

Plan soft-lock from server: `isSoftLocked: row.isSoftLocked || row.status == "published"` ([313](CreatorContentOS/Data/SupabaseRepositories.swift#L313)).

### 3.4 Client soft-lock coupling (regen / review / week window)

- `regenerateDayCard`: `guard !weeklyPlan.isSoftLocked` → `published_week_locked` ([573–577](CreatorContentOS/App/AppServices.swift#L573))
- `generateDayCard`: **no** soft-lock guard; server may attach a new draft container ([622–664](CreatorContentOS/App/AppServices.swift#L622))
- `updateWeeklyDayStateImmediately` (review_state): blocked if plan or day soft-locked ([810–814](CreatorContentOS/App/AppServices.swift#L810))
- `updateWeeklyStartDate`: no-op when soft-locked ([448](CreatorContentOS/App/AppServices.swift#L448))
- Calendar week cell “published” when `plan.isSoftLocked && hasFullSelectedWindow` ([392–393](CreatorContentOS/Features/Weekly/WeeklyControlView.swift#L392))
- Day regenerate UI: `canRegenerateDay` requires `!weeklyPlan.isSoftLocked` ([108–110](CreatorContentOS/Features/Weekly/WeeklyControlView.swift#L108))

User-facing copy for lock: `"This week is already published and locked."` ([1609](CreatorContentOS/App/AppServices.swift#L1609)).

---

## 4. What must change (facts / gaps only)

Target product (from CONTEXT / ticket 04): draft yellow vs ready package green, **per-day** available-on-Today, overwrite draft on regenerate, edit after ready. Below is **current coupling**, not a design.

### 4.1 Soft-lock is week-scoped, not day-scoped

1. Only `weekly_plans.is_soft_locked` exists in SQL ([503](supabase/migrations/20260605000000_initial_content_os_schema.sql#L503)). Day “lock” is client-derived from non-draft status ([423](CreatorContentOS/Data/SupabaseDTOs.swift#L423)).
2. Publish sets soft-lock on the **entire** plan and publishes **all seven** dates in one transaction ([284–307](supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql#L284)).
3. `publish-week` / `publish_week_atomic` require exactly seven cards ([89–90](supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql#L89), [238–241](supabase/functions/publish-week/index.ts#L238)).
4. Client publish gate also requires seven non-open days + complete week draft ([346–369](CreatorContentOS/App/AppServices.swift#L346)).
5. Unique index allows only one `status = 'published'` plan per creator+Monday ([795–797](supabase/migrations/20260605000000_initial_content_os_schema.sql#L795)); replace archives the previous week’s active cards ([129–134](supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql#L129)).

### 4.2 Today availability = card `status`, gated by week publish ceremony

6. Today read includes only published-lifecycle statuses ([42–50](supabase/functions/read-content/index.ts#L42), [154–160](supabase/functions/read-content/index.ts#L154)). Draft packages are invisible to Creator Today.
7. There is no per-day “available_on_today” / ready-package flag independent of week publish + `status`.
8. `review_state = 'ready'` does **not** put a card on Today; it only marks Manager draft review ([22–23](supabase/migrations/20260630143000_durable_review_state_atomic_publish.sql#L22)).

### 4.3 Regenerate / overwrite draft coupling to week lock + draft status

9. Server regenerate rejects published or soft-locked **plans** ([702–705](supabase/functions/generate-week/index.ts#L702), [251–257](supabase/functions/generate-week/generation-persistence.ts#L251)).
10. Server regenerate only overwrites cards with `status = 'draft'` ([224](supabase/functions/generate-week/generation-persistence.ts#L224), [727–733](supabase/functions/generate-week/index.ts#L727)). Once a day is published with the week, regenerate returns 404 for that date.
11. Client regenerate is additionally blocked whenever the **loaded** weekly plan is soft-locked ([573–577](CreatorContentOS/App/AppServices.swift#L573)) — even if product wanted to overwrite a non-available draft day in the same Monday container.
12. Overwrite-draft-on-regenerate **already works for draft-status cards** on unlocked draft plans; it does **not** work after week soft-lock publish.

### 4.4 Edit after ready

13. After publish, `update_daily_card_review_state` is blocked by soft-lock ([654–656](supabase/migrations/20260630143000_durable_review_state_atomic_publish.sql#L654)).
14. No Edge/RPC path found that updates published card content fields (script, caption, scenes, etc.). Creator `complete_today` only changes decision `status` ([30–38](supabase/migrations/20260605150000_write_content_boundary.sql#L30)).
15. To “edit after ready” under current model, the week must be unlocked/replaced or a parallel draft container published (whole-week replace), which archives prior active cards ([129–134](supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql#L129)).

### 4.5 Cache / dual plan surfaces

16. `TodayCacheStore` assumes a published Today card snapshot; missing published day is a first-class empty state ([1334–1337](CreatorContentOS/App/AppServices.swift#L1334)), not “show draft.”
17. Manager `readWeekly` can show a working draft **and** a published week side-by-side ([299–305](supabase/functions/read-content/index.ts#L299)); Today only sees published statuses. Per-day available-on-Today must define which row wins when draft + published cards share a `scheduled_date` across plans (Today currently picks latest `updated_at` among published-lifecycle statuses only ([161](supabase/functions/read-content/index.ts#L161))).

### 4.6 Doc mismatch to treat carefully

18. Slice doc claims publish soft-locks “all seven weekly day rows” ([11–12](docs/weekly-publish-soft-lock-creator-content-os-v2.md#L11)); DB soft-locks the **plan**; days flip to published status / client `isSoftLocked`.

---

## 5. Sources consulted · confidence · known gaps

### Sources

| Source | Use |
| --- | --- |
| `supabase/migrations/20260605000000_initial_content_os_schema.sql` | Core tables, indexes, comments |
| `supabase/migrations/20260630143000_durable_review_state_atomic_publish.sql` | `review_state`, initial atomic publish + write_content gate |
| `supabase/migrations/20260701100000_preserve_storyboard_thumbnail_assets_on_publish.sql` | Current `publish_week_atomic` |
| `supabase/migrations/20260605150000_write_content_boundary.sql` | `complete_today` |
| `supabase/functions/publish-week/index.ts` (+ tests) | Publish Edge Function |
| `supabase/functions/generate-week/index.ts`, `generation-persistence.ts` | Soft-lock on generate/regenerate |
| `supabase/functions/read-content/index.ts` | Today + weekly reads |
| `docs/supabase-schema-creator-content-os-v2.md` | Query-path narrative |
| `docs/weekly-publish-soft-lock-creator-content-os-v2.md` | Publish product/slice contract |
| `docs/offline-today-cache-creator-content-os-v2.md` | Cache boundary |
| `docs/day-at-a-time-pivot-brief.md` | Day container vs week publish |
| `CreatorContentOS/Data/{SupabaseRepositories,TodayCacheStore,WeeklyPublishingModels,SupabaseDTOs}.swift` | Client I/O |
| `CreatorContentOS/App/{AppServices,CreatorContentOSApp}.swift` | Orchestration |
| `CreatorContentOS/Features/Weekly/WeeklyControlView.swift` | Manager publish UI |
| `CONTEXT.md` | Target vocabulary (draft / ready package / available on Today) |

### Confidence

| Area | Level | Notes |
| --- | --- | --- |
| Schema flags / statuses | **High** | Migration source of truth |
| publish-week + RPC write semantics | **High** | Code + latest SQL |
| Today read filter | **High** | Explicit status list |
| generate/regenerate soft-lock | **High** | Multiple consistent gates |
| Client soft-lock UX | **Medium-high** | Derived day lock; fixture path mirrors |
| “Edit after ready” absence | **High** for write_content surface; **medium** that no other function edits published packages (spot-checked generate/publish/write/read only) |

### Known gaps / not fully traced

- Full `write-content` Edge Function wrapper vs SQL RPC (client invokes function; mutation rules cited from SQL).
- Whether any admin tooling or SQL scripts manually flip soft-lock outside `publish-week`.
- Exact production data shape for partial day-at-a-time weeks that never reach seven cards (publish blocked by both client and RPC).
- Ticket 04 product rules for edit-after-ready and overwrite semantics are out of scope here; this note only records current coupling.

---

## Ticket link

Wayfinder: [issues/03-publish-data-model-research.md](../issues/03-publish-data-model-research.md).
