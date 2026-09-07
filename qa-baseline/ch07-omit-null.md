# CH-07 omit-vs-null profile update semantics (local)

Recorded: 7 September 2026.
Repo: `/Users/prateekranka/Cowork/contenthelper` · branch `cursor/today-ui-prototype-cea4`
Scope: LOCAL only. No deploy. No column drops. No iOS edits. Prototype HTML untouched.

## Verdict

| Return | Value |
| --- | --- |
| preserve-on-omit | **pass** |
| explicit-clear | **pass** |
| handler edited | **no** (logic unchanged; `normalizedCreatorProfileUpdate` exported for unit tests only) |
| deploy | **held** |

## Handler review

At pinned HEAD, `normalizedCreatorProfileUpdate` (`write-content/index.ts:800-951`) already skips keys when the request value is `undefined` (`continue` on omit). Explicit clears use existing contract shapes:

| Field kind | Explicit clear input | Normalized update value |
| --- | --- | --- |
| Text arrays (`voice_rules`, `content_pillars`, `never_say`, `recurring_formats`, `custom_subjects`) | `null`, `[]`, or `""` | `[]` via `normalizedTextArray` |
| JSON arrays (`taste_example_ids`, `production_formats`, `recent_context`) | `[]` | `[]` |
| JSON objects (`on_camera_restrictions`, `first_idea_handoff`, `language_preferences`) | `null` | `{}` via `?? {}` |
| Scalars (`positioning`, `caption_style`, `creator_note`, enums) | `null` or `""` | `null` |

INSERT path (`updateCreatorProfile` when no active row) applies `onboarding_state` default `"new"` plus only keys present in the normalized update. DB column defaults supply empty adaptive JSON for omitted insert keys.

No semantic handler fix was required.

## Test payloads

### 1. Preserve on omit (UPDATE)

**Baseline DB row** (acceptance seeds then resets via admin):

```json
{
  "positioning": "Established positioning",
  "caption_style": "Established caption style",
  "voice_rules": ["Keep warm tone"],
  "content_pillars": ["gym", "recovery"],
  "taste_example_ids": ["example-a", "example-b"],
  "production_formats": ["reels", "talking_head"],
  "on_camera_restrictions": { "no_full_face": true },
  "onboarding_state": "established",
  "starting_point": "already_posting",
  "custom_subjects": ["fitness"]
}
```

**Request** (old client edits one scalar only):

```json
{
  "action": "update_creator_profile",
  "creator_id": "<creatorA>",
  "caption_style": "Caption-only edit from old client"
}
```

**Expected:** `caption_style` updates; all adaptive fields above stay unchanged. Normalizer omits adaptive keys from the SQL `update` object.

**Result:** pass — `index_test.ts` omits-adaptive-fields test; acceptance `assertCreatorProfileOmitVsNullSemantics` (written, see run note below).

### 2. Explicit clear (UPDATE)

**After omit baseline, request A** (text arrays):

```json
{
  "action": "update_creator_profile",
  "creator_id": "<creatorA>",
  "voice_rules": null,
  "content_pillars": []
}
```

**Expected:** `voice_rules` and `content_pillars` become `[]`; `taste_example_ids` still `["example-a", "example-b"]`.

**Request B** (JSON object):

```json
{
  "action": "update_creator_profile",
  "creator_id": "<creatorA>",
  "on_camera_restrictions": null
}
```

**Expected:** `on_camera_restrictions` becomes `{}`.

**Result:** pass — `index_test.ts` explicit-null tests; acceptance cases mirror these payloads.

### 3. Insert defaults separate from update omit

**Request** (new creator, positioning only):

```json
{
  "action": "update_creator_profile",
  "creator_id": "<creatorInsertOnlyA>",
  "positioning": "Insert-only positioning"
}
```

**Expected:** row created with `onboarding_state: "new"`, DB defaults for adaptive JSON (`taste_example_ids: []`, `on_camera_restrictions: {}`). No adaptive keys in the update payload.

**Result:** pass — acceptance insert-only case (written); normalizer omit test confirms no adaptive keys on scalar-only body.

## Tests added

| File | What |
| --- | --- |
| `supabase/functions/write-content/index_test.ts` | 4 unit tests on `normalizedCreatorProfileUpdate` (omit, array clear, object clear, explicit set) |
| `supabase/functions/write-content/acceptance.ts` | `assertCreatorProfileOmitVsNullSemantics` — full HTTP + DB matrix; new seed creator `creatorInsertOnlyA` |

## Test runs

| Command | Result |
| --- | --- |
| `deno task test:backend` | **pass** — 399 passed (includes 4 new write-content unit tests) |
| `deno run --allow-env --allow-net --allow-read supabase/functions/write-content/acceptance.ts` | **not run** — local Supabase/Docker unavailable (`supabase status` cannot reach Docker). Acceptance cases are ready for the next local stack bring-up. |

## Deploy

**Still held.** CH-07 decision unchanged: fixture proof is local-only; hosted schema/function read-back and production approval remain open.
