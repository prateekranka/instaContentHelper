# Step 6: correct

Base: `8ce636ab3b380bca1db500b18f8ce1dbe4506521`, branch `redesign/creator-loop`.
The initial checkout was clean. The approved redesign plan was read first.
Changes are local and uncommitted. No live database, Supabase project, deployment, or e2e runner was used.

## Evidence and selected correction classes

The review covered commit messages and relevant diffs from `ea5db00`, `240eba8`, `92406c5`,
`a17a4d8` through `07a4d70`, `f0d5b36`, `061f94a`, `8daa6b1`, and `8ce636a`.
It also covered the redesign, lifecycle, round 4, round 5, and Step 5 reports, `CLAUDE.md`,
the supplied global agent instructions, existing workaround comments, and the operator's Step 4/5 corrections.
No separate local review-comment export was found. Remote review comments were not fetched.

| Class and repeated evidence | Level selected | Why a higher level does not finish the correction |
| --- | --- | --- |
| Competing state owners. `240eba8` retained unsynced decisions separately; `92406c5` repaired their card/date recovery again. Redesign phases 2/3 replaced stored Today/week/progress copies and separate saved-work stores with `DayStore` and the outbox. | Existing architecture plus a source check against new mutable owners. | `DayStore` already owns the state with private setters. Swift still permits a view or service to declare another stored value of the same model type. The check protects that boundary without changing the public content models. |
| Repeated formatter construction. `ea5db00` repaired calendar-day formatting but retained a new formatter per call. The Step 5 profile found the same allocations in context labels, timestamp parsing, and today helpers. | Existing shared cache plus an allocation check. | Foundation constructors remain available to every SwiftUI file. A formatter has the same type whether cached or newly constructed. Removing Foundation from those files would require a larger module redesign. |
| Repeated card projection construction. Before Step 5, `AppServices.todayCard`, `DayStore.readyCards`, and both revision lookup branches built a card on every read. | Existing `DayStore` cache plus a conversion-call check. | Draft/revision conversion remains necessary at model, migration, and fixture boundaries. Hiding all conversion would remove those uses too. The check rejects new conversions outside the model owner while retaining existing uses. |
| Synchronous snapshot saves. Before Step 5, the main-actor service called synchronous `saveSnapshot`; the file store encoded and wrote inline. Step 5 added async saving, but the protocol still exposed synchronous saving and supplied a synchronous async fallback. | Architecture and types first, then a source check. | Synchronous `saveSnapshot` is removed from the protocol and its fallback extension is deleted. `AppServices` cannot call that method through `any TodayCacheStoring`. Concrete fixture setup retains its synchronous method. The check prevents restoring the old protocol surface and checks the serial-queue route. |
| Control visibility confused with safe hit geometry. Step 4's pinned bar covered a swipe start; Step 5's raw Plan scroll/tap hit the Save caption dock. The Step 5 helper repair made pinned controls the bottom edge. | One shared e2e helper plus a source check. | Screens and sheets need different scroll containers, so the helper now selects the visible container containing the target and handles sheets without a tab bar. The e2e library still exposes raw scrolling; changing that external type would require a library fork. The check rejects raw calls in repository tests. |
| Ambiguous accessibility contracts. Step 4 gave `you.screen.account` to both container and child and split `Story · 10 sec` into two nodes. R3-C5 and round 4 also needed narrower text targets. | Identifier ownership check plus existing exact e2e assertions. | SwiftUI accessibility output depends on the composed runtime tree. Global identifier enums alone cannot stop two views from using the same value. The source check prevents new duplicate owners and missing identifier expressions. Exact text and runtime tree composition remain e2e responsibilities. |

The source checks use a fixed Git baseline, not a list of approved offending lines.
For patterns still present, counters are keyed by file and declaration scope. A new occurrence fails.
Identifier counts apply across app Swift source. Existing duplicate expressions are retained at their baseline count.
No exception syntax, expiry, approval bypass, or new exception was added.

These checks recognize source patterns. They do not resolve inferred Swift types, evaluate arbitrary
identifier expressions, or prove runtime cache invalidation, task ordering, or hit testing.
No passing check is presented as complete app-behavior proof.

## Past-mistake proof

Run the complete proof locally or in CI:

```sh
python3 scripts/prove-agent-rules.py
```

The command first checks current source. Each case then copies only app Swift and test TypeScript
into an isolated temporary directory. It installs the historical file with `git show <ref>:<file>`
and runs `python3 scripts/check-agent-rules.py --class <class> --source-root <copy>`.
The proof requires exit 1 and a diagnostic for the selected class. Tool errors do not count as rejection.
The working tree's source is never replaced. The temporary copy is discarded after each case.

For a single class, append `--class <class>` to the proof command.

| Class | Actual restored source | Observed proof output |
| --- | --- | --- |
| `state_ownership` | `240eba8^:CreatorContentOS/App/AppServices.swift` and `92406c5^:CreatorContentOS/App/AppServices.swift` | Both rejected with exit 1. Diagnostics identify the stored `todayCard`, `shotSceneIDs`, week cards, and pending-decision copies and name `DayStore`/`ContentIntent`. |
| `formatter_allocation` | `ea5db00^:CreatorContentOS/Data/SupabaseDTOs.swift` and `8ce636a^:CreatorContentOS/Data/SupabaseDTOs.swift` | Both rejected with exit 1. Examples include `SupabaseDTOs.swift:1255` and `:1291`; output names `SupabaseDateFormatting.withFormatter`. |
| `card_projection` | `8ce636a^:CreatorContentOS/App/AppServices.swift` and `8ce636a^:CreatorContentOS/Data/TodayCacheStore.swift` | Both rejected with exit 1. `AppServices.swift:33` and `TodayCacheStore.swift:54,62,63` name `DayStore.projection`, `card`, and `readyCards`. |
| `snapshot_persistence` | `8ce636a^:CreatorContentOS/App/AppServices.swift` and `8ce636a^:CreatorContentOS/Data/TodayCacheStore.swift` | Both rejected with exit 1. `AppServices.swift:1994` identifies the synchronous call; the file-store diagnostic identifies the synchronous protocol surface and missing background implementation. |
| `scroll_controls` | `8daa6b1:tests/pocket-plan.e2e.ts` and `8ce636a^:tests/pocket-support.ts` | Both rejected with exit 1. The Plan diagnostic includes line 47, the real raw scroll to `plan.package.replaceIdea`. The helper diagnostic identifies the missing dock boundary calculation. |
| `accessibility_identity` | Reapplied the operator-supplied Step 4 line on the account identity child while retaining the same identifier on the screen container. | Rejected with exit 1: `YouAccountView.swift:36: error [accessibility_identity]: Identifier "you.screen.account" gained another owner.` This is a reconstruction of the supplied uncommitted mistake, not a claim that a duplicate survived in a commit. |

Final proof result: **11 historical reproductions rejected; current source passes all six checks.**
Every violation prints a file, line, and supported type or function.

## Files and separate commit groups

Stage these groups in order. No commit was made.
The first group includes shared check infrastructure. The final group includes the requested rule table and this report.
Each check module owns its own historical proof cases. The runner discovers modules automatically.

| Group | File | One-line change |
| --- | --- | --- |
| 1 — state ownership | `scripts/agent_rules/state_ownership.py` | Rejects added typed mutable day/package/outbox owners in services and views. |
| 1 — shared infrastructure | `scripts/agent_rules/support.py` | Reads the fixed baseline, tokenizes source, tracks declaration scopes, and reports additions. |
| 1 — shared infrastructure | `scripts/check-agent-rules.py` | Runs every discovered class with one local command and actionable diagnostics. |
| 1 — shared infrastructure | `scripts/prove-agent-rules.py` | Reproduces historical mistakes in isolated copies and requires the selected check to reject them. |
| 1 — CI | `.github/workflows/backend-checks.yml` | Runs the same check and proof commands with full Git history and includes the redesign branch. |
| 2 — formatter allocation | `scripts/agent_rules/formatter_allocation.py` | Rejects added formatter construction, including construction in string interpolation. |
| 3 — card projection | `scripts/agent_rules/card_projection.py` | Rejects added direct revision and draft card conversion calls outside the model owner. |
| 4 — snapshot persistence | `CreatorContentOS/Data/TodayCacheStore.swift` | Removes synchronous saving and the synchronous async fallback from the protocol. |
| 4 — snapshot persistence | `scripts/agent_rules/snapshot_persistence.py` | Rejects synchronous app-flow saving and restoration of the old cache protocol surface. |
| 5 — scroll controls | `scripts/agent_rules/scroll_controls.py` | Restricts raw scrolling to the shared helper and protects its dock boundary calculation. |
| 5 — scroll controls | `tests/pocket-support.ts` | Chooses the target's visible scroll container and supports sheets without a tab bar. |
| 5 — scroll controls | `tests/pocket-accessibility.e2e.ts` | Routes Plan-tomorrow and production-row scrolling through the shared helper. |
| 5 — scroll controls | `tests/pocket-alternatives.e2e.ts` | Routes backup-confirmation scrolling through the shared helper. |
| 5 — scroll controls | `tests/pocket-loop.e2e.ts` | Routes archive and error scrolling through the shared helper. |
| 5 — scroll controls | `tests/pocket-plan.e2e.ts` | Routes remaining Plan navigation/header scrolling through the shared helper. |
| 5 — scroll controls | `tests/pocket-screens.e2e.ts` | Routes both backup sheets through the shared helper and deletes the separate backup scroller. |
| 5 — scroll controls | `tests/pocket-today.e2e.ts` | Routes posted-state and archive scrolling through the shared helper. |
| 6 — accessibility identity | `scripts/agent_rules/accessibility_identity.py` | Rejects missing identifier expressions and added duplicate owners; reconstructs the supplied account mistake for proof. |
| 6 — rule table | `CLAUDE.md` | Names the approved plan first and pairs each correction rule with its enforcement. |
| 6 — report | `docs/design/step6-correct.md` | Records evidence, chosen levels, proof results, file groups, commands, and limits. |

Existing e2e assertions, test names, fixture session behavior, and app-owned UI remain intact.
No accessibility identifier was renamed or removed. No code comment, Swift unit test, or test target was added.

## Commands and results

Checks used `command-watchdog.sh` with separate absolute stdout/stderr log paths.
Evidence directory: `work/evidence/step6-correct/20261021T084510Z.xydM6g/`.
The global evidence helper could not create its directory in this sandbox; the project-local helper succeeded.

| Command | Result |
| --- | --- |
| `workspace-guard.sh --root <checkout> --branch redesign/creator-loop` | Passed. Initial HEAD was `8ce636a`; checkout was clean. |
| `git log`, `git show`, `git diff`, `rg`, `cat`, and `sed` | Read the correction history, owners, existing tests, and instructions. |
| `python3 scripts/check-agent-rules.py` | All six classes pass on current source. Also runs at the start of every full proof. |
| `python3 scripts/prove-agent-rules.py` | Passed. All 11 historical reproductions rejected with exit 1. No app executed. |
| `env -u MCO_LOCAL_DATABASE_URL deno task ci:backend` | Exit 0. Type checks passed; 403 tests passed, 0 failed, 2 ignored. No database was contacted. |
| `node --input-type=module` using `esbuild.transform` with `loader: "ts"` | Exit 0. All seven changed TypeScript files parsed. No test module was executed. |
| `DEVELOPER_DIR=/Applications/Xcode-27.1-beta.app/Contents/Developer xcrun swiftc -frontend -parse CreatorContentOS/Data/TodayCacheStore.swift` | Exit 0. Swift syntax passed; this is not type checking. |
| `disk-preflight.sh` | Passed; 21.40 GiB free at the check. |
| `xcode-proof-preflight.sh ... --derived-data-path <checkout>/DerivedData/Step6Correct` | Passed. An earlier call used the unsupported `--derived-data` spelling; the help output supplied the correct option. |
| Native build below | Exit 65 before app compilation: `Missing package product 'Supabase'`. Xcode also reported restricted simulator-service access. No simulator was operated. |
| `git diff --check` | Passed. |

Native build command, with task-local home/module/package caches and existing Phase 5 package checkouts:

```sh
DEVELOPER_DIR=/Applications/Xcode-27.1-beta.app/Contents/Developer \
xcodebuild -project CreatorContentOS.xcodeproj -scheme CreatorContentOS \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData/Step6Correct \
  -clonedSourcePackagesDirPath DerivedData/Phase5/SourcePackages \
  -packageCachePath DerivedData/Step6Correct/PackageCache \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -IDEPackageSupportDisableManifestSandbox=YES CODE_SIGNING_ALLOWED=NO build
```

Proof output is in `proofs-complete.stdout.log`. Backend output is in `backend.stdout.log` and `backend.stderr.log`.
Build output is in `build.stdout.log` and `build.stderr.log`.
TypeScript and Swift syntax logs have the `typescript-syntax` and `swift-syntax` prefixes.

## Remaining verification and coverage

- The owner runs TesterArmy e2e. This step did not run or claim continued acceptance for the 12 groups, 35 loop tests, or 7 screen tests.
- A full native build needs a runner with a resolved Supabase package product. Swift parsing does not replace that build.
- GitHub CI was extended but not remotely triggered because no push was authorized. Its exact commands passed locally.
- The two ignored backend cases remain the local-database transaction regression and the existing partial-progress generation-status case.
- The existing exact screen assertion protects the combined `Story · 10 sec` node at runtime. A source scan cannot prove the complete accessibility tree.
- The existing 600 ms filming tap guard was preserved. The supplied evidence identifies one timing correction, so this step did not invent a repeated class or a new timing constant rule.
- Server revision identity, atomic replacement, and shot-validation drift already have shared server paths and existing Deno/SQL contract checks. This step did not replace them with source-text assertions or touch the backend.

No implementation item in the selected six classes remains unfinished. Native build, CI execution,
and e2e acceptance remain separate verification limits.
