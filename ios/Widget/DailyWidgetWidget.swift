import WidgetKit
import SwiftUI
import AppIntents

struct DailyWidgetEntry: TimelineEntry { let date: Date; let snapshot: WidgetSnapshot }

struct DailyWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyWidgetEntry { .init(date: .now, snapshot: .empty(dateKey: Date().dayKey)) }
    func getSnapshot(in context: Context, completion: @escaping (DailyWidgetEntry) -> Void) { completion(entry(at: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyWidgetEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        var entries = [entry(at: now)]
        // A second entry at 0:00 switches the widget to the new day even if the system delays the next reload.
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) { entries.append(entry(at: midnight)) }
        completion(Timeline(entries: entries, policy: .after(calendar.date(byAdding: .minute, value: 30, to: now)!)))
    }
    private func entry(at date: Date) -> DailyWidgetEntry { .init(date: date, snapshot: WidgetSnapshot.resolve(for: date)) }
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
        try TaskRepository.shared?.toggleDone(taskID: taskID, dateKey: dateKey, deviceID: "widget")
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

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    private var homeScreen: some View {
        Group {
            switch family {
            case .systemSmall: smallHome
            case .systemMedium: mediumHome
            default: largeHome
            }
        }
        .containerBackground(for: .widget) { DWColors.surface(colorScheme) }
    }

    private var smallHome: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { dateLabel; Spacer(minLength: 4); countLabel("\(entry.snapshot.completed)/\(entry.snapshot.total)") }
            nextCard(titleLines: 2).frame(maxHeight: .infinity)
            progressBar
        }
        .widgetURL(nextItem.map(taskURL) ?? todayURL)
    }

    private var mediumHome: some View {
        HStack(alignment: .top, spacing: 12) {
            // The whole left column is the one place that opens the app.
            Link(destination: nextItem.map(taskURL) ?? todayURL ?? URL(string: "dailywidget://today")!) {
                VStack(alignment: .leading, spacing: 8) {
                    dateLabel
                    nextCard(titleLines: 1).frame(maxHeight: .infinity)
                }
                .frame(width: 150)
                .contentShape(Rectangle())
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack { countLabel(text("Today \(entry.snapshot.completed)/\(entry.snapshot.total)", "今天 \(entry.snapshot.completed)/\(entry.snapshot.total)")); Spacer(minLength: 4) }
                    .frame(minHeight: 20)
                taskList(limit: 3)
                Spacer(minLength: 0)
            }
        }
    }

    private var largeHome: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { dateLabel; Spacer(minLength: 4); countLabel(text("\(entry.snapshot.completed)/\(entry.snapshot.total) done", "\(entry.snapshot.completed)/\(entry.snapshot.total) 完成")) }
            progressBar
            nextLink(titleLines: 1, showsEnd: true, fills: false)
            taskList(limit: 4)
            Spacer(minLength: 0)
            HStack {
                Text(text("Inbox \(entry.snapshot.inboxCount)", "收集箱 \(entry.snapshot.inboxCount) 件")).font(.caption).foregroundStyle(DWColors.muted)
                Spacer(minLength: 4)
            }
        }
    }

    private var dateLabel: some View {
        let day = Date.date(fromKey: entry.snapshot.date)
        return (Text(day, format: .dateTime.month().day()).font(.footnote.weight(.bold)).foregroundStyle(DWColors.text)
            + Text(" ") + Text(day, format: .dateTime.weekday(.abbreviated)).font(.footnote.weight(.medium)).foregroundStyle(DWColors.muted))
            .environment(\.locale, Locale(identifier: entry.snapshot.language == "en" ? "en_US" : "zh_CN"))
            .lineLimit(1)
    }

    private func countLabel(_ value: String) -> some View {
        Text(value).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(DWColors.muted).lineLimit(1)
    }

    private var progressBar: some View {
        let total = entry.snapshot.total
        return HStack(spacing: 3) {
            if total > 0 && total <= 12 {
                ForEach(0..<total, id: \.self) { index in Capsule().fill(index < entry.snapshot.completed ? DWColors.accent : DWColors.line) }
            } else {
                // Too many tasks for one segment each: fall back to a single bar.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DWColors.line)
                        Capsule().fill(DWColors.accent).frame(width: proxy.size.width * CGFloat(entry.snapshot.completed) / CGFloat(max(total, 1)))
                    }
                }
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel(text("Today's progress", "今日进度"))
        .accessibilityValue("\(entry.snapshot.completed) / \(total)")
    }

    @ViewBuilder
    private func nextLink(titleLines: Int, showsEnd: Bool = false, fills: Bool = true) -> some View {
        if let item = nextItem { Link(destination: taskURL(item)) { nextCard(titleLines: titleLines, showsEnd: showsEnd, fills: fills) } }
        else { nextCard(titleLines: titleLines, showsEnd: showsEnd, fills: fills) }
    }

    /// - Parameter fills: true where the card takes the remaining height and its text sits at the bottom (small, medium).
    private func nextCard(titleLines: Int, showsEnd: Bool = false, fills: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if fills { Spacer(minLength: 0) }
            if let item = nextItem {
                Text(item.id == entry.snapshot.current?.id ? text("Now", "进行中") : text("Next", "下一件")).font(.caption2.weight(.semibold)).opacity(0.85)
                Text(displayTitle(item)).font(.callout.weight(.bold)).lineLimit(titleLines).multilineTextAlignment(.leading)
                if let start = item.start {
                    (Text(showsEnd ? timeRange(item) : time(start)) + Text(" · ") + countdown(item))
                        .font(.caption.monospacedDigit()).opacity(0.9).lineLimit(1)
                }
            } else {
                Text(entry.snapshot.total == 0 ? text("Nothing planned", "今天还没有安排") : text("All clear today", "今天清空了")).font(.callout.weight(.bold)).lineLimit(2)
            }
        }
        .foregroundStyle(DWColors.onAccent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(DWColors.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func taskList(limit: Int) -> some View {
        let items = Array(listItems.prefix(limit))
        return VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text(text("Nothing else today", "今天没有别的了")).font(.caption).foregroundStyle(DWColors.muted).padding(.vertical, 6)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Rectangle().fill(DWColors.line).frame(height: 1) }
                taskRow(item)
            }
        }
    }

    private func taskRow(_ item: WidgetSnapshot.Item) -> some View {
        let color = DWColors.taskColor(mode: "category", token: nil, category: item.category)
        return HStack(spacing: 9) {
            if #available(iOS 17.0, *) {
                Button(intent: ToggleTaskIntent(taskID: item.id, dateKey: item.date)) {
                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle").font(.body).foregroundStyle(color)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(text("Complete \(displayTitle(item))", "完成 \(displayTitle(item))"))
            }
            // Rows do not open the app: only the circle acts here, so a stray tap on the list does nothing.
            HStack(spacing: 6) {
                Text(displayTitle(item)).font(.footnote.weight(.semibold)).foregroundStyle(DWColors.text).lineLimit(1)
                Spacer(minLength: 4)
                Text(item.start.map(time) ?? text("Any time", "全天")).font(.caption.monospacedDigit()).foregroundStyle(DWColors.muted)
            }
        }
        .padding(.vertical, 6)
    }

    /// The task shown in the big card: the one running now, otherwise the earliest one still to come.
    private var nextItem: WidgetSnapshot.Item? {
        if let current = entry.snapshot.current, !current.done { return current }
        return entry.snapshot.upcoming.filter { !$0.done }.min { ($0.start ?? Int.max) < ($1.start ?? Int.max) }
    }

    /// Open tasks after the big card, in time order.
    private var listItems: [WidgetSnapshot.Item] {
        visibleItems.filter { $0.id != nextItem?.id }.sorted { ($0.start ?? Int.max) < ($1.start ?? Int.max) }
    }

    /// "35 分钟后" before the task starts, "还剩 40 分钟" while it runs. The number counts down on its
    /// own; the system updates relative dates without a timeline reload.
    private func countdown(_ item: WidgetSnapshot.Item) -> Text {
        if let start = startDate(item), start > entry.date {
            return entry.snapshot.language == "en" ? Text("in ") + Text(start, style: .relative) : Text(start, style: .relative) + Text("后")
        }
        if let end = endDate(item), end > entry.date {
            return entry.snapshot.language == "en" ? Text(end, style: .relative) + Text(" left") : Text("还剩 ") + Text(end, style: .relative)
        }
        return Text(text("now", "进行中"))
    }

    private func endDate(_ item: WidgetSnapshot.Item) -> Date? {
        guard let end = item.end else { return nil }
        return Calendar.current.date(byAdding: .minute, value: end, to: Calendar.current.startOfDay(for: Date.date(fromKey: entry.snapshot.date)))
    }

    private func timeRange(_ item: WidgetSnapshot.Item) -> String {
        guard let start = item.start else { return "" }
        guard let end = item.end, end > start else { return time(start) }
        return "\(time(start))–\(time(end % 1440))"
    }

    private func displayTitle(_ item: WidgetSnapshot.Item) -> String { item.title.isEmpty ? text("Untitled task", "未命名任务") : item.title }

    private func taskURL(_ item: WidgetSnapshot.Item) -> URL {
        URL(string: "dailywidget://task?date=\(entry.snapshot.date)&id=\(item.id)") ?? URL(string: "dailywidget://today")!
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
                    // Counts down on its own; the system updates relative dates without a timeline reload.
                    (Text("\(time(start)) · ") + (startDate(item).map { $0 > entry.date ? Text($0, style: .relative) : Text(text("now", "进行中")) } ?? Text(remainingText)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let following = visibleItems.dropFirst().first {
                    Text("\(following.start.map(time) ?? "") \(following.title)")
                        .font(.caption2.monospacedDigit())
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

    private var visibleItems: [WidgetSnapshot.Item] {
        let all = (entry.snapshot.current.map { [$0] } ?? []) + entry.snapshot.upcoming
        var seen = Set<String>()
        return all.filter { seen.insert($0.id).inserted && !$0.done }
    }

    private var lockScreenItem: WidgetSnapshot.Item? { visibleItems.first }

    private func startDate(_ item: WidgetSnapshot.Item) -> Date? {
        guard let start = item.start else { return nil }
        return Calendar.current.date(byAdding: .minute, value: start, to: Calendar.current.startOfDay(for: Date.date(fromKey: entry.snapshot.date)))
    }

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

    private func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    private func text(_ english: String, _ chinese: String) -> String { entry.snapshot.language == "en" ? english : chinese }
}

/// The widget's own microphone mark, drawn on a 16 x 16 grid.
struct MicGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        let origin = CGPoint(x: rect.midX - 8 * scale, y: rect.midY - 8 * scale)
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: origin.x + x * scale, y: origin.y + y * scale, width: width * scale, height: height * scale)
        }
        var path = Path()
        path.addRoundedRect(in: box(5.25, 1, 5.5, 9), cornerSize: CGSize(width: 2.75 * scale, height: 2.75 * scale))
        var arc = Path()
        arc.addArc(center: CGPoint(x: origin.x + 8 * scale, y: origin.y + 7.4 * scale), radius: 4.6 * scale, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        path.addPath(arc.strokedPath(StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round)))
        path.addRoundedRect(in: box(7.2, 12, 1.6, 2.2), cornerSize: CGSize(width: 0.4 * scale, height: 0.4 * scale))
        path.addRoundedRect(in: box(5, 13.6, 6, 1.6), cornerSize: CGSize(width: 0.8 * scale, height: 0.8 * scale))
        return path
    }
}

/// A lock-screen circle that opens voice capture.
struct QuickAddAccessoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyWidgetQuickAdd", provider: DailyWidgetProvider()) { entry in
            let circle = ZStack {
                AccessoryWidgetBackground()
                MicGlyph().fill(.primary).frame(width: 24, height: 24).widgetAccentable()
            }
            Group {
                if #available(iOS 18.0, *) {
                    // Listens in the background instead of opening the app.
                    Button(intent: RecordTaskIntent()) { circle }.buttonStyle(.plain)
                } else {
                    circle.widgetURL(URL(string: "dailywidget://quickadd"))
                }
            }
            .containerBackground(.clear, for: .widget)
            .accessibilityLabel(entry.snapshot.language == "en" ? "Add a task by voice" : "语音记一件事")
        }
        .configurationDisplayName("语音添加 · Voice add")
        .description("点一下，直接说要记的事。Tap and say what to add.")
        .supportedFamilies([.accessoryCircular])
    }
}

/// The same entry point as a control for the lock screen's bottom slots, Control Center and the Action Button.
@available(iOS 18.0, *)
struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.guanshiyang.dailywidget.quickadd") {
            ControlWidgetButton(action: RecordTaskIntent()) { Label("记一件事", systemImage: "mic.fill") }
        }
        .displayName("记一件事")
        .description("不打开 App，直接听你说。Listens without opening the app.")
    }
}

@main
struct DailyWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyWidgetWidget()
        QuickAddAccessoryWidget()
        if #available(iOS 18.0, *) { QuickAddControl() }
        VoiceCaptureLiveActivity()
    }
}
