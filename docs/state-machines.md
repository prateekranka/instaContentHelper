# Mira state machines

## How to change a state machine

1. Edit the Swift machine or the server transition code linked below.
2. Update the diagram and table here. Update the related [TLA+ model](../specs/tla/) if the change affects a modeled rule.
3. Run these checks from the repository root.

   ```sh
   python3 scripts/check-state-machine-doc.py
   python3 scripts/check-agent-rules.py
   python3 scripts/prove-agent-rules.py
   specs/tla/run.sh
   ```

The last column gives the primary next step for each state. Conditions can change the step the creator sees. A dash means the machine supplies no step. An event with no matching rule leaves the state alone.

The store keeps the current location, library, words, request, interview, brand document, and pick states.
The speech service and insights view each keep their own state. Send an event
through the existing transition path to change one of these fields. Reel
progress, Today cards, consent, and brief state are read from other records.
The store owns the active Reel renders and applies delivery events to each project’s optional delivery record.

## `MiraReelProgress`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraReelProgress.swift)

```mermaid
stateDiagram-v2
    state "Read saved work" as workChanged
    [*] --> workChanged
    workChanged --> choosing: no idea
    workChanged --> writing: no script
    workChanged --> planning: shots missing
    workChanged --> approving: words need approval
    workChanged --> planning: shots are stale or contain different dialogue
    workChanged --> ready: ready to start
    workChanged --> filming: filming started
    workChanged --> complete: all shots filmed and checked
```

In every state, `workChanged` reads the project and follows the first matching rule in the diagram, from top to bottom. Edits and undo can return the Reel to an earlier state. Undo keeps filmed marks, review marks, and the current shot when the storyboard ID stays the same. Undoing a card change also restores the previous card selection, title, and constraints. Filming requires the current approved script, the current confirmed brief, and matching dialogue. The app joins the nonempty shot words in order and normalizes whitespace and curly quotes. If the normalized spoken text already starts with the hook, the app compares it directly with the joined shot words. Otherwise it prepends the hook.

| State | Allowed event | Next state | Next step |
| --- | --- | --- | --- |
| `choosing` | Saved work changes | First match above | Choose an idea |
| `writing` | Saved work changes | First match above | Write your script |
| `planning` | Saved work changes | First match above | Make your shot list if missing. Update shot list if old or different from the approved words. |
| `approving` | Saved work changes | First match above | Approve your words |
| `ready` | Saved work changes | First match above | Review your filming plan |
| `filming` | Saved work changes | First match above | Continue filming |
| `complete` | Saved work changes | First match above | Review your filming plan |

## `MiraAIRequest`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraAIRequest.swift)

```mermaid
stateDiagram-v2
    [*] --> saved
    state saved <<choice>>
    saved --> idle
    saved --> needsReconnect: working job
    saved --> failed
    saved --> stopped
    saved --> done
    needsReconnect --> sending: send
    waitingToStart --> sending: send
    sending --> waitingToStart: busy, try again
    sending --> needsReconnect: save or link fails, or send limit
    sending --> stopped: AI permission withdrawn before send
    sending --> active: accepted
    state active <<choice>>
    active --> working: optional generation step
    active --> waitingToRetry: server backoff
    working --> active: matching progress
    waitingToRetry --> active: matching progress
    waitingToStart --> stopping: stop
    sending --> stopping: stop
    working --> stopping: stop
    waitingToRetry --> stopping: stop
    needsReconnect --> stopping: stop
    working --> needsReconnect: link fails
    waitingToRetry --> needsReconnect: link fails
    stopping --> needsReconnect: link fails
    working --> saved: job received
    waitingToRetry --> saved: job received
    stopping --> saved: job received
    done --> done: picture status or matching image load failure
```

A saved job maps idle to `idle`, working to `needsReconnect`, failed to `failed`, cancelled to `stopped`, and succeeded to `done`. The store starts a fresh request with a new job. Every live start checks the current account and AI permission before sending text. A job from another account stays saved for its owner. A legacy job without a saved account can check existing server status. `Store read` in the table refers to the full saved-job mapping.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `idle` | — | — | — |
| `waitingToStart` | Send again. Stop. | `sending`. `stopping`. | Stop |
| `sending` | Save fails or link fails. Server accepts. Server is busy. AI permission is withdrawn. Stop. | `needsReconnect`. `working` with the job ID and optional step, or `waitingToRetry` during backoff. `waitingToStart`, or `needsReconnect` at the send limit. `stopped`. `stopping`. | Stop |
| `working` | Progress for the same job. Receive job. Link fails. Stop. | Replace the optional step in `working` or enter `waitingToRetry`. Store read. `needsReconnect`. `stopping`. | Stop |
| `waitingToRetry` | Progress for the same job. Receive job. Link fails. Stop. | `working` with the latest optional step, or `waitingToRetry` while backoff continues. Store read. `needsReconnect`. `stopping`. | Stop |
| `stopping` | Receive job. Link fails. | Store read. `needsReconnect`. | Wait |
| `needsReconnect` | Send again. Stop. | `sending`. `stopping`. | Reconnect |
| `failed` | — | — | Try again with a new job |
| `stopped` | — | — | Try again with a new job |
| `done` | Receive picture status. A picture fails to load from its current URL. | `done` with updated picture states by shot ID. A saved or newly completed job starts with an empty picture map. | — |

### Shot picture states

A successful text job can update its pictures independently. Each received picture list replaces the map. A shot missing from the list has no picture state and uses its drawn frame.

```mermaid
stateDiagram-v2
    [*] --> pictureStatus
    state pictureStatus <<choice>>
    pictureStatus --> pending: pending reply
    pictureStatus --> ready: ready reply with valid URL
    pictureStatus --> failed: failed reply or invalid ready URL
    pending --> pictureStatus: next reply
    ready --> ready: ready reply keeps current URL
    ready --> refreshing: current URL fails
    ready --> failed: refreshed URL fails within 60 seconds of the refresh request
    refreshing --> ready: different valid URL
    refreshing --> failed: same or invalid URL
    failed --> failed: ready reply
    ready --> pending: pending reply
    refreshing --> pending: pending reply
    failed --> pending: pending reply
    ready --> failed: failed reply or invalid ready URL
    refreshing --> failed: failed reply
```

| Picture state | Allowed events | Next state | Preview |
| --- | --- | --- | --- |
| `pending` | Receive picture status | `pending`, `ready` with a valid URL, or `failed` | Drawn frame while the store checks status |
| `ready` | Receive picture status. Loading the current URL fails. | Keep the current URL on a valid ready reply. Use `pending` or `failed` when the reply requires it. On a load failure, enter `refreshing` unless the refresh was requested less than 60 seconds ago, in which case enter `failed`. | AI picture |
| `refreshing` | Receive picture status | `pending`, `ready` with a different valid URL, or `failed` | Drawn frame while the store requests fresh status |
| `failed` | Receive picture status | `pending` on a pending reply. Otherwise keep `failed`. | Drawn frame |

## `MiraTodayCardState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraTodayCardState.swift)

```mermaid
stateDiagram-v2
    state "Read card and request" as workChanged
    [*] --> workChanged
    workChanged --> waiting: waiting to send
    workChanged --> making: working with optional step
    workChanged --> making: sending or stopping without step
    workChanged --> waitingToRetry: server backoff
    workChanged --> reconnect: link needed
    workChanged --> failed: failed, idle or stopped
    workChanged --> ready: valid result for this brief with any pictures
    workChanged --> needsUpdate: result missing parts or out of date
    ready --> ready: make or retry
    failed --> failed: retry
    needsUpdate --> needsUpdate: retry
```

`workChanged` works from any state. A ready result has one idea, a script, and a shot list for the current brief. Picture status does not affect readiness. Make and Retry let the store act. The next projection reflects its changes.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `waiting` | Card or request changes | Read card and request | Stop |
| `making` | Card or request changes | Read card and request. Keep prior output when available. Use the step from a working request. | Wait |
| `waitingToRetry` | Card or request changes | Read card and request | Stop |
| `reconnect` | Card or request changes | Read card and request | Reconnect |
| `failed` | Card or request changes. Retry. | Read card and request. `failed`. | Try again |
| `ready` | Card, request or picture state changes. Make or retry. | Read the current result and picture map. `ready`. | Make this one |
| `needsUpdate` | Card or request changes. Retry. | Read card and request. `needsUpdate`. | Update this idea |

### Today wait steps

The diagram shows how each server snapshot sets the wait screen for a card that is making its first result. A poll can skip steps. The card becomes ready after text success and validation.

```mermaid
stateDiagram-v2
    state "Read working request" as progress
    [*] --> progress
    progress --> simpleWait: step absent or unknown
    progress --> writingWords: ideaReady
    progress --> planningShots: scriptReady
    progress --> stepsDone: storyboardReady
```

| Generation step | Server value | Wait screen |
| --- | --- | --- |
| No step | Absent or unknown | Simple wait screen |
| `ideaReady` | `idea_ready` | Finding an idea is complete. Writing your words is in progress. |
| `scriptReady` | `script_ready` | The idea and words are complete. Planning shots is in progress. |
| `storyboardReady` | `storyboard_ready` | All three steps are complete. Wait for text success. |

## `MiraWordsState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraWordsState.swift)

```mermaid
stateDiagram-v2
    [*] --> reviewing
    state "Read request and project" as read
    read --> opening: still opening
    read --> waiting: waiting to send
    read --> waitingToRetry: server backoff
    read --> writing: sending or working
    read --> reconnecting: link needed
    read --> stopping: stop sent
    read --> proposal: new words
    read --> applyingShots: approved words and matching shot update job ID
    read --> needsShots: old shots or rejected update
    read --> retry: failed or stopped revision
    read --> ready: approved
    read --> reviewing: approval needed
    reviewing --> changing: change
    ready --> changing: change
    changing --> changing: note
    changing --> reviewing: cancel
    retry --> reviewing: retry or keep
    needsShots --> updatingShots: retry starts a new job
    updatingShots --> applyingShots: matching job succeeds
    proposal --> reviewing: use or keep
    ready --> opening: review the shot list
    applyingShots --> opening: shots applied
    applyingShots --> shotUpdateFailed: shots rejected
    shotUpdateFailed --> needsShots: read same rejected job
    opening --> reviewing: screen opens
```

On every read, the current request can set the view state. The screen keeps an open edit when the project and request allow it. `requestStarted` records the ID of a shot update from Your words or resets the state to `reviewing` for a script request. After relaunch, the creator reviews a finished shot update in the Reel editor because Your words keeps its automatic apply intent in memory. `appeared` keeps the state except when it clears `opening`. A send uses a nonempty note and keeps the state until the request starts.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `reviewing` | Change. Send. Approve. | `changing`. `reviewing`. `reviewing`, then read project. | Approve your words |
| `changing` | Edit note or send. Cancel. | `changing`. `reviewing`. | Send |
| `opening` | Screen opens | `reviewing` | Wait |
| `updatingShots` | A shot update starts from Your words. Read its result. | Read the request while it runs. `applyingShots` on success with the matching job ID. | Wait |
| `shotUpdateFailed` | Read the same rejected job | `needsShots` | Try again |
| `waiting` | Stop | `waiting`, then read request | Stop |
| `waitingToRetry` | Stop | `waitingToRetry`, then read request | Stop |
| `writing` | Stop | `writing`, then read request | Stop |
| `reconnecting` | Check again or stop | `reconnecting`, then read request | Check again |
| `stopping` | Read stop result | Read request and project | Wait |
| `proposal` | Use new words or keep current words | `reviewing` | Use this |
| `retry` | Retry or keep the current words | `reviewing` | Try again |
| `needsShots` | Retry | `updatingShots` when the request starts | Try again |
| `applyingShots` | Receive result. Apply shots. Reject shots. | `applyingShots`. `opening`. `shotUpdateFailed`. | Wait |
| `ready` | Change. Send. Review the shot list. | `changing`. `ready`. `opening`. | Review your filming plan |

When the creator requests a shot update from the editor and the words need approval, the button opens Your words. The store checks approval and dialogue before opening the reviewed shot list from Words. If the check fails, it restores the prior words state. Shooting has its own approval and dialogue checks. A rejected shot update keeps Try again available. A proposal from the editor requires Use this.

## `MiraLocationState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraLocation.swift)

```mermaid
stateDiagram-v2
    [*] --> savedTab
    state savedTab <<choice>>
    savedTab --> home: saved Today
    savedTab --> myBrand: saved Projects
    home --> myBrand: select or open My Brand
    myBrand --> home: select or open Home
    home --> deals: select Deals
    myBrand --> deals: select Deals
    deals --> home: select or open Home
    deals --> myBrand: select or open My Brand
```

All tabs accept `selectTab`, `open`, `setPath`, `push`, `showWords`, `showPlan`, `remember`, and `remove`.
Only selection and open change the active tab. Each tab keeps its own remembered section for each Reel while the app runs.
Show Plan opens the editor at Shots in the current tab. Show Words replaces trailing filming or Done destinations. Remove clears the Reel from all tab paths and section histories.
Home and My Brand use the existing `today` and `projects` saved paths and tab values. My Brand restores each Reel's saved editor section. Home restores the active destinations from its saved path and position. Deals restores the last selected saved tab on relaunch.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `home` | Select or open a tab. Update path or history. | Selected tab or `home` | Use the current destination |
| `deals` | Select or open a tab. Update path or history. | Selected tab or `deals` | Share a brand brief to Mira |
| `myBrand` | Select or open a tab. Update path or history. | Selected tab or `myBrand` | All Reels |

### `MiraLocation`

```mermaid
stateDiagram-v2
    [*] --> route
    state route <<choice>>
    route --> editor: project route
    route --> todayCards: Today cards route
    route --> words: words route
    route --> filming: shooting route
    route --> done: Done route
    route --> [*]: empty path
```

The last route on the active tab gives the current destination. Changing the path can select any destination in the table. An empty path has no current destination.

| State | Allowed event | Next state | Next step |
| --- | --- | --- | --- |
| `editor` | Change active path | Last route or no destination | Review your filming plan |
| `todayCards` | Change active path | Last route or no destination | Make this one |
| `words` | Change active path | Last route or no destination | Approve your words |
| `filming` | Change active path | Last route or no destination | Continue filming |
| `done` | Change active path | Last route or no destination | — |

## `MiraHomeFeed`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraHomeFeed.swift)

```mermaid
stateDiagram-v2
    state "Read the library" as workChanged
    [*] --> workChanged
    workChanged --> empty: no open deals or unfinished Reels
    workChanged --> deals: open deals and no unfinished Reels
    workChanged --> continuing: unfinished Reels, with or without deals
```

The store projects the feed from the library and the last opened Reel. It excludes archived and empty projects. A filmed Reel stays in Home until the creator confirms posting and, for a linked deal, confirms the brand note.
The most recently opened unfinished Reel appears first. The other Reels use their last update time.
Home includes confirmed, unpaid deals. Deals with dates appear in deadline order. Deals without dates follow them. The Deals tab keeps all confirmed deals. A pick in progress or ready appears on Home with these cards.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `empty` | Work changed | Read the library | Make today's Reel |
| `continuing` | Work changed | Read the library | Each Reel uses the next step from Reel progress. Each deal opens its card. |
| `deals` | Work changed | Read the library | Open deal |

## `MiraTaskStep`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraTaskStep.swift)

```mermaid
stateDiagram-v2
    state "Read current location" as route
    [*] --> route
    route --> idea
    route --> words
    route --> shotList
    route --> shoot
    route --> upload
    route --> deliver
```

The location and current editor section choose the visible step. The approval gate still controls filming. Step 5 opens clip matching. Step 6 opens after Mira saves an export for the current clip plan.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `idea` | Read open location | Step for that location | Choose an idea |
| `words` | Read open location | Step for that location | Use the words state or script editor |
| `shotList` | Read open location | Step for that location | Review the list and go shoot when permitted |
| `shoot` | Read open location | Step for that location | Mark the current shot filmed |
| `upload` | Read the existing Done route with an approved plan and no current export | `upload` | Add your clips |
| `deliver` | Read the same route with an approved plan and a current export | `deliver` | Watch your Reel |

## `MiraBrandInterview`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraBrandInterview.swift)

```mermaid
stateDiagram-v2
    idle --> answering: Start
    answering --> answering: Edit, Back or Next
    answering --> generating: Submit six answers
    generating --> idle: Receive document draft
    generating --> failed: Request fails
    failed --> generating: Retry
    failed --> answering: Edit answers
    answering --> idle: Cancel
    failed --> idle: Cancel
```

The interview keeps a question index and six answers in memory. Only a reply
for the current job can finish the interview. The draft moves to
`MiraBrandDocumentState`. The existing speech machine handles permission,
recording, and the Settings action on denial.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `idle` | Start. Reset. | `answering`. `idle`. | Start the interview |
| `answering` | Edit. Back. Next with an answer. Generate with the last answer. Reset. | Update the answer or question index. `generating` for Generate. `idle` for Reset. | Next, or Make my brand doc |
| `generating` | Receive a draft for the current job. Fail the current job. Reset on account change. | `idle`. `failed`. `idle`. | Wait |
| `failed` | Generate again. Back. Reset. | `generating`. `answering`. `idle`. | Try again |

## `MiraBrandDocumentState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraBrandDocumentState.swift)

```mermaid
stateDiagram-v2
    [*] --> empty: Read library without a doc
    [*] --> confirmed: Read library with a doc
    empty --> reviewing: Receive draft
    reviewing --> reviewing: Change an item
    reviewing --> confirmed: This is me
    confirmed --> reviewing: Edit
    reviewing --> empty: Cancel with no saved doc
    reviewing --> confirmed: Restore saved doc
```

The optional `MiraDocument.brandDoc` holds the confirmed value. The draft
stays in memory. Generation reads the confirmed value while the creator edits.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `empty` | Read saved value. Receive a valid draft. | `empty` or `confirmed`. `reviewing`. | Start the interview |
| `reviewing` | Change draft. Confirm valid draft. Read saved value on cancel. | `reviewing`. `confirmed` and save. `empty` or `confirmed`. | This is me |
| `confirmed` | Edit. Read saved value. | `reviewing`. `empty` or `confirmed`. | Edit my brand doc |

## `MiraPickState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraPickState.swift)

```mermaid
stateDiagram-v2
    idle --> working: Ask for a pick
    working --> working: Receive progress
    working --> ready: Receive valid pick and reason
    working --> failed: Request fails
    ready --> working: Ask for another pick
    ready --> idle: Make this one
    failed --> working: Try again
```

The store keeps the current pick and skipped titles in memory. The input
uses the confirmed brand document and the checklist from the latest confirmed
unpaid deal. Mira omits the checklist if that deal has no items or there is no
active deal. Instagram-derived context requires a separate saved choice for
the active creator. The store validates the job, the returned idea, the reason,
and the matching words and shots before presenting the pick. On Make, the store
checks that the deal and checklist still match. A change resets the pick. The
new Reel keeps the checklist revision and item IDs in its confirmed brief.
The store opens Your words. Only the accepted pick gives the saved shot list a
picture source.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `idle` | Start. Reset. | `working`. `idle`. | Make today's Reel |
| `working` | Progress, receive or fail the current job. Reset. | `working`, `ready` or `failed`. `idle`. | Wait |
| `ready` | Start another. Make. Reset. | `working` with the previous result. `idle` after making the Reel. `idle`. | Make this one |
| `failed` | Start again. Reset. | `working`. `idle`. | Try again |

## `MiraVoiceInputState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraVoiceInputState.swift)

```mermaid
stateDiagram-v2
    [*] --> idle
    idle --> askingPermission: start
    failed --> askingPermission: start
    askingPermission --> recording: recording starts
    askingPermission --> denied: permission denied
    askingPermission --> failed: start failed
    askingPermission --> idle: stop
    denied --> idle: speech allowed and microphone can be requested
    recording --> recording: tick
    recording --> finishing: stop
    finishing --> idle: words captured
    finishing --> failed: finish failed
```

Replies and ticks must match the current attempt ID. Stop also runs when capture ends or reaches 60 seconds.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `idle` | Start | `askingPermission` | Use microphone |
| `askingPermission` | Starts. Denied. Fails. Stop. | `recording`. `denied`. `failed`. `idle`. | Wait |
| `denied` | Speech is allowed and microphone access is granted or undecided | `idle` | Open Settings |
| `recording` | Tick. Stop. | `recording`. `finishing`. | Stop recording |
| `finishing` | Finish with words or an error | `idle` or `failed` | Wait |
| `failed` | Start | `askingPermission` | Use microphone |

## `MiraInsightsState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraInsightsState.swift)

```mermaid
stateDiagram-v2
    [*] --> unopened
    unopened --> loading: load
    loaded --> loading: check again
    loadFailed --> loading: check again
    loaded --> connecting: disconnected or permission needed
    connectionFailed --> connecting: connect
    connecting --> loading: connected
    connecting --> loaded: login cancelled
    connecting --> connectionFailed: login failed
    loading --> loaded: got report or restored prior result
    loading --> unopened: cancelled with no prior result
    loading --> loadFailed: read failed
```

Each reply must match the current attempt ID. A failed refresh retains the previous result when one exists.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `unopened` | Load | `loading` | Wait |
| `loading` | Read result. Read fails. Cancel. | `loaded`. `loadFailed`. `loaded` with prior result or `unopened`. | Wait |
| `connecting` | Connected. Login fails. Cancel. | `loading`. `connectionFailed`. `loaded` with its prior result. | Wait |
| `loaded` | Load again. Connect when disconnected or when permission is needed. | `loading`. `connecting`. | Connect Instagram if disconnected. Connect again if permission is needed. Otherwise use Check again. |
| `loadFailed` | Load again | `loading` | Check again |
| `connectionFailed` | Connect again | `connecting` | Connect Instagram |

## `MiraLibraryState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraLibraryState.swift)

```mermaid
stateDiagram-v2
    [*] --> unopened
    unopened --> opening: open
    openFailed --> opening: try again
    opening --> loaded: opened
    opening --> openFailed: read failed
    loaded --> loaded: save result or alert change
```

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `unopened` | Open | `opening` | Wait |
| `opening` | Opened. Open fails. | `loaded`. `openFailed`. | Wait |
| `openFailed` | Open again | `opening` | Update Mira for a newer save. Otherwise try opening saved work again. |
| `loaded` | Save succeeds or fails. Show or dismiss alert. | `loaded` | Continue |

## `MiraAIConsentState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraAIConsentState.swift)

```mermaid
stateDiagram-v2
    state "Read consent" as read
    [*] --> read
    read --> notAsked: no record
    read --> outOfDate: version changed
    read --> allowed: current Allow
    read --> declined: current Decline
```

The machine reads the record from any state. Allow and Decline save a choice for the next read.

| State | Allowed event | Next state | Next step |
| --- | --- | --- | --- |
| `notAsked` | Read record | Match the record above | Review AI permission |
| `allowed` | Read record | Match the record above | Continue |
| `declined` | Read record | Match the record above | Review AI permission |
| `outOfDate` | Read record | Match the record above | Review AI permission |

## `MiraBriefState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraBriefState.swift)

```mermaid
stateDiagram-v2
    state "Read updated brief" as read
    [*] --> read
    read --> confirmed: approved
    read --> unresolved: open details
    read --> reviewing: has requirements
    read --> draft: text only
    read --> empty: no text
    empty --> read: enter text
    draft --> read: extract or edit
    reviewing --> read: confirm, extract, or edit
    unresolved --> read: confirm, extract, or edit
    confirmed --> read: edit, extract, or stop using
```

In any state, a changed text, a changed existing detail, removal, extraction, or Stop using clears approval. Confirm works if there is at least one requirement and all excerpts and values occur in the original text. Each accepted event adds one to the revision and reads the updated brief in the order shown.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `empty` | Edit, remove, extract or stop using. Confirm if valid. | Read updated brief | Enter brand requirements |
| `draft` | Edit, remove, extract or stop using. Confirm if valid. | Read updated brief | Extract proposed requirements |
| `reviewing` | Edit, remove, extract or stop using. Confirm if valid. | Read updated brief | Confirm these requirements if valid. Otherwise extract proposed requirements. |
| `unresolved` | Edit, remove, extract or stop using. Confirm if valid. | Read updated brief | Confirm these requirements if valid. Otherwise extract proposed requirements. |
| `confirmed` | Edit, remove, extract or stop using. Confirm if valid. | Read updated brief | Edit brand requirements |

## `MiraDealBriefState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraDealBriefState.swift)

```mermaid
stateDiagram-v2
    [*] --> empty
    empty --> editing: begin
    editing --> editing: edit
    editing --> reading: read
    reading --> reconnect: interruption or reopen
    reconnect --> reading: resume
    reading --> failed: rejected or invalid result
    reading --> reviewing: valid result
    failed --> reading: retry
    failed --> editing: edit
    reviewing --> editing: edit
    reviewing --> empty: confirm and save card
```

The store saves the draft and request ID before it sends a new request. A reconnect checks the same ID. If the server does not know that ID, Mira sends the original input with the same ID. Start requires current AI permission. Mira checks the job owner and matches each reply to the job ID, revision and input. The result must quote the source. The creator checks it before the deal appears in Deals or Home.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `empty` | Begin with pasted or shared text | `editing` | Paste a brief |
| `editing` | Edit. Read valid text. Open a shared brief when the draft is empty. | `editing`, `reading` | Read this brief |
| `reading` | Receive a matching terminal reply. Record an interruption. | `reviewing`, `failed` or `reconnect` | Wait |
| `reconnect` | Resume | `reading` | Reconnect |
| `failed` | Edit. Read valid text with a new request. | `editing`, `reading` | Try again |
| `reviewing` | Edit. Confirm with the card transition. | `editing`, `empty` | Looks right |

## `MiraDealCardState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraDealCardState.swift)

```mermaid
stateDiagram-v2
    [*] --> reviewing
    reviewing --> saved: confirm
    saved --> saved: valid tracker event
```

The card keeps the original brief and the reviewed terms. The latest unpaid deal supplies the active checklist to `pickIdea`. An empty checklist supplies no value.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `reviewing` | Confirm | `saved` | Looks right |
| `saved` | Apply a valid tracker event | `saved` | Open deal |

## `MiraDealTrackerState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraDealTrackerState.swift)

```mermaid
stateDiagram-v2
    [*] --> toPost
    toPost --> toTellBrand: posted
    toTellBrand --> toConfirm: brand told
    toConfirm --> toPay: confirmed
    toPay --> paid: paid
```

The saved dates determine the current action. Each event records its own date and preserves earlier dates. A repeated or out-of-order event leaves the card unchanged.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `toPost` | Posted | `toTellBrand` | Mark as posted |
| `toTellBrand` | Brand told | `toConfirm` | Mark brand told |
| `toConfirm` | Confirmed | `toPay` | Mark as confirmed |
| `toPay` | Paid | `paid` | Mark as paid |
| `paid` | — | — | — |

## `MiraClipMatchState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraClipMatchState.swift)

```mermaid
stateDiagram-v2
    empty --> matching: import some clips
    empty --> matched: fill all shots on import
    matching --> matching: import or assign
    matching --> matched: fill the final shot
    matched --> matched: import or swap
```

The store keeps clip copies in the project library. It keeps a separate match list for each shot-list revision. The match uses clip duration, recording time when available, and pick order. Assigning a clip that another shot uses exchanges the two matches. A short match stays visible until the creator picks a longer clip.

| State | Events | Next state | Next action |
| --- | --- | --- | --- |
| `empty` | Import | `matching` or `matched` | Add your clips |
| `matching` | Import, assign or swap | `matching` or `matched` | Add your clips |
| `matched` | Import, assign or swap | `matched` | Join your Reel |

## `MiraReelJoinState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraReelJoinState.swift)

```mermaid
stateDiagram-v2
    needsClips --> ready: complete usable clip plan
    ready --> rendering: build
    rendering --> failed: failed
    rendering --> finished: rendered
    failed --> rendering: build again
    finished --> ready: matches changed
```

The store accepts the export only if its render ID and recipe match. The export remains current only while its recipe matches the approved shot list, clip assignments and overlay text.

| State | Events | Next state | Next action |
| --- | --- | --- | --- |
| `needsClips` | Read a usable clip plan | `ready` | Add your clips |
| `ready` | Build | `rendering` | Join your Reel |
| `rendering` | Receive a matching export or failure | `finished` or `failed` | Wait |
| `failed` | Build again | `rendering` | Try again |
| `finished` | Read a changed plan | `ready` or `needsClips` | Watch your Reel |

## `MiraDeliveryBriefState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraDeliveryBriefState.swift)

```mermaid
stateDiagram-v2
    unchecked --> checking: start
    checking --> reviewed: receive valid checks
    checking --> interrupted: lose contact
    checking --> rejected: receive terminal failure
    interrupted --> checking: reconnect to same request
    rejected --> checking: start again
    reviewed --> reviewed: approve a fix
    reviewed --> unchecked: check input changed
```

The reviewed checklist and text from the current export form the request. Mira checks coverage of all IDs and checks evidence for the required text. Footage and audio require separate review. A caption fix appends text. An approved on-screen fix saves a replacement export before its check changes to Met.

| State | Events | Next state | Next action |
| --- | --- | --- | --- |
| `unchecked` | Start | `checking` | Check the brief |
| `checking` | Receive, interrupt or reject | `reviewed`, `interrupted` or `rejected` | Wait |
| `interrupted` | Start with the same saved job | `checking` | Reconnect |
| `rejected` | Start a new job | `checking` | Try again |
| `reviewed` | Apply an approved fix or request a new check | `reviewed` or `checking` | Share to Instagram |

## `MiraReelPostState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraReelPostState.swift)

```mermaid
stateDiagram-v2
    ready --> shared: present share sheet
    shared --> shared: present again
    shared --> posted: creator confirms
    posted --> live: verified Instagram Reel link
```

The share sheet receives only the local export. The app copies the caption for the creator. The post confirmation must refer to the shared export. The current Instagram endpoint has no post identity, so the live transition has no production caller. The creator confirmation records Posted and updates the linked deal.

| State | Events | Next state | Next action |
| --- | --- | --- | --- |
| `ready` | Present the share sheet | `shared` | Share to Instagram |
| `shared` | Present again or confirm posting | `shared` or `posted` | Yes, I posted it |
| `posted` | Receive a verified link if it becomes available | `live` | Write the WhatsApp note or watch your Reel |
| `live` | — | — | Write the WhatsApp note or watch your Reel |

## `MiraTellBrandState`

[Swift source](../CreatorContentOS/Mira/Core/StateMachines/MiraTellBrandState.swift)

```mermaid
stateDiagram-v2
    needsNote --> writing: start
    writing --> draft: receive note
    writing --> interrupted: lose contact
    writing --> rejected: receive terminal failure
    interrupted --> writing: reconnect to same request
    rejected --> writing: start again
    draft --> opened: open WhatsApp or its link
    opened --> sent: creator confirms
```

Mira gives WhatsApp the text and a brand number the creator enters. The message remains a draft until the creator confirms sending it. Only that confirmation advances the linked deal to Brand told in the Reel flow.

| State | Events | Next state | Next action |
| --- | --- | --- | --- |
| `needsNote` | Start | `writing` | Write the WhatsApp note |
| `writing` | Receive, interrupt or reject | `draft`, `interrupted` or `rejected` | Wait |
| `interrupted` | Start with the same saved job | `writing` | Reconnect |
| `rejected` | Start a new job | `writing` | Try again |
| `draft` | Open WhatsApp or its link | `opened` | Send to the brand |
| `opened` | Open again or confirm sending | `opened` or `sent` | Yes, I sent it |
| `sent` | — | — | Open deal |

## Server text job

[Status schema](../supabase/migrations/20261026170000_mira_generation_jobs.sql) · [Current transition rules](../supabase/migrations/20261128040000_mira_astra_server_fixes.sql) · [Worker and API mapping](../supabase/functions/mira-generation/index.ts) · [Model](../specs/tla/MiraJobs.tla)

```mermaid
stateDiagram-v2
    [*] --> absent
    absent --> queued: request accepted
    absent --> stoppedBeforeStart: stop records job ID and scope
    queued --> running: claim
    queued --> failed: expires
    queued --> cancelled: stop
    running --> running: dispatch, progress, save output or reclaim before dispatch
    running --> queued: retry later
    running --> succeeded: finish with saved output
    running --> failed: failure or expiry
    running --> cancelled: stop
```

A lease gives a worker time to finish. A new claim needs a due job, fewer than three attempts, and a lease of at least 90 seconds. An unexpired claim can report progress in order from idea to script to shot list for `todayIdea` or `pickIdea`. A new claim resets progress. Daily Note gets one claim on the same UTC day and cannot return to the queue.

Stop before admission records the job ID, workspace, creator, and member. The API retains the existing 404 for this Stop and refuses a later start in that scope.

The worker records dispatch before calling the provider. It saves validated output before completing the job. A later claim completes saved output without spending an attempt. If the lease expires after dispatch and the database has no saved output, the job fails. A failed job requires an error.

The API maps queued and running rows to working requests. It exposes output after success. It reports `waiting_to_retry` during backoff or after an undispatched claim expires with attempts available. The Swift request and screen machines choose the visible next step.

| State | Allowed events | Next state | Next step |
| --- | --- | --- | --- |
| `queued` | Claim when due. Expire. Stop. | `running`. `failed`. `cancelled`. | Wait for the claim |
| `running` | Dispatch, report progress or save output. Reclaim after expiry before dispatch. Retry a temporary provider error. Finish with saved output. Fail or expire. Stop. | `running`. `running`. `queued`. `succeeded`. `failed`. `cancelled`. | Wait for the result or retry |
| `succeeded` | — | — | Open or review the result |
| `failed` | — | — | Try again if the screen offers it |
| `cancelled` | — | — | Try again if the screen offers it |

## Server picture job

[Status schema](../supabase/migrations/20261127200000_mira_steps_and_shot_pictures.sql) · [Current claim rules](../supabase/migrations/20261128040000_mira_astra_server_fixes.sql) · [Worker](../supabase/functions/mira-generation/shot-pictures.ts) · [Model](../specs/tla/MiraShotPictures.tla)

```mermaid
stateDiagram-v2
    [*] --> unreserved
    unreserved --> generating: opt in and reserve
    unreserved --> failed: opt in after cap reached
    generating --> ready: upload saved or found after expiry
    generating --> failed: call failed or no saved file after expiry
    failed --> ready: upload finishes or status finds the file
    ready --> ready: sign another link
```

The first request for pictures on a completed, enabled card can reserve each shot UUID once. UUID comparisons ignore case. The cap is 30 per member and reservation UTC day. A reservation holds a slot until dispatch, failure, or expiry. Failure or expiry before dispatch releases the slot. Picture jobs use separate slots from text jobs. Text stays usable while pictures finish.

| State | Allowed events | Next state | Next step in the picture contract |
| --- | --- | --- | --- |
| `unreserved` (no row) | Request pictures on an eligible card | `generating` if a slot is free. Otherwise `failed`. | Use the shot plan |
| `generating` | Save upload. Call fails. Check expired claim. | `ready`. `failed`. `ready` if a saved file exists, else `failed`. | Use the drawing while the preview is pending |
| `ready` | Read or refresh link | `ready` | View the picture when the link is available |
| `failed` | The same upload finishes or status finds its object | `ready` | Use the drawing until the picture is ready |

The picture API returns `pending` during generation or when it cannot sign a ready picture's link. The table describes the API contract. The client must opt in to show the previews.

The shared TLA+ suite covers bounded S1 and D2 behavior. [Phase E evidence](mira-evidence/2026-11-28-phase-e-server.md) covers its additional limits and Daily Note rules.
