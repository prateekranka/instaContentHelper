# Astra review fixes for Mira server

Base revision `1d78683`. Work started on 28 November 2026 IST. The API scenarios use local Supabase and fixture provider responses.

## Failure modes

| Finding | Failure to prevent |
| --- | --- |
| M05 | A board adds, omits, repeats or reorders dialogue. A single-shot revision hides a coverage gap in the merged board. A correct board fails when the validator counts a hook that is already in `script.spoken` twice. |
| M07 | Stop observes no admitted row, then start dispatches a paid call. A stop from a different member or creator affects the wrong scope. |
| M08 | A validated result is lost during a database write or the terminal update fails. A later claim spends another provider call or daily attempt. |
| M09 | A direct update admits a lease shorter than 90 seconds or writes a terminal row without the required payload. |
| M10 | A differently cased shot ID prevents dispatch. A reservation that expires or fails before dispatch uses the member's picture allowance. |
| M11 | A status poll records failure before the upload commits. Later polls fail to return the saved image. |
| M12 | A count from one metric is used to support a different metric. |
| M20 | A new migration weakens a lease while the checks still inspect the old SQL. |

## Fixes and regression evidence

| Finding | Fix | API regression |
| --- | --- | --- |
| M05 | Match the ordered shot dialogue to `script.spoken` when it starts with the hook. Prepend separately stored hooks. Normalize whitespace and curly quotes. Check a single-shot revision after merging it into the source board. | Accept a recorded Today response, a separately stored hook, and the permitted quote and whitespace changes. Reject substituted, missing, repeated and reordered words. Cover `storyboard`, `reviseStoryboard`, `reviseShot`, `todayIdea` and `pickIdea`. |
| M07 | Record Stop before admission in a private table keyed by job, workspace, creator and member. Serialize Stop, admission and claim for the member. Preserve the 404 for Stop before admission. | Repeat Stop before start. The late start receives 409, with zero provider calls and zero daily attempts. A different member can use that UUID in a separate scope. |
| M08 | Record dispatch before the provider call. Save the validated output and picture count before marking success. A later claim finishes staged output without another attempt. | Inject a failed result write and a failed success update through PostgREST. The next status completes the job. Check one provider call, one claim and one daily attempt. |
| M09 | Check the 90-second lease floor in the transition trigger. Require output on success and error on failure. | Reject a direct short claim and both missing payloads. Check the normal claim and failure paths. Existing scenarios cover retries, Stop, expiry, progress, pictures, Daily Note and caps. |
| M10 | Compare shot UUIDs without case. Count started pictures and valid reservations. Release capacity when a tracked reservation fails or expires before dispatch. | Return ready signed pictures for an uppercase UUID. Fill the cap, then release two unstarted reservations. A new card can reserve two shots. |
| M11 | Let the worker finish its original upload after expiry. Status also checks Storage for a failed lease with a saved object. | Hold the real Storage upload across expiry. Observe failed status, release the upload, and block the worker's ready update. Status recovers a signed JPEG after one image call. |
| M12 | Check each reported count against the metric named next to it. The prompt gives count-first examples in English and Hindi. | Reject 27 followers when 27 belongs to saves. Accept the supplied saves and views counts in Devanagari. |
| M20 | Apply all Mira migrations in version order in the PostgreSQL check. Resolve the latest SQL body of each lease function in the source rule. | Weaken the latest text claim floor to 89 seconds in a temporary copy. The proof reports a violation in the new migration. |

The provider prompts require verbatim, ordered coverage of the spoken script. They require a supplied count next to its metric name. These checks apply before the server accepts a result. The API scenarios use fixture responses. Claude must review the OpenAI prompt and validation changes before deployment.

## Migration and recovery

[20261128040000_mira_astra_server_fixes.sql](../../supabase/migrations/20261128040000_mira_astra_server_fixes.sql) adds a scoped cancellation table and dispatch fields. It replaces the admission, claim, transition and picture rules. The column defaults preserve existing rows without a backfill. The transaction check restored the prior SQL, applied the new migration twice, checked grants, and rolled back. Job, cancellation, picture, quota and Storage record counts matched.

The previous three-argument picture claim remains callable during deployment. It uses the previous reservation accounting because its worker does not report dispatch. Historical picture rows also retain that accounting. New picture requests track dispatch. The text claim accepts 90 seconds and allocates up to one extra second for the database trigger check when the caller requests that floor.

If all writes of a valid text result fail and no output reaches the database, an expired dispatched job fails. The database uses the dispatch record to prevent a second provider call. A provider error reported by the worker can still use the existing bounded retry policy. An older running row without a dispatch record keeps the prior lease recovery behavior.

## First review verification

| Check | Result |
| --- | --- |
| Baseline TesterArmy API | On `1d78683` with the prior local schema, all nine new regression scenarios failed. M10 has two scenarios. |
| Fixed TesterArmy API | **45 passed, 2 hosted cases skipped**. TesterArmy 0.15.2, Node 22.23.2, local Supabase CLI 2.121.0. The suite uses real local PostgREST, PostgreSQL and Storage for the database and image recovery cases. |
| Local migration and undo | All 43 local versions matched. The undo and two replays preserved all five record counts. Anonymous and authenticated grants stayed restricted. |
| SQL contracts | `python3 scripts/mira-sql-check.py` passed with all six Mira migrations. The local Supabase schema contract also passed. |
| Backend | `deno task ci:backend` passed with Deno 2.8.1. The local Edge endpoint returned 401 without a device session. |
| Source and documentation rules | Eight rule groups passed. The proof rejected all 19 reproductions, including the weakened floor in `20261128040000`. The state-machine check found 70 cases in 11 Swift enums with zero mismatches. |
| TLC v1.7.4 | Five positive configurations passed. All 13 negative configurations produced the required violation. The new negative cases cover Stop before admission, a second attempt after a valid result, and failed status after a late upload. |

The local logs and reports are in `work/evidence/mira-astra-server-fixes/20261127T232121Z.MD87mm/`. Use `baseline-verified.out`, `baseline-source/work/baseline-verified/report.json`, `api-final/report.json`, `sql-current.out`, `sql-full.out`, `replay.sql`, `undo-replay.out`, `rule-proof.out` and `tla.out`. The shared evidence volume was unavailable, so this checkout holds the artifacts.

The public tracker confirmed local verification at `2026-11-27T23:34:15.601Z`. MIRA-035 remains Working pending Claude review and rollout. [Mira tracker](https://mira-build-progress-production.up.railway.app)

### Reproduce locally

Use the existing Colima profile and repository test dependencies. Keep shell tracing off. The API configuration keeps report output inside the checkout. Run `deno task ci:backend`, the two agent-rule scripts, the state-machine check, and `bash specs/tla/run.sh` from the repository root.

```sh
colima start --profile mira-s4-20261127
export DOCKER_HOST="unix://$HOME/.colima/mira-s4-20261127/docker.sock"
supabase start -x vector >/dev/null
supabase migration up --local
python3 scripts/mira-sql-check.py
docker exec -i supabase_db_trying-to-create-an-aesthetically-pleasi \
  psql -U postgres -d postgres -X -v mira_full_schema=1 \
  <supabase/functions/mira-generation/jobs_test.sql

local_status=$(supabase status -o json)
export MIRA_API_E2E_LOCAL_SERVICE_ROLE=$(jq -er .SERVICE_ROLE_KEY <<<"$local_status")
export MIRA_API_E2E_LOCAL_ANON=$(jq -er .ANON_KEY <<<"$local_status")
unset local_status
export MIRA_API_E2E_LOCAL_PORT=54321 MIRA_API_E2E_LIVE=0 MIRA_API_E2E_LIVE_TODAY=0
export MIRA_API_E2E_OUTPUT="$PWD/work/evidence/astra-api-repro"
npx e2e run --config e2e.mira-api.config.ts
unset MIRA_API_E2E_LOCAL_SERVICE_ROLE MIRA_API_E2E_LOCAL_ANON MIRA_API_E2E_LOCAL_PORT

supabase stop
colima stop --profile mira-s4-20261127
```

To check the first review baseline, use a detached checkout at `1d78683`. Copy the API test and its two Mira fixture files from `fce1ce3`. Use the schema through `20261128030000`. Run the same API command with `--grep '^M(05|07|08|09|10|11|12|20)'`.

## M05 review round 2

Claude found that the first review fix rejected correct Today responses. All nine recorded Today outputs matched normalized `script.spoken`. Adding `script.hook` again produced zero matches. The [regression fixture](../../tests/fixtures/mira-recorded-today.json) contains the script and storyboard from one recorded response.

The previous validator always prepended `script.hook`. The updated validator uses `script.spoken` directly if it starts with the normalized hook. It prepends the hook for older scripts that keep it separate. The speech-rate check also uses this dialogue. The prompts ask for new `script.spoken` text that starts with the hook and for shot words that reproduce the full script in order.

- On `fce1ce3`, the new recorded-response scenario failed with `shot_words_script_coverage`. The same scenario passed after the fix. The existing M05 scenario also passed. It rejected all eight invalid responses and accepted a script with a separately stored hook.
- TesterArmy API reported **46 passed and 2 hosted scenarios skipped**. The first full run found that the Storage scenario reused a local member with an exhausted picture allowance. That scenario now uses a fresh local member.
- `deno task ci:backend` passed. All eight source rule groups passed. The proof rejected all 19 reproductions. The state-document check found zero mismatches.
- `bash specs/tla/run.sh` passed all five positive configurations and found all 13 expected violations. All 43 local migration versions matched. Supabase and Colima stopped with the database and Storage volumes retained.

Repeat the commands above with `MIRA_API_E2E_LIVE=0` and `MIRA_API_E2E_LIVE_TODAY=0`. To reproduce the baseline failure on `fce1ce3`, copy the updated API test and all three Mira fixtures. Run the API command with `--grep '^M05 accepts a recorded Today script'`.

Evidence is in `work/evidence/mira-astra-server-review-r2/20261127T234419Z.gta9NW/`. Use `recorded-coverage.json`, `api-baseline/report.json`, `api-final/report.json`, `deno.err`, `rules.out`, `prove.out`, and `tla.out`. The run used TesterArmy 0.15.2, Node 22.23.2, Deno 2.8.1, Supabase CLI 2.121.0 and TLC 1.7.4. The public tracker confirmed the round 2 result at `2026-11-27T23:47:11.697Z`. MIRA-035 is Working pending Claude review.

## Live steps for Claude

1. Review this branch and the prompt and validation changes. Confirm the live project has migrations through `20261128030000`.
2. In the authorized release checkout, link the intended project and run the dry run. Confirm that `20261128040000` is the only pending migration for this release.
3. Apply the migration and verify its history. Deploy `mira-generation` from the same reviewed revision.
4. Use the authorized QA member to smoke-test Stop before admission, generated dialogue, a signed picture and a grounded Daily Note. Check status and quota use.
5. Verify published GitHub commit links before adding them to MIRA-035. The tracker recorded the start at `2026-11-27T23:21:36.092Z`.

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

If a rollback is necessary, drain jobs with saved output and active picture uploads. Redeploy the previous Edge revision before restoring the previous SQL. Run this from the repository root in the authorized database's `psql` session. The undo includes the Phase E SQL and drops the new RPC signatures. It retains the new table, columns, job data, quota records and pictures. The previous admission function ignores the retained Stop records. Record the rollback in migration history before reapplying.

```sql
\set ON_ERROR_STOP on
begin;
\i docs/mira-evidence/2026-11-28-astra-server-fixes-undo.sql
commit;
```

The live Supabase project and real providers were outside this run. Swift and native behavior were outside the server scope. Local Supabase and Colima stopped with their volumes retained.
