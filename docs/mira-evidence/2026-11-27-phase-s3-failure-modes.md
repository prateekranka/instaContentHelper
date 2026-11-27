# Mira Phase S3 failure modes

Recorded before implementation. The phone checks use TesterArmy. Sample checks use a separate Debug library. The live library, Instagram connection and saved AI decision stay in place.

| Area | Failure | Check and expected result |
| --- | --- | --- |
| Voice input | The app asks for access before a tap, starts twice, accepts a reply from an old attempt, or leaves the mic busy after Stop or Done. | Open the note, then tap the mic. Observe the permitted path on the phone without changing its settings. Check the text, single next action, Stop and a second start. Review the attempt checks for delayed replies. |
| Instagram insights | Connect and load overlap, an old refresh replaces current data, or a failure hides the account status. | Read the connected handle and numbers on Profile. Compare before and after install and after the suites. Review the error and cancellation transitions in source. Leave the live connection in place. |
| Load and save | Relaunch loses edits, a damaged file skips backup recovery, a failed save claims success, or a newer file gets overwritten. | Save in the sample library and reopen it. Open an isolated damaged-file fixture and check the restore message and recovered project. Review the file version checks and compare saved declarations with main. |
| AI consent | The current decision becomes out of date unexpectedly, a stale record permits AI, or a Debug override writes a decision. | Check the Debug states for not asked, allowed, declined and out of date. Launch normally before and after testing and verify Allowed. Keep the existing decision and record keys. |
| Brand brief | Editing confirmed text leaves it approved, a blank brief becomes confirmed, or old Today work applies across a brief revision. | Edit and confirm a sample brief. Edit it again and check that confirmation is required. Compare the existing revision and stale-work rules. |
| Plan step by step | Helper notes confuse filming time with Reel length or obscure what happens to voice input. | Read the notes on the iPhone. Check the difference between time to film and Reel length, and keep the note about voice staying on the phone. |
| AI job phase | An old server reply fails to decode, server backoff looks like active work, or polling sends another start. | Use the existing missing-field fixture path and a fixture that reports waiting_to_retry. Check the new label, job identity and unchanged polling and Stop paths. |
| S1 and S2 regression | Approval, Stop, queue, tab clearance or navigation changes. | Run the existing sample cases, including B1–B5, on the phone. Review the S1 model rules against the changes. |
| Phone data and live budget | Install loses a login or decision, fixture data enters the live library, or an extra live attempt exceeds nine requests. | Run the three Keep checks around the in-place install and tests. Reserve three requests before each Today batch and count each live generation action. |
