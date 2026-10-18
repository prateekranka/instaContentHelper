# ContentHelper — four UI directions

Detailed interactive prototypes for choosing the finished app's daily creator experience. Sample content and actions stay in memory. No production app APIs are connected.

Phone preview over Tailscale:

- [Pocket](https://macbook.taile5de76.ts.net/contenthelper/index.html?variant=A)
- [Daybook](https://macbook.taile5de76.ts.net/contenthelper/index.html?variant=B)
- [Studio](https://macbook.taile5de76.ts.net/contenthelper/index.html?variant=C)
- [Cue](https://macbook.taile5de76.ts.net/contenthelper/index.html?variant=D)
- [Compare all four](https://macbook.taile5de76.ts.net/contenthelper/index.html?variant=A&compare=1)

Connect the phone to the same Tailscale network. Keep the Mac awake and connected to Tailscale.

Start with onboarding: [Pocket](https://macbook.taile5de76.ts.net/contenthelper/index.html?variant=A&flow=onboarding), [Daybook](https://macbook.taile5de76.ts.net/contenthelper/index.html?variant=B&flow=onboarding), [Studio](https://macbook.taile5de76.ts.net/contenthelper/index.html?variant=C&flow=onboarding), or [Cue](https://macbook.taile5de76.ts.net/contenthelper/index.html?variant=D&flow=onboarding).

The controls above the phone open **Daily idea**, **Onboarding**, **Weekly plan**, and **Creator profile**. Each direction has its own welcome screen. Sample Apple sign-in leads to one short, optional interest screen. Both **Show my first idea** and **Set up later** lead directly to a useful first package on Today. A three-part tour is available without blocking creation. Detailed preferences live in You, following the existing Launch-A contract.

The preview runs on loopback port `8766` through the user LaunchAgent `com.prateekranka.contenthelper-prototype`. It starts at login and stays available after the chat ends. Tailscale Serve forwards only `/contenthelper/` to this server. Existing routes are preserved. The LaunchAgent file is `/Users/prateekranka/Library/LaunchAgents/com.prateekranka.contenthelper-prototype.plist`.

To remove only this preview route, use `tailscale serve --https=443 --set-path=/contenthelper/ off`. To stop only its local server, use `launchctl bootout gui/501/com.prateekranka.contenthelper-prototype`.

Run:

```sh
python3 prototypes/creator-directions-2026-10-02/preview.py
```

Open the printed loopback URL. You can also open `index.html` directly.

| Variant | Name | Layout |
| --- | --- | --- |
| `?variant=A` | Pocket | Compact recommendation with a visible shot list. |
| `?variant=B` | Daybook | Warm editorial title, illustration, and opening quote. |
| `?variant=C` | Studio | Dark viewfinder, opening frame, and filming timeline. |
| `?variant=D` | Cue | Large opening script with a small task summary. |

Use **Compare all four** for a side-by-side view. Use the bottom switcher or left/right arrow keys to change directions. Variant changes keep the current task state, so you can compare filming or posting across styles. Keyboard changes have no motion. Reduce Motion follows your system preference.

Each direction includes:

- Today with one recommendation, effort, opening line, actionable shot cards, script and post tools, and the reason for the idea. The main recording or post-text action stays fixed while details scroll.
- A filming walkthrough with shot selection, completion, instructions, dialogue, and on-screen text. Record in the usual camera app.
- Editable script and caption drafts. Save commits the edit. Closing the editor discards an unsaved edit.
- Instagram, TikTok, and YouTube presentation choices, a visual post preview, hashtag toggle, caption copy, posted status, undo, and post history.
- A seven-day Plan. Save an idea for a selected day, open its complete package, prepare an empty day, or select another idea. A collision preserves the existing saved idea.
- You with profile editing, interests and custom subjects, time, recording style, content format, creator voice examples, optional context, removable reference links, reminder settings, and account information.
- Preference Save and cancel behavior. Changed interests, time, and format shape the next prepared sample package. The existing idea stays ready.
- Empty, preparing, retry, saved, posted, and day-off states. **Idea retry** opens the retry example.

The sample library covers books, food, travel, fitness, style, movies, art, and everyday life. Choosing a photo format produces a caption package with no filming steps. Sign-in, saving, reminders, and completion are simulated for design review. Recording and external publishing remain in the creator's usual apps.

Behavior verification uses [TesterArmy e2e](https://tester.army/e2e). The local configuration uses deterministic assertions without an AI model, API key, or provider change. Run the focused checks from this directory with `E2E_TELEMETRY_DISABLED=1 npx e2e run tests/contenthelper.e2e.ts --target contenthelper-static --exclude-tag visual --workers 1 --retries 0`. The desktop comparison and welcome captures use `--target contenthelper-desktop --tag visual`.

The preview server exposes only the HTML, CSS, and JavaScript assets. Dependencies, configuration, and test reports are not served. It sends `Cache-Control: no-store` so phone refreshes receive the current prototype.

Craft guidance: `/Users/prateekranka/.codex/skills/emil-design-eng/SKILL.md`. Buttons use subtle press feedback. The sheet has a short transition. Core daily navigation has no delayed entrance animation. Visual reference illustrations are original local SVGs. There are no external image or font requests.

The earlier prototype at `prototypes/today-ui/index.html` and all app source remain unchanged.

These artifacts are for selecting a direction. No design winner or production behavior change has been approved yet.
