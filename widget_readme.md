# FocusBell — Android Home Screen Widget

A complete reference for the Android home screen (and lock screen) widget feature.
Written for future maintainers and developers inheriting this codebase.

---

## Table of Contents

1. [What the Widget Does](#1-what-the-widget-does)
2. [How It Works — Architecture Overview](#2-how-it-works--architecture-overview)
3. [Dependencies](#3-dependencies)
4. [File Map — Every File That Matters](#4-file-map--every-file-that-matters)
5. [Android Native Files](#5-android-native-files)
6. [Flutter / Dart Files](#6-flutter--dart-files)
7. [Data Flow — How State Reaches the Widget](#7-data-flow--how-state-reaches-the-widget)
8. [What Gets Displayed](#8-what-gets-displayed)
9. [The One Critical Gotcha — Package Name](#9-the-one-critical-gotcha--package-name)
10. [Adding the Widget to Your Phone](#10-adding-the-widget-to-your-phone)
11. [Debugging the Widget](#11-debugging-the-widget)
12. [How to Make Common Changes](#12-how-to-make-common-changes)
13. [iOS Notes](#13-ios-notes)
14. [Known Limitations](#14-known-limitations)

---

## 1. What the Widget Does

The widget displays a compact summary of the active FocusBell project on the Android
home screen and lock screen (Android 13+), including:

- Priority emoji dot (🔴 🟠 🟡 🟢)
- Active project name
- Priority label (e.g. CRITICAL)
- Focus session timer (remaining time, or "No active session")
- Task summary (e.g. "3 tasks · 1 overdue")

Tapping the widget opens the app directly.

The widget updates:
- Immediately when the active project changes
- Immediately when a focus session starts, pauses, stops, or completes
- Every 30 seconds while a session is actively running (throttled to save battery)
- On cold app launch (boot)

---

## 2. How It Works — Architecture Overview

Android home screen widgets **cannot run Flutter/Dart code**. They are purely native
Android components. The bridge between Flutter and the widget is the `home_widget`
package, which works like this:

```
Flutter (Dart)                          Android (Kotlin)
──────────────────────────────────      ────────────────────────────────────
WidgetService.push()
  │
  ├─ HomeWidget.saveWidgetData()  ──►  SharedPreferences (native key-value store)
  │   writes key-value pairs           shared between Flutter and native code
  │
  └─ HomeWidget.updateWidget()    ──►  sends ACTION_APPWIDGET_UPDATE broadcast
                                        │
                                        ▼
                                   FocusWidgetProvider.onUpdate()
                                     reads SharedPreferences
                                     builds RemoteViews from XML layout
                                     calls appWidgetManager.updateAppWidget()
                                        │
                                        ▼
                                   Widget redraws on home screen
```

**Key insight:** Flutter never draws the widget. Flutter only writes data and sends a
signal. The native Kotlin class reads that data and renders the widget using Android's
`RemoteViews` system (which uses XML layouts, not Flutter widgets).

---

## 3. Dependencies

### pubspec.yaml

```yaml
dependencies:
  home_widget: ^0.6.0
```

Run `flutter pub get` after adding this.

### android/app/build.gradle

No changes needed — `home_widget` injects its own native dependencies automatically
via Gradle.

---

## 4. File Map — Every File That Matters

```
focusbell/
├── lib/
│   └── services/
│       ├── widget_service.dart          ← Flutter bridge (THE main file to edit)
│       ├── app_controller.dart          ← calls _pushWidget() on every state change
│       └── focus_timer_service.dart     ← calls WidgetService on timer events
│
└── android/
    └── app/
        └── src/
            └── main/
                ├── AndroidManifest.xml              ← registers the widget receiver
                ├── kotlin/
                │   └── com/example/focusbell/
                │       ├── MainActivity.kt           ← unchanged
                │       └── FocusWidgetProvider.kt    ← native widget renderer
                └── res/
                    ├── layout/
                    │   └── focus_widget_small.xml    ← widget UI layout
                    ├── drawable/
                    │   └── widget_background.xml     ← rounded dark background
                    ├── xml/
                    │   └── focus_widget_info.xml     ← widget metadata (size, etc.)
                    └── values/
                        └── strings.xml               ← contains widget_description
```

---

## 5. Android Native Files

### 5a. `FocusWidgetProvider.kt`

**Location:** `android/app/src/main/kotlin/com/example/focusbell/FocusWidgetProvider.kt`

**What it does:** The native Android `AppWidgetProvider`. Called by Android every time
the widget needs to redraw. Reads key-value data that Flutter wrote into SharedPreferences
and sets text on the `RemoteViews` layout.

**Critical rule:** The `package` declaration at the top MUST match the folder it lives in
AND the `namespace` in `build.gradle`. Currently:

```kotlin
package com.example.focusbell
```

**When to edit this file:**
- If you add a new data key and want to display it in the widget
- If you want to add a second tap target (e.g. tap the timer → open focus sheet)
- If you rename the package

**Key section — reading SharedPreferences and setting text:**

```kotlin
val prefs: SharedPreferences = HomeWidgetPlugin.getData(context)
val projectName = prefs.getString("active_project_name", "No active project") ?: "No active project"
// ... more keys ...

val views = RemoteViews(context.packageName, R.layout.focus_widget_small)
views.setTextViewText(R.id.widget_project_name, projectName)
```

The string keys here (e.g. `"active_project_name"`) MUST exactly match the keys used in
`WidgetService._writeData()` on the Flutter side. If they differ, the widget shows
default/stale values.

---

### 5b. `focus_widget_small.xml`

**Location:** `android/app/src/main/res/layout/focus_widget_small.xml`

**What it does:** The XML layout that defines what the widget looks like. Android's
`RemoteViews` system renders this layout — it does NOT support all Android View types.
Only a limited subset works in widgets (TextView, ImageView, LinearLayout, FrameLayout,
ProgressBar, etc.).

**When to edit this file:**
- To change widget visual design (colors, sizes, spacing)
- To add or remove displayed fields
- To change the widget layout (horizontal vs vertical, etc.)

**Important:** Every `android:id` here must match the `R.id.*` references in
`FocusWidgetProvider.kt`. If you add a new TextView, add its ID to both files.

**RemoteViews limitation:** You cannot use `ConstraintLayout`, custom views, or any
view that requires a context to initialize. Stick to `LinearLayout`, `TextView`,
`ImageView`, `FrameLayout`.

---

### 5c. `widget_background.xml`

**Location:** `android/app/src/main/res/drawable/widget_background.xml`

**What it does:** A simple shape drawable used as the widget's rounded dark background.
Currently: `#CC111111` (80% opacity black) with 16dp corner radius.

**When to edit:** To change the widget background color, opacity, or corner radius.

```xml
<solid android:color="#CC111111" />   <!-- change color here -->
<corners android:radius="16dp" />    <!-- change rounding here -->
```

---

### 5d. `focus_widget_info.xml`

**Location:** `android/app/src/main/res/xml/focus_widget_info.xml`

**What it does:** Metadata that tells Android how to present the widget in the widget
picker and what its minimum/default size is.

**Key attributes:**

```xml
android:minWidth="180dp"          <!-- minimum width on home screen -->
android:minHeight="60dp"          <!-- minimum height -->
android:targetCellWidth="3"       <!-- default: 3 grid cells wide -->
android:targetCellHeight="1"      <!-- default: 1 grid cell tall -->
android:updatePeriodMillis="1800000"  <!-- fallback refresh: 30 min (Android minimum) -->
android:widgetCategory="home_screen|keyguard"  <!-- enables lock screen on Android 13+ -->
```

**When to edit:** To change default widget size, or to add a preview image.

**Note on `updatePeriodMillis`:** Android enforces a minimum of 30 minutes regardless
of what you set. This is only a fallback — the app pushes updates imperatively via
`HomeWidget.updateWidget()` which fires instantly.

---

### 5e. `AndroidManifest.xml` — Widget Receiver Block

**Location:** `android/app/src/main/AndroidManifest.xml`

The following block registers `FocusWidgetProvider` with Android. It must be inside
the `<application>` tag:

```xml
<receiver
    android:name=".FocusWidgetProvider"
    android:exported="true">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>
    </intent-filter>
    <meta-data
        android:name="android.appwidget.provider"
        android:resource="@xml/focus_widget_info"/>
</receiver>
```

**`android:name=".FocusWidgetProvider"`** — the leading dot means "relative to the
app's package." Android expands this to `com.example.focusbell.FocusWidgetProvider`.

**When to edit:** Almost never. Only if you rename the Kotlin class or add a second
widget provider.

---

## 6. Flutter / Dart Files

### 6a. `widget_service.dart`

**Location:** `lib/services/widget_service.dart`

**This is the main file to edit for widget changes.** It is the complete Flutter-side
bridge to the native widget.

**Key constants — check these first when debugging:**

```dart
static const _kProviderName = 'FocusWidgetProvider';
static const _kQualifiedProvider = 'com.example.focusbell.FocusWidgetProvider';
//                                  ^^^^^^^^^^^^^^^^^^^^^ MUST match build.gradle namespace
```

If `_kQualifiedProvider` is wrong, `HomeWidget.updateWidget()` will silently fail and
the widget will never update. This is the #1 bug source.

**To find your correct package name:**
```bash
grep "namespace" android/app/build.gradle
# or
grep "applicationId" android/app/build.gradle
```

**How data keys work:**

`_writeData()` writes all key-value pairs to SharedPreferences. Each call to
`HomeWidget.saveWidgetData<Type>(key, value)` writes one key:

```dart
await HomeWidget.saveWidgetData<String>('active_project_name', p?.name ?? 'No active project');
await HomeWidget.saveWidgetData<String>('active_priority_dot', _priorityDot(p));
await HomeWidget.saveWidgetData<String>('active_priority_label', ...);
await HomeWidget.saveWidgetData<String>('session_timer_text', _timerText(timer, p));
await HomeWidget.saveWidgetData<int>   ('session_running', ...);
await HomeWidget.saveWidgetData<String>('task_summary', _taskSummary(p));
```

The string key name (e.g. `'active_project_name'`) MUST match exactly in both:
- `widget_service.dart` (writer)
- `FocusWidgetProvider.kt` (reader)

**Timer throttle:** While a session is running, `_pushWidgetThrottled()` is called every
second from the timer tick, but is gated to only actually push every 30 seconds:

```dart
static const _kWidgetThrottle = Duration(seconds: 30);
```

Change this constant to adjust the live-session update frequency.

**`pushSessionEnded()`:** A special method that bypasses the throttle and pushes
immediately. Called from `FocusTimerService` when a session stops, resets, or completes.

---

### 6b. `app_controller.dart`

**Location:** `lib/services/app_controller.dart`

**What was added:** A private `_pushWidget()` helper and calls to it after every
`notifyListeners()` in mutating methods.

```dart
void _pushWidget() {
  WidgetService.instance.push(activeProject: activeProject);
}
```

**Where `_pushWidget()` is called** (and why):

| Method | Called? | Reason |
|--------|---------|--------|
| `boot()` | ✅ | Cold start — sync widget to current state |
| `setActive()` | ✅ | Active project changed |
| `removeProject()` | ✅ | Active project may have changed |
| `archiveProject()` | ✅ | Active project cleared |
| `unarchiveProject()` | ✅ | Project list changed |
| `updateProject()` | ✅ | Name/priority shown in widget may have changed |
| `updateProjectPriority()` | ✅ | Priority dot shown in widget |
| `addTask()` | ✅ (active only) | Task count shown in widget |
| `updateTask()` | ✅ (active only) | Task status/overdue affects summary |
| `removeTask()` | ✅ (active only) | Task count changed |
| `addProject()` | ❌ | Doesn't change active project |
| `reorderProjects()` | ❌ | Doesn't change active project |
| `updateProjectNote()` | ❌ | Notes not shown in widget |

---

### 6c. `focus_timer_service.dart`

**Location:** `lib/services/focus_timer_service.dart`

**What was added:** Three things:

```dart
// 1. Throttle guard field
DateTime? _lastWidgetPush;

// 2. Throttled push — called every tick inside _tick()
void _pushWidgetThrottled({bool force = false}) { ... }

// 3. Calls to WidgetService at session lifecycle moments:
//    - start()              → _lastWidgetPush = null (so first tick pushes immediately)
//    - pause()              → _pushWidgetThrottled(force: true)
//    - stop()               → WidgetService.instance.pushSessionEnded(...)
//    - reset()              → WidgetService.instance.pushSessionEnded(...)
//    - skip()               → WidgetService.instance.pushSessionEnded(...)
//    - _onSegmentComplete() → _pushWidgetThrottled(force: true) at 00:00 snap
//                           → pushSessionEnded() after advancing to next segment
//    - init() bg restore    → _pushWidgetThrottled(force: true) after bg completion
```

---

## 7. Data Flow — How State Reaches the Widget

### Project switch (e.g. user double-taps a project in the list)

```
User double-taps project
  → AppController.setActive()
    → _projects updated in memory
    → notifyListeners()              [UI rebuilds]
    → _pushWidget()                  [widget push, fire-and-forget]
      → WidgetService.push(activeProject: ...)
        → HomeWidget.saveWidgetData('active_project_name', ...)
        → HomeWidget.saveWidgetData('active_priority_dot', ...)
        → ... (all keys)
        → HomeWidget.updateWidget(qualifiedAndroidName: ...)
          → Android broadcasts ACTION_APPWIDGET_UPDATE
            → FocusWidgetProvider.onUpdate()
              → reads SharedPreferences
              → RemoteViews.setTextViewText(...)
              → appWidgetManager.updateAppWidget()
                → Widget redraws on screen ✓
    → _storage.setActiveProject(id)  [persisted to SQLite]
```

### Session tick (every second while running)

```
Timer.periodic 1s
  → FocusTimerService._tick()
    → _state.remainingSeconds -= 1
    → notifyListeners()              [UI timer redraws]
    → _pushWidgetThrottled()
      → checks: has 30s passed since _lastWidgetPush?
        → NO: returns immediately (most ticks)
        → YES: WidgetService.push(fromTimer: true)
                 → writes session_timer_text key
                 → updateWidget() → widget redraws ✓
```

### Session ends (stop/complete/reset)

```
stop() / complete() / reset()
  → _lastWidgetPush = null
  → WidgetService.instance.pushSessionEnded(activeProject: ...)
    → _lastTimerPush = null (in WidgetService — resets throttle)
    → push(activeProject: ...)
      → session_timer_text = '⏱ No active session'
      → session_running = 0
      → updateWidget() → widget shows idle state ✓
```

---

## 8. What Gets Displayed

The widget reads these SharedPreferences keys. All are strings unless noted:

| Key | Type | Example value | Default |
|-----|------|---------------|---------|
| `active_project_name` | String | `"BriefBrew"` | `"No active project"` |
| `active_priority_dot` | String | `"🔴"` | `"⚪"` |
| `active_priority_label` | String | `"CRITICAL"` | `""` |
| `session_timer_text` | String | `"⏱ 18:42"` or `"⏸ 12:34"` | `"⏱ No active session"` |
| `session_running` | Int | `1` = running, `0` = not | `0` |
| `task_summary` | String | `"3 tasks · 1 overdue"` | `""` |

**Timer text format:**
- `⏱ MM:SS` — session running
- `⏸ MM:SS` — session paused
- `⏱ Hh MM:SS` — running, over 1 hour
- `⏱ No active session` — idle/finished

---

## 9. The One Critical Gotcha — Package Name

`_kQualifiedProvider` in `widget_service.dart` must be the fully-qualified class name:

```
{namespace from build.gradle}.{Kotlin class name}
```

**To verify your namespace:**

```bash
grep "namespace" android/app/build.gradle
```

**Then set it in `widget_service.dart`:**

```dart
static const _kQualifiedProvider = 'com.example.focusbell.FocusWidgetProvider';
//                                   ^^^^^^^^^^^^^^^^^^^^ must match namespace
```

If this is wrong: `HomeWidget.updateWidget()` succeeds (no error thrown) but Android
receives the broadcast for a non-existent provider and silently discards it. The widget
appears on the home screen but never updates. This is the hardest bug to diagnose.

**Also check:** The `package` line at the top of `FocusWidgetProvider.kt` must match:

```kotlin
package com.example.focusbell   // must match build.gradle namespace
```

And the folder path must match:
```
android/app/src/main/kotlin/com/example/focusbell/FocusWidgetProvider.kt
```

All three must be identical. A mismatch in any one of them causes either a build error
(Kotlin) or a silent runtime failure (qualified provider name).

---

## 10. Adding the Widget to Your Phone

1. **Long press** an empty spot on the home screen
2. Tap **"Widgets"**
3. Scroll to find **"FocusBell"**
4. **Long press** the widget thumbnail and drag it to the desired position
5. Release — the widget appears and starts showing live data

**Resize:** Long press the placed widget → drag the blue handles that appear around it.

**Lock screen (Android 13+):**
Long press lock screen → **Customize** → **Lock screen** → **Add widget** → FocusBell

**Widget not appearing in the list?**
- Launch the app at least once after install (so `boot()` runs and pushes initial data)
- Some launchers (e.g. MIUI/HiOS on Infinix) have the widget picker in a different
  location — swipe right past the last home screen page, or check Settings → Home screen

---

## 11. Debugging the Widget

### Step 1 — Confirm push() is firing

Add temporary debug prints to `widget_service.dart`:

```dart
Future<void> push({Project? activeProject, bool fromTimer = false}) async {
  debugPrint('[Widget] push() — project: ${activeProject?.name}');
  // ...
  try {
    await _writeData(activeProject);
    debugPrint('[Widget] _writeData done');
    await HomeWidget.updateWidget(...);
    debugPrint('[Widget] updateWidget done');
  } catch (e) {
    debugPrint('[Widget] ERROR: $e');
  }
}
```

Run `flutter run` and switch active project. Check the VS Code Debug Console.

### Diagnostic table

| Logs show | Diagnosis | Fix |
|-----------|-----------|-----|
| Nothing at all | `_pushWidget()` not wired in `AppController` | Check that `_pushWidget()` is called after `notifyListeners()` in `setActive()` |
| `push() called` but no `updateWidget done` | Exception thrown, swallowed | The `catch` block should print it — check for `ERROR:` line |
| All three lines, widget still stale | `_kQualifiedProvider` is wrong | Re-check package name — see §9 |
| All three lines, widget updates sometimes | Throttle too aggressive | Lower `_kWidgetThrottle` in `widget_service.dart` |

### Step 2 — Verify the package name

```bash
grep "namespace" android/app/build.gradle
# Should output something like: namespace 'com.example.focusbell'
```

Compare to `_kQualifiedProvider` in `widget_service.dart`. They must match.

### Step 3 — Check the manifest receiver

Open `android/app/src/main/AndroidManifest.xml` and confirm the `<receiver>` block
exists inside `<application>`. If it's missing, the widget will never receive update
broadcasts.

### Step 4 — Clean build

If behavior is unexpected after making changes:

```bash
flutter clean
flutter pub get
flutter run
```

Android caches a lot. A clean build resolves many widget-related anomalies.

---

## 12. How to Make Common Changes

### Add a new data field to the widget

**Step 1 — Add the key in `widget_service.dart` → `_writeData()`:**
```dart
await HomeWidget.saveWidgetData<String>('my_new_key', myValue);
```

**Step 2 — Add a TextView in `focus_widget_small.xml`:**
```xml
<TextView
    android:id="@+id/widget_my_field"
    android:layout_width="wrap_content"
    android:layout_height="wrap_content"
    android:textColor="#99FFFFFF"
    android:textSize="11sp" />
```

**Step 3 — Read and display it in `FocusWidgetProvider.kt`:**
```kotlin
val myValue = prefs.getString("my_new_key", "") ?: ""
views.setTextViewText(R.id.widget_my_field, myValue)
```

### Change the widget's visual style

Edit `focus_widget_small.xml` (colors, sizes, layout) and/or `widget_background.xml`
(background shape). Changes take effect after `flutter run` — you may need to remove and
re-add the widget from the home screen to see the new size/shape.

### Change the update frequency during a live session

In `widget_service.dart`:
```dart
static const _kWidgetThrottle = Duration(seconds: 30); // change this
```

### Change the default widget size on home screen

In `focus_widget_info.xml`:
```xml
android:targetCellWidth="3"   <!-- grid columns -->
android:targetCellHeight="1"  <!-- grid rows -->
android:minWidth="180dp"
android:minHeight="60dp"
```

### Rename the app package

If you ever change the app's package (e.g. from `com.example.focusbell` to
`com.focusbell.app`), you must update ALL of these:

1. `build.gradle` → `namespace` and `applicationId`
2. Kotlin folder path: `kotlin/com/example/focusbell/` → `kotlin/com/focusbell/app/`
3. `package` line at top of every `.kt` file in that folder
4. `widget_service.dart` → `_kQualifiedProvider`

Then run `flutter clean && flutter run`.

---

## 13. iOS Notes

iOS widgets use Apple's **WidgetKit** framework (Swift, not Kotlin). The `home_widget`
package supports iOS via a shared **App Group** container.

The iOS app group ID is already defined in `widget_service.dart`:
```dart
static const _kAppGroupId = 'group.com.example.focusbell';
```

And `init()` already registers it:
```dart
await HomeWidget.setAppGroupId(_kAppGroupId);
```

To complete iOS widget support you would need to:
1. Add a **Widget Extension** target in Xcode
2. Enable the App Group capability on both the main app target and the extension target
3. Write a Swift `Widget` struct that reads from the shared App Group container
   using the same key names defined in `widget_service.dart`

The Flutter side is already fully prepared — no Dart changes needed for iOS.

---

## 14. Known Limitations

**`updatePeriodMillis` minimum is 30 minutes.** Android enforces this system-wide.
The widget only reliably updates in real-time because the app pushes imperatively via
`HomeWidget.updateWidget()`. If the app is killed and the user hasn't opened it in 30+
minutes, the widget may show stale data until the next app launch or system refresh.

**RemoteViews is not Flutter.** The widget UI is defined in XML and rendered natively.
You cannot use Flutter widgets, custom fonts, custom drawables, animations, or any
feature that requires a Flutter context. Widget UI changes require editing XML files and
rebuilding — hot reload does not apply.

**Widget data survives app uninstall on some devices.** SharedPreferences written by
`home_widget` may persist on some Android versions. This is a system behavior, not a bug.

**Lock screen widgets require Android 13+.** On older Android versions,
`widgetCategory="keyguard"` is silently ignored. The home screen widget still works.

**Emoji rendering in widgets varies by device.** Priority dot emojis (🔴 🟠 🟡 🟢)
render correctly on most modern Android devices but may appear as boxes on very old
system fonts. This is an Android limitation, not a code issue.