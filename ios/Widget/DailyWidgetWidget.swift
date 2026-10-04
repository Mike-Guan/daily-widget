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
            .supportedFamilies([
                .systemSmall,
                .systemMedium,
                .systemLarge,
                .accessoryInline,
                .accessoryCircular,
                .accessoryRectangular,
            ])
    }
}

struct DailyWidgetWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyWidgetEntry

    @ViewBuilder
    var body: some View {
        switch family {
        case .accessoryInline:
            inlineLockScreen
        case .accessoryCircular:
            circularLockScreen
        case .accessoryRectangular:
            rectangularLockScreen
        default:
            homeScreen
        }
    }

    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            header
            ProgressView(value: Double(entry.snapshot.completed), total: Double(max(entry.snapshot.total, 1))).tint(DWColors.accent)
            if visibleItems.isEmpty { emptyState } else { ForEach(visibleItems.prefix(itemLimit)) { taskRow($0) } }
            Spacer(minLength: 0)
        }
        .padding(family == .systemSmall ? 14 : 16)
        .environment(\.colorScheme, .light)
        .containerBackground(for: .widget) { LinearGradient(colors: [.white, DWColors.accentSoft], startPoint: .topLeading, endPoint: .bottomTrailing) }
    }

    private var inlineLockScreen: some View {
        Label {
            Text(inlineText)
        } icon: {
            Image(systemName: lockScreenItem == nil ? "checkmark.circle.fill" : "clock")
        }
        .widgetAccentable()
        .containerBackground(.clear, for: .widget)
        .widgetURL(todayURL)
    }

    private var circularLockScreen: some View {
        Gauge(value: Double(entry.snapshot.completed), in: 0...Double(max(entry.snapshot.total, 1))) {
            Image(systemName: "checkmark")
        } currentValueLabel: {
            Text("\(entry.snapshot.completed)/\(entry.snapshot.total)")
                .font(.caption2.monospacedDigit().weight(.bold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .containerBackground(.clear, for: .widget)
        .widgetURL(todayURL)
        .accessibilityLabel(text("Today's progress", "今日进度"))
        .accessibilityValue("\(entry.snapshot.completed) / \(entry.snapshot.total)")
    }

    private var rectangularLockScreen: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .widgetAccentable()
                Text(text("Today", "今天"))
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                Text("\(entry.snapshot.completed)/\(entry.snapshot.total)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
            }
            if let item = lockScreenItem {
                Text(item.title.isEmpty ? text("Untitled task", "未命名任务") : item.title)
                    .font(.headline)
                    .lineLimit(1)
                if let start = item.start {
                    Text("\(time(start)) · \(remainingText)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(text("All clear for today", "今天已经清空"))
                    .font(.headline)
                    .lineLimit(1)
                Text(text("Make space for what matters", "为重要的事留一点空间"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .containerBackground(.clear, for: .widget)
        .widgetURL(todayURL)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DWColors.accent); Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) { Text(text("Today", "今天")).font(.subheadline.bold()).foregroundStyle(DWColors.text); if family != .systemSmall { Text(text("Daily plan", "今日计划")).font(.caption2).foregroundStyle(DWColors.muted) } }
            Spacer()
            Text("\(entry.snapshot.completed)/\(entry.snapshot.total)").font(.caption.monospacedDigit().weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 5).background(DWColors.accent.opacity(0.12), in: Capsule()).foregroundStyle(DWColors.accent)
        }
    }

    private var visibleItems: [WidgetSnapshot.Item] {
        let all = (entry.snapshot.current.map { [$0] } ?? []) + entry.snapshot.upcoming
        var seen = Set<String>()
        return all.filter { seen.insert($0.id).inserted && !$0.done }
    }

    private var lockScreenItem: WidgetSnapshot.Item? { visibleItems.first }

    private var remainingText: String {
        let count = visibleItems.count
        return text("\(count) remaining", "剩余 \(count) 项")
    }

    private var inlineText: String {
        guard let item = lockScreenItem else { return text("Today · All clear", "今天 · 已清空") }
        let title = item.title.isEmpty ? text("Untitled task", "未命名任务") : item.title
        guard let start = item.start else { return title }
        return "\(time(start)) \(title)"
    }

    private var todayURL: URL? {
        URL(string: "dailywidget://today?date=\(entry.snapshot.date)")
    }

    private var itemLimit: Int { family == .systemSmall ? 1 : family == .systemLarge ? 5 : 3 }

    private var emptyState: some View {
        HStack(spacing: 9) { Image(systemName: "sparkles").foregroundStyle(DWColors.accent); Text(text("All clear for today", "今天已经清空")).font(.caption.weight(.medium)).foregroundStyle(DWColors.muted) }.padding(.vertical, 10)
    }

    private func taskRow(_ item: WidgetSnapshot.Item) -> some View {
        HStack(spacing: 9) {
            if #available(iOS 17.0, *) { Button(intent: ToggleTaskIntent(taskID: item.id, dateKey: item.date)) { Image(systemName: item.done ? "checkmark.circle.fill" : "circle").font(.body).foregroundStyle(DWColors.category(item.category)) }.buttonStyle(.plain) }
            Link(destination: URL(string: "dailywidget://task?date=\(entry.snapshot.date)&id=\(item.id)")!) { HStack { VStack(alignment: .leading, spacing: 2) { Text(item.title.isEmpty ? text("Untitled task", "未命名任务") : item.title).font(.caption.weight(.semibold)).lineLimit(1); if let start = item.start { Text(time(start)).font(.caption2.monospacedDigit()).foregroundStyle(DWColors.muted) } }; Spacer(minLength: 0) }.foregroundStyle(DWColors.text) }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    private func text(_ english: String, _ chinese: String) -> String { entry.snapshot.language == "en" ? english : chinese }
}

@main
struct DailyWidgetBundle: WidgetBundle { var body: some Widget { DailyWidgetWidget() } }
