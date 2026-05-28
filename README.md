# FocusBell 🔔

A minimal mobile app that keeps your priority project front of mind.  
Sends **toast alerts** and **push notifications** — even when the screen is off.

---

## Features

- **Active project card** — one glance tells you what to work on
- **Priority levels** — Low 🟢 / Medium 🟡 / High 🟠 / Critical 🔴
- **Quick priority switcher** — tap inline on the home screen
- **Projects bottom sheet** — add, switch, or swipe-to-delete projects
- **Settings bottom sheet** — reminder interval + quiet hours
- **Screen-off notifications** — scheduled exact alarms (Android) & local notifications (iOS)
- **Toast feedback** — every action confirms instantly

---

## Project Structure

```
lib/
├── main.dart                         # Entry point
├── models/
│   ├── project.dart                  # Project + Priority enum
│   └── settings.dart                 # AppSettings + ReminderInterval enum
├── services/
│   ├── app_controller.dart           # Central ChangeNotifier state
│   ├── notification_service.dart     # flutter_local_notifications wrapper
│   └── storage_service.dart          # shared_preferences persistence
├── screens/
│   └── home_screen.dart              # Main screen
└── widgets/
    ├── projects_bottom_sheet.dart    # Projects sheet (page 1)
    └── settings_bottom_sheet.dart   # Settings sheet (page 2)
```

---

## Setup

### 1. Install dependencies

```bash
flutter pub get
```

### 2. Android — update `AndroidManifest.xml`

Replace `android/app/src/main/AndroidManifest.xml` with the contents of
`android_AndroidManifest.xml` (or merge the permissions and receivers into
your existing manifest).

Key additions:
- `POST_NOTIFICATIONS` — Android 13+ notification permission
- `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` — screen-off delivery
- `RECEIVE_BOOT_COMPLETED` — reschedule after reboot
- `WAKE_LOCK` — wake CPU to deliver notification
- Two `ScheduledNotificationReceiver` entries from `flutter_local_notifications`

### 3. iOS — update `Info.plist`

Add the keys from `ios_Info_additions.plist` inside the `<dict>` block of
`ios/Runner/Info.plist`.

### 4. Run

```bash
flutter run
```

---

## How notifications work (screen-off delivery)

FocusBell uses **`flutter_local_notifications`** with
`AndroidScheduleMode.exactAllowWhileIdle` on Android.

This tells the OS to wake the device and fire the notification at the exact
scheduled time, bypassing Doze mode — the same mechanism used by alarm clocks.

Up to **60 future notification slots** are pre-scheduled whenever you:
- Set a new active project
- Change the reminder interval in settings

Quiet hours are respected: any slot that falls in your silent window is skipped
and the next available slot outside it is used instead.

On **iOS**, `zonedSchedule` with `presentAlert: true` delivers notifications
even with the screen off; iOS handles wake and delivery natively.

---

## Notification permission flow

On first launch the app requests notification + exact alarm permissions.
If denied, the user can re-enable via the toggle in Settings.

---

## Extending

| What | Where |
|------|-------|
| Add a new priority level | `lib/models/project.dart` → `Priority` enum |
| Add a new interval option | `lib/models/settings.dart` → `ReminderInterval` enum |
| Change notification copy | `lib/services/notification_service.dart` → `scheduleReminders()` |
| Persist to a real DB | Replace `StorageService` with Hive/Drift/SQLite |
| Firebase push (server-side) | Add `firebase_messaging` + FCM backend |