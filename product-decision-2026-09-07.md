# Product decision — 7 September 2026 IST

**Record type:** audit decision log\
**Folder:** `/Users/prateekranka/Documents/Codex/2026-06-19/contenthelper-ui-audit`\
**This file does not change app source, tests, git, or Paper.**

---

## Identity

| Field | Value |
|---|---|
| **Decision ID** | `dec-20260907-002` |
| **Choice key** | **A** |
| **Short name** | Launch-A |
| **Decider** | Bobby |
| **When** | 7 September 2026, IST |
| **Mode** | Explicit spoken/written product gate. Not inferred from silence. |
| **Status** | Binding for this launch. Recorded before CH-02 behavior work. |
| **Companion contract** | `onboarding-contract-launch-A.md` (same folder) |

Prior same-day freeze remains: **`dec-20260907-001`** (launch-scope freeze at the current creator workflow). Launch-A reopens **first-use setup only**. It does not reopen product direction, shell, visual system, providers, or any held external action.

---

## Exact wording (source of truth)

Bobby, 7 Sep 2026 IST, explicit:

> **A.** Keep Sign in with Apple before first generation. External/manual publishing remains the post path. The first-run launch bar is **time to first useful script/storyboard/caption package**. Actual sharing is measured separately and is NOT the launch bar. Do not relabel generation as publication. Mark-as-posted is local bookkeeping, not a shared post.

This SUPERSEDES Sept-2 `dec-20260902-001` (zero fields + actual shared post within 60 seconds) **for this launch**. The old rule is recorded as **deferred**, not silently waived. If a later release must prove an actual share, that needs a **separate scoped sharing journey**.

---

## Also now authorized (still no code in the recording task)

Recommended minimal first-use:

- One short skippable choice screen.
- Move taste, detailed production prefs, and optional context to existing You editors.
- Reuse existing creator profile/generator. No second onboarding subsystem.
- No mandatory typing, handles, reference links, voice questionnaire, or voice-learning.
- Preserve established profiles; no new pass may overwrite them.
- Retry reuses saved profile; no duplicate packages.
- Back/cancel leaves recoverable state.

**CH-02** may proceed under this contract **after** the Step 2 change ledger is accepted. Do **not** implement `OnboardingFlowView` as part of recording this decision.

---

## What this decides

| Question | Answer under Launch-A |
|---|---|
| May launch retain Sign in with Apple before first generation? | **Yes.** Apple remains the front door. First generation happens after a live session. |
| Must launch satisfy account-after-value / guest-auth? | **No** for this launch. |
| First-run success bar? | **Time to first useful script / storyboard / caption package.** |
| Is an actual shared post the launch bar? | **No.** Measure sharing separately. |
| May generation be labeled publication? | **No.** |
| What is Mark as posted / Mark posted? | Local bookkeeping (`Decision`). Not evidence of a shared post. |
| What is the post path? | External / manual publishing (copy/shoot outside the app). Native Instagram publish is not required to close the launch bar. |
| Five mandatory onboarding stages before first package? | **No** for first-run. See companion contract. Current five-step remains **current-state evidence** in Paper. |
| Sept-2 ≤60 s actual-share rule? | **Deferred** for this launch. Not waived. Not the launch bar. |

---

## What is superseded

### `dec-20260902-001` — deferred, not waived

| Field | Value |
|---|---|
| **ID** | `dec-20260902-001` |
| **When / where** | 2 September 2026; KB + session `20260902_103547_881b4e`; room-agreed; tracker card 39 |
| **Exact prior bar** | Zero-setup first day. Delete onboarding steps as pre-conditions. First launch → shared post in ≤ 60 seconds. Zero fields filled by the user. First success = a real shared post. Visible Back / retry and independent repeat use. |
| **Conflict with current product** | The audited app requires Sign in with Apple, then (today) five adaptive steps, then a generated Today package. It does not confirm external publication. “Mark as posted” is not publication. Local card generation is not a shared post. |
| **Disposition under Launch-A** | **Superseded for this launch’s first-run bar.** Status = **deferred**. Do not silently delete the old rule. Do not pretend the launch bar is still an actual share. Do not relabel a generated package as that share. |
| **Re-open condition** | A later release that must prove an actual share needs a **separate scoped sharing journey** (capture / export / native share proof). That journey is **held** until explicitly scoped and approved. It is not CH-02. It is not copy cleanup. |

Launch-A does **not** resurrect the Sept-2 zero-field / guest / 60-second share design. Keep Apple sign-in. Keep manual/external post as the post path.

---

## What remains held

These are **not** approved by Decision A. Silence still does not approve them.

| Held item | Why it stays held | Evidence / prior gate |
|---|---|---|
| **Hosted deploy** | Local generation smoke is not hosted compatibility. No production migration or Edge Function deploy without a later explicit approval. | `dec-20260907-001` freeze; CH-07; contracts §J / §N migration gate; handoff Step 6 |
| **GitHub Discussions** | Publish + read-back of review documents remains blocked until auth, enablement, and explicit publish approval. Local audit files are not published discussions. | CH-14; handoff Step 9; `has_discussions=false` at audit time |
| **App Store submit** | Submission is a separate explicit approval. Validator/listing/privacy/build work may continue as planning. Do not submit. | Handoff Step 10; ASC app `6777027653` still `PREPARE_FOR_SUBMISSION` |
| **Automatic release** | Live ASC is configured for automatic release after approval. Manual release must be approved **before** any submission. Do not submit under automatic release while publication is independently held. Public release is a further separate approval. | Handoff Step 10 |
| **Sharing-journey native capture** | Actual share is **not** the launch bar. If a later release must prove a share, scope the smallest complete sharing journey (capture/export/guest-auth as needed) **before** implementation. Do not hide that work under onboarding or copy cleanup. | Handoff §3; `dec-20260902-001` deferred re-open condition |

Also still **not** authorized by this record:

- Implementing `OnboardingFlowView` / CH-02 in the recording task.
- Overwriting established creator profiles.
- A second onboarding or profile subsystem.
- Voice-learning machinery, mandatory handles, reference links, or a voice questionnaire as a first-run gate.
- Replacing generation providers.
- Changing Today / Plan / You chrome as a redesign.
- PipCount work.

---

## Effect on adjacent decisions and tickets

| ID | Effect |
|---|---|
| `dec-20260907-001` launch-scope freeze | Remains. Product stays the current creator workflow. Launch-A is a scoped first-use reduction, not a new product. |
| Sept-5 five-step adaptive contracts (`docs/adaptive-creator-onboarding-contracts.md`) | Remain the **current implemented** persistence / first-idea / no-HYROX / account-isolation contracts. First-run **presentation** for launch is superseded by Launch-A (one skippable screen). Do not treat the five-step UI as the launch first-run gate. Do not edit that repo file in this recording task. |
| CH-02 | **Unblocked for ledger + later implementation** under `onboarding-contract-launch-A.md`, **after** the Step 2 change ledger is accepted. |
| CH-08 lifecycle guards | Remain. First-idea still must not overwrite ready / edited / shot / posted / decision packages. |
| CH-15 copy/edit access | Unchanged. First useful package still requires a reachable script/storyboard/caption package. Copy/edit reachability is separate from this bar. |
| Gate G1 (handoff §8) | Answered: not five-step polish-only, and not Sept-2 actual-share. Chosen path = Apple sign-in + one skippable choice + You for deferred prefs + first useful package as the launch bar. |

---

## Language rules this decision locks

- **Useful package** = script + storyboard + caption the creator can use. Not an empty screen. Not a fixture card shown as live. Not a local posted flag.
- **Generation** = producing that package (`generate_day` + `makeDayAvailable`). Not publication.
- **Publication / shared post** = the creator actually sharing outside the app. Not measured as the launch bar.
- **Mark as posted** = Archive/Decision bookkeeping. Not a shared post.
- **Available on Today** = promoting a draft to the ready package. Not Instagram publish.

---

## Paper (constraint only; this task does not edit Paper)

- Keep the **current five-step** journey as **current-state evidence**.
- Show the **one-screen** first-use as **proposed**.
- Do not draw the one-screen as if it already ships.

---

## Implementation gate (for later work, not this file)

1. Record this decision (this file) and the companion contract. **Done by the recording task.**
2. Accept the Step 2 change ledger with a CH-02 row that cites `dec-20260907-002`.
3. Only then change onboarding presentation in existing `OnboardingFlowView` / `OnboardingViewModel` / store / presentation policy and existing You editors.
4. Do not start a second onboarding subsystem. Do not deploy hosted. Do not submit. Do not build sharing-journey native capture under CH-02.
