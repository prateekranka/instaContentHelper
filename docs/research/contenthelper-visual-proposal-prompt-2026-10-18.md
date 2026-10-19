# ContentHelper visual proposal prompt

Mode: built-in imagegen. Output: a concept board with four proposed screens, not an app screenshot or editable native design.

Palette was read from `CreatorContentOS/Features/Design/PocketSheetTheme.swift` on 18 October 2026. The app source was not changed.

```text
Use case: ui-mockup.
Create a polished, high-fidelity product design board for the native iPhone app ContentHelper. This is an original proposed interface, not an existing app screenshot. Show FOUR complete, straight-on iPhone screen designs in one horizontal row on a quiet light gray canvas. Large landscape board, ideally 3200 x 1800, with generous margins and crisp readable text. The phone screens should be the focus, not phone hardware: thin charcoal frames, softly rounded corners, standard 9:41 status bars and home indicators. No tilted devices, hands, photorealistic scenes, gradients, decorative blobs, or stock photos.

Match the existing creator design tokens: background #FAFAFA, white raised surfaces #FFFFFF, ink #111111, secondary text #737373, thin borders #E5E5E5, muted fills #F5F5F5. Black filled primary buttons with white text. Native Apple-style sans serif, large semibold headings, comfortable 16–24 pt spacing, card radius 16 and control radius 14. Black and white UI only. Calm, practical, precise, with strong readable hierarchy and very little decoration. Do not use the warmer editorial/manager palette.

Board title at top left: "ContentHelper". Subtitle: "Proposed interface · sample content". Small flow labels above the four screens: "01  QUICK CHOICES", "02  TODAY", "03  EDIT ONE LINE", "04  RESUME FILMING". Place a small right arrow between each phone. A short note under the first arrow: "Apple sign-in + AI consent before generation". These annotations are outside the phone UI.

PHONE 1 — the short skippable setup screen.
Back chevron top left; "Skip" top right.
Heading: "What would you like to make?"
Supporting copy: "A little context for your first plan"
Section label: "TOPIC"
A compact two-column chip group: "Fitness" selected with a clear checkmark and black fill; "Everyday life", "Food", "Books" outlined and unselected.
Section label: "CONTENT LANGUAGE"
A clean full-width selector row: "English" with a chevron.
Small support line: "You can change these later in You"
A small muted summary card: "Your starter plan" then "Fitness · English · Simple to film".
Near the bottom a large black button: "Make my first plan"
Below it a clear text action: "Skip for now".
No bottom tab bar on setup. Do not show any extra mandatory profile form.

PHONE 2 — first useful package on Today.
Small top line "SUNDAY, 18 OCTOBER"
Heading "Today" with a simple overflow menu on right.
Main heading: "A quiet moment before training"
Metadata "REEL · 3 SHOTS · ABOUT 5 MIN TO FILM"
A light gray information block labeled "WHY THIS IDEA" with the short text "A simple starting point for your fitness content"
Three clean rows or compact sections labeled "Script", "Shots", "Caption"; "Script" is expanded.
In expanded Script area show: "Before I start training, I take a minute to get everything ready"
A small "Edit" action beside the Script heading.
Two compact shot rows below: "01  Set out your gear" and "02  Get ready to move".
A large black primary button near bottom "Start filming"
Below it text action "Make it easier".
Native bottom tabs "Today", "Plan", "You", Today active in black, others muted, simple outline icons.

PHONE 3 — targeted script refinement, clearly visible original-versus-suggestion comparison.
Back chevron and title "Edit script line".
A small selected action chip "Make it shorter".
Muted label "ORIGINAL"
A bordered text card: "Before I start training, I take a minute to get everything ready"
Muted label "SUGGESTION"
A second light gray text card with larger readable text: "A minute to get ready, then I start"
Under the suggestion a small circular arrow icon and "Try another".
A small plain line with a lock icon: "Your shots and caption stay as saved"
Near bottom a large black button: "Apply suggestion"
Below it a full-width outlined button: "Keep original".
This is a full focused edit screen; no bottom tab bar and no keyboard. Do not add an "applied" status yet.

PHONE 4 — a resumed filming guide, not an in-app camera.
Back chevron top left and small title "Shoot Folio".
Large heading "Continue filming"
A subtle saved-state badge with checkmark: "Your place is saved"
Three-segment progress line, first segment black, others gray.
Label "SHOT 2 OF 3"
Heading "Get your gear ready"
A simple large framing diagram inside a white bordered rectangle: top-down outline of a folded towel, shoes, and water bottle, drawn as simple monochrome line art. No people or photographic image.
Instruction: "Capture a short clip in your usual camera app"
Small section "SAY THIS" then "A minute to get ready, then I start"
Small support line "1 of 3 shots marked captured"
Large black button "Mark captured"
Under it side-by-side plain actions "Previous shot" and "Pause for now".
No camera record button, no fake media thumbnail and no claim that a video was saved.

Below all four screens add four short, elegant numbered callouts, one aligned to each phone:
"One skippable setup screen"
"One clear next action"
"Preview before replacing"
"Return to the same shot"

All typography must be clean and correctly spelled. Keep button labels complete, content within safe areas, and phone designs aligned at equal scale. This is a design proposal only. No competitor logos, blue Mobbin highlights, or library Save/Copy overlays.
```
