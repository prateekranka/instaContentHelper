# ContentHelper screen index

Each board has four numbered screens. The numbers identify feedback targets; they are not a promise that every screen appears in one linear sequence.

| ID | Screen | Route and next action |
|---|---|---|
| 01 | Quick choices | New creator; retain topic and language through Make my first plan |
| 02 | AI choice | Before AI work; Allow AI or continue manually |
| 03 | Save your work | Apple sign-in; return to the requested draft after sign-in |
| 04 | First day empty | Alternate home after Skip/manual entry; create or write a piece |
| 05 | Today | Several pieces and separate states; open a piece, Add content, Review day |
| 06 | New content | Choose date, topic, format and effort; create or write draft |
| 07 | Review draft | Review script, shots and caption; edit or approve |
| 08 | Approved piece | Open approved version, start filming or create an edit |
| 09 | Plan | Calendar and selected day's pieces; open date or add content |
| 10 | Past day | Revisit earlier pieces; review, edit or add another piece |
| 11 | Content detail | Open script/shots/caption/versions and date; start filming |
| 12 | Move content | Choose another planned date without losing work |
| 13 | Edit script | Save draft changes; AI suggestions require review before replacement |
| 14 | Edit shots | Add, reorder and change shots while preserving their media links |
| 15 | Edit caption | Keep platform variants; accessibility notes are local for video plans |
| 16 | Versions | Preview revisions and compare a draft with approved work |
| 17 | Continue filming | Same saved shot; Mark captured, Previous or Pause |
| 18 | Attach clip | Review selected uploaded footage; Use this clip |
| 19 | All shots ready | Review captured shots; Mark as shot |
| 20 | Ready to post | Select final media and platform captions; Prepare to post |
| 21 | Post options | Select account/platform target; review each separately |
| 22 | Instagram review | Eligible account's reviewed direct-post route or finish externally |
| 23 | TikTok review | Audience initially unset, interactions unchecked, commercial disclosures |
| 24 | Post results | Separate platform outcomes; verified result or explicit manual mark |
| 25 | Your content | You → Your content; search/filter history and open rows directly |
| 26 | Past posted content | Open live post and saved version; Make changes |
| 27 | Reapprove edits | Compare old approval and new draft; review affected filming |
| 28 | Edit posted item | Local notes or new publishing revision; original record remains |
| 29 | You | Preferences, privacy, accounts, reminders and saved content |
| 30 | Connected accounts | Connection status, optional connect/reconnect routes |
| 31 | Account detail | Named account access, reconnect/disconnect and retained work |
| 32 | Post insights | Available metrics, fetch time, private note and follow-up draft |
| 33 | Review day | Select reviewed pieces; approve the stated count without publishing |
| 34 | Day ready | Approved day's pieces; add more or start filming |
| 35 | Draft generation failure | Preserved idea; retry or write manually |
| 36 | Offline edits | Local save and pending sync; keep editing, reconnect before posting |
| 37 | Voice and topics | Topics, language, tone, preferred words and words to avoid |
| 38 | Reminders | Opt-in days/time/timezone and a separate posting reminder |
| 39 | AI and privacy | Task-level choices, separate upload permission, export/delete entry |
| 40 | Appearance | System/light/dark; monochrome UI with media colors retained |

Content review, filming, editors and posting can be presented as a focused modal navigation stack. Today, Plan, You, past-day browsing, Your content and account browsing retain their main tab context. Raster boards illustrate the layout direction; the implementation must apply that presentation rule consistently.

The primary Today action depends on the current unfinished task. Review day belongs in the day's toolbar/menu, beside a visible count of pieces that need review. Add content remains visible even when a Continue filming action has priority.
