# Mira TLA+ models

Run `specs/tla/run.sh` from the repository root with Java on `PATH`. Set
`JAVA_BIN` to the full Java path if necessary. The runner downloads TLC v1.7.4
to `work/tla-cache` and verifies its SHA-256 before each run. The first run needs
network access. Use `TLA_CACHE_DIR` and `TLA_OUTPUT_DIR` to set other paths.
Each run stores its TLC output and traces under `work/tla-results` by default.

| Module | Checks |
| --- | --- |
| `MiraReel` | Approval before filming, correct stage and work labels, Stop, and the next step for Your words. |
| `MiraJobs` | Allowed job and progress transitions, lease budget, no overlapping calls, and no lost result. `MiraJobs-Refusal.cfg` checks safe refusal of a short lease. |
| `MiraShotPictures` | Reservation cap, one call per shot, an object for every ready picture, and separate text slots. |
| `MiraTodayLimit` | Three active jobs at most, honest work labels, and eventual completion without a manual reconnect. |

Configs in this folder must pass. Configs under `negative/` disable a guard.
Their filenames give the module, property type, property name and optional
scenario. Each must produce the named violation. A parse error or an unrelated
violation fails the suite. The runner disables TLC's default deadlock check
because jobs can finish with no enabled action.

These bounded models come from [S1](../../docs/mira-evidence/2026-11-27-phase-s1.md)
and [D2](../../docs/mira-evidence/2026-11-27-phase-d2-server.md). See the
[state-machine guide](../../docs/state-machines.md) for the source behavior.
