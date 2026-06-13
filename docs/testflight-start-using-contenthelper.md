# Start Using ContentHelper from TestFlight

For live backend deploy, smoke, and the final live-configured TestFlight
rebuild, use `docs/live-supabase-testflight-runbook.md`.

## A. Manager setup and use

1. Install ContentHelper from TestFlight.
2. Open the app once after install.
3. Sign in with an approved tester email. Supabase sends a one-time email code;
   enter that code in the app. A first-time tester must be approved by an owner
   from Manager Control before sign-in works.
4. From Profile, switch to Manager Control.
5. Open Testers when you need to add more testers. Owners can invite an email,
   resend a code, or revoke a tester. Testers sign in with email OTP; do not
   pass pairing codes around.
6. Open Weekly.
7. Confirm this week's plan:
   - Check that the week range is correct.
   - Confirm the seven day cards are useful for Creator.
   - Soft-lock or publish the week.
   - Verify that Today has a current card after publish.
8. Generate a weekly AI draft when the week is not published:
   - Confirm the weekly setup context looks current.
   - Tap Generate week.
   - Review the generated strategy, warnings, and assumptions.
   - Inspect all seven generated cards. Expand Full generated card to check the
     script, no-voiceover version, on-screen text, CTA, hashtags, cover, post
     instructions, audio notes, assumptions, and source.
   - Edit any card title, why-today note, shootability, shoot time, scene list,
     caption, backup story, or backup caption-only text that needs correction.
   - Regenerate an individual day when only one card is weak. The app updates
     that day only and keeps the rest of the reviewed draft intact.
   - Publish only after review.
   - Verify that Today shows the generated card after publish.
9. Open Intelligence.
10. Use Reference Import:
   - Paste Instagram account, reel, or audio URLs, or upload a CSV.
   - Preview the import.
   - Confirm the import.
   - Review any Needs your call items.
11. Weekly Sunday setup: capture location, workout or race schedule, family,
    travel or school moments, brand or collaboration obligations, trend and
    audio options worth considering, and no-go topics.
12. Daily check: verify Creator has a useful Today card, and intervene only if the
    card is wrong or no card appears.

### Manager troubleshooting

- Sign-in says email is not approved: open Manager Control, Testers, then invite
  or reactivate that email.
- No email code: resend from the app or from Manager Control, Testers. Also
  check spam and the email address spelling.
- App says `Fixtures`: the build is missing live Supabase config or the live
  session could not be restored.
- Release archive fails with a Supabase bootstrap error: this is intentional.
  Populate `CreatorContentOS/Config/Runtime.xcconfig` or pass the live values to
  `xcodebuild` before uploading the next TestFlight build.
- No Today card: publish the current week, then refresh the app. Confirm the
  daily card date matches today.
- Generate button disabled: confirm the device role is owner or editor,
  generation is not already running, and the week is not soft locked or
  published.
- Regenerate day disabled: confirm a draft weekly plan exists, the week is not
  published, and the device role is owner or editor.
- Missing AI provider key: set `DEEPSEEK_API_KEY` as the primary Supabase Edge
  Function secret, with `OPENAI_API_KEY` optional as fallback. The app must not
  contain these keys.
- Generation failed: check the stable error shown in Weekly, then inspect the
  `generate-week` Edge Function logs.
- Draft exists but is not published: open Weekly, review the generated draft,
  then publish.
- Published week is locked: create or generate a future week. Do not overwrite a
  published week.
- Ideas are too generic: add better Reference Import sources, update weekly
  setup details, and add no-go topics before regenerating a draft.
- Import disabled: confirm the app is live and the device role is owner or
  editor.
- Live sync error: check Supabase availability, device pairing, and whether the
  device token was revoked.
- Notification missing: open the app once after the Today card syncs.
  Notifications schedule from the synced Today card and may require iOS
  notification permission.

## B. Creator use

1. Install ContentHelper from TestFlight.
2. Open the app once a day.
3. Read Today's Reel.
4. Tap See what to shoot for the shot list, caption, and audio package.
5. Decide:
   - Can shoot today.
   - Not today.
6. If Not today:
   - Use the backup story.
   - Use the caption-only post.
   - Save the card for tomorrow.
7. Completed day means you made a decision. It does not mean you had to post.
8. You do not need to research trends, type prompts, or manage a calendar.
9. If something feels wrong, tell Manager in one short note. Edit only if you
   want to.
10. Keep Instagram recording and editing outside the app.
