# Phase D2 server failure modes

Record these cases before implementation. The scope is the Mira API, database, private Storage and provider adapters.

| Failure | Required behavior | Verification |
| --- | --- | --- |
| OpenAI stream ends mid-answer, sends invalid JSON, omits a section or reports truncation | Show progress only after a complete, valid section. Save the card only after a clean stream end and full output validation. Use S4 retry limits for interrupted transport. Reset progress on a new claim. | TesterArmy fake stream and local SQL transition checks. |
| Stream chunks divide UTF-8 characters, JSON strings, escapes or nested objects | Parse across chunk boundaries. Keep progress in idea, script and storyboard order. Do not count a field name embedded in prose. | TesterArmy fake stream with controlled chunk boundaries and staged output. |
| Cancel, lease expiry or a late write races with a step update | Accept progress only from the current, unexpired claim. Keep every other S4 transition rule. | Local SQL and TLC. |
| Duplicate status calls or retry try to generate a picture twice | Reserve each shot once under a database lock. Use one deterministic object path. Recover an uploaded image after a lost result update. Do not repeat an ambiguous paid request. | Concurrent API calls, SQL reservation checks and TLC. |
| Picture worker receives a lease that is too short | Refuse the provider call. Leave the card successful and allow the drawn fallback. | TesterArmy short-lease scenario and local SQL. |
| Edge worker reaches the maximum duration, or one image fails | Use a separate worker invocation after text success. Bound each image request and store pictures independently. Resolve expired picture leases without reopening the text job. | TesterArmy mixed outcomes and expiry recovery. Check hosted limits against Supabase documentation. |
| Duplicate requests, concurrent cards or provider failures inflate cost | Reserve against a 30-picture UTC daily cap before dispatch. Count ambiguous and failed calls. Picture work must not consume a text slot. | Local SQL cap and text admission checks. |
| Private previews leak to other members or through a public bucket | Sign only the authenticated member’s card. Deny direct reads and writes to clients. Keep the bucket private and omit object paths from the API. Send only visual shot text to the provider. | TesterArmy authorization and prompt checks, plus local Storage and SQL access checks. |
| Old apps poll a succeeded Today card, including a card with pictures from another client | Keep the old text fields, progress and terminal behavior. Run picture work and return `job.pictures` only on status requests with `pictures: true`. Preserve DeepSeek and Gemini text calls. | TesterArmy legacy status with previews enabled checks for zero picture rows and provider calls before opt-in. A legacy request after opt-in checks that the response still omits pictures. |
| Picture service or signing is unavailable | Return the valid text card. Use the drawn fallback while the picture is missing or unavailable. | TesterArmy fake service failures. |

Known trade-off before implementation. A worker that stops between reserving a shot and receiving a provider response can lose the preview. The daily cap still counts that reservation. A later opt-in status request can reconcile a saved Storage object without a second provider call.
