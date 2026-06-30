# Hosted Supabase Function Logs From the CLI

Status: Deferred, non-blocking tooling improvement

## Goal

Provide a repeatable local command for querying hosted Supabase Edge Function logs without opening the Dashboard.

Example target interface:

```sh
scripts/supabase-function-logs.sh generate-week --since 30m
```

The command should support:

- `function_logs` for internal Edge Function `console` output.
- `function_edge_logs` for invocation status, timing, and HTTP metadata.
- Filtering by function name, generation ID, and bounded time range.
- Human-readable output for investigation and JSON output for QA evidence.

## Current State

- Installed Supabase CLI version when assessed: `2.105.0`.
- Latest npm version when assessed: `2.108.0`.
- The documented CLI does not expose a hosted `functions logs` subcommand.
- Hosted logs are available in the Supabase Dashboard Logs Explorer.
- Supabase exposes the same log sources through its Management API.

Upgrading the CLI alone will not provide hosted log retrieval. The practical implementation is a small repository wrapper around the official Management API.

## Prerequisites

1. Create or use a Supabase fine-grained personal access token with `analytics_logs_read`.
2. Store it in macOS Keychain or provide it through `SUPABASE_ACCESS_TOKEN`.
3. Never commit the token, print it, include it in evidence, or pass it as a visible command-line argument.
4. Target project ref: `zogvvrxhiwozjmufvddu`.

The existing `supabase login` credential is stored in native credential storage and is usable by the official CLI. A custom wrapper should not scrape that credential from Keychain. It should receive a separately authorized token through a secure environment-loading mechanism.

## Proposed Implementation

Add `scripts/supabase-function-logs.sh` with:

- Required function-name argument.
- `--since`, `--start`, and `--end` options, bounded to the Management API's maximum query window.
- Optional `--generation-id`.
- Optional `--source function_logs|function_edge_logs|both`.
- Optional `--json`.
- Strict token-presence validation.
- URL-safe request construction.
- Redaction of authorization headers, tokens, secrets, and known sensitive fields.
- Nonzero exits for authentication, authorization, rate-limit, malformed-response, and API failures.
- No deployment or mutation capability.

Use the official endpoint:

```text
GET /v1/projects/{ref}/analytics/endpoints/logs.all
```

Supply a constrained SQL query for `function_logs` or `function_edge_logs`. Keep queries read-only and restrict them by time and function metadata.

## Verification

1. Run shell syntax/static checks.
2. Prove missing-token behavior without making a network request.
3. Query a narrow recent window for `generate-week`.
4. Confirm both log sources can be returned.
5. Confirm function-name and generation-ID filters work.
6. Confirm output contains no token or authorization header.
7. Save a sanitized JSON sample under `build-logs/`.
8. Document rate limits and retention behavior observed for the current Supabase plan.

## Completion Criteria

- One command retrieves hosted `generate-week` logs non-interactively.
- Authentication uses a token with only the required analytics permission.
- Secrets are neither stored in the repository nor emitted.
- Failures are actionable and machine-detectable.
- Output can be attached to future Gate 7/live-generation evidence.

## References

- [Supabase Management API logs endpoint](https://supabase.com/docs/reference/api/list-all-functions)
- [Supabase logging and Logs Explorer sources](https://supabase.com/docs/guides/telemetry/logs)
- [Supabase CLI authentication storage](https://supabase.com/docs/reference/cli/supabase-orgs-list)
