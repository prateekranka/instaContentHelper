# Start Using ContentHelper from TestFlight

For live backend deploy, smoke, and the final live-configured TestFlight rebuild, use `docs/live-supabase-testflight-runbook.md`.

## A. Prateek setup and use

1. Install ContentHelper from TestFlight.
2. Open the app once after install.
3. Confirm the app is paired to the live workspace. If the Profile screen says `Fixtures`, open Profile, find Pair device, enter the invite code in Invite code, then tap the link button. A first-time device can pair only when the TestFlight build has the live Supabase URL and publishable key configured.
4. From Profile, switch to Prateek Control.
5. Open Weekly.
6. Confirm this week's plan:
   - Check that the week range is correct.
   - Confirm the seven day cards are useful for Mamta.
   - Soft-lock or publish the week.
   - Verify that Today has a current card after publish.
7. Open Intelligence.
8. Use Reference Import:
   - Paste Instagram account, reel, or audio URLs, or upload a CSV.
   - Preview the import.
   - Confirm the import.
   - Review any Needs your call items.
9. Weekly Sunday setup:
   - Location for the week.
   - Workout or race schedule.
   - Family, travel, or school moments.
   - Brand or collaboration obligations.
   - Trend and audio options worth considering.
   - No-go topics.
10. Daily check:
   - Verify Mamta has a useful Today card.
   - Intervene only if the card is wrong or no card appears.

### Prateek troubleshooting

- App says `Fixtures`: the device is not paired to live runtime. Pair the device or reinstall and use a fresh live invite code.
- Pairing says Supabase bootstrap is missing: make a new TestFlight build with `MCO_SUPABASE_URL` and `MCO_SUPABASE_PUBLISHABLE_KEY` populated, then pair with a fresh invite code.
- Release archive fails with a Supabase bootstrap error: this is intentional. Populate `MamtaContentOS/Config/Runtime.xcconfig` or pass the live values to `xcodebuild` before uploading the next TestFlight build.
- No Today card: publish the current week, then refresh the app. Confirm the daily card date matches today.
- Import disabled: confirm the app is live and the device role is owner or editor.
- Live sync error: check Supabase availability, device pairing, and whether the device token was revoked.
- Notification missing: open the app once after the Today card syncs. Notifications schedule from the synced Today card and may require iOS notification permission.

## B. Mamta use

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
9. If something feels wrong, tell Prateek in one short note. Edit only if you want to.
10. Keep Instagram recording and editing outside the app.
