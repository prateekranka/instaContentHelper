# Mira test rounds

Use TesterArmy e2e. For each PR, run the changed areas and core scenarios on two simulators. Then run the phone smoke check. Allow about 40 minutes for the round. Plan about 6 minutes for core on two warm simulators and about 15 minutes for phone smoke. Builds, runner startup, live AI and the number of changed areas affect the time. Use the full simulator list before TestFlight or on request.

## Simulator round

Install the locked Node dependencies with `npm ci`. Fetch `origin/main` before choosing the areas.

```sh
selection=$(scripts/mira-test-areas.py) && if [ -n "$selection" ]; then
  scripts/mira-sim-pair.sh --tag "${selection#--tag }"
else
  scripts/mira-sim-pair.sh
fi
```

The selector uses `git diff --name-only origin/main...HEAD`. It prints its reason to stderr. A change limited to docs or evidence selects core. A shared or unknown file selects the full simulator list. The full selection leaves the argument list empty.

```sh
scripts/mira-sim-pair.sh --tag @core,@words
scripts/mira-sim-pair.sh --tag @home --exclude-tag @d2 --grep 'E1'
scripts/mira-sim-pair.sh --sims 1 --tag @core
scripts/mira-sim-pair.sh --app work/DerivedData/Build/Products/Debug-iphonesimulator/ContentHelper.app
scripts/mira-test-areas.py --dry-run
scripts/mira-sim-pair.sh --dry-run --tag @core
```

The pair script builds one app unless you supply its path. It assigns shard 1 to Sim Guard iPhone 1 and shard 2 to iPhone 2. Single mode uses iPhone 2. Each shard gets its own runner, fixture, HTTPS port, CA and evidence. The simulator app uses sample data and the loopback D2 fixture.

Each shard stops at its first failure. The pair waits for both and writes `summary.md` and `summary.json` under the printed evidence path. Reports include scenario results, error codes and times. A failed build, install, fixture or test gives a nonzero exit. A busy simulator or held lease stops the run. Cleanup stops owned runners and fixtures and releases the simulators. It preserves existing simulator apps and keychain entries. The fixture CA expires after two days.

## Tags

| Tags | Area |
| --- | --- |
| `@home`, `@words`, `@shots` | Home, script, shot list and filming |
| `@brand`, `@deals`, `@reel` | My Brand, deal briefs, saved Reels and delivery |
| `@insights`, `@consent`, `@d2` | Instagram insights, AI permission, wait steps and shot pictures |
| `@core` | Six simulator checks for the main paths |
| `@phone-smoke` | Scenarios used in the short phone round |
| `@phone-only` | Real keyboard, account state, live AI, Photos, Join Reel or share targets |

The simulator script always excludes `@phone-only`. The API and older live suites have separate configs. Run those suites when their scope and prerequisites apply.

Core checks:

1. Home shows Continue and the Words action for an unfinished Reel.
2. Home, Deals and My Brand show Ask Mira. My Brand can open an archived sample Reel.
3. A sample Reel restores Words, the one-page shot list and the saved shot.
4. The D2 wait screen follows server steps and opens the first ready card.
5. The Projects shot list asks for word approval before filming.
6. Sample Instagram insights offer Connect again after permission is missing.

```sh
npx e2e list --tag @core
npx e2e list --config e2e.mira-live-journey.config.ts --tag @phone-smoke
```

## Phone smoke

Use the signed Debug iPhone build from this branch. Put the private signing environment in `work/keep/pr37-phone-3.env`.

```sh
scripts/mira-phone-setup.sh --dry-run
scripts/mira-phone-smoke.sh --dry-run --app work/DerivedData-device/Build/Products/Debug-iphoneos/ContentHelper.app
```

Export the existing isolated live QA credentials from a private environment file. The script needs `MCO_LIVE_CREATOR_ID`, `MCO_LIVE_DEVICE_TOKEN` and `MCO_SUPABASE_PUBLISHABLE_KEY` before phone setup. The smoke round uses the QA API for generation so it can leave the phone's Reel library intact.

```sh
scripts/mira-phone-smoke.sh --app work/DerivedData-device/Build/Products/Debug-iphoneos/ContentHelper.app
```

The phone steps run in this order:

1. Stop old daemons. Check zero claims, USB pairing, unlock state and runner team `4JRB53LG5C`.
2. Run Keep. Confirm AI permission shows Allowed and Instagram shows the connected account and a live follower count.
3. Install over the verified Mira bundle. Keep its app data.
4. Run Keep again.
5. Find How you're doing by name on the phone. Start one ideas-only job in the live QA workspace and check that it returns three distinct ideas.
6. Open and close the real Profile keyboard. Compare the field value before and after.
7. Open the share sheet for a saved Reel and cancel it.
8. If E4 exists, open and cancel Photos. Join sample clips in a separate fixture library.
9. Run Keep after the tests.

Before dispatch, the live test reserves three text attempts for one ideas job, including server retries. The request disables pictures. The test checks for zero pictures and never creates or edits a Reel. The ledger records the reservation before dispatch and the result afterward. Only the provider ledger can confirm the exact number of calls charged.

Use `times.tsv`, `live-counts.json` and the TesterArmy reports under the printed evidence path to review results. A failed step stops the round. Resolve the specific blocker before a new run. Review the last live ledger before authorizing a new dispatch.

## Source checks

```sh
python3 scripts/check-agent-rules.py
python3 scripts/prove-agent-rules.py
```
