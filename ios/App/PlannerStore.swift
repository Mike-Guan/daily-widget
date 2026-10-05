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
    private let repository: TaskRepository

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
    var inbox: [PlannerTask] { records.filter { !$0.isDeleted && $0.date == nil }.sorted { $0.title < $1.title } }

    func tasks(for key: String) -> [ScheduledOccurrence] {
        records.flatMap { $0.occurrences(on: key) }.sorted { $0.start < $1.start }
    }

    func save(_ input: PlannerTask) {
        var task = input
        task.touch(deviceID: deviceID)
        do { records = try repository.upsert(task, language: language) } catch { syncState = .failure(error.localizedDescription) }
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
        let repository = repository
        let language = language
        Task { [weak self] in
            do {
                let merged = try await Task.detached(priority: .userInitiated) {
                    // Merge against what is on disk now, and fold the result back in with another
                    // read-modify-write, so a widget or Siri change made meanwhile is not lost.
                    let synced = try Self.synchronize(localRecords: try repository.load(), folder: folder)
                    return try repository.mutate(language: language) { $0 = TaskRepository.merge($0, with: synced) }
                }.value
                guard let self else { return }
                records = merged
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

    /// Picks up changes other processes (widget, Siri) wrote while the app was not looking.
    func reload() {
        do { records = try repository.load(); repository.refreshSnapshot(tasks: records, language: language) }
        catch { syncState = .failure(error.localizedDescription) }
    }

    private func restoreSyncFolder() {
        guard let bookmark = UserDefaults.standard.data(forKey: "syncFolderBookmark") else { return }
        var stale = false
        syncFolderURL = try? URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
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
