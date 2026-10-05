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

    var isScheduled: Bool { date != nil && start != nil && end != nil }
}

/// The one switch for how a spoken task is committed, shared by the app, Siri and the Action Button.
enum QuickAddPolicy {
    /// true: add as soon as the sentence is understood and offer Undo. false: always ask first.
    static let addsImmediately = true
    static let undoWindow: TimeInterval = 5
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
            if let title = groundedTitle(model.title, in: text) { draft.title = title; usedModel = true }
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

        if draft.isScheduled {
            if let day { draft.date = day }
        } else {
            // No time means Inbox. Keep the day that was named so it is not lost.
            draft.date = nil; draft.start = nil; draft.end = nil
            draft.recurrence = "none"
            if let day { draft.notes = day }
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
