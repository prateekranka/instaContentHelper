# Visual revision 2 — yellow-marked removals

The user requested these changes to the generated concept board. Scope: image only. App code and the original board remain unchanged.

- Quick choices: remove the introductory helper sentence and the bottom Skip for now action. Keep the top-right Skip action.
- Today: remove the Why this idea card.
- Edit one line: remove the Make it shorter chip, the lock/helper note, and the Keep original button. Keep the Original and Suggestion cards.
- Resume filming: remove the saved-place badge. Shorten Previous shot to Previous, and Pause for now to Pause.
- Remove the yellow annotation ink from the delivered version and close gaps left by deletions.

Tool: built-in imagegen, edit mode. Image 1: original concept board, edit target. Image 2: marked user image, reference only.

The first pass removed the marked elements. A second focused pass restores the unmarked sign-in/AI-consent caption between the first two phones.

## Exact edit prompt

```text
Use case: precise-object-edit.
Edit the supplied ContentHelper interface board.
Input image 1 is the CLEAN ORIGINAL and is the edit target.
Input image 2 is the user's yellow-marked feedback reference ONLY. It identifies deletions. Do not reproduce any yellow ink or handwriting.

Keep the same landscape composition, four phone frames, monochrome palette, typography, title, subtitle, screen headings, sample content, icons, phone status bars, bottom navigation, gear drawing, and numbered callouts. Make only the deletions and word removals listed below. Preserve the clean original rather than redesigning or reinterpreting the interface.

PHONE 1, QUICK CHOICES:
- Delete the helper line "A little context for your first plan" beneath the large heading.
- Delete the bottom secondary action "Skip for now".
- Keep the small TOP-RIGHT "Skip" action: it was not circled.
- Keep all topic chips, the language selector, "You can change these later in You", the starter-plan card, and "Make my first plan".
- Close the gap left by the deleted helper line with normal spacing. Keep the remaining primary action near the bottom.

PHONE 2, TODAY:
- Delete the ENTIRE "WHY THIS IDEA" card, including its small heading, explanatory text "A simple starting point for your fitness content", and gray card background.
- Move the Script, Shots, and Caption sections upward to close the space.
- Preserve the title, Reel metadata, script wording, Edit link, Start filming, Make it easier, and Today/Plan/You tabs.

PHONE 3, EDIT ONE LINE:
- Delete the black "Make it shorter" chip below the screen title.
- Delete the lock icon and the sentence "Your shots and caption stay as saved", including any separator used only for that note.
- Delete the entire outlined "Keep original" button at the bottom.
- KEEP the back chevron, title "Edit script line", BOTH original and suggestion cards and their labels, the complete text of both cards, "Try another" with its icon, and the black "Apply suggestion" button.
- The curved yellow arrow beside the original card is handwritten feedback; remove that arrow, not the Original or Suggestion card.
- Rebalance vertical spacing after deletion, with the sole Apply suggestion action near the bottom.

PHONE 4, RESUME FILMING:
- Delete the entire "Your place is saved" badge, including its check icon and gray pill.
- In the bottom-left action delete ONLY the word "shot", so "Previous shot" becomes "Previous".
- In the bottom-right action delete ONLY the words "for now", so "Pause for now" becomes "Pause".
- Keep the progress segments, Shot 2 of 3, Get your gear ready, illustration, camera-app instruction, Say this line, captured count, and Mark captured button.
- Close the badge gap naturally.

Return a clean board with NO yellow circles, yellow arrows, handwritten "Remove", annotations, new explanatory callouts, new UI text, or replacement controls. Keep all other content unchanged. Match the original's aspect ratio and high clarity, ideally preserve its 1672 by 941 pixel layout.
```

## Caption preservation pass

```text
undefined
```
