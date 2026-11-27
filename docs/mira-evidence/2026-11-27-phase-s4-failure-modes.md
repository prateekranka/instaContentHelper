# Phase S4 failure modes

Recorded before implementation on the `725c646` baseline.

| Failure | Expected behavior and check |
| --- | --- |
| A claim expires before its provider request ends. A second worker starts a request and can discard the first result. | Model both requests and the stale result in TLC. Give each call a lease sized from its timeout. Verify both adapters receive the worker deadline. |
| A claim is too short, or its reply arrives with too little time remaining. | Reject a short duration in SQL. Refuse the provider call and log the missing lease budget if the returned expiry is too close. |
| An active lease is reclaimed or an attempt is skipped. | Reject updates that change a running claim without expiry, a new lease ID and one additional attempt. Preserve the three-attempt limit. |
| A transient failure cannot return to the queue. | Verify a real worker retry state and keep the existing backoff. |
| A staff or worker update revives a terminal job or skips the claim. | Reject forbidden updates in PostgreSQL. Preserve cancellation, stale-job failure, and writes from the current lease owner. |
| An expired job is shown as active work or a legacy client loses its status mapping. | Verify the additive phase on the endpoint. Inspect the existing Swift decoder. |
| The migration breaks existing rows or old Edge workers. | Install the trigger without scanning rows. Keep the one-argument claim and its 90-second lease. Exercise both claim signatures and service-role privileges. |
| Cancel reaches the server before a start creates its row. | S4 guards existing rows. A missing-row cancel still returns `not_found`. The S1 late-start race needs a separate admission or cancellation protocol. |

## Baseline status writes

| From | To | Writer |
| --- | --- | --- |
| Queued | Running | `mira_claim` starts a ready attempt. |
| Running | Running | `mira_claim` reclaims an expired lease with attempts left. |
| Running | Queued | The Edge worker schedules a transient failure with attempts left. |
| Running | Succeeded | The Edge worker saves a result under its lease ID. |
| Queued | Failed | `mira_enqueue` expires an unreconciled job. |
| Running | Failed | The worker fails a job, or SQL expires a job or an exhausted lease. |
| Queued or running | Cancelled | The cancel endpoint updates an existing active job. |

`mira_enqueue` inserts new rows in `queued`. The existing code never updates a terminal job. No existing write goes directly from `queued` to `succeeded`.
