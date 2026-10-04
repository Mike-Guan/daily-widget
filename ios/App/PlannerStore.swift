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
        guard syncState != .syncing else { return true }
        syncState = .syncing
        let localRecords = records
        Task { [weak self] in
            do {
                let merged = try await Task.detached(priority: .userInitiated) {
                    try Self.synchronize(localRecords: localRecords, folder: folder)
                }.value
                guard let self else { return }
                records = merged
                persist()
                syncState = .synced(.now)
            } catch {
                self?.syncState = .failure(error.localizedDescription)
            }
        }
        return true
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
        let current = tasks.first { $0.start <= nowMinute && $0.end > nowMinute && !$0.isDone }
        let remaining = tasks.filter { !$0.isDone && $0.id != current?.id }.sorted { ($0.isFocus ? 0 : 1, $0.start) < ($1.isFocus ? 0 : 1, $1.start) }
        let snapshot = WidgetSnapshot(date: Date().dayKey, completed: tasks.filter(\.isDone).count, total: tasks.count, current: current.map(item), upcoming: remaining.prefix(3).map(item), updatedAt: .now, language: language)
        if let data = try? encoder.encode(snapshot) { try? data.write(to: container.appendingPathComponent("widget-today.json"), options: .atomic); WidgetCenter.shared.reloadAllTimelines() }
    }

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
        var merged = Dictionary(uniqueKeysWithValues: localRecords.map { ($0.id, $0) })
        let formatter = ISO8601DateFormatter()
        for incoming in remote {
            let incomingDate = formatter.date(from: incoming.updatedAt) ?? .distantPast
            let localDate = merged[incoming.id].flatMap { formatter.date(from: $0.updatedAt) } ?? .distantPast
            if merged[incoming.id] == nil || incomingDate > localDate { merged[incoming.id] = incoming }
        }
        let records = Array(merged.values)
        for task in records {
            let destination = tasksURL.appendingPathComponent("\(task.id).json")
            let data = try encoder.encode(task)
            try data.write(to: destination, options: .atomic)
        }
        return records
    }
}
