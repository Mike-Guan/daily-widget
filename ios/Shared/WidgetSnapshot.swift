import Foundation

struct WidgetSnapshot: Codable {
    struct Item: Codable, Identifiable {
        var id: String
        var title: String
        var start: Int?
        var end: Int?
        var done: Bool
        var category: String
        var recurrence: String = "none"
        var date: String = ""
    }

    var date: String
    var completed: Int
    var total: Int
    var current: Item?
    var upcoming: [Item]
    var updatedAt: Date
    var language: String = "zh"
    /// Snapshots for the days after `date` (currently just tomorrow), so the widget can roll over at midnight without the app running.
    var following: [WidgetSnapshot] = []
}

extension WidgetSnapshot.Item {
    private enum CodingKeys: String, CodingKey { case id, title, start, end, done, category, recurrence, date }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        start = try values.decodeIfPresent(Int.self, forKey: .start)
        end = try values.decodeIfPresent(Int.self, forKey: .end)
        done = try values.decodeIfPresent(Bool.self, forKey: .done) ?? false
        category = try values.decodeIfPresent(String.self, forKey: .category) ?? "personal"
        recurrence = try values.decodeIfPresent(String.self, forKey: .recurrence) ?? "none"
        date = try values.decodeIfPresent(String.self, forKey: .date) ?? ""
    }
}

extension WidgetSnapshot {
    private enum CodingKeys: String, CodingKey { case date, completed, total, current, upcoming, updatedAt, language, following }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        date = try values.decodeIfPresent(String.self, forKey: .date) ?? Date().dayKey
        completed = try values.decodeIfPresent(Int.self, forKey: .completed) ?? 0
        total = try values.decodeIfPresent(Int.self, forKey: .total) ?? 0
        current = try values.decodeIfPresent(Item.self, forKey: .current)
        upcoming = try values.decodeIfPresent([Item].self, forKey: .upcoming) ?? []
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
        language = try values.decodeIfPresent(String.self, forKey: .language) ?? "zh"
        following = try values.decodeIfPresent([WidgetSnapshot].self, forKey: .following) ?? []
    }
}

extension WidgetSnapshot {
    static let appGroupID = "group.com.guanshiyang.dailywidget"
    static let fileName = "widget-today.json"
    static let tasksFileName = "tasks.json"

    static var sharedDirectory: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) }

    static func empty(dateKey: String, language: String = "zh") -> WidgetSnapshot {
        WidgetSnapshot(date: dateKey, completed: 0, total: 0, current: nil, upcoming: [], updatedAt: .now, language: language)
    }

    /// One day's summary. `nowMinute` decides which task counts as current; pass 0 for a day that has not started yet.
    static func build(tasks: [PlannerTask], dateKey: String, nowMinute: Int, language: String) -> WidgetSnapshot {
        let occurrences = tasks.flatMap { $0.occurrences(on: dateKey) }.sorted { $0.start < $1.start }
        func item(_ task: ScheduledOccurrence) -> Item { .init(id: task.task.id, title: task.title, start: task.start, end: task.end, done: task.isDone, category: task.category, recurrence: task.task.recurrence, date: task.sourceDate) }
        let current = occurrences.first { $0.start <= nowMinute && $0.end > nowMinute && !$0.isDone }
        let remaining = occurrences.filter { !$0.isDone && $0.id != current?.id }.sorted { ($0.isFocus ? 0 : 1, $0.start) < ($1.isFocus ? 0 : 1, $1.start) }
        return WidgetSnapshot(date: dateKey, completed: occurrences.filter(\.isDone).count, total: occurrences.count, current: current.map(item), upcoming: remaining.prefix(5).map(item), updatedAt: .now, language: language)
    }

    /// Today's snapshot with tomorrow's attached in `following`.
    static func build(tasks: [PlannerTask], now: Date = .now, language: String) -> WidgetSnapshot {
        let calendar = Calendar.current
        let nowMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        var today = build(tasks: tasks, dateKey: now.dayKey, nowMinute: nowMinute, language: language)
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            today.following = [build(tasks: tasks, dateKey: tomorrow.dayKey, nowMinute: 0, language: language)]
        }
        return today
    }

    @discardableResult
    static func write(tasks: [PlannerTask], now: Date = .now, language: String, to directory: URL? = sharedDirectory) -> Bool {
        guard let directory else { return false }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(build(tasks: tasks, now: now, language: language)) else { return false }
        return (try? data.write(to: directory.appendingPathComponent(fileName), options: .atomic)) != nil
    }

    static func stored(in directory: URL? = sharedDirectory) -> WidgetSnapshot? {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// The snapshot to show at `date`: the stored day when it matches, otherwise rebuilt from the task list (the app may not have run for days), otherwise an empty day.
    static func resolve(for date: Date, in directory: URL? = sharedDirectory) -> WidgetSnapshot {
        let stored = stored(in: directory)
        let key = date.dayKey
        let language = stored?.language ?? "zh"
        let calendar = Calendar.current
        let nowMinute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if let directory, let data = try? Data(contentsOf: directory.appendingPathComponent(tasksFileName)), let tasks = try? JSONDecoder().decode([PlannerTask].self, from: data) {
            return build(tasks: tasks, dateKey: key, nowMinute: nowMinute, language: language)
        }
        if let stored, stored.date == key { return stored }
        if let match = stored?.following.first(where: { $0.date == key }) { return match }
        return empty(dateKey: key, language: language)
    }
}
