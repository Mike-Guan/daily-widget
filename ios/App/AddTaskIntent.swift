import AppIntents
import SwiftUI

/// "Add a task" for Siri, the Action Button and Shortcuts. The system does the dictation and hands
/// over plain text, so the app needs no microphone or speech permission.
struct AddTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Add task"
    static var description = IntentDescription("Adds a task from one sentence. With a time it goes on the timeline; without one it goes to the Inbox.")
    static var openAppWhenRun = false

    @Parameter(title: "Task", requestValueDialog: "What do you want to add?")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$text)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let repository = TaskRepository.shared else { throw AddTaskError.storageUnavailable }
        let english = (WidgetSnapshot.stored(in: repository.directory)?.language ?? "zh") == "en"
        let draft = await TaskInterpreter.interpret(text, english: english)
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw $text.needsValueError(IntentDialog(stringLiteral: english ? "What do you want to add?" : "要记什么？"))
        }

        // Nothing is written until the user confirms the card.
        let summary = AddTaskSummary(draft: draft, english: english)
        try await requestConfirmation(
            result: .result(dialog: IntentDialog(stringLiteral: summary.question)) { AddTaskConfirmationView(summary: summary) },
            confirmationActionName: .add
        )

        var task = PlannerTask.empty(date: draft.date, start: draft.start, end: draft.end, deviceID: "siri")
        task.apply(draft)
        try repository.upsert(task)
        return .result(dialog: IntentDialog(stringLiteral: summary.done))
    }
}

extension PlannerTask {
    mutating func apply(_ draft: TaskDraft) {
        title = draft.title
        date = draft.date
        start = draft.start
        end = draft.end
        category = draft.category
        recurrence = draft.recurrence
        if !draft.notes.isEmpty { notes = draft.notes }
    }
}

enum AddTaskError: LocalizedError {
    case storageUnavailable
    var errorDescription: String? { "Daily Widget could not open its storage. Open the app once and try again." }
}

struct AddTaskSummary {
    let title: String
    let when: String
    let isInbox: Bool
    let english: Bool
    /// Category, repeat rule and who understood the sentence, e.g. "健康 · 每天 · 由本机 AI 理解".
    let detail: String

    init(draft: TaskDraft, english: Bool, today: Date = .now) {
        self.title = draft.title
        self.english = english
        let categories = ["personal": "个人", "health": "健康", "home": "生活", "social": "关系", "learning": "学习", "errands": "杂事"]
        let recurrences = english ? ["daily": "Every day", "weekdays": "Weekdays", "weekly": "Every week"] : ["daily": "每天", "weekdays": "工作日", "weekly": "每周"]
        detail = [
            english ? draft.category.capitalized : categories[draft.category] ?? draft.category,
            recurrences[draft.recurrence],
            draft.source == .model ? (english ? "Understood by on-device AI" : "由本机 AI 理解") : (english ? "Parsed by rules" : "按规则解析"),
        ].compactMap { $0 }.joined(separator: " · ")
        guard let date = draft.date, let start = draft.start, let end = draft.end else {
            isInbox = true
            let keptDay = draft.notes.count == 10 ? DateFormatter.dayKey.date(from: draft.notes) : nil
            let dayNote = keptDay.map { " · " + $0.formatted(.dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier: english ? "en_US" : "zh_Hans_CN"))) } ?? ""
            when = (english ? "Inbox · no time" : "收集箱 · 未定时间") + dayNote
            return
        }
        isInbox = false
        let calendar = Calendar.current
        let day = Date.date(fromKey: date)
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: day)).day
        let dayText: String
        switch offset {
        case 0: dayText = english ? "Today" : "今天"
        case 1: dayText = english ? "Tomorrow" : "明天"
        case 2 where !english: dayText = "后天"
        default: dayText = day.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated).locale(Locale(identifier: english ? "en_US" : "zh_Hans_CN")))
        }
        when = "\(dayText) \(Self.time(start))–\(Self.time(end % (24 * 60)))\(end > 24 * 60 ? " (+1)" : "")"
    }

    var question: String { english ? "Add “\(title)”? \(when)" : "添加「\(title)」？\(when)" }
    var done: String { english ? (isInbox ? "Added to Inbox." : "Added.") : (isInbox ? "已放进收集箱。" : "已添加。") }

    private static func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
}

struct AddTaskConfirmationView: View {
    let summary: AddTaskSummary

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DWColors.accent)
                Image(systemName: summary.isInbox ? "tray.fill" : "calendar").font(.body.weight(.semibold)).foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title).font(.headline).lineLimit(2)
                Text(summary.when).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                Text(summary.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

struct DailyWidgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "Add to \(.applicationName)",
                "New \(.applicationName) task",
            ],
            shortTitle: "Add task",
            systemImageName: "plus.circle.fill"
        )
    }
}
