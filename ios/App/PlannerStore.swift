import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class PlannerStore: ObservableObject {
    @Published private(set) var records: [PlannerTask] = []
    @Published var selectedDate = Date()
    @Published var language = "zh"
    @Published var theme = "system"
    @Published var syncState: SyncState = .localOnly
    @Published var syncFolderURL: URL?

    enum SyncState: Equatable { case localOnly, syncing, synced(Date), failure(String) }

    private let deviceID: String
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private var appDirectory: URL

    init() {
        let defaults = UserDefaults.standard
        deviceID = defaults.string(forKey: "deviceID") ?? "iphone-\(UUID().uuidString)"
        defaults.set(deviceID, forKey: "deviceID")
        language = defaults.string(forKey: "language") ?? "zh"
        theme = defaults.string(forKey: "theme") ?? "system"
        let groupDirectory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.guanshiyang.dailywidget")
        appDirectory = groupDirectory ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
        restoreSyncFolder()
        refreshWidgetSnapshot()
    }

    var dateKey: String { selectedDate.dayKey }
    var todayTasks: [ScheduledOccurrence] { tasks(for: dateKey) }
    var inbox: [PlannerTask] { records.filter { !$0.isDeleted && $0.date == nil }.sorted { $0.title < $1.title } }

    func tasks(for key: String) -> [ScheduledOccurrence] {
        records.flatMap { $0.occurrences(on: key) }.sorted { $0.start < $1.start }
    }

    func save(_ input: PlannerTask) {
        var task = input
        task.touch(deviceID: deviceID)
        if let index = records.firstIndex(where: { $0.id == task.id }) { records[index] = task } else { records.append(task) }
        persist()
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
        if let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: "syncFolderBookmark")
        }
        syncNow()
    }

    @discardableResult
    func syncNow() -> Bool {
        guard let folder = syncFolderURL else { syncState = .localOnly; return false }
        syncState = .syncing
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        do {
            var coordinationError: NSError?
            var syncError: Error?
            NSFileCoordinator().coordinate(writingItemAt: folder, options: [], error: &coordinationError) { coordinatedFolder in
                do { try performSync(in: coordinatedFolder) } catch { syncError = error }
            }
            if let coordinationError { throw coordinationError }
            if let syncError { throw syncError }
            syncState = .synced(.now)
            return true
        } catch { syncState = .failure(error.localizedDescription); return false }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "dailywidget" else { return }
        if let date = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "date" })?.value { selectedDate = .date(fromKey: date) }
    }

    private func load() {
        let url = appDirectory.appendingPathComponent("tasks.json")
        records = (try? Data(contentsOf: url)).flatMap { try? decoder.decode([PlannerTask].self, from: $0) } ?? []
    }

    private func persist() {
        do { try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true); try write(records, to: appDirectory.appendingPathComponent("tasks.json")); refreshWidgetSnapshot() } catch { syncState = .failure(error.localizedDescription) }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        let temp = url.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        _ = try? fileManager.replaceItemAt(url, withItemAt: temp)
        if !fileManager.fileExists(atPath: url.path) { try fileManager.moveItem(at: temp, to: url) }
    }

    private func readTask(_ url: URL) -> PlannerTask? { guard url.pathExtension == "json", let data = try? Data(contentsOf: url) else { return nil }; return try? decoder.decode(PlannerTask.self, from: data) }
    private func taskIsNewer(_ left: PlannerTask, than right: PlannerTask) -> Bool { (ISO8601DateFormatter().date(from: left.updatedAt) ?? .distantPast) > (ISO8601DateFormatter().date(from: right.updatedAt) ?? .distantPast) }
    private func restoreSyncFolder() {
        guard let bookmark = UserDefaults.standard.data(forKey: "syncFolderBookmark") else { return }
        var stale = false
        syncFolderURL = try? URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    private func refreshWidgetSnapshot() {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.guanshiyang.dailywidget") else { return }
        let tasks = tasks(for: Date().dayKey)
        let nowMinute = Calendar.current.component(.hour, from: .now) * 60 + Calendar.current.component(.minute, from: .now)
        func item(_ task: ScheduledOccurrence) -> WidgetSnapshot.Item { .init(id: task.task.id, title: task.title, start: task.start, end: task.end, done: task.isDone, category: task.category, recurrence: task.task.recurrence, date: task.sourceDate) }
        let snapshot = WidgetSnapshot(date: Date().dayKey, completed: tasks.filter(\.isDone).count, total: tasks.count, current: tasks.first { $0.start <= nowMinute && $0.end > nowMinute && !$0.isDone }.map(item), upcoming: tasks.filter { $0.start >= nowMinute && !$0.isDone }.prefix(3).map(item), updatedAt: .now, language: language)
        if let data = try? encoder.encode(snapshot) { try? data.write(to: container.appendingPathComponent("widget-today.json"), options: .atomic); WidgetCenter.shared.reloadAllTimelines() }
    }

    private func performSync(in folder: URL) throws {
        let tasksURL = folder.appendingPathComponent("tasks", isDirectory: true)
        try fileManager.createDirectory(at: tasksURL, withIntermediateDirectories: true)
        let remote = try fileManager.contentsOfDirectory(at: tasksURL, includingPropertiesForKeys: nil).compactMap(readTask)
        var merged = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for incoming in remote {
            if let local = merged[incoming.id], taskIsNewer(incoming, than: local) { merged[incoming.id] = incoming }
            else if merged[incoming.id] == nil { merged[incoming.id] = incoming }
        }
        records = Array(merged.values)
        persist()
        try records.forEach { task in try write(task, to: tasksURL.appendingPathComponent("\(task.id).json")) }
    }
}
