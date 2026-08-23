# Daily Widget

Daily Widget is a local-first personal planner: a calm daily timeline, a lightweight inbox for loose thoughts, and an iPhone companion with a home-screen widget. Jira, repositories, tickets, and other work integrations are intentionally out of scope.

## Desktop and browser

Requirements: Node.js 20+ and npm.

```bash
npm install
npm start
```

The desktop app provides the full task and shared-folder sync experience. Opening `index.html` directly also works: it uses browser local storage and includes the full timeline, but browser security prevents direct folder sync.

After setup, use this from any terminal to launch the desktop app:

```bash
routine
```

## Daily workflow

- Drag on empty desktop time to create a task. Drag a task to move it and its bottom edge to resize it.
- Quick add understands entries such as `明天 9:30 跑步 45m` or `tomorrow 9:30 run 45m`.
- The Inbox is intentionally unscheduled: its tasks have no date/time and do not appear on a timeline until scheduled.
- Click `+` for a default-time schedule, or drag an Inbox item directly to a precise point on the timeline.
- Mark up to three Top 3 tasks, review unfinished one-off tasks at day end, and send them to tomorrow or Inbox.
- Each task supports category, notes, HTTPS link, and daily / weekday / weekly repeat.
- Switch the desktop language using `中 / EN`; the iOS app has the same preference in Settings.

## JSON and sync

Existing `data/YYYY-MM-DD.json` history remains untouched and is migrated automatically into independent records at `data/tasks/<task-id>.json`. This lets two devices merge edits to unrelated tasks safely.

Choose **Set sync folder** and select a folder in iCloud Drive, Dropbox, or OneDrive. The shared folder has a simple structure:

```text
Daily Widget/
  tasks/<task-id>.json
```

Sync is local-first and eventually consistent. It runs on request/startup, and desktop also watches the folder where the OS permits it. A same-task collision resolves to the newest `updatedAt`; desktop stores the losing record in `data/backups/conflicts/` rather than silently discarding it.

## iPhone and widget

Open [ios/DailyWidget.xcodeproj](ios/DailyWidget.xcodeproj) in Xcode 15+ after accepting the Xcode license. Select your Apple Developer team for both targets and confirm the included App Group. Details are in [ios/README.md](ios/README.md).

The SwiftUI app uses normal scrolling plus long-press-and-drag creation/movement and a bottom resize handle. The WidgetKit widget stays glanceable: it shows today, can complete a task on iOS 17+, and opens the app for full editing.

## Verification

```bash
npm test
```

The test suite covers quick input parsing, recurrence, deterministic merge behavior, legacy migration, Markdown export, and shared-folder sync records.
