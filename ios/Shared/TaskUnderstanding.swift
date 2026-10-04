import Foundation

/// What will be written if the user confirms: the result of understanding one sentence.
struct TaskDraft: Equatable {
    enum Source: Equatable { case rules, model }

    var title: String
    var date: String?
    var start: Int?
    var end: Int?
    var category: String = "personal"
    var recurrence: String = "none"
    var notes: String = ""
    var source: Source = .rules
    /// The user asked to be reminded ("提醒我", "remind me").
    var wantsReminder = false
    /// A day was named without a time, so the default time of day was used.
    var usesDefaultTime = false

    var isScheduled: Bool { date != nil && start != nil && end != nil }
}

/// The one switch for how a spoken task is committed, shared by the app, Siri and the Action Button.
enum QuickAddPolicy {
    /// true: add as soon as the sentence is understood and offer Undo. false: always ask first.
    static let addsImmediately = true
    static let undoWindow: TimeInterval = 5
    /// Where a task goes when a day was named but no time: 09:00.
    static let defaultStartMinute = 9 * 60
}

/// When a task's reminder should fire. Reminders are local notifications on this iPhone; which
/// tasks want one is kept in the App Group, not in the synced task file, so the data format the
/// Mac reads does not change.
enum ReminderPlan {
    static let defaultsKey = "reminderTaskIDs"

    static func fireDate(for task: PlannerTask) -> Date? {
        guard !task.isDeleted, !task.done, let date = task.date, let start = task.start, let day = DateFormatter.dayKey.date(from: date) else { return nil }
        return Calendar.current.date(byAdding: .minute, value: start, to: Calendar.current.startOfDay(for: day))
    }

    static var sharedDefaults: UserDefaults { UserDefaults(suiteName: WidgetSnapshot.appGroupID) ?? .standard }

    static func wantedIDs(in defaults: UserDefaults = sharedDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    static func setWanted(_ wanted: Bool, taskID: String, in defaults: UserDefaults = sharedDefaults) {
        var ids = wantedIDs(in: defaults)
        if wanted { ids.insert(taskID) } else { ids.remove(taskID) }
        defaults.set(ids.sorted(), forKey: defaultsKey)
    }
}

/// Raw fields as a language model returned them. The model only points at the words for the day
/// and the time; turning those words into a date is done in code. Nothing here is trusted until
/// `TaskUnderstanding` has checked it.
struct ModelTaskOutput: Equatable {
    var title: String = ""
    var dateText: String?
    var timeText: String?
    var durationMinutes: Int?
    var wantsReminder: Bool = false
    var category: String?
    var recurrence: String?
}

/// Combines the rule parser with an optional model answer. The rules are exact when they match, so
/// they keep the date and time they found; the model fills in what rules cannot see (a day or time
/// in the middle of the sentence, category, a cleaner title). Every model field is validated on its
/// own and dropped if it is out of range or not grounded in what was said.
enum TaskUnderstanding {
    static let categories = ["personal", "health", "home", "social", "learning", "errands"]
    static let recurrences = ["none", "daily", "weekdays", "weekly"]

    static func draft(text: String, model: ModelTaskOutput?, now: Date = .now) -> TaskDraft {
        let rules = QuickInputParser.parse(text, now: now)
        var draft = TaskDraft(title: rules.title, date: rules.date, start: rules.start, end: rules.end)
        var day = rules.day
        var usedModel = false

        if let model {
            // The model may only make the title tidier than the rules did, never put the lead-in or the date back.
            if let title = groundedTitle(model.title, in: text), title.count <= rules.title.count, title != rules.title { draft.title = title; usedModel = true }
            if let category = model.category, categories.contains(category), category != "personal" { draft.category = category; usedModel = true }
            if let recurrence = model.recurrence, recurrences.contains(recurrence), recurrence != "none" { draft.recurrence = recurrence; usedModel = true }

            if day == nil, let phrase = model.dateText, contains(text, phrase), let resolved = DatePhrase.resolve(phrase, now: now) { day = resolved.dayKey; usedModel = true }
            if !rules.hasExplicitTime, let phrase = model.timeText, contains(text, phrase), let minute = QuickInputParser.minute(fromTimePhrase: phrase) {
                let duration = model.durationMinutes.flatMap { (15...8 * 60).contains($0) ? snap($0) : nil } ?? rules.duration
                draft.date = day ?? now.dayKey
                draft.start = minute
                draft.end = minute + max(15, duration)
                usedModel = true
            }
        }

        draft.wantsReminder = QuickInputParser.mentionsReminder(text) || (model?.wantsReminder ?? false)
        if draft.isScheduled {
            if let day { draft.date = day }
        } else if let day {
            // A day without a time lands on that day at the default time, where it is visible and can be dragged.
            draft.date = day
            draft.start = QuickAddPolicy.defaultStartMinute
            draft.end = QuickAddPolicy.defaultStartMinute + 30
            draft.usesDefaultTime = true
        } else {
            // Neither day nor time: Inbox.
            draft.date = nil; draft.start = nil; draft.end = nil
            draft.recurrence = "none"
            draft.wantsReminder = false
        }
        if usedModel { draft.source = .model }
        return draft
    }

    /// The model may tidy the title ("记一下明天牙医" → "牙医") but may not invent one.
    static func groundedTitle(_ candidate: String, in text: String) -> String? {
        let title = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 80, contains(text, title) else { return nil }
        return title
    }

    private static func snap(_ minute: Int) -> Int { Int((Double(minute) / 15).rounded()) * 15 }

    private static func contains(_ text: String, _ part: String) -> Bool {
        func normalized(_ value: String) -> String { value.lowercased().filter { !$0.isWhitespace } }
        return normalized(text).contains(normalized(part))
    }
}
