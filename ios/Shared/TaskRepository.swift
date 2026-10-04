import Foundation
import WidgetKit

/// The single read/write path for tasks.json in the App Group. The app, the widget's intents and
/// Siri intents run in different processes, so every change is a coordinated read-modify-write on
/// the file instead of a write of whatever one process happens to hold in memory.
struct TaskRepository {
    enum RepositoryError: LocalizedError {
        case unreadable(String)
        var errorDescription: String? {
            switch self { case .unreadable(let detail): return "tasks.json could not be read: \(detail)" }
        }
    }

    let directory: URL
    /// Widget timelines are only reloaded for the real shared container, not for test directories.
    var reloadsWidgets = true

    var tasksURL: URL { directory.appendingPathComponent(WidgetSnapshot.tasksFileName) }

    /// The App Group container, or nil when the entitlement is missing.
    static var shared: TaskRepository? { WidgetSnapshot.sharedDirectory.map { TaskRepository(directory: $0) } }

    func load() throws -> [PlannerTask] {
        var coordinationError: NSError?
        var result: Result<[PlannerTask], Error> = .success([])
        NSFileCoordinator().coordinate(readingItemAt: tasksURL, options: [], error: &coordinationError) { url in
            result = Result { try Self.read(url) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// Reads the current file, applies `change`, writes the result and refreshes the widget snapshot.
    /// A file that exists but cannot be decoded throws rather than being replaced.
    @discardableResult
    func mutate(language: String? = nil, _ change: (inout [PlannerTask]) -> Void) throws -> [PlannerTask] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var coordinationError: NSError?
        var result: Result<[PlannerTask], Error> = .success([])
        NSFileCoordinator().coordinate(writingItemAt: tasksURL, options: .forMerging, error: &coordinationError) { url in
            result = Result {
                var tasks = try Self.read(url)
                change(&tasks)
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(tasks).write(to: url, options: .atomic)
                return tasks
            }
        }
        if let coordinationError { throw coordinationError }
        let tasks = try result.get()
        refreshSnapshot(tasks: tasks, language: language)
        return tasks
    }

    func refreshSnapshot(tasks: [PlannerTask], language: String? = nil) {
        let resolved = language ?? WidgetSnapshot.stored(in: directory)?.language ?? "zh"
        if WidgetSnapshot.write(tasks: tasks, language: resolved, to: directory), reloadsWidgets { WidgetCenter.shared.reloadAllTimelines() }
    }

    private static func read(_ url: URL) throws -> [PlannerTask] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do { return try JSONDecoder().decode([PlannerTask].self, from: Data(contentsOf: url)) }
        catch { throw RepositoryError.unreadable(error.localizedDescription) }
    }
}

extension TaskRepository {
    @discardableResult
    func upsert(_ task: PlannerTask, language: String? = nil) throws -> [PlannerTask] {
        try mutate(language: language) { tasks in
            if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = task } else { tasks.append(task) }
        }
    }

    @discardableResult
    func toggleDone(taskID: String, dateKey: String, deviceID: String) throws -> [PlannerTask] {
        try mutate { tasks in
            guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
            if tasks[index].recurrence == "none" { tasks[index].done.toggle() }
            else if let completed = tasks[index].completedDates.firstIndex(of: dateKey) { tasks[index].completedDates.remove(at: completed) }
            else { tasks[index].completedDates.append(dateKey); tasks[index].completedDates.sort() }
            tasks[index].touch(deviceID: deviceID)
        }
    }

    /// Per-task last-writer-wins on `updatedAt`; tasks only present on one side are kept.
    static func merge(_ local: [PlannerTask], with incoming: [PlannerTask]) -> [PlannerTask] {
        let formatter = ISO8601DateFormatter()
        var order = local.map(\.id)
        var merged = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for task in incoming {
            guard let existing = merged[task.id] else { merged[task.id] = task; order.append(task.id); continue }
            let incomingDate = formatter.date(from: task.updatedAt) ?? .distantPast
            let existingDate = formatter.date(from: existing.updatedAt) ?? .distantPast
            if incomingDate > existingDate { merged[task.id] = task }
        }
        var seen = Set<String>()
        return order.filter { seen.insert($0).inserted }.compactMap { merged[$0] }
    }
}
