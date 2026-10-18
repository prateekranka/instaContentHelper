# ContentHelper static copy ledger

Pinned source: `20766cd90fd6338592d8fb7792395f566eda1205` on branch `cursor/today-ui-prototype-cea4`.
Scope: `CreatorContentOS/` Swift UI chrome only. Excludes HTML prototype, fixture seed data, and model-generated script/caption/scene body text (presentation wrappers included).
Product note: launch bar = first useful package after Apple sign-in; sharing is separate. Do not call a generated card a shared post.

Columns: `ID | screen/state | file:line | existing text | keep/cut/rewrite | proposed text | information/action/safety job | evidence`

| ID | screen/state | file:line | existing text | disposition | proposed text | job | evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| COPY-0001 | AppRuntime | `CreatorContentOS/App/AppRuntime.swift:12` | Creator | keep | Creator | information |  |
| COPY-0002 | AppRuntime | `CreatorContentOS/App/AppRuntime.swift:55` | Creator | keep | Creator | information |  |
| COPY-0003 | AppRuntime | `CreatorContentOS/App/AppRuntime.swift:138` | Loading today's card | keep | Loading today's card | state |  |
| COPY-0004 | AppRuntime | `CreatorContentOS/App/AppRuntime.swift:148` | Loading daily content | keep | Loading daily content | state |  |
| COPY-0005 | AppRuntime | `CreatorContentOS/App/AppRuntime.swift:162` | Loading sources | keep | Loading sources | state |  |
| COPY-0006 | AppRuntime | `CreatorContentOS/App/AppRuntime.swift:163` | Checking Supabase | keep | Checking Supabase | information |  |
| COPY-0007 | AppRuntime | `CreatorContentOS/App/AppRuntime.swift:214` | Local Workspace | keep | Local Workspace | information |  |
| COPY-0008 | AppRuntime | `CreatorContentOS/App/AppRuntime.swift:215` | Creator | keep | Creator | information |  |
| COPY-0009 | Global / error display | `CreatorContentOS/App/AppServices.swift:309` | Checking today's plan | keep | Checking today's plan | action |  |
| COPY-0010 | Global / error display | `CreatorContentOS/App/AppServices.swift:317` | Generate a Week | keep | Generate a Week | action |  |
| COPY-0011 | Global / error display | `CreatorContentOS/App/AppServices.swift:329` | Checking sources | keep | Checking sources | action |  |
| COPY-0012 | Global / error display | `CreatorContentOS/App/AppServices.swift:330` | Loading live Supabase context | keep | Loading live Supabase context | state |  |
| COPY-0013 | Global / error display | `CreatorContentOS/App/AppServices.swift:690` | Open | keep | Open | action |  |
| COPY-0014 | Global / error display | `CreatorContentOS/App/AppServices.swift:1573` | We saved your preferences but couldn't prepare your first idea. | keep | We saved your preferences but couldn't prepare your first idea. | information |  |
| COPY-0015 | Global / error display | `CreatorContentOS/App/AppServices.swift:1758` | No ready package | keep | No ready package | action |  |
| COPY-0016 | Global / error display | `CreatorContentOS/App/AppServices.swift:2497` | Today's package could not be found. Refresh Plan, then try again. | keep | Today's package could not be found. Refresh Plan, then try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0017 | Global / error display | `CreatorContentOS/App/AppServices.swift:2498` | Could not save today's decision. Try again. | keep | Could not save today's decision. Try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0018 | Global / error display | `CreatorContentOS/App/AppServices.swift:2499` | Could not save today's archive entry. Try again. | keep | Could not save today's archive entry. Try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0019 | Global / error display | `CreatorContentOS/App/AppServices.swift:2500` | This device session is missing. Sign in again. | keep | This device session is missing. Sign in again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0020 | Global / error display | `CreatorContentOS/App/AppServices.swift:2501` | This device session has expired. Sign in again. | keep | This device session has expired. Sign in again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0021 | Global / error display | `CreatorContentOS/App/AppServices.swift:2502` | This session cannot save today's decision. | keep | This session cannot save today's decision. | information | Error map: private static let userFacingMessages = [ |
| COPY-0022 | Global / error display | `CreatorContentOS/App/AppServices.swift:2529` | No draft was found for that day. Generate a draft first. | keep | No draft was found for that day. Generate a draft first. | information | Error map: private static let userFacingMessages = [ |
| COPY-0023 | Global / error display | `CreatorContentOS/App/AppServices.swift:2530` | That day is already a ready package. | keep | That day is already a ready package. | information | Error map: private static let userFacingMessages = [ |
| COPY-0024 | Global / error display | `CreatorContentOS/App/AppServices.swift:2531` | That draft is incomplete. Generate again, then approve. | keep | That draft is incomplete. Generate again, then approve. | information | Error map: private static let userFacingMessages = [ |
| COPY-0025 | Global / error display | `CreatorContentOS/App/AppServices.swift:2532` | Approve could not accept that request. Refresh and try again. | rewrite | Make ready could not accept that request. Refresh and try again. | recovery / safety | C1/C4: align error copy with Make ready verb |
| COPY-0026 | Global / error display | `CreatorContentOS/App/AppServices.swift:2533` | Could not approve this day. Try again. | keep | Could not approve this day. Try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0027 | Global / error display | `CreatorContentOS/App/AppServices.swift:2534` | Approve is already running. Wait a moment. | keep | Approve is already running. Wait a moment. | information | Error map: private static let userFacingMessages = [ |
| COPY-0028 | Global / error display | `CreatorContentOS/App/AppServices.swift:2535` | This session cannot make a day available. | keep | This session cannot make a day available. | information | Error map: private static let userFacingMessages = [ |
| COPY-0029 | Global / error display | `CreatorContentOS/App/AppServices.swift:2536` | This creator workspace is no longer available. Refresh and try again. | keep | This creator workspace is no longer available. Refresh and try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0030 | Global / error display | `CreatorContentOS/App/AppServices.swift:2537` | This device session is missing. Sign in again. | keep | This device session is missing. Sign in again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0031 | Global / error display | `CreatorContentOS/App/AppServices.swift:2538` | This device session has expired. Sign in again. | keep | This device session has expired. Sign in again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0032 | Global / error display | `CreatorContentOS/App/AppServices.swift:2539` | Approve is not configured for this runtime. | keep | Approve is not configured for this runtime. | information | Error map: private static let userFacingMessages = [ |
| COPY-0033 | Global / error display | `CreatorContentOS/App/AppServices.swift:2564` | No package was found for that day. | keep | No package was found for that day. | information | Error map: private static let userFacingMessages = [ |
| COPY-0034 | Global / error display | `CreatorContentOS/App/AppServices.swift:2565` | That day is not a ready package. | keep | That day is not a ready package. | information | Error map: private static let userFacingMessages = [ |
| COPY-0035 | Global / error display | `CreatorContentOS/App/AppServices.swift:2566` | That day is already a draft. | keep | That day is already a draft. | information | Error map: private static let userFacingMessages = [ |
| COPY-0036 | Global / error display | `CreatorContentOS/App/AppServices.swift:2567` | Could not unpublish — the day changed. Refresh and try again. | keep | Could not unpublish — the day changed. Refresh and try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0037 | Global / error display | `CreatorContentOS/App/AppServices.swift:2568` | Unpublish could not accept that request. Refresh and try again. | keep | Unpublish could not accept that request. Refresh and try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0038 | Global / error display | `CreatorContentOS/App/AppServices.swift:2569` | Could not unpublish this day. Try again. | keep | Could not unpublish this day. Try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0039 | Global / error display | `CreatorContentOS/App/AppServices.swift:2570` | Unpublish is already running. Wait a moment. | keep | Unpublish is already running. Wait a moment. | information | Error map: private static let userFacingMessages = [ |
| COPY-0040 | Global / error display | `CreatorContentOS/App/AppServices.swift:2571` | Unpublish is not configured for this runtime. | keep | Unpublish is not configured for this runtime. | information | Error map: private static let userFacingMessages = [ |
| COPY-0041 | Global / error display | `CreatorContentOS/App/AppServices.swift:2572` | Could not save those edits. Refresh and try again. | keep | Could not save those edits. Refresh and try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0042 | Global / error display | `CreatorContentOS/App/AppServices.swift:2573` | Could not save package edits. Try again. | keep | Could not save package edits. Try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0043 | Global / error display | `CreatorContentOS/App/AppServices.swift:2574` | Package save is already running. Wait a moment. | keep | Package save is already running. Wait a moment. | information | Error map: private static let userFacingMessages = [ |
| COPY-0044 | Global / error display | `CreatorContentOS/App/AppServices.swift:2575` | Package editing is not configured for this runtime. | keep | Package editing is not configured for this runtime. | information | Error map: private static let userFacingMessages = [ |
| COPY-0045 | Global / error display | `CreatorContentOS/App/AppServices.swift:2576` | Could not save edits — the day changed. Refresh and try again. | keep | Could not save edits — the day changed. Refresh and try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0046 | Global / error display | `CreatorContentOS/App/AppServices.swift:2577` | This day already has a draft or package. Confirm Overwrite to replace it with a new draft. | keep | This day already has a draft or package. Confirm Overwrite to replace it with a new draft. | action / safety | Error map: private static let userFacingMessages = [ |
| COPY-0047 | Global / error display | `CreatorContentOS/App/AppServices.swift:2578` | This session cannot change that day package. | keep | This session cannot change that day package. | information | Error map: private static let userFacingMessages = [ |
| COPY-0048 | Global / error display | `CreatorContentOS/App/AppServices.swift:2579` | This creator workspace is no longer available. Refresh and try again. | keep | This creator workspace is no longer available. Refresh and try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0049 | Global / error display | `CreatorContentOS/App/AppServices.swift:2580` | This device session is missing. Sign in again. | keep | This device session is missing. Sign in again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0050 | Global / error display | `CreatorContentOS/App/AppServices.swift:2581` | This device session has expired. Sign in again. | keep | This device session has expired. Sign in again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0051 | Global / error display | `CreatorContentOS/App/AppServices.swift:2609` | The AI returned an incomplete draft. Try Generate again. | keep | The AI returned an incomplete draft. Try Generate again. | information | Error map: private static let userFacingMessages = [ |
| COPY-0052 | Global / error display | `CreatorContentOS/App/AppServices.swift:2610` | The AI draft did not pass validation. Try Generate again. | keep | The AI draft did not pass validation. Try Generate again. | information | Error map: private static let userFacingMessages = [ |
| COPY-0053 | Global / error display | `CreatorContentOS/App/AppServices.swift:2611` | The generated card did not match the requested date. Try Generate again. | keep | The generated card did not match the requested date. Try Generate again. | information | Error map: private static let userFacingMessages = [ |
| COPY-0054 | Global / error display | `CreatorContentOS/App/AppServices.swift:2612` | The AI service failed. Try Generate again. | keep | The AI service failed. Try Generate again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0055 | Global / error display | `CreatorContentOS/App/AppServices.swift:2613` | AI generation is not configured in Supabase. | keep | AI generation is not configured in Supabase. | information | Error map: private static let userFacingMessages = [ |
| COPY-0056 | Global / error display | `CreatorContentOS/App/AppServices.swift:2614` | The generation request could not be accepted. Refresh and try again. | keep | The generation request could not be accepted. Refresh and try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0057 | Global / error display | `CreatorContentOS/App/AppServices.swift:2615` | The draft could not be saved. Try Generate again. | keep | The draft could not be saved. Try Generate again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0058 | Global / error display | `CreatorContentOS/App/AppServices.swift:2616` | The weekly brief could not be found. Save the brief and try again. | keep | The weekly brief could not be found. Save the brief and try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0059 | Global / error display | `CreatorContentOS/App/AppServices.swift:2617` | This week is already published and locked. | keep | This week is already published and locked. | information | Error map: private static let userFacingMessages = [ |
| COPY-0060 | Global / error display | `CreatorContentOS/App/AppServices.swift:2618` | You cannot generate content for a past date. Select today or a future date. | keep | You cannot generate content for a past date. Select today or a future date. | information | Error map: private static let userFacingMessages = [ |
| COPY-0061 | Global / error display | `CreatorContentOS/App/AppServices.swift:2619` | Generation timed out. Wait a moment, then try Generate again. | keep | Generation timed out. Wait a moment, then try Generate again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0062 | Global / error display | `CreatorContentOS/App/AppServices.swift:2620` | This day’s draft stopped before it finished. You can try Generate again. | keep | This day’s draft stopped before it finished. You can try Generate again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0063 | Global / error display | `CreatorContentOS/App/AppServices.swift:2621` | A generation is already in progress for this day. Wait for it to finish, then try again. | keep | A generation is already in progress for this day. Wait for it to finish, then try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0064 | Global / error display | `CreatorContentOS/App/AppServices.swift:2622` | Set up your creator voice first — or defer voice in You. | keep | Set up your creator voice first — or defer voice in You. | information | Error map: private static let userFacingMessages = [ |
| COPY-0065 | Global / error display | `CreatorContentOS/App/AppServices.swift:2623` | Generation status is still syncing. Refresh and try Generate again. | keep | Generation status is still syncing. Refresh and try Generate again. | state | Error map: private static let userFacingMessages = [ |
| COPY-0066 | Global / error display | `CreatorContentOS/App/AppServices.swift:2624` | This day’s draft stopped before it finished. You can try Generate again. | keep | This day’s draft stopped before it finished. You can try Generate again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0067 | Global / error display | `CreatorContentOS/App/AppServices.swift:2681` | Paste at least one handle, reel link, audio link, or CSV row before previewing. | keep | Paste at least one handle, reel link, audio link, or CSV row before previewing. | information | Error map: private static let userFacingMessages = [ |
| COPY-0068 | Global / error display | `CreatorContentOS/App/AppServices.swift:2682` | This import is too large. Split it into smaller batches and try again. | keep | This import is too large. Split it into smaller batches and try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0069 | Global / error display | `CreatorContentOS/App/AppServices.swift:2683` | The import changed. Preview it again before saving. | keep | The import changed. Preview it again before saving. | information | Error map: private static let userFacingMessages = [ |
| COPY-0070 | Global / error display | `CreatorContentOS/App/AppServices.swift:2684` | Story URLs cannot be used as references. Add a reel, post, audio link, or account instead. | keep | Story URLs cannot be used as references. Add a reel, post, audio link, or account instead. | information | Error map: private static let userFacingMessages = [ |
| COPY-0071 | Global / error display | `CreatorContentOS/App/AppServices.swift:2685` | Add a reference URL before saving this review item. | keep | Add a reference URL before saving this review item. | information | Error map: private static let userFacingMessages = [ |
| COPY-0072 | Global / error display | `CreatorContentOS/App/AppServices.swift:2686` | Enter a valid Instagram handle for this account reference. | keep | Enter a valid Instagram handle for this account reference. | information | Error map: private static let userFacingMessages = [ |
| COPY-0073 | Global / error display | `CreatorContentOS/App/AppServices.swift:2687` | This review item is missing required details. Refresh and try again. | keep | This review item is missing required details. Refresh and try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0074 | Global / error display | `CreatorContentOS/App/AppServices.swift:2688` | This review action is not supported. Refresh and try again. | keep | This review action is not supported. Refresh and try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0075 | Global / error display | `CreatorContentOS/App/AppServices.swift:2689` | This review item is no longer available. Refresh References. | keep | This review item is no longer available. Refresh References. | information | Error map: private static let userFacingMessages = [ |
| COPY-0076 | Global / error display | `CreatorContentOS/App/AppServices.swift:2690` | This creator workspace is no longer available. Refresh and try again. | keep | This creator workspace is no longer available. Refresh and try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0077 | Global / error display | `CreatorContentOS/App/AppServices.swift:2691` | This action is not available for your account role. | keep | This action is not available for your account role. | information | Error map: private static let userFacingMessages = [ |
| COPY-0078 | Global / error display | `CreatorContentOS/App/AppServices.swift:2692` | This device session is missing. Sign in again. | keep | This device session is missing. Sign in again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0079 | Global / error display | `CreatorContentOS/App/AppServices.swift:2693` | This device session has expired. Sign in again. | keep | This device session has expired. Sign in again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0080 | Global / error display | `CreatorContentOS/App/AppServices.swift:2694` | The import could not be saved. Try previewing again. | keep | The import could not be saved. Try previewing again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0081 | Global / error display | `CreatorContentOS/App/AppServices.swift:2695` | Duplicate checking failed. Try previewing again. | keep | Duplicate checking failed. Try previewing again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0082 | Global / error display | `CreatorContentOS/App/AppServices.swift:2696` | The import could not be parsed. Check the pasted rows or CSV format. | keep | The import could not be parsed. Check the pasted rows or CSV format. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0083 | Global / error display | `CreatorContentOS/App/AppServices.swift:2697` | Choose paste or CSV import and try again. | keep | Choose paste or CSV import and try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0084 | Global / error display | `CreatorContentOS/App/AppServices.swift:2698` | Choose preview or import and try again. | keep | Choose preview or import and try again. | recovery / safety | Error map: private static let userFacingMessages = [ |
| COPY-0085 | CreatorContentOSApp | `CreatorContentOS/App/CreatorContentOSApp.swift:170` | ai-runway | DEBUG | ai-runway | information | AdminShell or DEBUG-only surface |
| COPY-0086 | CreatorContentOSApp | `CreatorContentOS/App/CreatorContentOSApp.swift:171` | storyboard-card | DEBUG | storyboard-card | information | AdminShell or DEBUG-only surface |
| COPY-0087 | CreatorContentOSApp | `CreatorContentOS/App/CreatorContentOSApp.swift:172` | tester-access | DEBUG | tester-access | information | AdminShell or DEBUG-only surface |
| COPY-0088 | CreatorContentOSApp | `CreatorContentOS/App/CreatorContentOSApp.swift:208` | Storyboard card preview | DEBUG | Storyboard card preview | information | AdminShell or DEBUG-only surface |
| COPY-0089 | CreatorContentOSApp | `CreatorContentOS/App/CreatorContentOSApp.swift:228` | Checking your session | keep | Checking your session | information |  |
| COPY-0090 | AppRepositories | `CreatorContentOS/Data/AppRepositories.swift:150` | Open | keep | Open | action |  |
| COPY-0091 | AppRepositories | `CreatorContentOS/Data/AppRepositories.swift:160` | Generate a Week | keep | Generate a Week | action |  |
| COPY-0092 | AppRepositories | `CreatorContentOS/Data/AppRepositories.swift:205` | Open | keep | Open | action |  |
| COPY-0093 | AppRepositories | `CreatorContentOS/Data/AppRepositories.swift:215` | Generate a Week | keep | Generate a Week | action |  |
| COPY-0094 | AppRepositories | `CreatorContentOS/Data/AppRepositories.swift:586` | Creator | keep | Creator | information |  |
| COPY-0095 | DevicePairingService | `CreatorContentOS/Data/DevicePairingService.swift:196` | Creator | keep | Creator | information |  |
| COPY-0096 | DeviceReadDTOs | `CreatorContentOS/Data/DeviceReadDTOs.swift:74` | Daily content loaded from live cards. | keep | Daily content loaded from live cards. | information |  |
| COPY-0097 | ReferenceImportDTOs | `CreatorContentOS/Data/ReferenceImportDTOs.swift:158` | Reference import complete. | keep | Reference import complete. | information |  |
| COPY-0098 | ReferenceImportDTOs | `CreatorContentOS/Data/ReferenceImportDTOs.swift:249` | Reference updated. | keep | Reference updated. | information |  |
| COPY-0099 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:121` | 3 sec | keep | 3 sec | information |  |
| COPY-0100 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:317` | Prepared for today. | keep | Prepared for today. | information |  |
| COPY-0101 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:353` | Prepared for this day. | keep | Prepared for this day. | information |  |
| COPY-0102 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:354` | Support this week’s content arc. | keep | Support this week’s content arc. | information |  |
| COPY-0103 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:355` | Pattern | keep | Pattern | information |  |
| COPY-0104 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:356` | Not specified | keep | Not specified | information |  |
| COPY-0105 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:358` | Not specified | keep | Not specified | information |  |
| COPY-0106 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:359` | Natural | keep | Natural | information |  |
| COPY-0107 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:422` | Prepared for this day. | keep | Prepared for this day. | information |  |
| COPY-0108 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:498` | Place | keep | Place | action |  |
| COPY-0109 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:498` | No location set. | keep | No location set. | information |  |
| COPY-0110 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:499` | Body | keep | Body | action |  |
| COPY-0111 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:500` | Family | keep | Family | action |  |
| COPY-0112 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:501` | Constraints | keep | Constraints | action |  |
| COPY-0113 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:502` | Source pulse | keep | Source pulse | action |  |
| COPY-0114 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:503` | Boundaries | keep | Boundaries | action |  |
| COPY-0115 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:523` | Weekly routine | keep | Weekly routine | action |  |
| COPY-0116 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:529` | Family/travel | keep | Family/travel | action |  |
| COPY-0117 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:535` | Energy/shooting constraints | keep | Energy/shooting constraints | action |  |
| COPY-0118 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:541` | References to consider | keep | References to consider | action |  |
| COPY-0119 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:547` | Avoid | keep | Avoid | action |  |
| COPY-0120 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:590` | Saved for future use. | keep | Saved for future use. | information |  |
| COPY-0121 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:592` | Easy | keep | Easy | information |  |
| COPY-0122 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:634` | Imported reference | keep | Imported reference | information |  |
| COPY-0123 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:635` | Imported row needs a decision. | keep | Imported row needs a decision. | information |  |
| COPY-0124 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:677` | Reference creator | keep | Reference creator | information |  |
| COPY-0125 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:682` | Candidate inspiration account. | keep | Candidate inspiration account. | information |  |
| COPY-0126 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:714` | Pattern | keep | Pattern | information |  |
| COPY-0127 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:742` | Trend | keep | Trend | information |  |
| COPY-0128 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:772` | Audio | keep | Audio | information |  |
| COPY-0129 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:891` | English | keep | English | information |  |
| COPY-0130 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:925` | Daily card | keep | Daily card | information |  |
| COPY-0131 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:1046` | Opening detail | keep | Opening detail | action |  |
| COPY-0132 | SupabaseDTOs | `CreatorContentOS/Data/SupabaseDTOs.swift:1048` | One useful takeaway | keep | One useful takeaway | action |  |
| COPY-0133 | SupabaseRepositories | `CreatorContentOS/Data/SupabaseRepositories.swift:409` | Generate a Week | keep | Generate a Week | action |  |
| COPY-0134 | SupabaseRepositories | `CreatorContentOS/Data/SupabaseRepositories.swift:1051` | Source Pulse | keep | Source Pulse | action |  |
| COPY-0135 | SupabaseRepositories | `CreatorContentOS/Data/SupabaseRepositories.swift:1066` | Source Pulse | keep | Source Pulse | action |  |
| COPY-0136 | SupabaseRepositories | `CreatorContentOS/Data/SupabaseRepositories.swift:1090` | Patterns | keep | Patterns | action |  |
| COPY-0137 | SupabaseRepositories | `CreatorContentOS/Data/SupabaseRepositories.swift:1090` | Reusable Creator-safe structures. | keep | Reusable Creator-safe structures. | information |  |
| COPY-0138 | SupabaseRepositories | `CreatorContentOS/Data/SupabaseRepositories.swift:1091` | Trends | keep | Trends | action |  |
| COPY-0139 | SupabaseRepositories | `CreatorContentOS/Data/SupabaseRepositories.swift:1091` | Manual USA feed observations. | keep | Manual USA feed observations. | information |  |
| COPY-0140 | SupabaseRepositories | `CreatorContentOS/Data/SupabaseRepositories.swift:1092` | Audio Options | keep | Audio Options | action |  |
| COPY-0141 | SupabaseRepositories | `CreatorContentOS/Data/SupabaseRepositories.swift:1092` | Verified and fallback sounds. | keep | Verified and fallback sounds. | information |  |
| COPY-0142 | SupabaseRepositories | `CreatorContentOS/Data/SupabaseRepositories.swift:1093` | Ideas | keep | Ideas | action |  |
| COPY-0143 | SupabaseRepositories | `CreatorContentOS/Data/SupabaseRepositories.swift:1093` | Prepared card candidates. | keep | Prepared card candidates. | information |  |
| COPY-0144 | SupabaseRepositories | `CreatorContentOS/Data/SupabaseRepositories.swift:1094` | Inspiration | keep | Inspiration | action |  |
| COPY-0145 | SupabaseRepositories | `CreatorContentOS/Data/SupabaseRepositories.swift:1094` | Reference creators in the watchlist. | keep | Reference creators in the watchlist. | information |  |
| COPY-0146 | SupabaseRepositories | `CreatorContentOS/Data/SupabaseRepositories.swift:1235` | Idea | keep | Idea | information |  |
| COPY-0147 | WeeklyPublishingModels | `CreatorContentOS/Data/WeeklyPublishingModels.swift:67` | Product or kit detail | keep | Product or kit detail | action |  |
| COPY-0148 | WeeklyPublishingModels | `CreatorContentOS/Data/WeeklyPublishingModels.swift:68` | Training movement | keep | Training movement | action |  |
| COPY-0149 | WeeklyPublishingModels | `CreatorContentOS/Data/WeeklyPublishingModels.swift:69` | Disclosure-safe close | keep | Disclosure-safe close | action |  |
| COPY-0150 | WeeklyPublishingModels | `CreatorContentOS/Data/WeeklyPublishingModels.swift:73` | Quiet context | keep | Quiet context | action |  |
| COPY-0151 | WeeklyPublishingModels | `CreatorContentOS/Data/WeeklyPublishingModels.swift:74` | One human detail | keep | One human detail | action |  |
| COPY-0152 | WeeklyPublishingModels | `CreatorContentOS/Data/WeeklyPublishingModels.swift:75` | Soft closing line | keep | Soft closing line | action |  |
| COPY-0153 | WeeklyPublishingModels | `CreatorContentOS/Data/WeeklyPublishingModels.swift:79` | Opening detail | keep | Opening detail | action |  |
| COPY-0154 | WeeklyPublishingModels | `CreatorContentOS/Data/WeeklyPublishingModels.swift:81` | One useful takeaway | keep | One useful takeaway | action |  |
| COPY-0155 | Archive | `CreatorContentOS/Features/Archive/ArchiveView.swift:24` | Archive | keep | Archive | information |  |
| COPY-0156 | Archive | `CreatorContentOS/Features/Archive/ArchiveView.swift:27` | Past decisions and outputs. | keep | Past decisions and outputs. | information |  |
| COPY-0157 | Archive | `CreatorContentOS/Features/Archive/ArchiveView.swift:60` | All | keep | All | information |  |
| COPY-0158 | Archive | `CreatorContentOS/Features/Archive/ArchiveView.swift:61` | Completed | rewrite | Shot & posted | information | C11: Completed contradicts Skipped sibling filter |
| COPY-0159 | Archive | `CreatorContentOS/Features/Archive/ArchiveView.swift:62` | Backups | keep | Backups | information |  |
| COPY-0160 | Archive | `CreatorContentOS/Features/Archive/ArchiveView.swift:63` | Skipped | keep | Skipped | action / safety |  |
| COPY-0161 | Archive | `CreatorContentOS/Features/Archive/ArchiveView.swift:207` | Done | keep | Done | action |  |
| COPY-0162 | Sign-in | `CreatorContentOS/Features/Authentication/SignInView.swift:25` | ContentHelper | keep | ContentHelper | information |  |
| COPY-0163 | Sign-in | `CreatorContentOS/Features/Authentication/SignInView.swift:28` | Sign in with Apple to open your Creator workspace. | keep | Sign in with Apple to open your Creator workspace. | information |  |
| COPY-0164 | Sign-in | `CreatorContentOS/Features/Authentication/SignInView.swift:80` | Apple sign-in returned an unexpected credential. | keep | Apple sign-in returned an unexpected credential. | information |  |
| COPY-0165 | Sign-in | `CreatorContentOS/Features/Authentication/SignInView.swift:90` | Apple did not return a usable identity token. | keep | Apple did not return a usable identity token. | information |  |
| COPY-0166 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:69` | Detail not specified. | keep | Detail not specified. | information |  |
| COPY-0167 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:172` | No storyboard scenes yet. | keep | No storyboard scenes yet. | information |  |
| COPY-0168 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:275` | SCENE / VISUAL | keep | SCENE / VISUAL | action |  |
| COPY-0169 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:294` | WHAT TO SHOW | keep | WHAT TO SHOW | action |  |
| COPY-0170 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:299` | AUDIO / DIALOGUE | keep | AUDIO / DIALOGUE | action |  |
| COPY-0171 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:304` | ON-SCREEN TEXT | keep | ON-SCREEN TEXT | action |  |
| COPY-0172 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:360` | Resize scene column | keep | Resize scene column | action | C14: keep working VoiceOver resize control |
| COPY-0173 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:599` | Tips for Filming | keep | Tips for Filming | information |  |
| COPY-0174 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:604` | • | keep | • | information |  |
| COPY-0175 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:657` | Reel | keep | Reel | information |  |
| COPY-0176 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:687` | Caption | keep | Caption | action |  |
| COPY-0177 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:688` | CTA | keep | CTA | action |  |
| COPY-0178 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:689` | Cover text | keep | Cover text | action |  |
| COPY-0179 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:690` | Post instructions | keep | Post instructions | action |  |
| COPY-0180 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:691` | Hashtags | keep | Hashtags | action |  |
| COPY-0181 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:730` | Script | keep | Script | information |  |
| COPY-0182 | Today or Plan / package detail | `CreatorContentOS/Features/Daily/GeneratedDayPlannedContent.swift:775` | No script lines yet. | keep | No script lines yet. | information |  |
| COPY-0183 | Plan / calendar sheet | `CreatorContentOS/Features/Daily/PlanCalendarSheet.swift:23` | Choose a day | keep | Choose a day | information |  |
| COPY-0184 | Plan / calendar sheet | `CreatorContentOS/Features/Daily/PlanCalendarSheet.swift:27` | Done | keep | Done | action |  |
| COPY-0185 | Plan / calendar sheet | `CreatorContentOS/Features/Daily/PlanCalendarSheet.swift:44` | Empty | keep | Empty | information |  |
| COPY-0186 | Plan / calendar sheet | `CreatorContentOS/Features/Daily/PlanCalendarSheet.swift:50` | Legend: filled ready, muted draft, none empty | keep | Legend: filled ready, muted draft, none empty | action |  |
| COPY-0187 | Plan / calendar sheet | `CreatorContentOS/Features/Daily/PlanCalendarSheet.swift:76` | Previous month | keep | Previous month | action |  |
| COPY-0188 | Plan / calendar sheet | `CreatorContentOS/Features/Daily/PlanCalendarSheet.swift:93` | Next month | keep | Next month | action |  |
| COPY-0189 | Plan / idea launcher | `CreatorContentOS/Features/Daily/PlanDayIdeaLauncher.swift:19` | Choose an idea for this day | keep | Choose an idea for this day | information |  |
| COPY-0190 | Plan / idea launcher | `CreatorContentOS/Features/Daily/PlanDayIdeaLauncher.swift:42` | Generating this day… | keep | Generating this day… | state |  |
| COPY-0191 | Plan / idea launcher | `CreatorContentOS/Features/Daily/PlanDayIdeaLauncher.swift:85` | Other | keep | Other | information |  |
| COPY-0192 | Plan / idea launcher | `CreatorContentOS/Features/Daily/PlanDayIdeaLauncher.swift:88` | Write your own direction for this day. | keep | Write your own direction for this day. | information |  |
| COPY-0193 | Plan / idea launcher | `CreatorContentOS/Features/Daily/PlanDayIdeaLauncher.swift:107` | Write another idea | keep | Write another idea | action |  |
| COPY-0194 | Plan / idea launcher | `CreatorContentOS/Features/Daily/PlanDayIdeaLauncher.swift:114` | Your direction | keep | Your direction | information |  |
| COPY-0195 | Plan / idea launcher | `CreatorContentOS/Features/Daily/PlanDayIdeaLauncher.swift:117` | Use a specific idea, moment, or format. This creates one day only. | keep | Use a specific idea, moment, or format. This creates one day only. | information |  |
| COPY-0196 | Plan / idea launcher | `CreatorContentOS/Features/Daily/PlanDayIdeaLauncher.swift:124` | e.g. A quiet pre-race check-in before the first mile… | rewrite | e.g. A low-key check-in about what I'm working on this week… | information | C13: HYROX-flavored placeholder example |
| COPY-0197 | Plan / idea launcher | `CreatorContentOS/Features/Daily/PlanDayIdeaLauncher.swift:147` | Generate for this day | keep | Generate for this day | information |  |
| COPY-0198 | Plan / idea settings summary | `CreatorContentOS/Features/Daily/PlanGenerationInputsSummary.swift:11` | Generation inputs | rewrite | Idea settings | information | C9: avoid backend term generation |
| COPY-0199 | Plan / idea settings summary | `CreatorContentOS/Features/Daily/PlanGenerationInputsSummary.swift:25` | Content categories | keep | Content categories | action |  |
| COPY-0200 | Plan / idea settings summary | `CreatorContentOS/Features/Daily/PlanGenerationInputsSummary.swift:26` | Creator voice | keep | Creator voice | action |  |
| COPY-0201 | Plan / idea settings summary | `CreatorContentOS/Features/Daily/PlanGenerationInputsSummary.swift:27` | References | keep | References | action |  |
| COPY-0202 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:66` | Generation stopped | cut | (drop title; show human message only) | recovery / safety | C4: error tile title duplicates message noun |
| COPY-0203 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:66` | Generation error | cut | (drop title; show human message only) | recovery / safety | C4: error tile title duplicates message noun |
| COPY-0204 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:74` | Approve | cut | (drop title; show human message only) | information | C4: error tile title duplicates message noun |
| COPY-0205 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:82` | Unpublish | cut | (drop title; show human message only) | information | C4: error tile title duplicates message noun |
| COPY-0206 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:90` | Save edits | cut | (drop title; show human message only) | information | C4: error tile title duplicates message noun |
| COPY-0207 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:54` | Personalize your Creator Voice or use the one we have prefilled based on your references and domain | keep | Personalize your Creator Voice or use the one we have prefilled based on your references and domain | information |  |
| COPY-0208 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:67` | Generation stopped | cut | (drop title; show human message only) | recovery / safety | C4: error tile title duplicates message noun |
| COPY-0209 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:67` | Generation error | cut | (drop title; show human message only) | recovery / safety | C4: error tile title duplicates message noun |
| COPY-0210 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:75` | Approve | cut | (drop title; show human message only) | action | C4: error tile title duplicates message noun |
| COPY-0211 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:83` | Unpublish | cut | (drop title; show human message only) | action | C4: error tile title duplicates message noun |
| COPY-0212 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:91` | Save edits | cut | (drop title; show human message only) | action | C4: error tile title duplicates message noun |
| COPY-0213 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:122` | Unpublish this day? | keep | Unpublish this day? | information |  |
| COPY-0214 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:123` | Cancel | keep | Cancel | action / safety |  |
| COPY-0215 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:124` | Unpublish | keep | Unpublish | action |  |
| COPY-0216 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:128` | Returns this ready package to draft. If there was a Decision, the live Decision clears and Archive history stays. | keep | Returns this ready package to draft. If there was a Decision, the live Decision clears and Archive history stays. | information |  |
| COPY-0217 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:130` | Overwrite current draft? | keep | Overwrite current draft? | action / safety |  |
| COPY-0218 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:131` | Cancel | keep | Cancel | action / safety |  |
| COPY-0219 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:134` | Overwrite | keep | Overwrite | action / safety |  |
| COPY-0220 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:141` | This replaces the current draft or package for this day with a new draft. Any live Decision clears; Archive history stays. You will need to approve again. | keep | This replaces the current draft or package for this day with a new draft. Any live Decision clears; Archive history stays. You will need to approve again. | information |  |
| COPY-0221 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:328` | Back | keep | Back | action |  |
| COPY-0222 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:333` | Plan | keep | Plan | information |  |
| COPY-0223 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:339` | Pick a day, choose an idea, then approve the draft for Today. | keep | Pick a day, choose an idea, then approve the draft for Today. | information |  |
| COPY-0224 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:390` | Change selected day | keep | Change selected day | action |  |
| COPY-0225 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:403` | Deep reasoning takes a couple of minutes. Validation may retry once or twice. | rewrite | Preparing your idea… | information | C5: remove internal reasoning/validation jargon |
| COPY-0226 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:439` | Choose another idea | keep | Choose another idea | information |  |
| COPY-0227 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:455` | Light edit | keep | Light edit | information |  |
| COPY-0228 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:458` | Edits keep this day ready — no Unpublish required. | keep | Edits keep this day ready — no Unpublish required. | information |  |
| COPY-0229 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:468` | Saving… | keep | Saving… | information |  |
| COPY-0230 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:468` | Save caption | keep | Save caption | information |  |
| COPY-0231 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:487` | Approving… | rewrite | Making ready… | state | C1: action verb; lifecycle unchanged |
| COPY-0232 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:487` | Approve | rewrite | Make ready | information | C1: action verb; lifecycle unchanged |
| COPY-0233 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:496` | Clicking this will add the card to the Today page. | rewrite | Remove or use date-aware readiness wording | information | C2: desktop Clicking; future dates must not promise immediate Today |
| COPY-0234 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:520` | Unpublishing… | keep | Unpublishing… | information |  |
| COPY-0235 | Plan / day detail | `CreatorContentOS/Features/Daily/PlanHubView.swift:520` | Unpublish | keep | Unpublish | information |  |
| COPY-0236 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:85` | Recently used | keep | Recently used | action |  |
| COPY-0237 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:107` | Open Reference Import | keep | Open Reference Import | action |  |
| COPY-0238 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:115` | References | keep | References | information |  |
| COPY-0239 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:133` | Reference import preview failed. | keep | Reference import preview failed. | recovery / safety |  |
| COPY-0240 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:151` | Reference import failed. | keep | Reference import failed. | recovery / safety |  |
| COPY-0241 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:219` | Import inspiration | keep | Import inspiration | information |  |
| COPY-0242 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:245` | Growth References | keep | Growth References | action |  |
| COPY-0243 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:341` | Growth Reference | keep | Growth Reference | information |  |
| COPY-0244 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:379` | Hook formulas | keep | Hook formulas | information |  |
| COPY-0245 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:384` | Hook | keep | Hook | action |  |
| COPY-0246 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:394` | When to use | keep | When to use | information |  |
| COPY-0247 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:403` | Creator idea | keep | Creator idea | action |  |
| COPY-0248 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:411` | Sources | keep | Sources | information |  |
| COPY-0249 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:498` | Needs your call | keep | Needs your call | action |  |
| COPY-0250 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:558` | Approve | cut | (drop title; show human message only) | action | C4: error tile title duplicates message noun |
| COPY-0251 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:559` | Dismiss | keep | Dismiss | action |  |
| COPY-0252 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:560` | Edit | keep | Edit | action |  |
| COPY-0253 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:561` | Open | keep | Open | action |  |
| COPY-0254 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:668` | Library | keep | Library | action |  |
| COPY-0255 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:792` | How this should be used | keep | How this should be used | information |  |
| COPY-0256 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:800` | Priority signal | keep | Priority signal | action |  |
| COPY-0257 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:809` | Source | keep | Source | information |  |
| COPY-0258 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:820` | No source link attached. | keep | No source link attached. | information |  |
| COPY-0259 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:825` | Open source | keep | Open source | action |  |
| COPY-0260 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:874` | Saved references | keep | Saved references | action |  |
| COPY-0261 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:875` | Scope | keep | Scope | action |  |
| COPY-0262 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:880` | What belongs here | keep | What belongs here | information |  |
| COPY-0263 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:883` | This section groups references that can inform daily content generation. The next useful layer is a filtered list of all saved references in this bucket. | keep | This section groups references that can inform daily content generation. The next useful layer is a filtered list of all saved references in this bucket. | information |  |
| COPY-0264 | Intelligence | `CreatorContentOS/Features/Intelligence/IntelligenceHomeView.swift:910` | Reference Library | keep | Reference Library | information |  |
| COPY-0265 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:31` | Clean rows | keep | Clean rows | action |  |
| COPY-0266 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:32` | Will be imported after confirmation. | keep | Will be imported after confirmation. | action / safety |  |
| COPY-0267 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:39` | Needs your call | keep | Needs your call | action |  |
| COPY-0268 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:40` | Imported as review items, not ready ideas. | keep | Imported as review items, not ready ideas. | information |  |
| COPY-0269 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:47` | Invalid rows | keep | Invalid rows | recovery / safety |  |
| COPY-0270 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:48` | Not stored. Story URLs cannot be used. | keep | Not stored. Story URLs cannot be used. | information |  |
| COPY-0271 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:75` | INSPIRATION | keep | INSPIRATION | information |  |
| COPY-0272 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:78` | Preview | keep | Preview | information |  |
| COPY-0273 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:99` | Instagram couldn't be reached, so these references were not verified live. You can still add them — the server re-checks everything when saving. | rewrite | Instagram couldn't be reached, so these references were not verified live. You can still add them — we'll re-check everything when saving. | information | C10: server is architecture jargon |
| COPY-0274 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:120` | INSPIRATION | keep | INSPIRATION | information |  |
| COPY-0275 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:123` | Preview | keep | Preview | information |  |
| COPY-0276 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:136` | Rows are parsed by the server. Confirming will import clean references and keep ambiguous rows in Needs your call. | keep | Rows are parsed by the server. Confirming will import clean references and keep ambiguous rows in Needs your call. | action / safety |  |
| COPY-0277 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:222` | DUPLICATES | keep | DUPLICATES | information |  |
| COPY-0278 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:397` | @fitover60 | keep | @fitover60 | action |  |
| COPY-0279 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:410` | Race week warmup reel | keep | Race week warmup reel | action |  |
| COPY-0280 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:423` | keep an eye on post-run family moment | keep | keep an eye on post-run family moment | action |  |
| COPY-0281 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:436` | Instagram story URL | keep | Instagram story URL | action |  |
| COPY-0282 | References / import preview | `CreatorContentOS/Features/Intelligence/ReferenceImportPreviewView.swift:449` | @fitover60 | keep | @fitover60 | action |  |
| COPY-0283 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:171` | MC | keep | MC | information |  |
| COPY-0284 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:188` | Inspiration | keep | Inspiration | information |  |
| COPY-0285 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:193` | Paste handles, reel links, audio links, or a CSV. The server decides what is clean and what needs your call. | rewrite | Paste handles, reel links, audio links, or a CSV. We'll sort what's usable and flag anything that needs your review. | information | C10: server is architecture jargon |
| COPY-0286 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:346` | INPUT | keep | INPUT | information |  |
| COPY-0287 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:366` | Choose CSV | keep | Choose CSV | action |  |
| COPY-0288 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:376` | Clear import input | keep | Clear import input | action |  |
| COPY-0289 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:389` | Paste Instagram handles, profile URLs, reel/audio links, one note per line, or CSV text. | keep | Paste Instagram handles, profile URLs, reel/audio links, one note per line, or CSV text. | information |  |
| COPY-0290 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:407` | Max 500 rows. Story URLs are rejected. | keep | Max 500 rows. Story URLs are rejected. | information |  |
| COPY-0291 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:445` | Live workspace required | keep | Live workspace required | information |  |
| COPY-0292 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:448` | Reference Import writes through Supabase Edge Functions. Fixtures keep Creator Mode unchanged but do not import. | keep | Reference Import writes through Supabase Edge Functions. Fixtures keep Creator Mode unchanged but do not import. | information |  |
| COPY-0293 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:468` | What the preview will separate | keep | What the preview will separate | action |  |
| COPY-0294 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:473` | Accounts | keep | Accounts | action |  |
| COPY-0295 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:479` | Reels and audio | keep | Reels and audio | action |  |
| COPY-0296 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:485` | Unknown rows | keep | Unknown rows | action |  |
| COPY-0297 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:491` | Stories | keep | Stories | action |  |
| COPY-0298 | References / import | `CreatorContentOS/Features/Intelligence/ReferenceImportView.swift:536` | CONFIRMED | keep | CONFIRMED | action / safety |  |
| COPY-0299 | References / review sheet | `CreatorContentOS/Features/Intelligence/ReferenceReviewEditSheet.swift:39` | NEEDS YOUR CALL | keep | NEEDS YOUR CALL | information |  |
| COPY-0300 | References / review sheet | `CreatorContentOS/Features/Intelligence/ReferenceReviewEditSheet.swift:42` | Resolve reference | keep | Resolve reference | information |  |
| COPY-0301 | References / review sheet | `CreatorContentOS/Features/Intelligence/ReferenceReviewEditSheet.swift:52` | TYPE | keep | TYPE | information |  |
| COPY-0302 | References / review sheet | `CreatorContentOS/Features/Intelligence/ReferenceReviewEditSheet.swift:57` | Account | keep | Account | information |  |
| COPY-0303 | References / review sheet | `CreatorContentOS/Features/Intelligence/ReferenceReviewEditSheet.swift:58` | Reel | keep | Reel | information |  |
| COPY-0304 | References / review sheet | `CreatorContentOS/Features/Intelligence/ReferenceReviewEditSheet.swift:59` | Audio | keep | Audio | information |  |
| COPY-0305 | References / review sheet | `CreatorContentOS/Features/Intelligence/ReferenceReviewEditSheet.swift:60` | Unknown | keep | Unknown | information |  |
| COPY-0306 | References / review sheet | `CreatorContentOS/Features/Intelligence/ReferenceReviewEditSheet.swift:66` | Handle | keep | Handle | action |  |
| COPY-0307 | References / review sheet | `CreatorContentOS/Features/Intelligence/ReferenceReviewEditSheet.swift:67` | @creator | keep | @creator | input guidance |  |
| COPY-0308 | References / review sheet | `CreatorContentOS/Features/Intelligence/ReferenceReviewEditSheet.swift:72` | URL | keep | URL | action |  |
| COPY-0309 | References / review sheet | `CreatorContentOS/Features/Intelligence/ReferenceReviewEditSheet.swift:79` | Notes | keep | Notes | information |  |
| COPY-0310 | References / review sheet | `CreatorContentOS/Features/Intelligence/ReferenceReviewEditSheet.swift:104` | Cancel | keep | Cancel | action / safety |  |
| COPY-0311 | Onboarding / context | `CreatorContentOS/Features/Onboarding/OnboardingContextQuestions.swift:22` | I just finished Fourth Wing! | keep | I just finished Fourth Wing! | input guidance |  |
| COPY-0312 | Onboarding / context | `CreatorContentOS/Features/Onboarding/OnboardingContextQuestions.swift:30` | I'm watching Dune and excited for Wicked. | keep | I'm watching Dune and excited for Wicked. | input guidance |  |
| COPY-0313 | Onboarding / context | `CreatorContentOS/Features/Onboarding/OnboardingContextQuestions.swift:38` | Building a consistent morning walk habit. | keep | Building a consistent morning walk habit. | input guidance |  |
| COPY-0314 | Onboarding / context | `CreatorContentOS/Features/Onboarding/OnboardingContextQuestions.swift:45` | Mostly documenting with quick tips mixed in. | keep | Mostly documenting with quick tips mixed in. | input guidance |  |
| COPY-0315 | Onboarding / context | `CreatorContentOS/Features/Onboarding/OnboardingContextQuestions.swift:53` | Slow mornings and cooking more at home. | keep | Slow mornings and cooking more at home. | input guidance |  |
| COPY-0316 | Onboarding / context | `CreatorContentOS/Features/Onboarding/OnboardingContextQuestions.swift:61` | Quick vegetarian bowls and sourdough experiments. | keep | Quick vegetarian bowls and sourdough experiments. | input guidance |  |
| COPY-0317 | Onboarding / context | `CreatorContentOS/Features/Onboarding/OnboardingContextQuestions.swift:69` | Planning a long weekend in Lisbon. | keep | Planning a long weekend in Lisbon. | input guidance |  |
| COPY-0318 | Onboarding / context | `CreatorContentOS/Features/Onboarding/OnboardingContextQuestions.swift:77` | Minimal outfits and dewy skin. | keep | Minimal outfits and dewy skin. | input guidance |  |
| COPY-0319 | Onboarding / context | `CreatorContentOS/Features/Onboarding/OnboardingContextQuestions.swift:85` | Growing a freelance design practice. | keep | Growing a freelance design practice. | input guidance |  |
| COPY-0320 | Onboarding / context | `CreatorContentOS/Features/Onboarding/OnboardingContextQuestions.swift:93` | Cozy indie games after work. | keep | Cozy indie games after work. | input guidance |  |
| COPY-0321 | Onboarding / context | `CreatorContentOS/Features/Onboarding/OnboardingContextQuestions.swift:101` | Watercolour sketches and short animations. | keep | Watercolour sketches and short animations. | input guidance |  |
| COPY-0322 | Onboarding / context | `CreatorContentOS/Features/Onboarding/OnboardingContextQuestions.swift:109` | Navigating toddler routines and bedtime. | keep | Navigating toddler routines and bedtime. | input guidance |  |
| COPY-0323 | Onboarding / context | `CreatorContentOS/Features/Onboarding/OnboardingContextQuestions.swift:117` | Tell us what's current for you. | keep | Tell us what's current for you. | input guidance |  |
| COPY-0324 | Onboarding / context | `CreatorContentOS/Features/Onboarding/OnboardingContextQuestions.swift:124` | Honest reviews, behind-the-scenes, quick tips… | keep | Honest reviews, behind-the-scenes, quick tips… | input guidance |  |
| COPY-0325 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:6` | 3 underrated books that deserve a screen adaptation | keep | 3 underrated books that deserve a screen adaptation | action |  |
| COPY-0326 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:7` | Books vs. the movie — which is better? | keep | Books vs. the movie — which is better? | action |  |
| COPY-0327 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:8` | A day in my life as a book lover and movie fan | keep | A day in my life as a book lover and movie fan | action |  |
| COPY-0328 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:9` | What I'm reading this month (honest takes) | keep | What I'm reading this month (honest takes) | action |  |
| COPY-0329 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:10` | Unpopular opinion: this bestseller didn't land for me | keep | Unpopular opinion: this bestseller didn't land for me | action |  |
| COPY-0330 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:13` | Shows worth your weekend — my short list | keep | Shows worth your weekend — my short list | action |  |
| COPY-0331 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:14` | Hot take: the finale was actually fine | keep | Hot take: the finale was actually fine | action |  |
| COPY-0332 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:15` | Things only binge-watchers understand | keep | Things only binge-watchers understand | action |  |
| COPY-0333 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:16` | One scene that changed how I watch films | keep | One scene that changed how I watch films | action |  |
| COPY-0334 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:17` | Remakes vs. originals — my verdict | keep | Remakes vs. originals — my verdict | action |  |
| COPY-0335 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:20` | A realistic morning routine that actually sticks | keep | A realistic morning routine that actually sticks | action |  |
| COPY-0336 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:21` | What I stopped doing at the gym (and why) | keep | What I stopped doing at the gym (and why) | recovery / safety |  |
| COPY-0337 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:22` | POV: you said you'd start Monday | keep | POV: you said you'd start Monday | action |  |
| COPY-0338 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:23` | 3 stretches that saved my back | keep | 3 stretches that saved my back | action |  |
| COPY-0339 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:24` | Wellness trends I think are overrated | keep | Wellness trends I think are overrated | action |  |
| COPY-0340 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:27` | Small habits that made my week smoother | keep | Small habits that made my week smoother | action |  |
| COPY-0341 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:28` | Things I stopped buying to simplify life | keep | Things I stopped buying to simplify life | recovery / safety |  |
| COPY-0342 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:29` | A chaotic but honest day in my life | keep | A chaotic but honest day in my life | action |  |
| COPY-0343 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:30` | Sunday reset routine — what actually helps | keep | Sunday reset routine — what actually helps | action |  |
| COPY-0344 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:31` | Aesthetic vs. practical — where I land | keep | Aesthetic vs. practical — where I land | action |  |
| COPY-0345 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:34` | 5-ingredient dinners I make on repeat | keep | 5-ingredient dinners I make on repeat | action |  |
| COPY-0346 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:35` | Restaurant dish I'd never order again | keep | Restaurant dish I'd never order again | action |  |
| COPY-0347 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:36` | Cooking fail turned into a win | keep | Cooking fail turned into a win | action |  |
| COPY-0348 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:37` | Pantry staples worth keeping stocked | keep | Pantry staples worth keeping stocked | action |  |
| COPY-0349 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:38` | Fusion food hot take | keep | Fusion food hot take | action |  |
| COPY-0350 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:41` | Hidden spots I'd revisit tomorrow | keep | Hidden spots I'd revisit tomorrow | action |  |
| COPY-0351 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:42` | Overrated tourist stops — skip these | keep | Overrated tourist stops — skip these | action / safety |  |
| COPY-0352 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:43` | Packing like I haven't learned anything | keep | Packing like I haven't learned anything | action |  |
| COPY-0353 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:44` | How I plan trips without overplanning | keep | How I plan trips without overplanning | action |  |
| COPY-0354 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:45` | Solo travel vs. group — my preference | keep | Solo travel vs. group — my preference | action |  |
| COPY-0355 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:48` | Outfits I reach for every week | keep | Outfits I reach for every week | action |  |
| COPY-0356 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:49` | Trend I'm not buying into | keep | Trend I'm not buying into | action |  |
| COPY-0357 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:50` | Getting ready vs. how I actually look | keep | Getting ready vs. how I actually look | action |  |
| COPY-0358 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:51` | Products that earned a permanent spot | keep | Products that earned a permanent spot | action |  |
| COPY-0359 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:52` | Drugstore vs. luxury — honest compare | keep | Drugstore vs. luxury — honest compare | action |  |
| COPY-0360 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:55` | Tools that actually speed up my work | keep | Tools that actually speed up my work | action |  |
| COPY-0361 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:56` | Career advice I wish I'd ignored | keep | Career advice I wish I'd ignored | action |  |
| COPY-0362 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:57` | Monday me vs. Friday me at work | keep | Monday me vs. Friday me at work | action |  |
| COPY-0363 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:58` | How I structure a focused work block | keep | How I structure a focused work block | action |  |
| COPY-0364 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:59` | Hustle culture — where I draw the line | keep | Hustle culture — where I draw the line | action |  |
| COPY-0365 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:62` | Games I'd recommend to a friend right now | keep | Games I'd recommend to a friend right now | action |  |
| COPY-0366 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:63` | This game didn't live up to the hype | keep | This game didn't live up to the hype | action |  |
| COPY-0367 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:64` | One more game before bed (narrator: it wasn't) | keep | One more game before bed (narrator: it wasn't) | action |  |
| COPY-0368 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:65` | Beginner-friendly picks I'd start with | keep | Beginner-friendly picks I'd start with | action |  |
| COPY-0369 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:66` | Single-player vs. multiplayer — my mood | keep | Single-player vs. multiplayer — my mood | action |  |
| COPY-0370 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:69` | Creative prompts that got me unstuck | keep | Creative prompts that got me unstuck | action |  |
| COPY-0371 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:70` | Why I stopped chasing perfection | keep | Why I stopped chasing perfection | recovery / safety |  |
| COPY-0372 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:71` | Sketch vs. final — the gap is real | keep | Sketch vs. final — the gap is real | action |  |
| COPY-0373 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:72` | Supplies I'd rebuy without hesitation | keep | Supplies I'd rebuy without hesitation | action |  |
| COPY-0374 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:73` | AI art tools — my honest line | keep | AI art tools — my honest line | action |  |
| COPY-0375 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:76` | Routines that made evenings easier | keep | Routines that made evenings easier | action |  |
| COPY-0376 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:77` | Parenting advice I quietly ignored | keep | Parenting advice I quietly ignored | action |  |
| COPY-0377 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:78` | What I thought parenting would be vs. today | keep | What I thought parenting would be vs. today | action |  |
| COPY-0378 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:79` | Books and shows we actually enjoy together | keep | Books and shows we actually enjoy together | action |  |
| COPY-0379 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:80` | Screen time rules — what works here | keep | Screen time rules — what works here | action |  |
| COPY-0380 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:83` | Something I learned recently that surprised me | keep | Something I learned recently that surprised me | action |  |
| COPY-0381 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:84` | A take I don't see enough people sharing | keep | A take I don't see enough people sharing | action |  |
| COPY-0382 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:85` | A day in my life around this topic | keep | A day in my life around this topic | action |  |
| COPY-0383 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:86` | 3 things I'd tell someone just starting | keep | 3 things I'd tell someone just starting | action |  |
| COPY-0384 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingExamplePacks.swift:87` | What's overrated in this space | keep | What's overrated in this space | action |  |
| COPY-0385 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:100` | Let's get to know you | keep | Let's get to know you | information |  |
| COPY-0386 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:101` | Which of these could you imagine posting? | keep | Which of these could you imagine posting? | information |  |
| COPY-0387 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:102` | What can you comfortably create? | keep | What can you comfortably create? | information |  |
| COPY-0388 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:103` | A bit more about you | keep | A bit more about you | information |  |
| COPY-0389 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:104` | Here's what we've understood | keep | Here's what we've understood | information |  |
| COPY-0390 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:192` | None of these — show different examples | keep | None of these — show different examples | information |  |
| COPY-0391 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:292` | Anything else you want to share? (Optional) | keep | Anything else you want to share? (Optional) | information |  |
| COPY-0392 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:323` | Preparing your first idea… | keep | Preparing your first idea… | state |  |
| COPY-0393 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:333` | Your interests | keep | Your interests | action |  |
| COPY-0394 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:342` | Starting point | keep | Starting point | action |  |
| COPY-0395 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:349` | Your style | keep | Your style | action |  |
| COPY-0396 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:360` | Your formats | keep | Your formats | action |  |
| COPY-0397 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:366` | Your time | keep | Your time | action |  |
| COPY-0398 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:372` | Language & camera | keep | Language & camera | action |  |
| COPY-0399 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:386` | Recent interests | keep | Recent interests | action |  |
| COPY-0400 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:414` | Edit | keep | Edit | action |  |
| COPY-0401 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:437` | Continue | keep | Continue | action |  |
| COPY-0402 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:449` | Continue | keep | Continue | action |  |
| COPY-0403 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:459` | Continue | keep | Continue | action |  |
| COPY-0404 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:468` | Nothing specific right now | keep | Nothing specific right now | action |  |
| COPY-0405 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:476` | Continue | keep | Continue | action |  |
| COPY-0406 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:486` | Retry | keep | Retry | information |  |
| COPY-0407 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:491` | Show my first idea | keep | Show my first idea | information |  |
| COPY-0408 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:506` | Back | keep | Back | information |  |
| COPY-0409 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingFlowView.swift:525` | Set up later | keep | Set up later | action |  |
| COPY-0410 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingModels.swift:127` | Just starting | keep | Just starting | information |  |
| COPY-0411 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingModels.swift:128` | Already posting | keep | Already posting | information |  |
| COPY-0412 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingModels.swift:145` | Talking to camera | keep | Talking to camera | information |  |
| COPY-0413 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingModels.swift:146` | Voiceover (with b-roll) | keep | Voiceover (with b-roll) | information |  |
| COPY-0414 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingModels.swift:147` | Text-led videos | keep | Text-led videos | information |  |
| COPY-0415 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingModels.swift:148` | Photo / carousel posts | keep | Photo / carousel posts | information |  |
| COPY-0416 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingModels.swift:171` | 5–10 min | keep | 5–10 min | information |  |
| COPY-0417 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingModels.swift:172` | 10–30 min | keep | 10–30 min | information |  |
| COPY-0418 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingModels.swift:173` | 30+ min | keep | 30+ min | information |  |
| COPY-0419 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingModels.swift:508` | English | keep | English | information |  |
| COPY-0420 | Onboarding | `CreatorContentOS/Features/Onboarding/OnboardingModels.swift:711` | Not set | keep | Not set | information |  |
| COPY-0421 | Onboarding / production | `CreatorContentOS/Features/Onboarding/OnboardingProductionForm.swift:21` | How much time do you usually have? | keep | How much time do you usually have? | information |  |
| COPY-0422 | Onboarding / production | `CreatorContentOS/Features/Onboarding/OnboardingProductionForm.swift:24` | Time you usually have to film or create, not the length of the finished video. | keep | Time you usually have to film or create, not the length of the finished video. | information |  |
| COPY-0423 | Onboarding / production | `CreatorContentOS/Features/Onboarding/OnboardingProductionForm.swift:36` | Content language | keep | Content language | information |  |
| COPY-0424 | Onboarding / production | `CreatorContentOS/Features/Onboarding/OnboardingProductionForm.swift:53` | Are you comfortable showing your face? | keep | Are you comfortable showing your face? | action |  |
| COPY-0425 | Onboarding / production | `CreatorContentOS/Features/Onboarding/OnboardingProductionForm.swift:61` | Are you comfortable using your voice? | keep | Are you comfortable using your voice? | action |  |
| COPY-0426 | Onboarding / toast | `CreatorContentOS/Features/Onboarding/OnboardingViewModel.swift:184` | We saved your preferences but couldn't prepare your first idea. | keep | We saved your preferences but couldn't prepare your first idea. | information |  |
| COPY-0427 | Onboarding / toast | `CreatorContentOS/Features/Onboarding/OnboardingViewModel.swift:294` | Pick at least one topic | keep | Pick at least one topic | feedback |  |
| COPY-0428 | Onboarding / toast | `CreatorContentOS/Features/Onboarding/OnboardingViewModel.swift:298` | Choose Just starting or Already posting | keep | Choose Just starting or Already posting | feedback |  |
| COPY-0429 | Onboarding / toast | `CreatorContentOS/Features/Onboarding/OnboardingViewModel.swift:347` | Pick at least one example, or show different examples | keep | Pick at least one example, or show different examples | feedback |  |
| COPY-0430 | Onboarding / toast | `CreatorContentOS/Features/Onboarding/OnboardingViewModel.swift:387` | Select formats, time, language, and face/voice preferences | keep | Select formats, time, language, and face/voice preferences | feedback |  |
| COPY-0431 | Onboarding / toast | `CreatorContentOS/Features/Onboarding/OnboardingViewModel.swift:437` | Set up later — we'll ask again next launch | rewrite (proposed) | You can finish setup in You. | feedback | C12: proposed until skippable-setup behavior lands |
| COPY-0432 | Onboarding / toast | `CreatorContentOS/Features/Onboarding/OnboardingViewModel.swift:554` | Max 10 references during onboarding | keep | Max 10 references during onboarding | feedback |  |
| COPY-0433 | Onboarding / toast | `CreatorContentOS/Features/Onboarding/OnboardingViewModel.swift:583` | Profile added. We couldn't check Instagram right now. | keep | Profile added. We couldn't check Instagram right now. | feedback |  |
| COPY-0434 | Onboarding / toast | `CreatorContentOS/Features/Onboarding/OnboardingViewModel.swift:589` | Already added | keep | Already added | feedback |  |
| COPY-0435 | Onboarding / toast | `CreatorContentOS/Features/Onboarding/OnboardingViewModel.swift:637` | Add at least one reel URL and one profile @handle to continue. | keep | Add at least one reel URL and one profile @handle to continue. | information |  |
| COPY-0436 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:13` | Other ideas | keep | Other ideas | information |  |
| COPY-0437 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:19` | Choose the smallest useful win. | keep | Choose the smallest useful win. | information |  |
| COPY-0438 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:28` | 10-second story | keep | 10-second story | action |  |
| COPY-0439 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:35` | Caption-only post | keep | Caption-only post | action |  |
| COPY-0440 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:42` | Save for tomorrow | keep | Save for tomorrow | action | Backup option label; keep |
| COPY-0441 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:43` | Keep the card ready. | keep | Keep the card ready. | information |  |
| COPY-0442 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:51` | Skip intentionally | keep | Skip intentionally | action / safety |  |
| COPY-0443 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:69` | Keep the streak alive. | cut |  | information | C3: decorative backup subtitles |
| COPY-0444 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:70` | Keep the streak alive. | cut |  | information | C3: decorative backup subtitles |
| COPY-0445 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:74` | Share the thought. | cut |  | information | C3: decorative backup subtitles |
| COPY-0446 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:75` | Share the thought. | cut |  | information | C3: decorative backup subtitles |
| COPY-0447 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:94` | caption-only | keep | caption-only | information |  |
| COPY-0448 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:145` | Use backup | keep | Use backup | information |  |
| COPY-0449 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:158` | Cancel | keep | Cancel | action / safety |  |
| COPY-0450 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:234` | Copied | keep | Copied | information |  |
| COPY-0451 | Today / backup sheet | `CreatorContentOS/Features/Today/NotTodaySheet.swift:234` | Copy | keep | Copy | information |  |
| COPY-0452 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:47` | Caption | keep | Caption | action |  |
| COPY-0453 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:47` | No caption recorded for today. | keep | No caption recorded for today. | information |  |
| COPY-0454 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:49` | Audio | keep | Audio | action |  |
| COPY-0455 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:49` | No audio notes recorded for today. | keep | No audio notes recorded for today. | information |  |
| COPY-0456 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:60` | Saving… | keep | Saving… | information |  |
| COPY-0457 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:60` | Save edits | keep | Save edits | information |  |
| COPY-0458 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:72` | Mark as posted | keep | Mark as posted | information |  |
| COPY-0459 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:72` | All scenes shot | keep | All scenes shot | information |  |
| COPY-0460 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:72` | Mark all as shot | keep | Mark all as shot | information |  |
| COPY-0461 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:125` | Shoot Folio | keep | Shoot Folio | information |  |
| COPY-0462 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:128` | Today's shoot | keep | Today's shoot | information |  |
| COPY-0463 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:142` | Cancel | keep | Cancel | action / safety |  |
| COPY-0464 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:154` | Edit | keep | Edit | information |  |
| COPY-0465 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:165` | Edit today’s scenes and script | keep | Edit today’s scenes and script | action |  |
| COPY-0466 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:171` | Plan | keep | Plan | action |  |
| COPY-0467 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:185` | Shoot Folio options | keep | Shoot Folio options | action |  |
| COPY-0468 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:280` | No Shoot Folio yet | keep | No Shoot Folio yet | information |  |
| COPY-0469 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:391` | What to capture | keep | What to capture | action |  |
| COPY-0470 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:394` | On-screen text | keep | On-screen text | action |  |
| COPY-0471 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:397` | Example | keep | Example | action |  |
| COPY-0472 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:449` | What to capture | keep | What to capture | action |  |
| COPY-0473 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:450` | Example | keep | Example | action |  |
| COPY-0474 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:453` | On-screen text | keep | On-screen text | action |  |
| COPY-0475 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:456` | Post guidance | keep | Post guidance | action |  |
| COPY-0476 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:459` | Backup option | keep | Backup option | action |  |
| COPY-0477 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:465` | Scene shot | keep | Scene shot | information |  |
| COPY-0478 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:465` | Mark shot | keep | Mark shot | information |  |
| COPY-0479 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:563` | Copied | keep | Copied | information |  |
| COPY-0480 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:563` | Copy | keep | Copy | information |  |
| COPY-0481 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:602` | Script | keep | Script | information |  |
| COPY-0482 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:605` | One line per beat. Timestamps stay tied to scene order. | keep | One line per beat. Timestamps stay tied to scene order. | information |  |
| COPY-0483 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:617` | Script | keep | Script | action |  |
| COPY-0484 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:622` | Script | keep | Script | information |  |
| COPY-0485 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:655` | Copied | keep | Copied | information |  |
| COPY-0486 | Shoot Folio | `CreatorContentOS/Features/Today/ShootFolioView.swift:655` | Copy full script | keep | Copy full script | information |  |
| COPY-0487 | Shoot Folio / scene example wrapper | `CreatorContentOS/Features/Today/ShootFolioView.swift:543` | The creator can shoot this at home, in the society garden, or in the gym | rewrite | You can shoot this at home or wherever makes the scene easiest to capture clearly and safely. | information | C6: third-person + India/HYROX default in client fallback |
| COPY-0488 | Shoot Folio / empty state | `CreatorContentOS/Features/Today/ShootFolioView.swift:294` | The app is checking live Supabase content. | keep | The app is checking live Supabase content. | information |  |
| COPY-0489 | Shoot Folio / empty state | `CreatorContentOS/Features/Today/ShootFolioView.swift:296` | Today's published card does not include shoot scenes. | rewrite | Today's ready card does not include shoot scenes. | information | C8: Ready package vocabulary; avoid machine voice |
| COPY-0490 | Today | `CreatorContentOS/Features/Today/TodayView.swift:39` | Mark posted | rewrite | Mark as posted | information | C7: unify with Shoot Folio |
| COPY-0491 | Today | `CreatorContentOS/Features/Today/TodayView.swift:47` | All scenes shot | keep | All scenes shot | information |  |
| COPY-0492 | Today | `CreatorContentOS/Features/Today/TodayView.swift:47` | Mark all as shot | keep | Mark all as shot | information |  |
| COPY-0493 | Today | `CreatorContentOS/Features/Today/TodayView.swift:56` | Give me other ideas | keep | Give me other ideas | information |  |
| COPY-0494 | Today | `CreatorContentOS/Features/Today/TodayView.swift:77` | Today | keep | Today | information |  |
| COPY-0495 | Today | `CreatorContentOS/Features/Today/TodayView.swift:99` | Plan | keep | Plan | action |  |
| COPY-0496 | Today | `CreatorContentOS/Features/Today/TodayView.swift:113` | Today options | keep | Today options | action |  |
| COPY-0497 | Today | `CreatorContentOS/Features/Today/TodayView.swift:193` | Checking today's plan | keep | Checking today's plan | information |  |
| COPY-0498 | Today | `CreatorContentOS/Features/Today/TodayView.swift:196` | The app is loading the latest published card. | rewrite | Getting your latest card… | state | C8: Ready package vocabulary; avoid machine voice |
| COPY-0499 | Today | `CreatorContentOS/Features/Today/TodayView.swift:218` | Nothing ready for today | keep | Nothing ready for today | information |  |
| COPY-0500 | Today | `CreatorContentOS/Features/Today/TodayView.swift:221` | There’s no ready package for this date yet. Open Plan to generate one and make it available on Today. | keep | There’s no ready package for this date yet. Open Plan to generate one and make it available on Today. | information |  |
| COPY-0501 | Today | `CreatorContentOS/Features/Today/TodayView.swift:230` | Plan today’s content | keep | Plan today’s content | information |  |
| COPY-0502 | Today | `CreatorContentOS/Features/Today/TodayView.swift:243` | Plan today’s content | keep | Plan today’s content | action |  |
| COPY-0503 | You / benchmark (DEBUG-adjacent) | `CreatorContentOS/Features/You/DayGenerationBenchmarkView.swift:25` | Benchmark needs the paired live runtime. Sign in and pair a device first. | keep | Benchmark needs the paired live runtime. Sign in and pair a device first. | information |  |
| COPY-0504 | You / benchmark (DEBUG-adjacent) | `CreatorContentOS/Features/You/DayGenerationBenchmarkView.swift:38` | Generation benchmark | keep | Generation benchmark | information |  |
| COPY-0505 | You / benchmark (DEBUG-adjacent) | `CreatorContentOS/Features/You/DayGenerationBenchmarkView.swift:42` | Done | keep | Done | action |  |
| COPY-0506 | You / benchmark (DEBUG-adjacent) | `CreatorContentOS/Features/You/DayGenerationBenchmarkView.swift:69` | Runs | keep | Runs | information |  |
| COPY-0507 | You / benchmark (DEBUG-adjacent) | `CreatorContentOS/Features/You/DayGenerationBenchmarkView.swift:88` | Cancel | keep | Cancel | action / safety |  |
| COPY-0508 | You / benchmark (DEBUG-adjacent) | `CreatorContentOS/Features/You/DayGenerationBenchmarkView.swift:116` | Summary | keep | Summary | information |  |
| COPY-0509 | You / benchmark (DEBUG-adjacent) | `CreatorContentOS/Features/You/DayGenerationBenchmarkView.swift:125` | Copied | keep | Copied | information |  |
| COPY-0510 | You / benchmark (DEBUG-adjacent) | `CreatorContentOS/Features/You/DayGenerationBenchmarkView.swift:125` | Copy summary | keep | Copy summary | information |  |
| COPY-0511 | You / benchmark (DEBUG-adjacent) | `CreatorContentOS/Features/You/DayGenerationBenchmarkView.swift:133` | Failure detail | keep | Failure detail | information |  |
| COPY-0512 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:9` | Account | keep | Account | action |  |
| COPY-0513 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:10` | Signed-in identity, runtime health, and sign-out. | keep | Signed-in identity, runtime health, and sign-out. | information |  |
| COPY-0514 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:31` | Identity | keep | Identity | information |  |
| COPY-0515 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:39` | Sample | keep | Sample | information |  |
| COPY-0516 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:54` | Using sample data | keep | Using sample data | information |  |
| COPY-0517 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:88` | Status | keep | Status | information |  |
| COPY-0518 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:91` | Supabase | keep | Supabase | action |  |
| COPY-0519 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:97` | Gemini | keep | Gemini | action |  |
| COPY-0520 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:153` | Offline | keep | Offline | information |  |
| COPY-0521 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:154` | Live | keep | Live | information |  |
| COPY-0522 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:155` | Checking | keep | Checking | information |  |
| COPY-0523 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:156` | Down | keep | Down | information |  |
| COPY-0524 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:157` | — | keep | — | information |  |
| COPY-0525 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:229` | Debug | DEBUG | Debug | information | AdminShell or DEBUG-only surface |
| COPY-0526 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:231` | Clears onboarding progress and completion flags for QA reruns. | DEBUG | Clears onboarding progress and completion flags for QA reruns. | information | AdminShell or DEBUG-only surface |
| COPY-0527 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:237` | Onboarding reset | DEBUG | Onboarding reset | information | AdminShell or DEBUG-only surface |
| COPY-0528 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:237` | Reset onboarding | DEBUG | Reset onboarding | information | AdminShell or DEBUG-only surface |
| COPY-0529 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:255` | Signing out | keep | Signing out | information |  |
| COPY-0530 | You / account | `CreatorContentOS/Features/You/YouAccountView.swift:255` | Sign out | keep | Sign out | action / safety |  |
| COPY-0531 | You / content categories | `CreatorContentOS/Features/You/YouContentCategoriesView.swift:15` | Interests & style | keep | Interests & style | action |  |
| COPY-0532 | You / content categories | `CreatorContentOS/Features/You/YouContentCategoriesView.swift:16` | Topics and starting point that shape your daily ideas. | keep | Topics and starting point that shape your daily ideas. | information |  |
| COPY-0533 | You / content categories | `CreatorContentOS/Features/You/YouContentCategoriesView.swift:20` | Your interests | keep | Your interests | information |  |
| COPY-0534 | You / content categories | `CreatorContentOS/Features/You/YouContentCategoriesView.swift:22` | Pick as many as you like. Custom topics are welcome. | keep | Pick as many as you like. Custom topics are welcome. | information |  |
| COPY-0535 | You / content categories | `CreatorContentOS/Features/You/YouContentCategoriesView.swift:113` | Saving… | keep | Saving… | information |  |
| COPY-0536 | You / content categories | `CreatorContentOS/Features/You/YouContentCategoriesView.swift:121` | Changes save automatically and shape future ideas. | keep | Changes save automatically and shape future ideas. | information |  |
| COPY-0537 | You / creator voice | `CreatorContentOS/Features/You/YouCreatorVoiceView.swift:40` | Creator voice | keep | Creator voice | action |  |
| COPY-0538 | You / creator voice | `CreatorContentOS/Features/You/YouCreatorVoiceView.swift:52` | Saved voice | keep | Saved voice | information |  |
| COPY-0539 | You / creator voice | `CreatorContentOS/Features/You/YouCreatorVoiceView.swift:58` | Prefilled from your references and categories — your ideas still start from your references alone until you save your own voice. | keep | Prefilled from your references and categories — your ideas still start from your references alone until you save your own voice. | information |  |
| COPY-0540 | You / creator voice | `CreatorContentOS/Features/You/YouCreatorVoiceView.swift:65` | Positioning | keep | Positioning | action |  |
| COPY-0541 | You / creator voice | `CreatorContentOS/Features/You/YouCreatorVoiceView.swift:75` | Voice rules | keep | Voice rules | action |  |
| COPY-0542 | You / creator voice | `CreatorContentOS/Features/You/YouCreatorVoiceView.swift:85` | Pillars | keep | Pillars | action |  |
| COPY-0543 | You / creator voice | `CreatorContentOS/Features/You/YouCreatorVoiceView.swift:91` | Caption style | keep | Caption style | action |  |
| COPY-0544 | You / creator voice | `CreatorContentOS/Features/You/YouCreatorVoiceView.swift:97` | Never sounds like | keep | Never sounds like | action |  |
| COPY-0545 | You / creator voice | `CreatorContentOS/Features/You/YouCreatorVoiceView.swift:107` | Saving | keep | Saving | information |  |
| COPY-0546 | You / creator voice | `CreatorContentOS/Features/You/YouCreatorVoiceView.swift:107` | Save voice | keep | Save voice | information |  |
| COPY-0547 | You / current context | `CreatorContentOS/Features/You/YouCurrentContextView.swift:22` | Current reads & watches | keep | Current reads & watches | action |  |
| COPY-0548 | You / current context | `CreatorContentOS/Features/You/YouCurrentContextView.swift:23` | What's current for you — helps ideas feel personal. | keep | What's current for you — helps ideas feel personal. | information |  |
| COPY-0549 | You / current context | `CreatorContentOS/Features/You/YouCurrentContextView.swift:27` | Your context | keep | Your context | information |  |
| COPY-0550 | You / current context | `CreatorContentOS/Features/You/YouCurrentContextView.swift:53` | Anything else you want to share? (Optional) | keep | Anything else you want to share? (Optional) | information |  |
| COPY-0551 | You / current context | `CreatorContentOS/Features/You/YouCurrentContextView.swift:90` | Saving… | keep | Saving… | information |  |
| COPY-0552 | You / current context | `CreatorContentOS/Features/You/YouCurrentContextView.swift:98` | Changes save automatically and shape future ideas. | keep | Changes save automatically and shape future ideas. | information |  |
| COPY-0553 | You / production preferences | `CreatorContentOS/Features/You/YouProductionPreferencesView.swift:20` | Content preferences | keep | Content preferences | action |  |
| COPY-0554 | You / production preferences | `CreatorContentOS/Features/You/YouProductionPreferencesView.swift:21` | Formats, time, language, and on-camera comfort. | keep | Formats, time, language, and on-camera comfort. | information |  |
| COPY-0555 | You / production preferences | `CreatorContentOS/Features/You/YouProductionPreferencesView.swift:25` | Production setup | keep | Production setup | information |  |
| COPY-0556 | You / production preferences | `CreatorContentOS/Features/You/YouProductionPreferencesView.swift:70` | Saving… | keep | Saving… | information |  |
| COPY-0557 | You / production preferences | `CreatorContentOS/Features/You/YouProductionPreferencesView.swift:78` | Changes save automatically and shape future ideas. | keep | Changes save automatically and shape future ideas. | information |  |
| COPY-0558 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:12` | References | keep | References | action |  |
| COPY-0559 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:13` | Save reels, audio, and inspiration accounts for future drafts. | keep | Save reels, audio, and inspiration accounts for future drafts. | information |  |
| COPY-0560 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:41` | Add references | keep | Add references | information |  |
| COPY-0561 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:46` | Import inspiration | keep | Import inspiration | action |  |
| COPY-0562 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:47` | Paste links, handles, notes, or upload CSV. | keep | Paste links, handles, notes, or upload CSV. | information |  |
| COPY-0563 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:78` | Needs your call | keep | Needs your call | information |  |
| COPY-0564 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:122` | Approve | cut | (drop title; show human message only) | action | C4: error tile title duplicates message noun |
| COPY-0565 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:125` | Dismiss | keep | Dismiss | action |  |
| COPY-0566 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:128` | Edit | keep | Edit | action |  |
| COPY-0567 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:162` | Confirmed references | keep | Confirmed references | action / safety |  |
| COPY-0568 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:164` | No references yet — add one above. | keep | No references yet — add one above. | information |  |
| COPY-0569 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:215` | Growth references | keep | Growth references | information |  |
| COPY-0570 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:259` | Recently used | keep | Recently used | information |  |
| COPY-0571 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:302` | Library | keep | Library | information |  |
| COPY-0572 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:359` | Reference import preview failed. | keep | Reference import preview failed. | recovery / safety |  |
| COPY-0573 | You / references | `CreatorContentOS/Features/You/YouReferencesView.swift:372` | Reference import failed. | keep | Reference import failed. | recovery / safety |  |
| COPY-0574 | You / hub | `CreatorContentOS/Features/You/YouView.swift:17` | You | keep | You | information |  |
| COPY-0575 | You / hub | `CreatorContentOS/Features/You/YouView.swift:53` | Dev | DEBUG | Dev | information | AdminShell or DEBUG-only surface |
| COPY-0576 | You / hub | `CreatorContentOS/Features/You/YouView.swift:58` | Run generation benchmark | DEBUG | Run generation benchmark | action | AdminShell or DEBUG-only surface |
| COPY-0577 | You / hub | `CreatorContentOS/Features/You/YouView.swift:59` | N real generations through the live runtime — p95 gate | DEBUG | N real generations through the live runtime — p95 gate | information | AdminShell or DEBUG-only surface |
| COPY-0578 | You / hub | `CreatorContentOS/Features/You/YouView.swift:70` | Account | keep | Account | information |  |
| COPY-0579 | You / hub | `CreatorContentOS/Features/You/YouView.swift:86` | Generation inputs | rewrite | Idea settings | information | C9: avoid backend term generation |
| COPY-0580 | You / hub | `CreatorContentOS/Features/You/YouView.swift:88` | Interests & style | keep | Interests & style | action |  |
| COPY-0581 | You / hub | `CreatorContentOS/Features/You/YouView.swift:90` | Content preferences | keep | Content preferences | action |  |
| COPY-0582 | You / hub | `CreatorContentOS/Features/You/YouView.swift:92` | Current reads & watches | keep | Current reads & watches | action |  |
| COPY-0583 | You / hub | `CreatorContentOS/Features/You/YouView.swift:94` | Creator voice | keep | Creator voice | action |  |
| COPY-0584 | You / hub | `CreatorContentOS/Features/You/YouView.swift:96` | References | keep | References | action |  |
| COPY-0585 | You / hub | `CreatorContentOS/Features/You/YouView.swift:103` | Archive | keep | Archive | information |  |
| COPY-0586 | You / hub | `CreatorContentOS/Features/You/YouView.swift:110` | Signing out | keep | Signing out | information |  |
| COPY-0587 | You / hub | `CreatorContentOS/Features/You/YouView.swift:110` | Sign out | keep | Sign out | action / safety |  |
| COPY-0588 | You / hub | `CreatorContentOS/Features/You/YouView.swift:272` | Nothing posted yet. | keep | Nothing posted yet. | information |  |
| COPY-0589 | You / hub | `CreatorContentOS/Features/You/YouView.swift:292` | See more | keep | See more | information |  |
| COPY-0590 | ContentQualityLearningLoop | `CreatorContentOS/Models/ContentQualityLearningLoop.swift:43` | 1h | keep | 1h | information |  |
| COPY-0591 | ContentQualityLearningLoop | `CreatorContentOS/Models/ContentQualityLearningLoop.swift:44` | 6h | keep | 6h | information |  |
| COPY-0592 | ContentQualityLearningLoop | `CreatorContentOS/Models/ContentQualityLearningLoop.swift:45` | 24h | keep | 24h | information |  |
| COPY-0593 | ContentQualityLearningLoop | `CreatorContentOS/Models/ContentQualityLearningLoop.swift:46` | 72h | keep | 72h | information |  |
| COPY-0594 | ContentQualityLearningLoop | `CreatorContentOS/Models/ContentQualityLearningLoop.swift:47` | 7d | keep | 7d | information |  |
| COPY-0595 | ContentQualityLearningLoop | `CreatorContentOS/Models/ContentQualityLearningLoop.swift:48` | 30d | keep | 30d | information |  |
| COPY-0596 | ContentQualityLearningLoop | `CreatorContentOS/Models/ContentQualityLearningLoop.swift:1321` | under_15 | keep | under_15 | information |  |
| COPY-0597 | ContentQualityLearningLoop | `CreatorContentOS/Models/ContentQualityLearningLoop.swift:1322` | 15_30 | keep | 15_30 | information |  |
| COPY-0598 | ContentQualityLearningLoop | `CreatorContentOS/Models/ContentQualityLearningLoop.swift:1323` | 30_60 | keep | 30_60 | information |  |
| COPY-0599 | ContentQualityLearningLoop | `CreatorContentOS/Models/ContentQualityLearningLoop.swift:1324` | 60_90 | keep | 60_90 | information |  |
| COPY-0600 | ContentQualityLearningLoop | `CreatorContentOS/Models/ContentQualityLearningLoop.swift:1325` | over_90 | keep | over_90 | information |  |
| COPY-0601 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:86` | Editor access required | DEBUG | Editor access required | information | AdminShell or DEBUG-only surface |
| COPY-0602 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:94` | Profile save error | DEBUG | Profile save error | recovery / safety | AdminShell or DEBUG-only surface |
| COPY-0603 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:377` | Generation error | cut | (drop title; show human message only) | recovery / safety | C4: error tile title duplicates message noun; AdminShell or DEBUG-only surface |
| COPY-0604 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:501` | No draft loaded | DEBUG | No draft loaded | information | AdminShell or DEBUG-only surface |
| COPY-0605 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:807` | Owner access required | DEBUG | Owner access required | information | AdminShell or DEBUG-only surface |
| COPY-0606 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:815` | Tester access | DEBUG | Tester access | information | AdminShell or DEBUG-only surface |
| COPY-0607 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:823` | Tester access error | DEBUG | Tester access error | recovery / safety | AdminShell or DEBUG-only surface |
| COPY-0608 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:19` | Daily | DEBUG | Daily | action | AdminShell or DEBUG-only surface |
| COPY-0609 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:24` | References | DEBUG | References | action | AdminShell or DEBUG-only surface |
| COPY-0610 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:87` | Editor access required | DEBUG | Editor access required | action | AdminShell or DEBUG-only surface |
| COPY-0611 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:95` | Profile save error | DEBUG | Profile save error | recovery / safety | AdminShell or DEBUG-only surface |
| COPY-0612 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:142` | Back | DEBUG | Back | action | AdminShell or DEBUG-only surface |
| COPY-0613 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:144` | Creator Profile | DEBUG | Creator Profile | information | AdminShell or DEBUG-only surface |
| COPY-0614 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:156` | Creator mode | DEBUG | Creator mode | action | AdminShell or DEBUG-only surface |
| COPY-0615 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:162` | Refresh | DEBUG | Refresh | action | AdminShell or DEBUG-only surface |
| COPY-0616 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:173` | Creator Profile options | DEBUG | Creator Profile options | action | AdminShell or DEBUG-only surface |
| COPY-0617 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:181` | Content Pillars | DEBUG | Content Pillars | action | AdminShell or DEBUG-only surface |
| COPY-0618 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:183` | gym lifestyle eating recovery | DEBUG | gym lifestyle eating recovery | input guidance | AdminShell or DEBUG-only surface |
| COPY-0619 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:187` | Recurring Formats | DEBUG | Recurring Formats | action | AdminShell or DEBUG-only surface |
| COPY-0620 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:189` | one practical detail caption-only backup | DEBUG | one practical detail caption-only backup | input guidance | AdminShell or DEBUG-only surface |
| COPY-0621 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:199` | Creator voice | DEBUG | Creator voice | action | AdminShell or DEBUG-only surface |
| COPY-0622 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:200` | Shape how this creator sounds, feels, and never sounds. | DEBUG | Shape how this creator sounds, feels, and never sounds. | information | AdminShell or DEBUG-only surface |
| COPY-0623 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:205` | Point of view | DEBUG | Point of view | action | AdminShell or DEBUG-only surface |
| COPY-0624 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:221` | Point of view, using positioning | DEBUG | Point of view, using positioning | action | AdminShell or DEBUG-only surface |
| COPY-0625 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:224` | Voice essence | DEBUG | Voice essence | action | AdminShell or DEBUG-only surface |
| COPY-0626 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:226` | Warm Precise Light Hinglish when natural | DEBUG | Warm Precise Light Hinglish when natural | input guidance | AdminShell or DEBUG-only surface |
| COPY-0627 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:231` | Sounds like this creator | DEBUG | Sounds like this creator | action | AdminShell or DEBUG-only surface |
| COPY-0628 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:233` | Short, useful, and human. | DEBUG | Short, useful, and human. | input guidance | AdminShell or DEBUG-only surface |
| COPY-0629 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:240` | Never sounds like | DEBUG | Never sounds like | action | AdminShell or DEBUG-only surface |
| COPY-0630 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:242` | Politics Weight talk Negativity | DEBUG | Politics Weight talk Negativity | input guidance | AdminShell or DEBUG-only surface |
| COPY-0631 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:248` | Identity context | DEBUG | Identity context | action | AdminShell or DEBUG-only surface |
| COPY-0632 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:251` | Age or identity details should only be used when they add emotional weight or context, not in every post. | DEBUG | Age or identity details should only be used when they add emotional weight or context, not in every post. | information | AdminShell or DEBUG-only surface |
| COPY-0633 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:257` | Identity context rule, read-only | DEBUG | Identity context rule, read-only | action | AdminShell or DEBUG-only surface |
| COPY-0634 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:261` | Writing test | DEBUG | Writing test | action | AdminShell or DEBUG-only surface |
| COPY-0635 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:264` | If another creator could say a line unchanged, rewrite it with this creator's lived detail, opinion, relationships, home context, or humour. | DEBUG | If another creator could say a line unchanged, rewrite it with this creator's lived detail, opinion, relationships, home context, or humour. | information | AdminShell or DEBUG-only surface |
| COPY-0636 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:270` | Writing test rule, read-only | DEBUG | Writing test rule, read-only | action | AdminShell or DEBUG-only surface |
| COPY-0637 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:378` | Generation error | cut | (drop title; show human message only) | recovery / safety | C4: error tile title duplicates message noun; AdminShell or DEBUG-only surface |
| COPY-0638 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:390` | Creator mode | DEBUG | Creator mode | action | AdminShell or DEBUG-only surface |
| COPY-0639 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:408` | AI Runway | DEBUG | AI Runway | information | AdminShell or DEBUG-only surface |
| COPY-0640 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:429` | Runtime | DEBUG | Runtime | action | AdminShell or DEBUG-only surface |
| COPY-0641 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:435` | Week | DEBUG | Week | action | AdminShell or DEBUG-only surface |
| COPY-0642 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:441` | Draft cards | DEBUG | Draft cards | action | AdminShell or DEBUG-only surface |
| COPY-0643 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:447` | Sources | DEBUG | Sources | action | AdminShell or DEBUG-only surface |
| COPY-0644 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:466` | Latest Draft | DEBUG | Latest Draft | action | AdminShell or DEBUG-only surface |
| COPY-0645 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:467` | No generation has completed in this session. | DEBUG | No generation has completed in this session. | information | AdminShell or DEBUG-only surface |
| COPY-0646 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:479` | Cards | DEBUG | Cards | action | AdminShell or DEBUG-only surface |
| COPY-0647 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:484` | Ideas | DEBUG | Ideas | action | AdminShell or DEBUG-only surface |
| COPY-0648 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:489` | Source | DEBUG | Source | action | AdminShell or DEBUG-only surface |
| COPY-0649 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:493` | Warnings | DEBUG | Warnings | action | AdminShell or DEBUG-only surface |
| COPY-0650 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:496` | Assumptions | DEBUG | Assumptions | action | AdminShell or DEBUG-only surface |
| COPY-0651 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:502` | No draft loaded | DEBUG | No draft loaded | action | AdminShell or DEBUG-only surface |
| COPY-0652 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:513` | Input Context | DEBUG | Input Context | action | AdminShell or DEBUG-only surface |
| COPY-0653 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:513` | Profile, setup, references, archive, and ideas. | DEBUG | Profile, setup, references, archive, and ideas. | information | AdminShell or DEBUG-only surface |
| COPY-0654 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:518` | Creator | DEBUG | Creator | action | AdminShell or DEBUG-only surface |
| COPY-0655 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:523` | Access | DEBUG | Access | action | AdminShell or DEBUG-only surface |
| COPY-0656 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:540` | Idea Queue | DEBUG | Idea Queue | action | AdminShell or DEBUG-only surface |
| COPY-0657 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:571` | Refresh | DEBUG | Refresh | action | AdminShell or DEBUG-only surface |
| COPY-0658 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:575` | Open Today | DEBUG | Open Today | action | AdminShell or DEBUG-only surface |
| COPY-0659 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:592` | Live QA | DEBUG | Live QA | information | AdminShell or DEBUG-only surface |
| COPY-0660 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:597` | Checks that live data is loading, writable, and safe to publish. | DEBUG | Checks that live data is loading, writable, and safe to publish. | state | AdminShell or DEBUG-only surface |
| COPY-0661 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:613` | Runtime | DEBUG | Runtime | action | AdminShell or DEBUG-only surface |
| COPY-0662 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:619` | Today | DEBUG | Today | action | AdminShell or DEBUG-only surface |
| COPY-0663 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:620` | Loaded | DEBUG | Loaded | information | AdminShell or DEBUG-only surface |
| COPY-0664 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:625` | Archive | DEBUG | Archive | action | AdminShell or DEBUG-only surface |
| COPY-0665 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:631` | Publish | DEBUG | Publish | action | AdminShell or DEBUG-only surface |
| COPY-0666 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:633` | No publish summary | DEBUG | No publish summary | information | AdminShell or DEBUG-only surface |
| COPY-0667 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:641` | Creator Today Card | DEBUG | Creator Today Card | action | AdminShell or DEBUG-only surface |
| COPY-0668 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:652` | Effort | DEBUG | Effort | action | AdminShell or DEBUG-only surface |
| COPY-0669 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:654` | Caption | DEBUG | Caption | action | AdminShell or DEBUG-only surface |
| COPY-0670 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:657` | Backup | DEBUG | Backup | action | AdminShell or DEBUG-only surface |
| COPY-0671 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:666` | Published Week Path | DEBUG | Published Week Path | action | AdminShell or DEBUG-only surface |
| COPY-0672 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:682` | Live data signals | DEBUG | Live data signals | action | AdminShell or DEBUG-only surface |
| COPY-0673 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:682` | Latest app-side sync state. | DEBUG | Latest app-side sync state. | information | AdminShell or DEBUG-only surface |
| COPY-0674 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:687` | Repository | DEBUG | Repository | action | AdminShell or DEBUG-only surface |
| COPY-0675 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:688` | No sync error | DEBUG | No sync error | recovery / safety | AdminShell or DEBUG-only surface |
| COPY-0676 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:692` | Generation | DEBUG | Generation | action | AdminShell or DEBUG-only surface |
| COPY-0677 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:693` | Ready | DEBUG | Ready | information | AdminShell or DEBUG-only surface |
| COPY-0678 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:697` | AI boundary | DEBUG | AI boundary | action | AdminShell or DEBUG-only surface |
| COPY-0679 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:703` | Reminder | DEBUG | Reminder | action | AdminShell or DEBUG-only surface |
| COPY-0680 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:734` | Creator mode | DEBUG | Creator mode | action | AdminShell or DEBUG-only surface |
| COPY-0681 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:762` | Testers | DEBUG | Testers | information | AdminShell or DEBUG-only surface |
| COPY-0682 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:765` | Approve email OTP access for people testing Creator's live workspace. | DEBUG | Approve email OTP access for people testing Creator's live workspace. | information | AdminShell or DEBUG-only surface |
| COPY-0683 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:776` | Invite tester | DEBUG | Invite tester | information | AdminShell or DEBUG-only surface |
| COPY-0684 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:792` | Send email code | DEBUG | Send email code | action | AdminShell or DEBUG-only surface |
| COPY-0685 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:808` | Owner access required | DEBUG | Owner access required | action | AdminShell or DEBUG-only surface |
| COPY-0686 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:816` | Tester access | DEBUG | Tester access | action | AdminShell or DEBUG-only surface |
| COPY-0687 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:824` | Tester access error | DEBUG | Tester access error | recovery / safety | AdminShell or DEBUG-only surface |
| COPY-0688 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:836` | Approved Testers | DEBUG | Approved Testers | action | AdminShell or DEBUG-only surface |
| COPY-0689 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:842` | Refresh to load approved tester emails from Supabase. | DEBUG | Refresh to load approved tester emails from Supabase. | information | AdminShell or DEBUG-only surface |
| COPY-0690 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:884` | Resend code | DEBUG | Resend code | action | AdminShell or DEBUG-only surface |
| COPY-0691 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:888` | Revoke | DEBUG | Revoke | action | AdminShell or DEBUG-only surface |
| COPY-0692 | Admin shell (DEBUG) | `CreatorContentOS/Navigation/AdminShellView.swift:1064` | Manager Weekly Control | DEBUG | Manager Weekly Control | information | AdminShell or DEBUG-only surface |
