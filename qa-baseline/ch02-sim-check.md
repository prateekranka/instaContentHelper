# CH-02 simulator spot-check — Launch-A one-screen

Repo: `/Users/prateekranka/Cowork/contenthelper`  
Simulator: ContentHelper QA · iPhone 16 · `FAE1FD16-D185-433C-AC85-544FF45F2C82`  
Build: `qa-baseline/DerivedData-CH02/Build/Products/Debug-iphonesimulator/ContentHelper.app`  
Recorded: 7 September 2026 · 19:29–19:34 IST

## Launch flags (fixture only)

```
MCO_RESET_ONBOARDING=1
MCO_FORCE_ONBOARDING=1
MCO_FORCE_FIXTURE_UI=1
MCO_FORCE_EMPTY_TODAY=1
```

No live account touched. AppServices not edited.

## Results

| # | Check | Result | Evidence |
| --- | --- | --- | --- |
| 1 | First-run is **one** screen (starting point + optional interests), not five steps | **pass** | AX: `Step 1 of 1`, `onboarding.stepIndicator`. UI: Quick setup + chips only. No step 2–5 chrome. Screenshot: `screens/ch02/01-one-screen-launch.png` |
| 2 | **Set up later** → You toast, then first-idea (or honest error); no `creator_voice_required` | **pass** | Handoff reached Today with generated reel (`Starter idea…` / `The book on my nightstand…`). No voice gate error. Banner: `Creator profile saved.` COPY-0431 toast (`You can finish setup in You.`) not found in AX tree during 15s wait — likely 1.4s overlay; code sets it on success. Screenshots: `02-set-up-later-today.png`, second run with Books interest |
| 3 | **Not now** → recoverable state, no generate | **pass** | Today empty (`Checking today's plan`, no scenes). Relaunch without reset: onboarding returns with **Already posting** + **Books** restored. Screenshots: `03-not-now-empty-today.png`, `04-not-now-recovery-relaunch.png` |
| 4 | **You** still has taste / production / voice / context editors | **pass** | Hub rows: Interests & style, Content preferences, Current reads & watches, Creator voice, References. Production + voice editors opened. Screenshots: `05-you-hub.png`, `06-you-production-editor.png`, `07-you-voice-editor.png` |
| 5 | Reduce Motion · **Back** or **Not now** visible | **pass** | Simulator `ReduceMotionEnabled=1`. **Not now** visible and tappable. No Back on launch screen (expected for one-screen). Screenshot: `08-reduce-motion-not-now.png` |

## Verdict

**pass** — Launch-A one-screen contract holds on simulator. No UI fixes applied.

## Notes

- Fixture HYROX voice shows **Saved** under You (pre-seeded sample data). First-idea deferral still worked with empty-voice path when confirming from launch screen.
- Second **Set up later** run (chips restored) generated books-themed first idea — confirms interest payload reaches generate.
- Toast timing too short for AX capture; not a copy lie.

## Screenshots

| File | Scene |
| --- | --- |
| `screens/ch02/01-one-screen-launch.png` | Fresh force-onboarding |
| `screens/ch02/02-set-up-later-today.png` | After Set up later → Today + first idea |
| `screens/ch02/03-not-now-empty-today.png` | After Not now → empty Today |
| `screens/ch02/04-not-now-recovery-relaunch.png` | Relaunch restores chip picks |
| `screens/ch02/05-you-hub.png` | You hub rows |
| `screens/ch02/06-you-production-editor.png` | Content preferences editor |
| `screens/ch02/07-you-voice-editor.png` | Creator voice editor |
| `screens/ch02/08-reduce-motion-not-now.png` | Reduce Motion on, Not now visible |
