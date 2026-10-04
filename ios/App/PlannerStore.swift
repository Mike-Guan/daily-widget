import Foundation
import SwiftUI
import WidgetKit
import UIKit

@MainActor
final class PlannerStore: ObservableObject {
    @Published private(set) var records: [PlannerTask] = [] { didSet { syncReminders() } }
    /// Task ids that should fire a local notification at their start time.
    @Published private(set) var reminderIDs: Set<String> = ReminderPlan.wantedIDs()
    @Published var selectedDate = Date()
    @Published var language = "zh"
    @Published var theme = "system"
    @Published var syncState: SyncState = .localOnly
    @Published var syncFolderURL: URL?

    enum SyncState: Equatable { case localOnly, syncing, synced(Date), failure(String) }

    private let deviceID: String
    private let fileManager = FileManager.default
    private let repository: TaskRepository
    /// Shared with the extensions so the sync folder is not tied to the app's own defaults.
    private let sharedDefaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID) ?? .standard
    private static let bookmarkKey = "syncFolderBookmark"

    init() {
        let defaults = UserDefaults.standard
        deviceID = defaults.string(forKey: "deviceID") ?? "iphone-\(UUID().uuidString)"
        defaults.set(deviceID, forKey: "deviceID")
        language = defaults.string(forKey: "language") ?? "zh"
        theme = defaults.string(forKey: "theme") ?? "system"
        repository = TaskRepository.shared ?? TaskRepository(directory: fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0])
        reload()
        restoreSyncFolder()
    }

    var dateKey: String { selectedDate.dayKey }
    var todayTasks: [ScheduledOccurrence] { tasks(for: dateKey) }
    /// Newest first, so something just captured is at the top.
    var inbox: [PlannerTask] { records.filter { !$0.isDeleted && $0.date == nil }.sorted { $0.createdAt > $1.createdAt } }

    func newTask(date: String? = nil, start: Int? = nil, end: Int? = nil) -> PlannerTask {
        PlannerTask.empty(date: date, start: start, end: end, deviceID: deviceID)
    }

    func tasks(for key: String) -> [ScheduledOccurrence] {
        records.flatMap { $0.occurrences(on: key) }.sorted { $0.start < $1.start }
    }

    func save(_ input: PlannerTask) {
        var task = input
        task.touch(deviceID: deviceID)
        do { records = try repository.upsert(task, language: language) } catch { syncState = .failure(error.localizedDescription) }
    }

    /// The task most recently added by voice or quick add, while its Undo banner is showing.
    @Published var recentlyAdded: PlannerTask?
    /// Whether the on-device model contributed to that task, shown on the banner.
    @Published private(set) var recentlyAddedEngine = "rules"

    func hasReminder(_ task: PlannerTask) -> Bool { reminderIDs.contains(task.id) }

    /// False for a task that is still only a draft in an editor.
    func contains(_ task: PlannerTask) -> Bool { records.contains { $0.id == task.id && !$0.isDeleted } }

    func setReminder(_ wanted: Bool, for task: PlannerTask) {
        ReminderPlan.setWanted(wanted, taskID: task.id)
        syncReminders()
    }

    private func syncReminders() {
        // Siri and the Action Button add ids from outside the app, so read the shared set again.
        reminderIDs = ReminderPlan.wantedIDs()
        let tasks = records, english = language == "en"
        Task { await ReminderScheduler.reconcile(tasks: tasks, english: english) }
    }

    func addFromQuickAdd(_ draft: TaskDraft, jumpToDate: Bool = true) {
        var task = newTask()
        task.apply(draft)
        if draft.wantsReminder { ReminderPlan.setWanted(true, taskID: task.id) }
        save(task)
        if jumpToDate, let date = draft.date { selectedDate = .date(fromKey: date) }
        recentlyAddedEngine = TaskInterpreter.lastEngine
        recentlyAdded = records.first { $0.id == task.id }
    }

    func undoRecentlyAdded() {
        guard let task = recentlyAdded else { return }
        recentlyAdded = nil
        delete(task)
    }

    func delete(_ task: PlannerTask) {
        var deleted = task
        deleted.deletedAt = ISO8601DateFormatter().string(from: .now)
        save(deleted)
    }

    func toggleDone(_ occurrence: ScheduledOccurrence) {
        guard var changed = records.first(where: { $0.id == occurrence.task.id }) else { return }
        let dateKey = occurrence.sourceDate
        if changed.recurrence == "none" { changed.done.toggle() }
        else if let index = changed.completedDates.firstIndex(of: dateKey) { changed.completedDates.remove(at: index) }
        else { changed.completedDates.append(dateKey); changed.completedDates.sort() }
        save(changed)
    }

    func move(_ occurrence: ScheduledOccurrence, start: Int, end: Int) {
        guard var changed = records.first(where: { $0.id == occurrence.task.id }) else { return }
        changed.start = start; changed.end = end
        save(changed)
    }

    func moveToInbox(_ task: PlannerTask) {
        var changed = task
        changed.date = nil; changed.start = nil; changed.end = nil; changed.focus = false
        save(changed)
    }

    func setLanguage(_ value: String) {
        language = value
        UserDefaults.standard.set(value, forKey: "language")
        refreshWidgetSnapshot()
    }

    func setTheme(_ value: String) {
        theme = value
        UserDefaults.standard.set(value, forKey: "theme")
    }

    func setSyncFolder(_ url: URL) {
        syncFolderURL = url
        storeBookmark(for: url)
        syncNow()
    }

    @discardableResult
    func syncNow() -> Bool {
        guard syncFolderURL != nil else { syncState = .localOnly; return false }
        Task { await performSync() }
        return true
    }

    /// Called when the app becomes active: pick up widget/Siri changes from disk, then sync.
    func appBecameActive() {
        reload()
        syncNow()
    }

    /// Called when the app leaves the foreground: push local changes out while iOS still gives us time.
    func appEnteredBackground() {
        guard syncFolderURL != nil else { return }
        var identifier = UIBackgroundTaskIdentifier.invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: "DailyWidgetSync") {
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
        Task {
            await performSync()
            if identifier != .invalid { UIApplication.shared.endBackgroundTask(identifier); identifier = .invalid }
        }
    }

    private func performSync() async {
        guard let folder = syncFolderURL, syncState != .syncing else { return }
        syncState = .syncing
        let repository = repository
        let language = language
        do {
            records = try await Task.detached(priority: .userInitiated) {
                // Merge against what is on disk now, and fold the result back in with another
                // read-modify-write, so a widget or Siri change made meanwhile is not lost.
                let synced = try Self.synchronize(localRecords: try repository.load(), folder: folder)
                return try repository.mutate(language: language) { $0 = TaskRepository.merge($0, with: synced) }
            }.value
            syncState = .synced(.now)
        } catch {
            syncState = .failure(error.localizedDescription)
        }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "dailywidget" else { return }
        if url.host == "quickadd" { NotificationCenter.default.post(name: .dailyWidgetQuickAdd, object: nil); return }
        if let date = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "date" })?.value { selectedDate = .date(fromKey: date) }
    }

    /// Picks up changes other processes (widget, Siri) wrote while the app was not looking.
    func reload() {
        do { records = try repository.load(); repository.refreshSnapshot(tasks: records, language: language) }
        catch { syncState = .failure(error.localizedDescription) }
    }

    private func storeBookmark(for url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
            sharedDefaults.set(bookmark, forKey: Self.bookmarkKey)
        }
    }

    private func restoreSyncFolder() {
        // Earlier builds kept the bookmark in the app's own defaults; move it to the App Group once.
        if sharedDefaults.data(forKey: Self.bookmarkKey) == nil, let legacy = UserDefaults.standard.data(forKey: Self.bookmarkKey) {
            sharedDefaults.set(legacy, forKey: Self.bookmarkKey)
            if sharedDefaults !== UserDefaults.standard { UserDefaults.standard.removeObject(forKey: Self.bookmarkKey) }
        }
        guard let bookmark = sharedDefaults.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        syncFolderURL = try? URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale, let url = syncFolderURL { storeBookmark(for: url) }
    }

    private func refreshWidgetSnapshot() { repository.refreshSnapshot(tasks: records, language: language) }

    private nonisolated static func synchronize(localRecords: [PlannerTask], folder: URL) throws -> [PlannerTask] {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }

        var coordinationError: NSError?
        var syncResult: Result<[PlannerTask], Error>?
        NSFileCoordinator().coordinate(writingItemAt: folder, options: [], error: &coordinationError) { coordinatedFolder in
            syncResult = Result { try synchronizeFiles(localRecords: localRecords, folder: coordinatedFolder) }
        }
        if let coordinationError { throw coordinationError }
        return try syncResult?.get() ?? localRecords
    }

    private nonisolated static func synchronizeFiles(localRecords: [PlannerTask], folder: URL) throws -> [PlannerTask] {
        let manager = FileManager.default
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let tasksURL = folder.appendingPathComponent("tasks", isDirectory: true)
        try manager.createDirectory(at: tasksURL, withIntermediateDirectories: true)
        let remote = try manager.contentsOfDirectory(at: tasksURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> PlannerTask? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(PlannerTask.self, from: data)
            }
        let records = TaskRepository.merge(localRecords, with: remote)
        for task in records {
            let destination = tasksURL.appendingPathComponent("\(task.id).json")
            let data = try encoder.encode(task)
            try data.write(to: destination, options: .atomic)
        }
        return records
    }
}
