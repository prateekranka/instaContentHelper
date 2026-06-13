# Local Notifications - Creator Content OS V2

Section 6 schedules a gentle local notification from Creator's synced Today card.

## Behavior

- Creator's phone schedules the notification locally.
- The backend does not send push notifications in V1.
- The scheduler uses the current `DailyCard` title whenever possible.
- The primary reminder is set for 8:00 AM local calendar time.
- A completed card cancels the pending Today reminder.

Default copy:

- Title: `Today's reel is ready`
- Body: the synced Daily Card title, for example `Race week has entered the house`

The live scheduler requests provisional alert authorization and uses passive interruption level so the reminder stays gentle.

## App Boundary

`TodayNotificationScheduling` lives in the data layer:

- `LocalTodayNotificationScheduler`: real `UNUserNotificationCenter` implementation.
- `NoopTodayNotificationScheduler`: preview/default no-op.
- Test schedulers can capture scheduled requests without touching iOS notification state.

`AppRuntime` injects `LocalTodayNotificationScheduler` into the running app.

`AppServices` schedules after:

- loading a cached Today card on launch,
- refreshing Today from repositories,
- publishing the current week.

`AppServices` cancels after:

- Creator records any final decision for Today.

## V1 Scope

Included:

- One local 8:00 AM reminder for the current synced Today card.
- Idempotent replacement using one pending notification identifier per workspace and creator.
- Cancel on decision.

Deferred:

- Optional 5:00 PM backup reminder.
- Multi-day week notification scheduling.
- Server push notifications.
- Notification settings UI.
