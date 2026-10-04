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
        let parsed = QuickInputParser.parse(text)
        guard !parsed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw $text.needsValueError(IntentDialog(stringLiteral: english ? "What do you want to add?" : "要记什么？"))
        }

        // Nothing is written until the user confirms the card.
        let summary = AddTaskSummary(parsed: parsed, english: english)
        try await requestConfirmation(
            result: .result(dialog: IntentDialog(stringLiteral: summary.question)) { AddTaskConfirmationView(summary: summary) },
            confirmationActionName: .add
        )

        var task = PlannerTask.empty(date: parsed.date, start: parsed.start, end: parsed.end, deviceID: "siri")
        task.title = parsed.title
        try repository.upsert(task)
        return .result(dialog: IntentDialog(stringLiteral: summary.done))
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

    init(parsed: QuickInputParser.Result, english: Bool, today: Date = .now) {
        self.title = parsed.title
        self.english = english
        guard let date = parsed.date, let start = parsed.start, let end = parsed.end else {
            isInbox = true
            when = english ? "Inbox · no time" : "收集箱 · 未定时间"
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
