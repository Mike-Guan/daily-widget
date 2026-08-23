import WidgetKit
import SwiftUI
import AppIntents

struct DailyWidgetEntry: TimelineEntry { let date: Date; let snapshot: WidgetSnapshot }

struct DailyWidgetProvider: TimelineProvider {
    private static let sampleSnapshot = WidgetSnapshot(date: Date().dayKey, completed: 1, total: 3, current: .init(id: "sample", title: "晨间散步", start: 540, end: 570, done: false, category: "health", date: Date().dayKey), upcoming: [], updatedAt: .now)
    func placeholder(in context: Context) -> DailyWidgetEntry { .init(date: .now, snapshot: Self.sampleSnapshot) }
    func getSnapshot(in context: Context, completion: @escaping (DailyWidgetEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyWidgetEntry>) -> Void) { let entry = entry(); completion(Timeline(entries: [entry], policy: .after(Calendar.current.date(byAdding: .minute, value: 30, to: .now)!))) }
    private func entry() -> DailyWidgetEntry { let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.guanshiyang.dailywidget")?.appendingPathComponent("widget-today.json"); let snapshot = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) } ?? Self.sampleSnapshot; return .init(date: .now, snapshot: snapshot) }
}

@available(iOS 17.0, *)
struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete task"
    static var openAppWhenRun = false
    @Parameter(title: "Task ID") var taskID: String
    @Parameter(title: "Date") var dateKey: String
    init() {}
    init(taskID: String, dateKey: String) { self.taskID = taskID; self.dateKey = dateKey }
    func perform() async throws -> some IntentResult {
        let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.guanshiyang.dailywidget")
        guard let group, let data = try? Data(contentsOf: group.appendingPathComponent("tasks.json")), var tasks = try? JSONDecoder().decode([PlannerTask].self, from: data), let index = tasks.firstIndex(where: { $0.id == taskID }) else { return .result() }
        if tasks[index].recurrence == "none" { tasks[index].done.toggle() }
        else if let completed = tasks[index].completedDates.firstIndex(of: dateKey) { tasks[index].completedDates.remove(at: completed) }
        else { tasks[index].completedDates.append(dateKey); tasks[index].completedDates.sort() }
        tasks[index].updatedAt = ISO8601DateFormatter().string(from: .now); tasks[index].updatedBy = "widget"
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(tasks).write(to: group.appendingPathComponent("tasks.json"), options: .atomic)
        let snapshotURL = group.appendingPathComponent("widget-today.json")
        if var snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: snapshotURL)) {
            func refreshed(_ item: WidgetSnapshot.Item) -> WidgetSnapshot.Item {
                guard let task = tasks.first(where: { $0.id == item.id }) else { return item }
                var next = item; next.done = task.isDone(on: item.date); return next
            }
            let dayOccurrences = tasks.flatMap { $0.occurrences(on: snapshot.date) }
            snapshot.current = snapshot.current.map(refreshed); snapshot.upcoming = snapshot.upcoming.map(refreshed); snapshot.completed = dayOccurrences.filter(\.isDone).count; snapshot.total = dayOccurrences.count; snapshot.updatedAt = .now
            try encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct DailyWidgetWidget: Widget {
    let kind = "DailyWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyWidgetProvider()) { entry in DailyWidgetWidgetView(entry: entry) }
            .configurationDisplayName("Daily Widget")
            .description("Today at a glance.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DailyWidgetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyWidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Label(text("Today", "今天"), systemImage: "checkmark.circle").font(.caption.weight(.semibold)); Spacer(); Text("\(entry.snapshot.completed)/\(entry.snapshot.total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            if let current = entry.snapshot.current { item(current, current: true) } else if let next = entry.snapshot.upcoming.first { item(next, current: false) } else { Spacer(); Text(text("Make space for what matters.", "为重要的事留一点空间。")).font(.caption).foregroundStyle(.secondary); Spacer() }
            if family != .systemSmall { ForEach(entry.snapshot.upcoming.dropFirst().prefix(family == .systemLarge ? 3 : 1)) { item in self.item(item, current: false) } }
            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }
    @ViewBuilder private func item(_ item: WidgetSnapshot.Item, current: Bool) -> some View {
        HStack(spacing: 7) {
            if #available(iOS 17.0, *) { Button(intent: ToggleTaskIntent(taskID: item.id, dateKey: item.date)) { Image(systemName: item.done ? "checkmark.circle.fill" : "circle").foregroundStyle(current ? .indigo : .secondary) }.buttonStyle(.plain) }
            Link(destination: URL(string: "dailywidget://task?date=\(entry.snapshot.date)&id=\(item.id)")!) { VStack(alignment: .leading, spacing: 1) { Text(item.title.isEmpty ? text("Untitled task", "未命名任务") : item.title).font(current ? .headline : .subheadline).lineLimit(1); if let start = item.start { Text(time(start)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) } }.foregroundStyle(.primary) }
        }
    }
    private func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    private func text(_ english: String, _ chinese: String) -> String { entry.snapshot.language == "en" ? english : chinese }
}

@main
struct DailyWidgetBundle: WidgetBundle { var body: some Widget { DailyWidgetWidget() } }
