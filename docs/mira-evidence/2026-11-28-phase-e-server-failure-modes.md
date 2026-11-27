# Mira Phase E server failure modes

Baseline `8405e89` on `claude/mira-e-server`. This plan precedes the implementation.

| Failure | Required behavior and proof |
| --- | --- |
| A new request has unknown fields, lacks AI consent, or carries an Instagram token. | Reject it before enqueue. Use only the optional Instagram data in the admitted request. Cover requests with and without Instagram data in API e2e. |
| An interview, caption, brief or other shared string contains instructions. | Keep it in the provider's data message. Validate provider output independently. Observe the fixture request and reject bad output for all six operations. |
| Brand or idea output adds unsupported history, metrics or trends. | Use only supplied context. Validate the document shape, idea count, skipped titles and linked artifacts. Verify real wording and factual grounding separately with a reviewed provider run. |
| Brief extraction changes a quote, fabricates a fee, code or disclosure, or guesses a date. | Check source strings against the brief. Require a source date for a normalized deadline and an unresolved note when a date is unclear. Exercise invalid responses through the endpoint. |
| Brief check certifies video, drops a checklist item, or offers a video edit. | Check every supplied item ID once. Require exact supplied text evidence to mark a text item met. Allow fixes to caption or on-screen text only. Cover missing visual items and invalid evidence in e2e. |
| Brand note invents a post link or the daily note links to a missing task. | Use the supplied link only. Check daily action targets against the input. Check numeric grounding and language instructions. |
| Concurrent jobs, retries or a lost result exceed an operation's daily cap. | Reserve provider attempts in the SQL claim transaction. Count failed and interrupted attempts. Exercise limits, contention and retry accounting with local PostgREST. Model the new rules with TLC. |
| Concurrent daily-note requests create separate claims, or cache reuse exposes another creator's note. | Reuse one job per member and UTC day within its creator and workspace scope. Retain its terminal result. An interrupted attempt consumes the day. Exercise races, scope, cancellation and day rollover. |
| A provider call outlives its lease or a stale worker writes a result. | Apply the per-operation deadline and existing lease filter. Cover a short remaining lease and run the agent rules. |
| The daily note bypasses the active-job limit or a new operation changes an old response. | Count uncached daily notes in the existing three queued/running slots. Return cached jobs before admission checks. Re-run legacy API and D2 picture opt-in scenarios. |
| A pick starts pictures without opt-in or repeats reservations when clients poll. | Use the D2 picture status opt-in and separate picture cap. Verify text progress and picture reuse with fixtures. |
| Migration runs twice or during an old Edge deployment. | Preserve function signatures, old job data and old transitions. Apply and replay against local Supabase. Check undo SQL in a rolled-back transaction. |
