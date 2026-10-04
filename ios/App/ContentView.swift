import SwiftUI
import UniformTypeIdentifiers

private enum AppTab: Hashable, CaseIterable { case today, inbox, topThree, review }

struct ContentView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTask: PlannerTask?
    @State private var showingEditor = false
    @State private var showingQuickCreate = false
    @State private var showingSettings = false
    @State private var showingQuickAdd = false
    @State private var pickingSyncFolder = false
    @State private var tab: AppTab = .today
    @State private var showSyncFolderPrompt = false
    @State private var showingCalendar = false
    @Environment(\.scenePhase) private var scenePhase

    /// From the lock-screen widget or control: drop whatever sheet is up and start listening.
    private func openQuickAdd() {
        _ = OpenQuickAddIntent.consumePendingRequest()
        showingEditor = false; showingQuickCreate = false; showingSettings = false; showingCalendar = false
        tab = .today
        if !showingQuickAdd { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showingQuickAdd = true } }
    }

    var body: some View {
        ZStack {
            page(.today) { todayPage }
            page(.inbox) { InboxPage(selectedTask: $selectedTask, showingEditor: $showingEditor) }
            page(.topThree) { TopThreePage(selectedTask: $selectedTask, showingEditor: $showingEditor) }
            page(.review) { DailyReviewPage(selectedTask: $selectedTask, showingEditor: $showingEditor) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { VStack(spacing: 0) { addedBanner; bottomBar } }
        .tint(DWColors.accent)
        .preferredColorScheme(colorScheme)
        .sheet(isPresented: $showingEditor) { if let task = selectedTask { TaskEditor(task: task) } }
        .sheet(isPresented: $showingQuickCreate) { if let task = selectedTask { QuickCreateSheet(task: task, selectedTask: $selectedTask, showingEditor: $showingEditor) } }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .onReceive(NotificationCenter.default.publisher(for: .dailyWidgetQuickAdd)) { _ in openQuickAdd() }
        .onChange(of: scenePhase) { _, phase in if phase == .active, OpenQuickAddIntent.consumePendingRequest() { openQuickAdd() } }
        .onAppear { if OpenQuickAddIntent.consumePendingRequest() { openQuickAdd() } }
        .sheet(isPresented: $showingQuickAdd) { QuickAddSheet(selectedTask: $selectedTask, showingEditor: $showingEditor) }
        .fileImporter(isPresented: $pickingSyncFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { store.setSyncFolder(url) }
        }
        .alert(text("Choose a shared folder first", "请先选择共享文件夹"), isPresented: $showSyncFolderPrompt) {
            Button(text("Choose folder", "选择文件夹")) { pickingSyncFolder = true }
            Button(text("Cancel", "取消"), role: .cancel) {}
        } message: { Text(text("Select the Daily Widget folder in iCloud Drive to enable sync.", "请在 iCloud Drive 中选择 Daily Widget 文件夹以启用同步。")) }
        .sheet(isPresented: $showingCalendar) {
            VStack(spacing: 10) {
                HStack { Text(text("Choose date", "选择日期")).font(.title3.bold()); Spacer(); Button(text("Today", "今天")) { store.selectedDate = .now }; Button(text("Done", "完成")) { showingCalendar = false }.buttonStyle(.borderedProminent).tint(DWColors.accent) }
                    .padding(.horizontal, 18).padding(.top, 18)
                Divider()
                DatePicker("", selection: $store.selectedDate, displayedComponents: .date).labelsHidden().datePickerStyle(.graphical).padding(.horizontal, 16).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    /// Pages stay alive while hidden so scroll position survives a tab switch.
    private func page<Content: View>(_ value: AppTab, @ViewBuilder content: () -> Content) -> some View {
        content().opacity(tab == value ? 1 : 0).allowsHitTesting(tab == value).accessibilityHidden(tab != value)
    }

    // MARK: Today

    private var todayPage: some View {
        TimelineView(selectedTask: $selectedTask, showingEditor: $showingEditor, showingQuickCreate: $showingQuickCreate) {
            VStack(alignment: .leading, spacing: DWSpacing.xs) {
                PageHeader(eyebrow: dateLine, title: selectedDateTitle) { todayMenu }
                syncStatusBanner
            }
        }
    }

    private var todayMenu: some View {
        Menu {
            Button { showingCalendar = true } label: { Label(text("Choose date", "选择日期"), systemImage: "calendar") }
            if store.dateKey != Date().dayKey { Button { store.selectedDate = .now } label: { Label(text("Back to today", "回到今天"), systemImage: "arrow.uturn.backward") } }
            Divider()
            Button { if !store.syncNow() { showSyncFolderPrompt = true } } label: { Label(text("Sync now", "立即同步"), systemImage: "arrow.triangle.2.circlepath") }.disabled(isSyncing)
            Button { store.setLanguage(store.language == "en" ? "zh" : "en") } label: { Label(store.language == "en" ? "切换到中文" : "Switch to English", systemImage: "character.bubble") }
            Menu {
                Picker(text("Theme", "主题"), selection: Binding(get: { store.theme }, set: store.setTheme)) {
                    Label(text("System", "跟随系统"), systemImage: "circle.lefthalf.filled").tag("system")
                    Label(text("Light", "浅色"), systemImage: "sun.max").tag("light")
                    Label(text("Dark", "深色"), systemImage: "moon.stars").tag("dark")
                }
            } label: { Label(text("Theme", "主题"), systemImage: "circle.lefthalf.filled") }
            Divider()
            Button { showingSettings = true } label: { Label(text("Settings", "设置"), systemImage: "gearshape") }
        } label: {
            Image(systemName: "ellipsis.circle").font(.title2).foregroundStyle(DWColors.accent).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(text("More", "更多"))
    }

    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
    private var locale: Locale { Locale(identifier: store.language == "en" ? "en_US" : "zh_Hans_CN") }
    private var colorScheme: ColorScheme? { store.theme == "system" ? nil : (store.theme == "dark" ? .dark : .light) }
    private var isToday: Bool { store.dateKey == Date().dayKey }
    private var selectedDateTitle: String { isToday ? text("Today", "今天") : store.selectedDate.formatted(.dateTime.month(.abbreviated).day().locale(locale)) }
    private var dateLine: String {
        isToday ? store.selectedDate.formatted(.dateTime.month().day().weekday(.wide).locale(locale)) : store.selectedDate.formatted(.dateTime.year().weekday(.wide).locale(locale))
    }
    private var isSyncing: Bool { store.syncState == .syncing }

    @ViewBuilder private var syncStatusBanner: some View {
        switch store.syncState {
        case .syncing:
            Label { Text(text("Syncing…", "正在同步…")) } icon: { ProgressView().controlSize(.mini) }.font(DWFont.caption).foregroundStyle(DWColors.muted)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(DWFont.caption).foregroundStyle(DWColors.danger).lineLimit(2)
        case .synced, .localOnly:
            EmptyView()
        }
    }

    // MARK: Added banner with Undo

    @ViewBuilder private var addedBanner: some View {
        if let task = store.recentlyAdded {
            HStack(spacing: DWSpacing.sm) {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(DWColors.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(text("Added", "已添加") + " · " + task.title).font(DWFont.headline).foregroundStyle(DWColors.text).lineLimit(1)
                    Text(AddTaskSummary(draft: TaskDraft(title: task.title, date: task.date, start: task.start, end: task.end, category: task.category, recurrence: task.recurrence, notes: task.notes), english: store.language == "en").when).font(DWFont.caption).foregroundStyle(DWColors.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { selectedTask = task; store.recentlyAdded = nil; showingEditor = true } label: { Text(text("Edit", "改一下")).font(DWFont.label).frame(minWidth: 44, minHeight: 44) }
                Button { store.undoRecentlyAdded() } label: { Text(text("Undo", "撤销")).font(DWFont.label).frame(minWidth: 44, minHeight: 44) }
            }
            .padding(.horizontal, DWSpacing.md).padding(.vertical, DWSpacing.xxs)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous).stroke(DWColors.line.opacity(0.6)))
            .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
            .padding(.horizontal, DWSpacing.md)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .task(id: task.id) {
                try? await Task.sleep(for: .seconds(QuickAddPolicy.undoWindow))
                if !Task.isCancelled, store.recentlyAdded?.id == task.id { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { store.recentlyAdded = nil } }
            }
            .accessibilityElement(children: .contain)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: DWSpacing.sm) {
            HStack(spacing: 0) {
                tabButton(.today, text("Today", "今天"), "calendar")
                tabButton(.inbox, text("Inbox", "收集箱"), "tray", badge: store.inbox.count)
                tabButton(.topThree, text("Focus", "重点"), "star")
                tabButton(.review, text("Review", "回顾"), "moon.stars")
            }
            .padding(DWSpacing.xxs)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(DWColors.line.opacity(0.6)))
            .shadow(color: .black.opacity(0.08), radius: 16, y: 6)

            Button { showingQuickAdd = true } label: {
                Image(systemName: "mic.fill").font(.title3.weight(.semibold)).foregroundStyle(DWColors.onAccent).frame(width: 56, height: 56).background(DWColors.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .shadow(color: DWColors.accent.opacity(0.35), radius: 12, y: 6)
            .accessibilityLabel(text("Quick add", "快速添加"))
            .accessibilityHint(text("Type or dictate a task", "输入或口述一条任务"))
        }
        .padding(.horizontal, DWSpacing.md)
        .padding(.top, DWSpacing.xs)
        .padding(.bottom, DWSpacing.xxs)
    }

    private func tabButton(_ value: AppTab, _ title: String, _ symbol: String, badge: Int = 0) -> some View {
        let selected = tab == value
        return Button {
            if reduceMotion { tab = value } else { withAnimation(.easeOut(duration: 0.18)) { tab = value } }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: selected && symbol != "calendar" ? "\(symbol).fill" : symbol).font(.body.weight(.semibold)).frame(height: 22)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 { Text("\(min(badge, 99))").font(.system(size: 10, weight: .bold)).monospacedDigit().foregroundStyle(DWColors.onAccent).padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16).background(DWColors.accent, in: Capsule()).offset(x: 12, y: -6) }
                    }
                Text(title).font(.caption2.weight(selected ? .bold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? DWColors.accent : DWColors.muted)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(selected ? DWColors.accentSoft : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(badge > 0 ? "\(badge)" : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Small muted line over a large title, with one optional trailing control.
struct PageHeader<Trailing: View>: View {
    var eyebrow: String?
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow { Text(eyebrow).font(DWFont.label).foregroundStyle(DWColors.muted) }
                Text(title).font(DWFont.title).foregroundStyle(DWColors.text).accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: DWSpacing.sm)
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(eyebrow: String? = nil, title: String) { self.init(eyebrow: eyebrow, title: title) { EmptyView() } }
}

/// Shared page scaffold: tinted background, scrolling column of cards.
private struct PageScroll<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DWSpacing.md) { content() }
                .padding(.horizontal, DWSpacing.md).padding(.top, DWSpacing.xs).padding(.bottom, DWSpacing.lg)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(DWColors.background(colorScheme).ignoresSafeArea())
    }
}

private struct EmptyStateCard: View {
    let symbol: String
    let title: String
    let hint: String
    var body: some View {
        VStack(spacing: DWSpacing.xs) {
            Image(systemName: symbol).font(.title).foregroundStyle(DWColors.accent).frame(width: 56, height: 56).background(DWColors.accentSoft, in: Circle())
            Text(title).font(DWFont.headline).foregroundStyle(DWColors.text)
            Text(hint).font(DWFont.body).foregroundStyle(DWColors.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DWSpacing.lg)
        .dailyWidgetCard()
        .accessibilityElement(children: .combine)
    }
}

private struct SectionLabel: View {
    let title: String
    var body: some View { Text(title).font(DWFont.label).foregroundStyle(DWColors.muted).padding(.horizontal, DWSpacing.xxs).accessibilityAddTraits(.isHeader) }
}

/// One task line inside a card: color dot or check, title, secondary line.
private struct TaskRow<Leading: View, Trailing: View>: View {
    let title: String
    let detail: String
    var done = false
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(spacing: DWSpacing.sm) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DWFont.headline).foregroundStyle(DWColors.text).strikethrough(done).lineLimit(2)
                if !detail.isEmpty { Text(detail).font(DWFont.caption).foregroundStyle(DWColors.muted) }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .opacity(done ? 0.5 : 1)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private func taskColor(_ task: PlannerTask) -> Color { DWColors.taskColor(mode: task.colorMode, token: task.colorToken, category: task.category) }

// MARK: Inbox

private struct InboxPage: View {
    @EnvironmentObject private var store: PlannerStore
    @Binding var selectedTask: PlannerTask?
    @Binding var showingEditor: Bool
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        PageScroll {
            PageHeader(eyebrow: text("Capture now, schedule later", "先记下来，再安排"), title: text("Inbox", "收集箱"))
            quickAddField
            if store.inbox.isEmpty {
                EmptyStateCard(symbol: "tray", title: text("Inbox is clear", "收集箱是空的"), hint: text("Ideas without a time land here.", "还没定时间的想法会放在这里。"))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.inbox.enumerated()), id: \.element.id) { index, task in
                        if index > 0 { Divider().overlay(DWColors.line).padding(.leading, 22) }
                        Button { selectedTask = task; showingEditor = true } label: {
                            TaskRow(title: task.title.isEmpty ? text("Untitled task", "未命名任务") : task.title, detail: categoryName(task.category)) {
                                Circle().fill(taskColor(task)).frame(width: 10, height: 10)
                            } trailing: {
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DWColors.muted.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, DWSpacing.xxs)
                    }
                }
                .dailyWidgetCard(padding: DWSpacing.sm)
            }
        }
    }

    private var quickAddField: some View {
        HStack(spacing: DWSpacing.xs) {
            Image(systemName: "plus").font(.body.weight(.semibold)).foregroundStyle(DWColors.accent)
            TextField(text("Add to Inbox", "记一件事"), text: $draft).font(.body).focused($fieldFocused).submitLabel(.done).onSubmit(add)
            if !draft.isEmpty {
                Button(action: add) { Image(systemName: "arrow.up.circle.fill").font(.title2).foregroundStyle(DWColors.accent) }.buttonStyle(.plain).frame(width: 44, height: 44).accessibilityLabel(text("Add", "添加"))
            }
        }
        .padding(.horizontal, DWSpacing.md)
        .frame(minHeight: 52)
        .dailyWidgetCard(padding: 0)
    }

    private func add() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var task = store.newTask()
        task.title = title
        store.save(task)
        draft = ""
    }

    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
    private func categoryName(_ value: String) -> String { store.language == "en" ? value.capitalized : ["personal":"个人", "health":"健康", "home":"生活", "social":"关系", "learning":"学习", "errands":"杂事"][value] ?? value }
}

// MARK: Top 3

private struct TopThreePage: View {
    @EnvironmentObject private var store: PlannerStore
    @Binding var selectedTask: PlannerTask?
    @Binding var showingEditor: Bool

    var body: some View {
        let items = store.todayTasks.filter(\.isFocus)
        PageScroll {
            PageHeader(eyebrow: text("What matters today", "今天最重要的事"), title: text("Top 3", "今日重点"))
            if items.isEmpty {
                EmptyStateCard(symbol: "star", title: text("No Top 3 yet", "还没有设置重点"), hint: text("Open a task and turn on Top task.", "打开一个任务，把它设为今日重点。"))
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    TaskRow(title: item.title.isEmpty ? text("Untitled task", "未命名任务") : item.title, detail: "\(DWFormat.time(item.start)) – \(DWFormat.time(item.end))\(item.spansNextDay ? " (+1)" : "")", done: item.isDone) {
                        Text("\(index + 1)").font(DWFont.headline).monospacedDigit().foregroundStyle(DWColors.accent).frame(width: 32, height: 32).background(DWColors.accentSoft, in: Circle())
                    } trailing: {
                        Button { store.toggleDone(item) } label: { Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(item.isDone ? DWColors.accent : DWColors.muted).frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel(item.isDone ? text("Mark not done", "标为未完成") : text("Mark done", "标为完成"))
                    }
                    .onTapGesture { selectedTask = item.task; showingEditor = true }
                    .dailyWidgetCard(padding: DWSpacing.sm)
                }
            }
        }
    }
    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
}

// MARK: Review

private struct DailyReviewPage: View {
    @EnvironmentObject private var store: PlannerStore
    @Binding var selectedTask: PlannerTask?
    @Binding var showingEditor: Bool

    var body: some View {
        let tasks = store.todayTasks.sorted { ($0.isFocus ? 0 : 1, $0.start) < ($1.isFocus ? 0 : 1, $1.start) }
        let done = tasks.filter(\.isDone)
        let remaining = tasks.filter { !$0.isDone }
        PageScroll {
            PageHeader(eyebrow: text("Look back gently", "轻轻回看这一天"), title: text("Daily review", "日末回顾"))
            HStack(spacing: DWSpacing.md) {
                DWProgressRing(completed: done.count, total: tasks.count, size: 64, lineWidth: 6)
                Text(encouragement(done: done.count, total: tasks.count)).font(DWFont.body).foregroundStyle(DWColors.text).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .dailyWidgetCard()
            if !remaining.isEmpty { SectionLabel(title: text("Unfinished", "未完成") + " · \(remaining.count)"); list(remaining, unfinished: true) }
            if !done.isEmpty { SectionLabel(title: text("Completed", "已完成") + " · \(done.count)"); list(done, unfinished: false) }
        }
    }

    private func list(_ items: [ScheduledOccurrence], unfinished: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, occurrence in
                if index > 0 { Divider().overlay(DWColors.line).padding(.leading, 22) }
                TaskRow(title: occurrence.title.isEmpty ? text("Untitled task", "未命名任务") : occurrence.title, detail: "\(DWFormat.time(occurrence.start)) – \(DWFormat.time(occurrence.end))", done: occurrence.isDone) {
                    Circle().fill(taskColor(occurrence.task)).frame(width: 10, height: 10)
                } trailing: {
                    HStack(spacing: 0) {
                        if occurrence.isFocus { Image(systemName: "star.fill").font(.caption).foregroundStyle(DWColors.accent).accessibilityLabel(text("Top task", "今日重点")) }
                        if unfinished {
                            Menu { Button { store.moveToInbox(occurrence.task) } label: { Label(text("Move to inbox", "放入收集箱"), systemImage: "tray.and.arrow.down") } } label: { Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(DWColors.muted).frame(width: 44, height: 44).contentShape(Rectangle()) }
                                .accessibilityLabel(text("More", "更多"))
                        }
                    }
                }
                .onTapGesture { selectedTask = occurrence.task; showingEditor = true }
                .padding(.vertical, DWSpacing.xxs)
            }
        }
        .dailyWidgetCard(padding: DWSpacing.sm)
    }

    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
    private func encouragement(done: Int, total: Int) -> String { if total == 0 { return text("Nothing was scheduled today. Leaving space is valid, too.", "今天没有已计划的任务；留一点空白也是一种安排。") }; if done == total { return text("Wonderful — every planned task is complete.", "太棒了，今天安排的事项已经全部完成。") }; return text("Nice work: \(done) task(s) complete. The rest can be arranged with care.", "做得很好，已经完成 \(done) 项；剩下的也可以从容安排。") }
}

// MARK: Quick add (type or dictate) with the same confirmation card as Siri

private struct QuickAddSheet: View {
    private enum Stage: Equatable { case input, understanding, confirm }

    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTask: PlannerTask?
    @Binding var showingEditor: Bool
    @StateObject private var dictation = SpeechDictation()
    @State private var input = ""
    @State private var stage: Stage = .input
    @State private var draft: TaskDraft?
    @FocusState private var fieldFocused: Bool

    private var english: Bool { store.language == "en" }
    private var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: DWSpacing.md) {
            HStack {
                Text(heading).font(DWFont.title)
                Spacer()
                Button { dictation.stop(); dismiss() } label: { Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(DWColors.muted).frame(width: 44, height: 44) }.accessibilityLabel(text("Close", "关闭"))
            }
            switch stage {
            case .input: editor
            case .understanding: understanding
            case .confirm: confirmation
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DWSpacing.lg).padding(.top, DWSpacing.md)
        .tint(DWColors.accent)
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .presentationBackground(DWColors.surface(colorScheme))
        .task { TaskInterpreter.prewarm(); await dictation.start(english: english) }
        .onChange(of: dictation.transcript) { _, value in if dictation.isListening { input = value } }
        .onDisappear { dictation.stop() }
    }

    private var heading: String {
        switch stage {
        case .input: return dictation.isListening ? text("Listening…", "正在听…") : text("Quick add", "快速添加")
        case .understanding: return text("Understanding…", "正在理解…")
        case .confirm: return text("Add this?", "这样添加？")
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: DWSpacing.sm) {
            TextField(text("Tomorrow 3pm dentist", "明天下午三点牙医"), text: $input, axis: .vertical)
                .font(.title3).lineLimit(1...3).focused($fieldFocused).submitLabel(.done)
                .onChange(of: input) { _, value in if value.contains("\n") { input = value.replacingOccurrences(of: "\n", with: ""); understand() } }
                .padding(DWSpacing.md)
                .background(DWColors.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous))
                .disabled(dictation.isListening)
            Text(hint).font(DWFont.body).foregroundStyle(DWColors.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DWSpacing.sm) {
                Button {
                    if dictation.isListening { input = dictation.stop(); understand() } else { fieldFocused = false; Task { await dictation.start(english: english) } }
                } label: {
                    Label(dictation.isListening ? text("Done", "说完了") : text("Speak", "说话"), systemImage: dictation.isListening ? "stop.fill" : "mic.fill").font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent).tint(dictation.isListening ? DWColors.now : DWColors.accent).foregroundStyle(dictation.isListening ? Color.white : DWColors.onAccent)
                if !dictation.isListening {
                    Button(action: understand) { Text(text("Next", "下一步")).font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 50) }
                        .buttonStyle(.bordered).tint(DWColors.accent).disabled(trimmed.isEmpty)
                }
            }
        }
    }

    private var hint: String {
        if case .unavailable(let reason) = dictation.state { return reason }
        return dictation.isListening ? text("Say it in one sentence, then tap Done.", "用一句话说出来，说完点“说完了”。") : text("Speak or type. No time means Inbox.", "可以说，也可以打字。没说时间就放进收集箱。")
    }

    private var understanding: some View {
        VStack(alignment: .leading, spacing: DWSpacing.sm) {
            Label(trimmed, systemImage: "quote.opening").font(DWFont.body).foregroundStyle(DWColors.muted).lineLimit(3)
            HStack(spacing: DWSpacing.xs) { ProgressView(); Text(text("Working it out on this iPhone", "正在本机理解这句话")).font(DWFont.body).foregroundStyle(DWColors.muted) }
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(DWColors.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous))
        }
    }

    @ViewBuilder private var confirmation: some View {
        if let draft {
            VStack(alignment: .leading, spacing: DWSpacing.sm) {
                Label(trimmed, systemImage: "quote.opening").font(DWFont.body).foregroundStyle(DWColors.muted).lineLimit(2)
                AddTaskConfirmationView(summary: AddTaskSummary(draft: draft, english: english))
                    .background(DWColors.accentSoft.opacity(0.6), in: RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous))
                HStack(spacing: DWSpacing.sm) {
                    Button { edit(draft) } label: { Text(text("Edit", "改一下")).font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 50) }
                        .buttonStyle(.bordered).tint(DWColors.accent)
                    Button { save(draft) } label: { Text(text("OK", "好")).font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 50) }
                        .buttonStyle(.borderedProminent).tint(DWColors.accent).foregroundStyle(DWColors.onAccent)
                }
                Button { stage = .input; Task { await dictation.start(english: english) } } label: { Label(text("Say it again", "重说一遍"), systemImage: "arrow.counterclockwise").font(DWFont.label).frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.plain).foregroundStyle(DWColors.muted)
            }
        }
    }

    private func understand() {
        let sentence = trimmed
        guard !sentence.isEmpty, stage == .input else { return }
        fieldFocused = false
        stage = .understanding
        Task {
            let result = await TaskInterpreter.interpret(sentence, english: english)
            if QuickAddPolicy.addsImmediately {
                store.addFromQuickAdd(result)
                dismiss()
                return
            }
            draft = result
            if reduceMotion { stage = .confirm } else { withAnimation(.easeOut(duration: 0.2)) { stage = .confirm } }
        }
    }

    private func task(from draft: TaskDraft) -> PlannerTask {
        var task = store.newTask()
        task.apply(draft)
        return task
    }

    /// Opens the full editor with everything prefilled; nothing is saved until the user saves there.
    private func edit(_ draft: TaskDraft) {
        selectedTask = task(from: draft)
        dismiss()
        showingEditor = true
    }

    private func save(_ draft: TaskDraft) {
        store.save(task(from: draft))
        if let date = draft.date { store.selectedDate = .date(fromKey: date) }
        dismiss()
    }

    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
}

private struct QuickCreateSheet: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    let task: PlannerTask
    @Binding var selectedTask: PlannerTask?
    @Binding var showingEditor: Bool
    @State private var title = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(text("What is this time for?", "这段时间要做什么？")).font(.headline)
                Text("\(time(task.start ?? 0)) – \(time(task.end ?? 0))").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                TextField(text("Task name", "任务名称"), text: $title).textFieldStyle(.roundedBorder).submitLabel(.done).onSubmit { _ = save() }
                Button { if save() { showingEditor = true } } label: { Label(text("Add details", "补充详情"), systemImage: "slider.horizontal.3") }.buttonStyle(.bordered).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }
            .padding()
            .navigationTitle(text("New task", "新任务"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(text("Cancel", "取消")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(text("Save", "保存")) { _ = save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    private func save() -> Bool { let name = title.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return false }; var value = task; value.title = name; store.save(value); selectedTask = value; dismiss(); return true }
    private func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute % 1440 / 60, minute % 60) }
    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: PlannerStore
    @State private var pickingFolder = false
    var body: some View { NavigationStack { Form { Section(store.language == "en" ? "Language" : "语言") { Picker("Language", selection: Binding(get: { store.language }, set: store.setLanguage)) { Text("中文").tag("zh"); Text("English").tag("en") }.pickerStyle(.segmented) }; Section(store.language == "en" ? "Appearance" : "外观") { Picker(store.language == "en" ? "Theme" : "主题", selection: Binding(get: { store.theme }, set: store.setTheme)) { Text(store.language == "en" ? "System" : "跟随系统").tag("system"); Text(store.language == "en" ? "Light" : "浅色").tag("light"); Text(store.language == "en" ? "Dark" : "深色").tag("dark") }.pickerStyle(.segmented) }; Section(store.language == "en" ? "Sync" : "同步") { Button(store.syncFolderURL == nil ? (store.language == "en" ? "Choose shared folder" : "选择共享文件夹") : (store.language == "en" ? "Change shared folder" : "更换共享文件夹")) { pickingFolder = true }; if let folder = store.syncFolderURL { LabeledContent(store.language == "en" ? "Folder" : "文件夹", value: folder.lastPathComponent) }; Button(store.language == "en" ? "Sync now" : "立即同步") { store.syncNow() }.disabled(store.syncFolderURL == nil); switch store.syncState { case .localOnly: Text(store.language == "en" ? "Choose an iCloud Drive folder to enable sync." : "选择 iCloud Drive 文件夹后即可启用同步。").foregroundStyle(.secondary); case .syncing: ProgressView(store.language == "en" ? "Syncing" : "正在同步"); case .synced(let date): Text((store.language == "en" ? "Synced " : "已同步 ") + date.formatted(date: .omitted, time: .shortened)).foregroundStyle(.green); case .failure(let error): Text(error).foregroundStyle(.red) } }; Section(store.language == "en" ? "Widget" : "小组件") { Text(store.language == "en" ? "Add Daily Widget from the Home Screen widget gallery. It shows today and opens a task in the app." : "在主屏幕小组件库中添加 Daily Widget；它会显示今天，并可打开对应任务。").foregroundStyle(.secondary) } }.navigationTitle(store.language == "en" ? "Settings" : "设置") } .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in switch result { case .success(let urls): if let url = urls.first { store.setSyncFolder(url) }; case .failure(let error): store.syncState = .failure(error.localizedDescription) } } }
}

private struct TaskEditor: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var task: PlannerTask
    init(task: PlannerTask) { _task = State(initialValue: task) }
    var body: some View { NavigationStack { Form { TextField(text("What needs doing?", "要完成什么？"), text: $task.title); Section(text("Schedule", "安排")) { Toggle(text("Schedule it", "排入时间轴"), isOn: Binding(get: { task.isScheduled }, set: { scheduled in if scheduled { task.date = store.dateKey; task.start = 9 * 60; task.end = 9 * 60 + 30 } else { task.date = nil; task.start = nil; task.end = nil } })); if task.isScheduled { DatePicker(text("Date", "日期"), selection: Binding(get: { Date.date(fromKey: task.date ?? store.dateKey) }, set: { task.date = $0.dayKey }), displayedComponents: .date); Stepper(text("Start: ", "开始：") + minuteText(task.start ?? 0), value: Binding(get: { task.start ?? 0 }, set: { task.start = $0; if (task.end ?? 0) <= $0 { task.end = $0 + 30 } }), in: 0...23 * 60 + 45, step: 15); Stepper(text("Duration: ", "时长：") + "\((task.end ?? 0) - (task.start ?? 0)) min", value: Binding(get: { max(15, (task.end ?? 0) - (task.start ?? 0)) }, set: { task.end = (task.start ?? 0) + $0 }), in: 15...24 * 60, step: 15); if (task.end ?? 0) > 24 * 60 { Text(text("Ends next day", "次日结束")).font(.caption).foregroundStyle(.indigo) } } }; Section(text("Details", "详情")) { Picker(text("Category", "分类"), selection: $task.category) { ForEach(["personal", "health", "home", "social", "learning", "errands"], id: \.self) { Text(categoryName($0)).tag($0) } }; Picker(text("Color", "颜色"), selection: colorSelection) { Text(text("Follow category", "跟随分类")).tag("auto"); Text(text("Indigo", "靛蓝")).tag("indigo"); Text(text("Sky", "天蓝")).tag("sky"); Text(text("Mint", "薄荷绿")).tag("mint"); Text(text("Amber", "琥珀黄")).tag("amber"); Text(text("Rose", "玫瑰粉")).tag("rose"); Text(text("Violet", "紫罗兰")).tag("violet"); Text(text("Coral", "珊瑚橙")).tag("coral") }; Picker(text("Repeat", "重复"), selection: $task.recurrence) { Text(text("Does not repeat", "不重复")).tag("none"); Text(text("Every day", "每天")).tag("daily"); Text(text("Weekdays", "工作日")).tag("weekdays"); Text(text("Every week", "每周")).tag("weekly") }; Toggle(text("Top task", "今日重点"), isOn: $task.focus); if task.isScheduled { Toggle(text("Remind me at the start time", "到点提醒我"), isOn: Binding(get: { store.hasReminder(task) }, set: { store.setReminder($0, for: task) })) }; TextField("URL", text: $task.url, axis: .vertical).textInputAutocapitalization(.never).keyboardType(.URL); TextField(text("Notes", "备注"), text: $task.notes, axis: .vertical) }; if !task.id.isEmpty { Button(role: .destructive) { store.delete(task); dismiss() } label: { Text(text("Delete task", "删除任务")) } } }.navigationTitle(task.title.isEmpty ? text("New task", "新任务") : text("Edit task", "编辑任务")).toolbar { ToolbarItem(placement: .cancellationAction) { Button(text("Cancel", "取消")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(text("Save", "保存")) { store.save(task); dismiss() }.disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } } } }
    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
    private var colorSelection: Binding<String> { Binding(get: { task.colorMode == "custom" ? (task.colorToken ?? "indigo") : "auto" }, set: { value in task.colorMode = value == "auto" ? "category" : "custom"; task.colorToken = value == "auto" ? nil : value }) }
    private func minuteText(_ minute: Int) -> String { String(format: "%02d:%02d", minute % 1440 / 60, minute % 60) }
    private func categoryName(_ value: String) -> String { store.language == "en" ? value.capitalized : ["personal":"个人", "health":"健康", "home":"生活", "social":"关系", "learning":"学习", "errands":"杂事"][value] ?? value }
}
