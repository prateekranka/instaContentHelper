# Mira Phase D2 server evidence and app handoff

Branch `claude/mira-d2-server` started at `9809976`, the verified GitHub `main` tip at the start of this work. It contains S4. The [failure modes](2026-11-27-phase-d2-server-failure-modes.md) were committed before implementation. D2 changed server code, migration, checks and documentation.

## App contract

Send the existing authenticated POST to `/functions/v1/mira-generation`. Use the existing device token and Supabase publishable key. Start each Today card with today's usual `todayIdea` input, input revision and consent version 1. Poll that card with this body.

```json
{
  "action": "status",
  "id": "10000000-0000-4000-8000-000000000101",
  "creatorID": "10000000-0000-4000-8000-000000000002"
}
```

Working response after the provider completes the script.

```json
{
  "job": {
    "id": "10000000-0000-4000-8000-000000000101",
    "inputRevision": 1,
    "input": {
      "operation": "todayIdea",
      "angle": "Quick breakfast",
      "profile": {
        "name": "Creator",
        "themes": "Food",
        "audience": "Friends",
        "language": "English",
        "writingSystem": "Romanised",
        "tone": "Warm",
        "avoid": "",
        "samples": "",
        "solo": true
      },
      "constraints": {
        "filmingMinutes": 15,
        "location": "Kitchen",
        "style": "Either",
        "reelSeconds": 20,
        "equipment": "Phone and books"
      },
      "request": "Plan a quick breakfast Reel.",
      "recentIdeas": []
    },
    "state": "working",
    "phase": "running",
    "step": "script_ready"
  }
}
```

Successful response with one ready picture, one in progress, and one failed picture. The URL below illustrates the signed route with a placeholder token.

```json
{
  "job": {
    "id": "10000000-0000-4000-8000-000000000101",
    "inputRevision": 1,
    "input": {
      "operation": "todayIdea",
      "angle": "Quick breakfast",
      "profile": {
        "name": "Creator",
        "themes": "Food",
        "audience": "Friends",
        "language": "English",
        "writingSystem": "Romanised",
        "tone": "Warm",
        "avoid": "",
        "samples": "",
        "solo": true
      },
      "constraints": {
        "filmingMinutes": 15,
        "location": "Kitchen",
        "style": "Either",
        "reelSeconds": 20,
        "equipment": "Phone and books"
      },
      "request": "Plan a quick breakfast Reel.",
      "recentIdeas": []
    },
    "state": "succeeded",
    "phase": "succeeded",
    "step": "storyboard_ready",
    "output": {
      "ideas": [{
        "id": "20000000-0000-4000-8000-000000000001",
        "title": "Quick breakfast",
        "hook": "Make breakfast with me.",
        "visual": "Show the bowl from overhead.",
        "fit": "One person can film this in the kitchen.",
        "filmingMinutes": 10,
        "setup": "Put the phone against a stack of books."
      }],
      "script": {
        "id": "20000000-0000-4000-8000-000000000002",
        "hook": "Make breakfast with me.",
        "spoken": "Add fruit to the bowl. Breakfast is ready.",
        "caption": "A quick breakfast.",
        "durationSeconds": 20,
        "language": "English"
      },
      "storyboard": {
        "id": "20000000-0000-4000-8000-000000000003",
        "sourceScriptID": "20000000-0000-4000-8000-000000000002",
        "requirementsRevision": 0,
        "shots": [
          {
            "id": "30000000-0000-4000-8000-000000000001",
            "purpose": "Introduce breakfast",
            "editedSeconds": 6,
            "recordingSeconds": 10,
            "location": "Kitchen",
            "props": "Bowl",
            "placement": "Prop the phone against books.",
            "distance": "One arm’s length",
            "framing": "Head and shoulders",
            "frameType": "headShoulders",
            "action": "Hold up the bowl.",
            "words": "Make breakfast with me.",
            "voiceover": false,
            "onScreenText": "",
            "simplerAlternative": "Keep the bowl on the table."
          },
          {
            "id": "30000000-0000-4000-8000-000000000002",
            "purpose": "Show the fruit",
            "editedSeconds": 9,
            "recordingSeconds": 12,
            "location": "Kitchen",
            "props": "Fruit and bowl",
            "placement": "Prop the phone next to the bowl.",
            "distance": "Half an arm’s length",
            "framing": "Hands and bowl",
            "frameType": "closeUp",
            "action": "Put fruit in the bowl.",
            "words": "Add fruit to the bowl.",
            "voiceover": true,
            "onScreenText": "",
            "simplerAlternative": "Keep the camera level with the table."
          },
          {
            "id": "30000000-0000-4000-8000-000000000003",
            "purpose": "Show the finished breakfast",
            "editedSeconds": 5,
            "recordingSeconds": 7,
            "location": "Kitchen",
            "props": "Bowl",
            "placement": "Prop the phone against the same books.",
            "distance": "One arm’s length",
            "framing": "Bowl and hands",
            "frameType": "closeUp",
            "action": "Slide the bowl forward.",
            "words": "Breakfast is ready.",
            "voiceover": true,
            "onScreenText": "",
            "simplerAlternative": "Hold the bowl still."
          }
        ],
        "mappings": []
      },
      "conflicts": []
    },
    "pictures": [
      {
        "shotID": "30000000-0000-4000-8000-000000000001",
        "status": "ready",
        "url": "https://example.supabase.co/storage/v1/object/sign/mira-shot-pictures/10000000-0000-4000-8000-000000000101/30000000-0000-4000-8000-000000000001.jpg?token=example"
      },
      { "shotID": "30000000-0000-4000-8000-000000000002", "status": "pending" },
      { "shotID": "30000000-0000-4000-8000-000000000003", "status": "failed" }
    ]
  }
}
```

| Optional field or value | App handling |
| --- | --- |
| No `step` | Show the initial wait state while the job works. A non-streaming provider, a retry, an expired claim, a failure or a cancellation has no step. |
| `step: "idea_ready"` | Mark “Finding an idea” done. Show “Writing your words” in progress. |
| `step: "script_ready"` | Mark the idea and words done. Show “Planning shots” in progress. The final script and shot count arrive in `output`. |
| `step: "storyboard_ready"` | Mark all three parts done. Wait for terminal success before opening the card. |
| `pictures` missing or no entry for a shot | Use the drawn fallback. Old cards and cards with previews disabled have no list. A temporary picture lookup error can also omit it. |
| Picture `status: "pending"` | Use the drawn fallback. Continue status requests for this card while the previews are needed. |
| Picture `status: "ready"` | Match by `shotID` and load the signed URL with GET. If it expires or fails, request status again to refresh it. |
| Picture `status: "failed"` | Use the drawn fallback. The server does not try that picture again. |

Both additions are optional keys on `job`. `id`, `inputRevision`, `input`, `state`, `phase`, `output` and `error` preserve their S4 meanings. `state: "succeeded"` makes the card usable regardless of picture status. Each response reports a snapshot; one response can skip intermediate steps if several parts arrive between polls. A new text claim can start the steps again. Responses use `Cache-Control: no-store`. Signed URLs last one hour from signing. Treat them as temporary credentials.

## OpenAI request changes for review

| Before D2 | After D2 |
| --- | --- |
| OpenAI Chat Completions returns one JSON response. | The same request adds `stream: true`. The adapter reads content deltas. It requires `finish_reason: "stop"` and `[DONE]` before final JSON and contract validation. |
| Today returns a card after all text passes validation. | The prompt requests idea, script and storyboard in that order. The scanner checks complete top-level JSON fields against their schemas. It writes only when the furthest completed step advances. Each write matches the active lease. |
| The server sends no OpenAI image requests for Today. | One text-only Images API request uses the shot’s location, props, camera position, distance, framing and action. The prompt asks for a generic subject. The request contains no photo, Instagram payload, profile fields, script, or spoken lines. |

DeepSeek and Gemini keep their non-streaming text paths. A transport cut uses S4 retry and backoff. Invalid output and refused or truncated answers take the validation-failure path. The existing consent says the listed providers help write ideas and make pictures. [Consent source](../../CreatorContentOS/Features/Privacy/AIConsentCopy.swift), [OpenAI streaming reference](https://developers.openai.com/api/reference/resources/chat/subresources/completions/streaming-events/)

## Pictures, limits and cost

- Operation `shotPictures` uses a separate table with one job per shot. The first non-cancel request that reads a succeeded Today card reserves its previews and starts the jobs in the background. This includes the request that first shows success to an existing app. A card that nobody reads after text finishes starts its previews when a later request reads it.
- `MIRA_IMAGE_MODEL` defaults to `gpt-image-2.6-flare`. `MIRA_PICTURES_PER_CARD` accepts 0 to 5 and defaults to 5. An invalid count or missing `OPENAI_API_KEY` disables previews for newly completed cards. The server records the count when text finishes. The default covers all three to five shots on each card. With three shots per card, one Today request uses nine pictures.
- Flare uses `quality: "low"`, `complexity: "low"`, `size: "720x1280"`, `output_format: "jpeg"` and `output_compression: 75`. This is the smallest exact 9:16 size that meets the documented pixel minimum and 16-pixel dimension rule. [OpenAI image generation guide](https://developers.openai.com/api/docs/guides/image-generation), [Flare model](https://developers.openai.com/api/docs/models/gpt-image-2.6-flare)
- Each picture request has a 100-second deadline from `job-policy.ts`, including the response body. The claim grants 125 seconds. The worker requires at least 120 seconds remaining before every call. This gives 20 seconds after the provider deadline and five seconds to receive the claim. A card runs at most five requests in parallel and uploads each JPEG when it arrives. The worker starts from a separate status request after text generation completes. Supabase lists a 150-second free-plan and 400-second paid-plan worker lifetime. A reused worker can have less time remaining, so the next status request also reconciles expired claims. [Supabase Edge limits](https://supabase.com/docs/guides/functions/limits)
- The primary key and a per-member transaction lock reserve each shot once. The worker uploads to a deterministic path with overwrite disabled. If the upload succeeded and its status write was lost, the next status request after lease expiry checks Storage and returns the saved image without another provider call. An expired reservation with no file becomes failed. Ambiguous failures use the drawn fallback and keep their reservation.
- A member can reserve 30 pictures per UTC day. The cap includes failed or interrupted attempts and applies across cards and devices. The original three active text jobs and ten text starts per minute still apply. Picture rows use neither text allowance. The private `mira-shot-pictures` bucket accepts JPEGs up to 2 MiB. The service role owns metadata and object writes. Device clients only receive signed URLs after a scoped status request.
- The local provider fixture made no billable calls. Actual image quality, latency and per-picture cost are unverified. Public standard Flare rates are USD 5 per million uncached text input tokens and USD 30 per million image output tokens. Measure with actual usage from the approved QA run. The 1–5 cent estimate in the brief has no measured basis in this run. [Flare pricing](https://developers.openai.com/api/docs/models/gpt-image-2.6-flare)

## Migration and undo SQL

[`20261127200000_mira_steps_and_shot_pictures.sql`](../../supabase/migrations/20261127200000_mira_steps_and_shot_pictures.sql) adds two nullable fields, the picture reservation table, its RPC, and the private bucket and policy. The migration leaves existing job rows readable. It resets step only on a new claim. During a valid lease the S4 trigger allows a forward step with the same job fields except `updated_at`. All other S4 grants and transitions still apply. The migration takes a brief DDL lock on the jobs table.

After approval, restore the S4 Edge function first. Then run the data-preserving undo below. It restores the S4 claim and trigger and disables picture claims. Keep the pictures, bucket, policy and added columns to preserve data. Follow the authorized release process to record the rollback and reapply the D2 SQL if needed.

```sql
begin;

revoke execute on function public.mira_claim_shot_pictures(uuid, uuid, integer) from service_role;

create or replace function public.mira_claim(p_id uuid, p_lease_seconds integer)
returns setof public.mira_generation_jobs language plpgsql security definer set search_path = public as $$
begin
  if p_lease_seconds is null or p_lease_seconds < 90 then
    raise exception using errcode = '22023', message = 'mira_lease_too_short';
  end if;

  update public.mira_generation_jobs
    set status = 'failed', error = 'worker_interrupted_retry_limit', updated_at = clock_timestamp()
    where id = p_id and status = 'running' and lease_until <= clock_timestamp() and attempts >= 3;

  return query update public.mira_generation_jobs
    set status = 'running', attempts = attempts + 1, lease_id = gen_random_uuid(),
        lease_until = clock_timestamp() + make_interval(secs => p_lease_seconds), updated_at = clock_timestamp()
    where id = p_id and attempts < 3 and next_attempt_at <= clock_timestamp()
      and (status = 'queued' or (status = 'running' and lease_until <= clock_timestamp()))
    returning *;
end $$;

create or replace function public.mira_enforce_job_transition()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.status = 'running'
     and (old.status = 'queued' or (old.status = 'running' and old.lease_until <= clock_timestamp()))
     and old.attempts < 3 and new.attempts = old.attempts + 1
     and old.next_attempt_at <= clock_timestamp()
     and new.lease_id is not null and new.lease_id is distinct from old.lease_id
     and new.lease_until > clock_timestamp() then
    return new;
  end if;

  if new.attempts = old.attempts
     and new.lease_id is not distinct from old.lease_id
     and new.lease_until is not distinct from old.lease_until
     and (
       (old.status = 'queued' and new.status in ('failed', 'cancelled'))
       or (old.status = 'running' and new.status in ('succeeded', 'failed', 'cancelled'))
       or (old.status = 'running' and new.status = 'queued' and old.attempts < 3)
     ) then
    return new;
  end if;

  raise exception using errcode = '23514', message = 'mira_invalid_job_transition',
    detail = format('%s -> %s', old.status, new.status);
end $$;

commit;
```

## Local verification

Use the existing local Colima profile and the Supabase CLI from this clone. The commands preserve the database volume. Keep shell tracing off.

```sh
colima start --profile mira-s4-20261127
export DOCKER_HOST="unix://$HOME/.colima/mira-s4-20261127/docker.sock"
supabase start -x vector >/dev/null
supabase migration up --local
supabase migration list --local
docker exec -i supabase_db_trying-to-create-an-aesthetically-pleasi psql -U postgres -d postgres -X -v mira_full_schema=1 < supabase/functions/mira-generation/jobs_test.sql
python3 scripts/mira-sql-check.py
deno task ci:backend
python3 scripts/check-agent-rules.py
python3 scripts/prove-agent-rules.py

d2_local_config=$(supabase status -o json)
export MIRA_API_E2E_LOCAL_SERVICE_ROLE=$(jq -er .SERVICE_ROLE_KEY <<<"$d2_local_config")
export MIRA_API_E2E_LOCAL_ANON=$(jq -er .ANON_KEY <<<"$d2_local_config")
unset d2_local_config
export MIRA_API_E2E_LOCAL_PORT=54321 MIRA_API_E2E_LIVE=0 MIRA_API_E2E_LIVE_TODAY=0
export MIRA_API_E2E_OUTPUT="$PWD/work/evidence/d2/repro-api"
npx e2e run --config e2e.mira-api.config.ts
unset MIRA_API_E2E_LOCAL_SERVICE_ROLE MIRA_API_E2E_LOCAL_ANON MIRA_API_E2E_LOCAL_PORT

supabase stop
colima stop --profile mira-s4-20261127
```

The artifacts for this run are in `work/evidence/d2/20261127T201709Z.rUllrd/`. The final TesterArmy report is `api-handoff/report.json` in that directory. Use Java with the [TLC v1.7.4 jar](https://github.com/tlaplus/tlaplus/releases/tag/v1.7.4), SHA-1 `bee4a54f3ee3d4afc347c3240ec2d9e93b075104`. Use the matching configuration and module in [tla-d2](tla-d2). Example command from the root of this clone.

```sh
/opt/homebrew/opt/openjdk/bin/java -XX:+UseParallelGC \
  -cp work/evidence/d2/20261127T201709Z.rUllrd/tla2tools.jar tlc2.TLC -workers 1 -deadlock \
  -metadir work/evidence/d2/repro-tlc \
  -config docs/mira-evidence/tla-d2/MiraShotPictures.cfg \
  docs/mira-evidence/tla-d2/MiraShotPictures.tla
```

| Check | Observed result |
| --- | --- |
| TLC S4 job model with D2 progress | Passed on 41,990 distinct states. The short-lease refusal passed on 372 states. The three negative configs produced the expected forbidden-transition, overlap or lost-result counterexamples. |
| TLC `MiraShotPictures` and `MiraTodayLimit` | Passed on 7,876 and 11,615 distinct states. The picture model abstracts four shots and a cap of three to cover cap saturation, claim loss, object recovery and text-slot independence. |
| Supabase CLI 2.121.0 local migrations and SQL | All 41 migrations applied. The full-schema and pinned PostgreSQL runs passed. The cap test reserved 30 and rejected the overflow. The local Edge endpoint returned 401 for a request without a device token. The undo SQL and two replays preserved jobs and objects in a rolled-back transaction. |
| Deno 2.8.1 backend check | Passed. |
| TesterArmy 0.15.2, Node 22.23.2 | 17 passed. Two hosted scenarios skipped. The fixture supplies provider responses. Local Supabase supplies real SQL, PostgREST and private Storage for three scenarios. Signed-only fetch, lost-status recovery, concurrent cap, active text slots and guarded transitions passed. |
| Agent rules | All seven groups passed. The proof script rejected 14 historical or reconstructed mistakes. |

Supabase and the dedicated Colima profile stopped. The local database and Storage volumes are present.

The public tracker recorded MIRA-032 as Working at `2026-11-27T20:17:48.014Z`. The verification update landed at `2026-11-27T20:27:23.731Z`. The branch remains local. [Mira tracker](https://mira-build-progress-production.up.railway.app)

## Live steps for Claude after Bobby approves

1. Review the OpenAI request changes above. Confirm the intended project and the isolated QA workspace. Confirm the QA picture budget before any paid calls.
2. Link the approved checkout. Verify the migration plan and confirm that D2 is the only pending migration.

   ```sh
   supabase link --project-ref "$MIRA_PROJECT_REF"
   supabase db push --linked --dry-run
   supabase db push --linked
   supabase migration list --linked
   ```

3. Verify the bucket, policy and claim RPC in SQL Editor.

   ```sql
   select id, public, file_size_limit, allowed_mime_types
     from storage.buckets where id = 'mira-shot-pictures';
   select policyname, permissive, roles from pg_policies
     where schemaname = 'storage' and tablename = 'objects'
       and policyname = 'mira_shot_pictures_private';
   select to_regprocedure('public.mira_claim_shot_pictures(uuid,uuid,integer)');
   ```

   Expect a private bucket, a 2 MiB JPEG limit, a restrictive policy, and the new RPC signature.
4. Check `OPENAI_API_KEY` privately and confirm its account can use Flare. The hosted runtime supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. For real steps, select `MIRA_AI_PROVIDER=openai` and keep the reviewed text model setting. Keep the image defaults unless Bobby approves overrides. If secrets require changes, use an ignored env file and record only the setting names.

   ```sh
   supabase secrets set --project-ref "$MIRA_PROJECT_REF" --env-file "$MIRA_PRIVATE_ENV_FILE"
   supabase functions deploy mira-generation --project-ref "$MIRA_PROJECT_REF"
   supabase functions list --project-ref "$MIRA_PROJECT_REF"
   ```

5. Run the existing Today QA scenario only if its pinned endpoint matches the approved project. It starts three cards. The default setting can reserve up to 15 pictures. Set the existing QA credentials in the environment and keep the report private.

   ```sh
   mkdir -p work/evidence/d2-live
   MIRA_API_E2E_LIVE=0 MIRA_API_E2E_LIVE_TODAY=1 MIRA_API_E2E_EXPECT_STEPS=1 MIRA_API_E2E_LOCAL_PORT= \
     MIRA_API_E2E_LIVE_TODAY_PATH="$PWD/work/evidence/d2-live/today.json" \
     MIRA_API_E2E_OUTPUT="$PWD/work/evidence/d2-live/api" \
     npx e2e run --config e2e.mira-api.config.ts
   ```

6. Use each recorded card ID to send the status body above with the same QA creator and device token. Continue while any picture is pending. Verify the signed JPEG and reject an unsigned download. The Today report records observed steps and timestamps. Redact signed URLs and credentials from evidence. Review the provider usage and Edge logs for cost, failure rate and lease refusals.
7. Verify the published GitHub commit links before attaching them to the public tracker.

## Limits and documentation differences

- Real streaming and pictures not verified. The approved ignored env paths had no OpenAI key. No provider requests ran against OpenAI. Hosted migration, hosted worker lifetime, app decoding at runtime, visual quality and measured cost remain open.
- The README describes the generation backend as deployment-unverified and shows `supabase stop --no-backup`. The task brief establishes the S4 live baseline. This run used `supabase stop` to preserve volumes.
- The D1 handoff gives the model family and Flare tier. The documented API model ID is `gpt-image-2.6-flare`.
- Use the original S4 rules for backoff and cancellation. The D2 picture recovery path applies only to reserved shots.
