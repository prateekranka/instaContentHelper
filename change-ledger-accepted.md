# Change ledger — parent ack

**Ack:** yes\
**Decision A bound as:** `dec-20260907-002` (Launch-A). Companion: `product-decision-2026-09-07.md`, `onboarding-contract-launch-A.md`.\
**Parent ack timestamp:** 2026-09-07 18:36 IST\
**Candidate SHA:** `20766cd90fd6338592d8fb7792395f566eda1205`\
**Ack file only.** Does not edit app source, tests, git, or Paper.

`accepted` means authorized after this ack. It does not mean already done.

---

## Baseline gate (code waits)

`qa-baseline/` has an xcodebuild unit-test run (ended 2026-09-07 18:33 IST). That run is **not** a Today copy/edit gap record. No Script/Caption pasteboard capture. No Today screenshots of the current gap.

**Parent acks the ledger anyway.** App code for CH-15 / CH-02 / CH-03 / CH-05 / CH-06 still **waits** until `qa-baseline/` records the Today copy/edit gap (so screenshots show the current gap), unless a later parent note says the baseline is blocked and code may start.

**CH-04 Paper may start now.** Paper-only. No app source.

---

## Decision A (binding)

Bobby, 7 Sep 2026 IST, choice **A**, ID **`dec-20260907-002`**.

1. Keep Apple sign-in first.
2. Launch bar = time to first useful script / storyboard / caption package.
3. Sharing is measured separately. Not the launch bar.
4. Do not call generation a publication.
5. Mark-as-posted is not a shared post.
6. Sept-2 60-second actual-share rule is **superseded for this launch** and **deferred, not deleted** (CH-17).
7. CH-02 in-scope: one short skippable choice screen; defer taste / production / context to existing You editors; preserve established profiles; no second profile subsystem.

---

## CH-01 … CH-16 — decisions confirmed

No missing rows. No ledger rewrite. No CH-09 / CH-11 addendum.

| ID | Decision | Notes |
| --- | --- | --- |
| CH-01 | accepted (keep) | September candidate is the baseline. Not August `2026081102`. |
| CH-02 | accepted | One skippable screen. Cites this ack + `dec-20260907-002` + `onboarding-contract-launch-A.md`. Code waits for baseline capture. |
| CH-03 | accepted | **Scoped.** See CH-03 lock below. Code waits for baseline capture. |
| CH-04 | accepted | Paper may start **now**. |
| CH-05 | accepted (implement) | In-app deletion. **Hosted deletion proof held.** Code waits for baseline capture. |
| CH-06 | accepted (implement) | Manifest, in-app policy link, AI consent. **Hosted policy pages held.** Code waits for baseline capture. |
| CH-07 | **held** | Omit-vs-null. Fixture later. **No deploy.** |
| CH-08 | accepted (keep) | Lifecycle / isolation / overwrite / recovery guards. |
| CH-09 | deferred | Measured hotspot refactor **only**. Not this launch unless a later measure on a touched function. |
| CH-10 | accepted (plan) | Named removals only after Step 8 survivor proof. No test deletions now. |
| CH-11 | rejected | Trial / paywall **not applicable**. Do not add. |
| CH-12 | accepted | Replace CozyStack listing. After the next queue, not before Paper / CH-15. |
| CH-13 | accepted | Unused build number + signed Release. Upload/submit stay separate approvals. |
| CH-14 | **held** | GitHub Discussions **off**. Do not enable. Do not publish. |
| CH-15 | accepted | Restore copy on Today inline Script/Caption. Code waits for baseline capture. |
| CH-16 | accepted (keep) | Keep storyboard resize / VoiceOver. Deletion rejected. |

CH-17 remains **deferred** (not deleted). Not in this launch.

---

## Accepted IDs that may be implemented

### May start now (Paper only)

- **CH-04** — new editable Paper file `ContentHelper — Launch screens and states — 2026-09-07` plus full state map. Current five-step = current. One-screen + You editors + deletion/consent = proposed.

### May implement after baseline records the Today copy/edit gap

- **CH-15** — copy on existing inline Script/Caption. Narrow editor only if scene edit is otherwise lost. No production Shoot Folio launcher. External share is not this row.
- **CH-03** — only the copy-ledger rows listed in the CH-03 lock.
- **CH-02** — Launch-A one-screen in existing onboarding types. Grok integrates first-idea through existing `AppServices`. No second profile subsystem.
- **CH-05** — in-app account deletion UX + session-scoped client path. Hosted proof still held.
- **CH-06** — app-owned privacy manifest, in-app ContentHelper policy link, AI consent including automatic thumbnail / Plan-idea paths. Hosted pages still held. Do not break PipCount URLs.

### Accepted keeps (no rewrite work)

- **CH-01**, **CH-08**, **CH-16**

### Accepted later (not the next queue)

- **CH-12** — ASC listing after the product surfaces exist in Paper / candidate screenshots.
- **CH-13** — unused build number and signed Release after privacy/deletion work is in the archive story.
- **CH-10** — named test removals only after Step 8 survivor proof.

---

## Held IDs

| ID | Hold |
| --- | --- |
| **CH-07** | Omit-vs-null contract. No deploy. Hosted schema/functions unverified. |
| **CH-14** | Discussions feature off. Do not enable. Local files are not published discussions. |
| **CH-05 hosted verify** | Disposable-account deletion on hosted backend. Do not mark verified. |
| **CH-06 host pages** | ContentHelper routes on privacy/support hosts without replacing PipCount. |

Also still not authorized by this ack: App Store submit, automatic public release, hosted function/migration deploy, sharing-journey native capture.

---

## CH-03 lock (not a free rewrite)

Copy ledger exists: `copy-ledger.md` / `copy-ledger-summary.md`. **692** rows: **557 keep**, **15 rewrite**, **1 rewrite (proposed)**, **18 cut**, **101 DEBUG**.

CH-03 implementation = those **15 rewrite + 18 cut + 1 proposed skip-toast** rows. **Do not rewrite the 557 keep rows.** COPY-0172 (Resize scene column) is **keep** (CH-16), not a CH-03 rewrite.

**Rewrite (15):** COPY-0025, COPY-0158, COPY-0196, COPY-0198, COPY-0225, COPY-0231, COPY-0232, COPY-0233, COPY-0273, COPY-0285, COPY-0487, COPY-0489, COPY-0490, COPY-0498, COPY-0579.

**Cut (18):** COPY-0202, COPY-0203, COPY-0204, COPY-0205, COPY-0206, COPY-0208, COPY-0209, COPY-0210, COPY-0211, COPY-0212, COPY-0250, COPY-0443, COPY-0444, COPY-0445, COPY-0446, COPY-0564, COPY-0603, COPY-0637.

**Rewrite (proposed) skip-toast (1):** COPY-0431 — apply with CH-02 skippable-setup, not as a lone copy patch that still promises “ask again next launch.”

COPY-0603 / COPY-0637 are AdminShell DEBUG cuts, not Release consumer chrome.

`copy-ledger-summary.md` still lists “Bobby launch decision unresolved.” That blocker is **closed** by `dec-20260907-002`. Remaining C12 gate is CH-02 behavior, not a missing product choice.

---

## Next queue

1. **Paper (CH-04)** — now.
2. **Baseline capture** — record the Today copy/edit gap in `qa-baseline/` (screenshots of current Script/Caption with no copy/edit). Then code may start.
3. **CH-15** — restore copy/edit on the inline Today package.
4. **CH-03** — apply the locked copy rows only.
5. **CH-02** — one skippable onboarding screen per Launch-A.
6. **CH-05 / CH-06** — privacy and account **contracts in parallel docs**; **Grok integrates AppServices** (deletion path, consent before automatic AI, in-app policy link). Hosted proof stays held.

Keeps CH-01 / CH-08 / CH-16 apply across the queue. CH-07 not deployed. CH-14 stays off.

---

## Ledger notes (not a rewrite)

`change-ledger.md` Sources table still says `product-decision-2026-09-07.md`, `onboarding-contract-launch-A.md`, and the copy ledger were missing. Those files are present now. Decision A in the ledger matches `dec-20260907-002`. CH-03 “fill the copy ledger” is done; remaining work is the locked rows above.

This ack **overrides the ledger’s implementation-facing order** for start sequence. Rank-by-consequence in `change-ledger.md` stays. Execution order is the next queue above, so Paper and gap screenshots happen before code that would hide the gap.

---

*End of parent ack. Ack = yes. CH-04 now. All other app code waits for Today copy/edit baseline evidence.*
