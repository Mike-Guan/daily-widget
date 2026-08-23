# Daily Widget iOS

This is the native SwiftUI iPhone/iPad companion and WidgetKit home-screen widget. It shares the task-record JSON contract with the Electron app:

```json
{
  "schemaVersion": 1,
  "id": "uuid",
  "date": "2026-08-20",
  "start": 540,
  "end": 600,
  "title": "Morning walk",
  "done": false,
  "focus": true,
  "category": "health",
  "recurrence": "none",
  "completedDates": [],
  "createdAt": "2026-08-20T00:00:00Z",
  "updatedAt": "2026-08-20T00:00:00Z",
  "updatedBy": "iphone-device-id",
  "deletedAt": null
}
```

## Open and run

1. Finish installing Xcode, then open `DailyWidget.xcodeproj`.
2. Select the `DailyWidget` target, choose your Personal Team, and let Xcode register the `com.guanshiyang.dailywidget` bundle ID. Do the same for `com.guanshiyang.dailywidget.widget`.
3. In both targets, confirm the App Group `group.com.guanshiyang.dailywidget` exists in **Signing & Capabilities**. The entitlements are already checked in.
4. Choose an iPhone simulator or your device and run.
5. In app Settings, choose the same `Daily Widget` shared folder used on desktop from the Files picker (normally in iCloud Drive). The app writes `tasks/<task-id>.json` files there.

The first version uses eventual folder sync: it syncs on request and retains local data first. iOS requires the user to grant the selected folder access through Files; the security-scoped bookmark is retained for later launches.

For TestFlight and App Store preparation, use the native Apple workflow in [Release Path.md](Release%20Path.md).

## Interaction model

- Scroll normally with one finger.
- Long-press an empty point in the timeline, then drag and release to create a 15-minute-snapped task.
- Long-press an existing task, then drag to move it.
- Drag the small bottom handle to resize it.
- The widget is intentionally glanceable: it can complete a task or deep-link into the app but cannot perform freeform timeline dragging.
