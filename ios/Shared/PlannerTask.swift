import Foundation

struct PlannerTask: Codable, Identifiable, Hashable {
    static let schemaVersion = 2

    var schemaVersion: Int = PlannerTask.schemaVersion
    var id: String
    var date: String?
    var start: Int?
    var end: Int?
    var title: String
    var done: Bool = false
    var focus: Bool = false
    var focusDates: [String] = []
    var category: String = "personal"
    var colorMode: String = "category"
    var colorToken: String?
    var notes: String = ""
    var url: String = ""
    var recurrence: String = "none"
    var completedDates: [String] = []
    var createdAt: String
    var updatedAt: String
    var updatedBy: String
    var deletedAt: String?

    var isScheduled: Bool { date != nil && start != nil && end != nil }
    var isDeleted: Bool { deletedAt != nil }

    static func empty(date: String? = nil, start: Int? = nil, end: Int? = nil, deviceID: String) -> PlannerTask {
        let now = ISO8601DateFormatter().string(from: .now)
        return PlannerTask(id: UUID().uuidString, date: date, start: start, end: end, title: "", createdAt: now, updatedAt: now, updatedBy: deviceID)
    }

    func primaryOccurs(on dateKey: String) -> Bool {
        guard !isDeleted, let firstDate = date, dateKey >= firstDate else { return false }
        switch recurrence {
        case "none": return firstDate == dateKey
        case "daily": return true
        case "weekdays":
            let weekday = Date.date(fromKey: dateKey).weekday
            return (2...6).contains(weekday)
        case "weekly": return Date.date(fromKey: firstDate).weekday == Date.date(fromKey: dateKey).weekday
        default: return false
        }
    }

    func occurrences(on dateKey: String) -> [ScheduledOccurrence] {
        guard isScheduled else { return [] }
        var results: [ScheduledOccurrence] = []
        if primaryOccurs(on: dateKey), let start, let end {
            results.append(ScheduledOccurrence(task: self, dateKey: dateKey, sourceDate: dateKey, start: start, end: min(end, 24 * 60), isContinuation: false, spansNextDay: end > 24 * 60))
        }
        let previousDate = Date.date(fromKey: dateKey).addingTimeInterval(-24 * 60 * 60).dayKey
        if let end, end > 24 * 60, primaryOccurs(on: previousDate) {
            results.append(ScheduledOccurrence(task: self, dateKey: dateKey, sourceDate: previousDate, start: 0, end: end - 24 * 60, isContinuation: true, spansNextDay: false))
        }
        return results
    }

    func isDone(on dateKey: String) -> Bool {
        recurrence == "none" ? done : completedDates.contains(dateKey)
    }

    func isFocus(on dateKey: String) -> Bool {
        recurrence == "none" ? focus : focusDates.contains(dateKey)
    }

    mutating func touch(deviceID: String) {
        updatedAt = ISO8601DateFormatter().string(from: .now)
        updatedBy = deviceID
    }
}

struct ScheduledOccurrence: Identifiable, Hashable {
    let task: PlannerTask
    let dateKey: String
    let sourceDate: String
    let start: Int
    let end: Int
    let isContinuation: Bool
    let spansNextDay: Bool

    var id: String { "\(task.id)@\(sourceDate)\(isContinuation ? ":continued" : "")" }
    var title: String { task.title }
    var category: String { task.category }
    var isDone: Bool { task.recurrence == "none" ? task.done : task.completedDates.contains(sourceDate) }
    var isFocus: Bool { task.recurrence == "none" ? task.focus : task.focusDates.contains(sourceDate) }
    var fullEnd: Int { task.end ?? end }
    var fullStart: Int { task.start ?? start }
}

extension Date {
    static func date(fromKey key: String) -> Date {
        DateFormatter.dayKey.date(from: key) ?? .now
    }

    var dayKey: String { DateFormatter.dayKey.string(from: self) }
    var weekday: Int { Calendar.current.component(.weekday, from: self) }
}

extension DateFormatter {
    static let dayKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension PlannerTask {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, date, start, end, title, done, focus, focusDates, category, colorMode, colorToken, notes, url, recurrence, completedDates, createdAt, updatedAt, updatedBy, deletedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let created = try values.decodeIfPresent(String.self, forKey: .createdAt) ?? ISO8601DateFormatter().string(from: .now)
        self.schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? PlannerTask.schemaVersion
        self.id = try values.decode(String.self, forKey: .id)
        self.date = try values.decodeIfPresent(String.self, forKey: .date)
        self.start = try values.decodeIfPresent(Int.self, forKey: .start)
        self.end = try values.decodeIfPresent(Int.self, forKey: .end)
        self.title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.done = try values.decodeIfPresent(Bool.self, forKey: .done) ?? false
        self.focus = try values.decodeIfPresent(Bool.self, forKey: .focus) ?? false
        self.focusDates = try values.decodeIfPresent([String].self, forKey: .focusDates) ?? []
        self.category = try values.decodeIfPresent(String.self, forKey: .category) ?? "personal"
        self.colorMode = try values.decodeIfPresent(String.self, forKey: .colorMode) == "custom" ? "custom" : "category"
        self.colorToken = try values.decodeIfPresent(String.self, forKey: .colorToken)
        self.notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.url = try values.decodeIfPresent(String.self, forKey: .url) ?? ""
        self.recurrence = try values.decodeIfPresent(String.self, forKey: .recurrence) ?? "none"
        self.completedDates = try values.decodeIfPresent([String].self, forKey: .completedDates) ?? []
        self.createdAt = created
        self.updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt) ?? created
        self.updatedBy = try values.decodeIfPresent(String.self, forKey: .updatedBy) ?? "unknown"
        self.deletedAt = try values.decodeIfPresent(String.self, forKey: .deletedAt)
    }
}
