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
5. Tester access uses approved-email OTP. Do not pass pairing codes around.
   Owner sessions can use the Testers tab in Manager Control to invite, resend,
   or revoke tester access. Editors can use Manager tools but cannot manage
   testers.
6. Open Daily to generate content one day at a time when the week is not
   published:
   - Keep all target dates inside one Monday-Sunday range. Check the range in
     Weekly first if needed; a date in another week belongs to a different
     weekly plan draft container.
   - Pick the target date.
   - Write a non-empty day brief for that date, including one-off asks such as
     brand deliverables.
   - Tap Generate for that date.
   - Review the returned storyboard and caption. Generated cards accumulate in
     the current weekly plan draft container as you add more days.
   - Repeat for the other dates in that same range until the week has seven
     reviewed cards.
7. Open Weekly to review, edit, regenerate, and publish:
   - Check that the week range is correct.
   - Use Edit brief to update the Weekly Brief and setup context.
   - Inspect generated cards for each day. Expand Full generated card to check
     the script, no-voiceover version, on-screen text, CTA, hashtags, cover,
     post instructions, audio notes, assumptions, and source.
   - Edit any card title, why-today note, shootability, shoot time, scene list,
     caption, backup story, or backup caption-only text that needs correction.
   - Regenerate an individual day when only one card is weak. The app updates
     that day only and keeps the rest of the reviewed draft intact.
   - Publish only after all seven cards are reviewed.
   - Verify that Today shows the generated card after publish.
8. Open References.
9. Use Reference Import:
   - Paste Instagram account, reel, or audio URLs, or upload a CSV.
   - Preview the import.
   - Confirm the import.
   - Review any Needs your call items.
10. Weekly Sunday setup: capture location, workout or race schedule, family,
    travel or school moments, brand or collaboration obligations, trend and
    audio options worth considering, and no-go topics.
11. Daily check: verify Creator has a useful Today card, and intervene only if
    the card is wrong or no card appears.

### Manager troubleshooting

- Sign-in says email is not approved: invite or reactivate that email through
  the backend/admin tester runbook.
- No email code: resend from the Testers tab or backend/admin tester flow. Also
  check spam and the email address spelling.
- App says `Fixtures`: the build is missing live Supabase config or the live
  session could not be restored.
- Release archive fails with a Supabase bootstrap error: this is intentional.
  Populate `CreatorContentOS/Config/Runtime.xcconfig` or pass the live values to
  `xcodebuild` before uploading the next TestFlight build.
- No Today card: publish the current week, then refresh the app. Confirm the
  daily card date matches today.
- Daily Generate button disabled: confirm the device role is owner or editor,
  the day brief is non-empty, and generation is not already running for that
  date. If the backend rejects a date in a published week, choose a date in an
  open future week.
- Weekly Brief edit failed: confirm the device role is owner or editor and the
  week has a matching weekly setup row in Supabase.
- Regenerate day disabled: confirm a draft weekly plan exists, the week is not
  published, and the device role is owner or editor.
- Missing AI provider key: set `DEEPSEEK_API_KEY` as the primary Supabase Edge
  Function secret, with `OPENAI_API_KEY` optional as fallback. The app must not
  contain these keys.
- Generation failed: check the stable error shown on Daily or Weekly, then inspect
  the `generate-week` Edge Function logs for `generate_day` or `regenerate_day`.
- Draft exists but is not published: open Weekly, finish reviewing all seven
  cards, then publish.
- Published week is locked: plan or generate days for a future week. Do not
  overwrite a published week.
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
