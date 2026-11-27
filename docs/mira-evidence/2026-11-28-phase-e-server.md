# Mira Phase E server handoff

Branch `claude/mira-e-server`. Base `8405e89` includes S2, S4 and D2 server. The failure modes were committed before implementation. [Failure modes](2026-11-28-phase-e-server-failure-modes.md)

The previous endpoint received creator profiles, constraints, scripts, storyboards and briefs. Phase E adds the six operations below. They can send brand documents, interview answers, approved Instagram summaries and deal context to the configured text provider. The provider selection and device authentication paths stay the same. Bobby approved the data and call scope. Claude reviews the code and confirms the app's consent flow before rollout.

## Common API

Send a POST to `/functions/v1/mira-generation` with the existing Supabase client headers and `x-mco-device-token`. A start request uses this envelope. Replace `input` with one of the six operation examples below.

```json
{
  "action": "start",
  "id": "10000000-0000-4000-8000-000000000011",
  "creatorID": "10000000-0000-4000-8000-000000000002",
  "inputRevision": 1,
  "consentVersion": 1,
  "input": {
    "operation": "brandDoc",
    "language": "English",
    "writingSystem": "Romanised",
    "answers": "I make quick breakfasts and train at home."
  }
}
```

Poll with the ID in the **returned job**. Use the same body with `action: "cancel"` to cancel queued or running work. This is the status request.

```json
{
  "action": "status",
  "id": "10000000-0000-4000-8000-000000000011",
  "creatorID": "10000000-0000-4000-8000-000000000002"
}
```

This is a succeeded response. The operation examples show the exact `job.output` payload. Result fields belong inside `job`.

```json
{
  "job": {
    "id": "10000000-0000-4000-8000-000000000011",
    "inputRevision": 1,
    "input": {
      "operation": "brandDoc",
      "language": "English",
      "writingSystem": "Romanised",
      "answers": "I make quick breakfasts and train at home."
    },
    "state": "succeeded",
    "phase": "succeeded",
    "output": {
      "brandDoc": {
        "pillars": ["Quick breakfasts", "Simple movement", "Small habits"],
        "tone": "Warm and direct",
        "audience": "Busy home cooks",
        "dos": ["Show easy steps"],
        "donts": ["Avoid health promises"],
        "goals": ["Share more home recipes"]
      }
    }
  }
}
```

- `state` is `working`, `succeeded`, `failed` or `cancelled`. The `phase` field distinguishes `queued`, `running` and `waiting_to_retry` while working. Start can return before the first claim. Keep polling the returned ID for the final output.
- `output` appears on success. `error` is optional. A failed validation leaves the job failed with no output.
- `step` and `pictures` follow D2 for `pickIdea`. Put `"pictures": true` on a **status** request to opt in. It can return `"pictures": [{"shotID": "…", "status": "pending"}]` inside `job`. A ready entry has `status: "ready"` and a signed `url`. A failed entry has `status: "failed"`. Keep polling with opt-in if a picture is pending. [D2 status and pictures](2026-11-27-phase-d2-server.md)
- Enqueue returns HTTP 429 with `{"error":"operation_daily_cap_reached"}` if the operation has spent its quota. If the last allowance goes to another job after enqueue, status returns `state: "failed"` with that error. The existing HTTP 409 `rate_limited` and `job_conflict` errors still apply.
- The request objects are strict. Omit optional fields instead of sending `null`. Use `language` of `English`, `Hindi` or `Hinglish` and `writingSystem` of `Devanagari` or `Romanised`. `pickIdea` takes these fields in `profile`.
- Ask for the new **Use your Instagram results to pick ideas** permission before including `instagramSummary`, Instagram-derived `bestPostPatterns` or Instagram snapshots. The existing `consentVersion: 1` checks general generation consent. The app owns the separate Instagram permission gate. The server uses only data supplied in these requests and sends no Instagram credentials. It accepts requests without the optional data. The job stores request and result data under the existing private jobs table.

## E2 · brandDoc

`input` example. The interview can be English, Hindi or Hinglish. `instagramSummary` and `oldBrandDoc` are optional. The latter has the same object shape as `output.brandDoc`.

```json
{
  "operation": "brandDoc",
  "language": "English",
  "writingSystem": "Romanised",
  "answers": "I make quick breakfasts and train at home. I want recipes to feel easy.",
  "instagramSummary": {
    "followers": 85,
    "topPosts": [{"caption": "My fast mango bowl", "saves": 4}]
  }
}
```

`job.output` example. Pillars have three to five distinct entries. Goals have one to three entries. Dos and don'ts each allow up to six entries. The result uses qualitative wording.

```json
{
  "brandDoc": {
    "pillars": ["Quick breakfasts", "Simple movement", "Small habits"],
    "tone": "Warm and direct",
    "audience": "Busy home cooks",
    "dos": ["Show easy steps"],
    "donts": ["Avoid health promises"],
    "goals": ["Share more home recipes"]
  }
}
```

## E2 · pickIdea

`input` example. `angle`, `brandDoc`, `bestPostPatterns` and `dealChecklist` are optional. `dealChecklist.items` uses the deal checklist item format below. Only include a reviewed deal checklist. Send an empty array for `avoid` or `recentIdeas` when there are no titles to skip. For Show another idea, include the skipped title in `avoid` and use a new request ID.

```json
{
  "operation": "pickIdea",
  "profile": {
    "name": "Maya",
    "themes": "Food",
    "audience": "Busy home cooks",
    "language": "English",
    "writingSystem": "Romanised",
    "tone": "Warm",
    "avoid": "Health promises",
    "samples": "",
    "solo": true
  },
  "constraints": {
    "filmingMinutes": 10,
    "location": "Home",
    "style": "Either",
    "reelSeconds": 15,
    "equipment": "Phone, table and books"
  },
  "request": "Something I can film before breakfast.",
  "recentIdeas": [],
  "avoid": ["My morning smoothie"],
  "bestPostPatterns": ["Simple bowl demos earned saves."]
}
```

`job.output` example. `reason` explains the pick in one sentence. The script and storyboard follow the D2 contract. The storyboard uses the supplied checklist revision and item IDs when present. Otherwise it uses revision `0` with empty mappings. The OpenAI streaming adapter reports `idea_ready`, `script_ready` and `storyboard_ready` under the claimed lease. Other adapters complete the text result without incremental steps.

```json
{
  "ideas": [{
    "id": "20000000-0000-4000-8000-000000000001",
    "title": "My fast mango bowl",
    "hook": "This is my fast breakfast.",
    "visual": "Mango on a bowl of curd.",
    "fit": "One bowl at home.",
    "filmingMinutes": 5,
    "setup": "Put your phone against books on the table."
  }],
  "reason": "Your simple bowl demos earned saves, and you can film this one at home today.",
  "script": {
    "id": "20000000-0000-4000-8000-000000000002",
    "hook": "This is my fast breakfast.",
    "spoken": "Add curd. Top with mango.",
    "caption": "My fast mango bowl.",
    "durationSeconds": 15,
    "language": "English"
  },
  "storyboard": {
    "id": "20000000-0000-4000-8000-000000000003",
    "sourceScriptID": "20000000-0000-4000-8000-000000000002",
    "requirementsRevision": 0,
    "mappings": [],
    "shots": [
      {
        "id": "30000000-0000-4000-8000-000000000001",
        "purpose": "Introduce the breakfast",
        "editedSeconds": 5,
        "recordingSeconds": 8,
        "location": "Kitchen table",
        "props": "Bowl and books",
        "placement": "Set the phone against books on the table.",
        "distance": "One arm's length",
        "framing": "Head and shoulders",
        "frameType": "headShoulders",
        "action": "Hold up the bowl.",
        "words": "This is my fast breakfast.",
        "voiceover": false,
        "onScreenText": "My fast mango bowl",
        "simplerAlternative": "Point to the bowl."
      },
      {
        "id": "30000000-0000-4000-8000-000000000002",
        "purpose": "Show the base",
        "editedSeconds": 5,
        "recordingSeconds": 8,
        "location": "Kitchen table",
        "props": "Curd and bowl",
        "placement": "Prop the phone against a book beside the bowl.",
        "distance": "Half an arm's length",
        "framing": "Hands and bowl",
        "frameType": "closeUp",
        "action": "Spoon curd into the bowl.",
        "words": "Add curd.",
        "voiceover": true,
        "onScreenText": "",
        "simplerAlternative": "Start with curd in the bowl."
      },
      {
        "id": "30000000-0000-4000-8000-000000000003",
        "purpose": "Show the topping",
        "editedSeconds": 5,
        "recordingSeconds": 8,
        "location": "Kitchen table",
        "props": "Chopped mango",
        "placement": "Leave the phone against the same book.",
        "distance": "Half an arm's length",
        "framing": "Hands and bowl",
        "frameType": "closeUp",
        "action": "Drop mango pieces onto the curd.",
        "words": "Top with mango.",
        "voiceover": true,
        "onScreenText": "",
        "simplerAlternative": "Show the finished bowl."
      }
    ]
  },
  "conflicts": []
}
```

## E3 · dealBrief

`input` example. Send the text the creator shared. An attachment can supply extracted text from the app.

```json
{
  "operation": "dealBrief",
  "language": "English",
  "writingSystem": "Romanised",
  "briefText": "Morning Oats. Fee ₹5,000. Due 2 December 2026. Put #ad in the caption. Show code OAT10 on screen. Show the oats pack in a close-up."
}
```

`job.output` example. Keep `brand`, `fee`, `deadlineExcerpt`, `disclosures`, `codes` and checklist excerpts verbatim. Unknown brand or fee uses an empty string. The deadline is `YYYY-MM-DD` if supported by one clear source date. A missing or ambiguous deadline uses an empty string and an unresolved note. Copy a date clause into `deadlineExcerpt` when present. If absent, use an empty string. The server supports ISO dates, named English or Hindi months with an explicit year, and numeric dates with one possible reading. Treat other formats as unresolved. Checklist kinds are `caption`, `onScreenText`, `script`, `shot` and `other`. `requiredText` is optional and matches exact text from the excerpt.

```json
{
  "deal": {
    "brand": "Morning Oats",
    "fee": "₹5,000",
    "deadline": "2026-12-02",
    "deadlineExcerpt": "Due 2 December 2026.",
    "checklist": [
      {
        "id": "40000000-0000-4000-8000-000000000001",
        "kind": "caption",
        "text": "Add the ad disclosure",
        "excerpt": "Put #ad in the caption.",
        "requiredText": "#ad"
      },
      {
        "id": "40000000-0000-4000-8000-000000000002",
        "kind": "onScreenText",
        "text": "Show the discount code",
        "excerpt": "Show code OAT10 on screen.",
        "requiredText": "OAT10"
      },
      {
        "id": "40000000-0000-4000-8000-000000000003",
        "kind": "shot",
        "text": "Show the oats pack",
        "excerpt": "Show the oats pack in a close-up."
      }
    ],
    "disclosures": ["#ad"],
    "codes": ["OAT10"],
    "unresolved": []
  }
}
```

## E4 · briefCheck

`input` example. Send the reviewed deal checklist, actual caption and on-screen text, known script words and a text list of clips or shots. Empty text fields are valid.

```json
{
  "operation": "briefCheck",
  "language": "English",
  "writingSystem": "Romanised",
  "checklist": [
    {
      "id": "40000000-0000-4000-8000-000000000001",
      "kind": "caption",
      "text": "Add the ad disclosure",
      "excerpt": "Put #ad in the caption.",
      "requiredText": "#ad"
    },
    {
      "id": "40000000-0000-4000-8000-000000000002",
      "kind": "onScreenText",
      "text": "Show the discount code",
      "excerpt": "Show code OAT10 on screen.",
      "requiredText": "OAT10"
    },
    {
      "id": "40000000-0000-4000-8000-000000000003",
      "kind": "shot",
      "text": "Show the oats pack",
      "excerpt": "Show the oats pack in a close-up."
    }
  ],
  "caption": "My breakfast #ad.",
  "onScreenText": "",
  "script": "Here are my oats.",
  "shots": ["Pack close-up is listed in the plan."]
}
```

`job.output` example. Match results to checklist IDs. `met` requires evidence with the exact `requiredText` in the specified field. For script evidence that means the supplied words. Visual, audio and posting checks need separate verification in the app. `missing` supplies no evidence or fix. `can-fix` supplies just the caption or on-screen text to add or use. The app controls whether to apply it.

```json
{
  "checks": [
    {
      "itemID": "40000000-0000-4000-8000-000000000001",
      "status": "met",
      "evidence": {"field": "caption", "excerpt": "#ad"}
    },
    {
      "itemID": "40000000-0000-4000-8000-000000000002",
      "status": "can-fix",
      "fix": {"field": "onScreenText", "text": "Use code OAT10."}
    },
    {"itemID": "40000000-0000-4000-8000-000000000003", "status": "missing"}
  ]
}
```

## E4 · brandNote

`input` example. `postLink` is optional. Send an HTTPS post link when known.

```json
{
  "operation": "brandNote",
  "language": "English",
  "writingSystem": "Romanised",
  "brand": "Morning Oats",
  "itemsDone": ["Published the Reel", "Included the discount code"],
  "postLink": "https://www.instagram.com/reel/example/"
}
```

`job.output` example. Use the result as draft text. The creator sends it in WhatsApp.

```json
{
  "message": "Hi Morning Oats, the Reel is live and includes the discount code. Thanks for working with me!\nhttps://www.instagram.com/reel/example/"
}
```

## E5 · dailyNote

`input` example. Send zero to two snapshots, oldest first. Snapshot counts `followers`, `reach7d` and `saves7d` are optional. Each optional `topPosts` array has up to five objects. Each post has a caption and optional integer `views`, `reach`, `likes`, `comments`, `saves` or `shares`. These post fields also apply to `brandDoc.instagramSummary`. Omit unavailable counts. Send empty arrays if there are no snapshots, open Reels or open deals.

```json
{
  "operation": "dailyNote",
  "language": "English",
  "writingSystem": "Romanised",
  "snapshots": [
    {"saves7d": 12},
    {"saves7d": 27, "topPosts": [{"caption": "My fast mango bowl", "saves": 11}]}
  ],
  "openReels": [{"id": "41000000-0000-4000-8000-000000000001", "title": "My breakfast Reel"}],
  "openDeals": []
}
```

`job.output` example. `action` is exactly one of `{"type":"makeIdea"}`, `{"type":"continueReel","id":"<open Reel UUID>"}`, `{"type":"openDeal","id":"<open deal UUID>"}` or `{"type":"none"}`. Use an empty `buttonText` for `none`. The server checks action IDs against the admitted request. Check a cached action against the app's current open items before showing its button.

```json
{
  "dailyNote": {
    "noticed": "Your latest snapshot shows 27 saves.",
    "action": {"type": "continueReel", "id": "41000000-0000-4000-8000-000000000001"},
    "buttonText": "Continue Reel"
  }
}
```

The first valid start creates the job for the member's UTC day. Later valid starts in that creator and workspace scope return the same job ID, original input and input revision. Always use the returned ID for status or cancel. A new request UUID on the next UTC day can create a new note. The same original request ID still identifies its historical job. A different creator in the same member's daily scope receives HTTP 409 with `daily_note_scope_conflict`. Terminal failures and cancellations are also kept for the day. A queued note from a previous day expires on claim. A claim that expires after its single attempt stays spent.

## Limits and storage

Counts apply per member, operation and UTC claim date. A claim reserves one call before the provider starts. Failures, interruptions, retries and refused remaining-lease checks keep their reservation. The bound applies to server attempts. A provider can continue processing a request after the client times out.

| Operation | Daily attempts | Provider deadline | Lease |
| --- | ---: | ---: | ---: |
| `brandDoc` | 5 | 40 s | 90 s |
| `pickIdea` | 20 | 55 s | 90 s |
| `dealBrief` | 10 | 40 s | 90 s |
| `briefCheck` | 10 | 40 s | 90 s |
| `brandNote` | 10 | 25 s | 90 s |
| `dailyNote` | 1 | 25 s | 90 s |

The worker requires 20 seconds beyond the provider deadline at dispatch. The existing three queued or running jobs and ten new jobs per minute still apply. A new daily note takes one active slot. Cache reuse takes no new slot and goes before the rate checks. Other Phase E jobs can make up to three attempts within their quota. D2 pictures keep their separate cap of 30 reservations per member per UTC day, up to five per card, with a 100-second deadline and 125-second lease.

Migration `20261128030000_mira_phase_e_jobs.sql` adds a service-role-only attempt ledger and reuses private job rows as the daily-note cache. It replaces the bodies of the existing enqueue, claim, transition and picture reservation functions. Both claim signatures remain callable. The only new table starts empty. A replay preserves existing rows. [Migration](../../supabase/migrations/20261128030000_mira_phase_e_jobs.sql)

## Verification

| Check | Result |
| --- | --- |
| Local Supabase and Colima | CLI 2.121.0. All 42 migration versions matched. The local Edge endpoint returned 401 without a device token. The full-schema and pinned PostgreSQL legacy checks passed. |
| Migration undo and replay | Restored the D2 function bodies inside a transaction, applied Phase E twice, and checked job, picture and quota row counts. Anonymous and authenticated SQL roles had no ledger read permission. The transaction rolled back. |
| TesterArmy API | 0.15.2 with Node 22.23.2. **36 passed, 2 hosted scenarios skipped.** Covered validation, literal codes, untrusted payloads, no-data paths, legacy status, caps, races, retry accounting, same-day cache, UTC rollover, cancellation, signed pictures and opt-in progress. Provider responses and device sessions use fixtures. The quota and cache scenarios use real local PostgREST and PostgreSQL. |
| TLC v1.7.4 | `MiraPhaseELimits` passed on 7,571,119 distinct states. The daily one-attempt job passed on 10,786 states. The D2 job, slot and picture models also passed on 41,990, 11,615 and 7,876 states. The new limits model uses two UTC days and a reduced text cap. The SQL and API runs check the actual caps. |
| Backend source and contract | `deno task ci:backend` passed with Deno 2.8.1. All six request and result examples passed the server schemas. All seven agent-rule groups passed. The proof script rejected all 14 historical reproductions. |

Artifacts are in `work/evidence/mira-phase-e-server/20261127T211041Z.DkmA4s/`. Use `api-handoff/report.json`, `undo-and-replay.log`, `migrations.json`, the TLC output files, and the backend and agent-rule logs. The checkout's ignored work directory holds the evidence because the shared evidence volume was unavailable. Supabase and Colima stopped with the database and Storage volumes retained.

MIRA-033 started at `2026-11-27T21:11:29.460Z`. The final verification update was confirmed at `2026-11-27T21:23:43.740Z`. The task is Working pending review and rollout. The Phase E branch remains local. [Mira tracker](https://mira-build-progress-production.up.railway.app)

### Reproduce

Use the local Colima profile. Keep shell tracing off. If local dependency setup is needed, use the existing lockfile with `npm ci --ignore-scripts`.

```sh
colima start --profile mira-s4-20261127
export DOCKER_HOST="unix://$HOME/.colima/mira-s4-20261127/docker.sock"
supabase start -x vector >/dev/null
supabase migration up --local
supabase migration list --local
docker exec -i supabase_db_trying-to-create-an-aesthetically-pleasi \
  psql -U postgres -d postgres -X -v mira_full_schema=1 \
  <supabase/functions/mira-generation/jobs_test.sql
python3 scripts/mira-sql-check.py
deno task ci:backend
python3 scripts/check-agent-rules.py
python3 scripts/prove-agent-rules.py

phase_e_local=$(supabase status -o json)
export MIRA_API_E2E_LOCAL_SERVICE_ROLE=$(jq -er .SERVICE_ROLE_KEY <<<"$phase_e_local")
export MIRA_API_E2E_LOCAL_ANON=$(jq -er .ANON_KEY <<<"$phase_e_local")
unset phase_e_local
export MIRA_API_E2E_LOCAL_PORT=54321 MIRA_API_E2E_LIVE=0 MIRA_API_E2E_LIVE_TODAY=0
export MIRA_API_E2E_OUTPUT="$PWD/work/evidence/phase-e-repro"
npx e2e run --config e2e.mira-api.config.ts
unset MIRA_API_E2E_LOCAL_SERVICE_ROLE MIRA_API_E2E_LOCAL_ANON MIRA_API_E2E_LOCAL_PORT

supabase stop
colima stop --profile mira-s4-20261127
```

Run TLC with Java and the v1.7.4 jar, SHA-1 `bee4a54f3ee3d4afc347c3240ec2d9e93b075104`. Run `MiraPhaseELimits.cfg` with `MiraPhaseELimits.tla`, and `MiraJobs-DailyNote.cfg` with `MiraJobs.tla`. [TLC release](https://github.com/tlaplus/tlaplus/releases/tag/v1.7.4) · [Phase E model](tla-e/)

```sh
java -XX:+UseParallelGC -cp "$TLC_JAR" tlc2.TLC -workers 1 -deadlock \
  -metadir work/evidence/tlc-phase-e-repro \
  -config docs/mira-evidence/tla-e/MiraPhaseELimits.cfg \
  docs/mira-evidence/tla-e/MiraPhaseELimits.tla
```

## Live steps for Claude

1. Review the added data fields, output validation, quota rules and app permission copy. Obtain review before shipping.
2. In the authorized release checkout, confirm the project ref. Use `supabase db push --linked --dry-run` after linking. Confirm that the Phase E migration is the only pending change. Apply it and verify the migration history before deploying `mira-generation`.
3. Smoke-test an old status payload and the six new operations with the approved QA context. Check a pick with and without picture opt-in. Repeat a daily-note request with a new UUID and verify that usage increases once. Use a separate QA member or a new UTC day for another daily-note provider call.
4. Capture provider latency, validation failures, consent behavior and visual result quality. Verify GitHub commit links before adding them to MIRA-033.

Use these commands in the authorized release checkout. Review the dry-run output before starting the second block.

```sh
supabase link --project-ref "$MIRA_PROJECT_REF"
supabase db push --linked --dry-run
```

```sh
supabase db push --linked
supabase migration list --linked
supabase functions deploy mira-generation --project-ref "$MIRA_PROJECT_REF"
supabase functions list --project-ref "$MIRA_PROJECT_REF"
```

### Undo SQL

Restore the D2 Edge revision before running the undo. Use a transaction with the SQL in the linked file. It restores the D2 functions and leaves the ledger, jobs, pictures and storage objects available. Record the rollback with the release migration history before reapplying Phase E. [Undo SQL](2026-11-28-phase-e-server-undo.sql)

```sql
begin;
\i docs/mira-evidence/2026-11-28-phase-e-server-undo.sql
commit;
```

## Verification limits

**Real outputs not verified.** This run made zero real AI calls. Live Supabase, provider quality and cost, app consent and decoding, and native flows remain for Claude's rollout and the app phases. The server uses supplied text and metadata for brief checks. The app handles clip matching and video review.
