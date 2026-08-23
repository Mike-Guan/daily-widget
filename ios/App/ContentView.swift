import SwiftUI
import UniformTypeIdentifiers

private enum AppTab: Hashable { case today, inbox, topThree, review }

struct ContentView: View {
    @EnvironmentObject private var store: PlannerStore
    @State private var selectedTask: PlannerTask?
    @State private var showingEditor = false
    @State private var showingSettings = false
    @State private var pickingSyncFolder = false
    @State private var tab: AppTab = .today
    @State private var showSyncFolderPrompt = false

    var body: some View {
        TabView(selection: $tab) {
            todayPage.tabItem { Label(text("Today", "今天"), systemImage: "calendar") }.tag(AppTab.today)
            InboxPage(selectedTask: $selectedTask, showingEditor: $showingEditor).tabItem { Label(text("Inbox", "收集箱"), systemImage: "tray") }.badge(store.inbox.count).tag(AppTab.inbox)
            TopThreePage(selectedTask: $selectedTask, showingEditor: $showingEditor).tabItem { Label(text("Top 3", "今日重点"), systemImage: "sparkles") }.tag(AppTab.topThree)
            DailyReviewPage(selectedTask: $selectedTask, showingEditor: $showingEditor).tabItem { Label(text("Review", "日末回顾"), systemImage: "arrow.counterclockwise") }.tag(AppTab.review)
        }
        .preferredColorScheme(colorScheme)
        .sheet(isPresented: $showingEditor) { if let task = selectedTask { TaskEditor(task: task) } }
        .sheet(isPresented: $showingSettings) { SettingsView(pickingFolder: $pickingSyncFolder) }
        .fileImporter(isPresented: $pickingSyncFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { store.setSyncFolder(url) }
        }
        .alert(text("Choose a shared folder first", "请先选择共享文件夹"), isPresented: $showSyncFolderPrompt) {
            Button(text("Choose folder", "选择文件夹")) { pickingSyncFolder = true }
            Button(text("Cancel", "取消"), role: .cancel) {}
        } message: { Text(text("Select the Daily Widget folder in iCloud Drive to enable sync.", "请在 iCloud Drive 中选择 Daily Widget 文件夹以启用同步。")) }
    }

    private var todayPage: some View {
        NavigationStack {
            TimelineView(selectedTask: $selectedTask, showingEditor: $showingEditor)
                .tint(.indigo)
                .navigationTitle(text("Today", "今天"))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button { store.selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: store.selectedDate) ?? store.selectedDate } label: { Image(systemName: "chevron.left") } }
                    ToolbarItem(placement: .topBarTrailing) { Button { store.selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: store.selectedDate) ?? store.selectedDate } label: { Image(systemName: "chevron.right") } }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { store.setLanguage(store.language == "en" ? "zh" : "en") } label: { Text(store.language == "en" ? "中" : "EN").font(.caption.weight(.bold)) }.accessibilityLabel(text("Switch language", "切换语言"))
                        Button { store.setTheme(store.theme == "system" ? "light" : store.theme == "light" ? "dark" : "system") } label: { Image(systemName: store.theme == "dark" ? "moon.fill" : store.theme == "light" ? "sun.max.fill" : "circle.lefthalf.filled") }.accessibilityLabel(text("Change theme", "切换主题"))
                        Button { if !store.syncNow() { showSyncFolderPrompt = true } } label: { Image(systemName: store.syncFolderURL == nil ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath.circle.fill").foregroundStyle(store.syncFolderURL == nil ? Color.secondary : Color.green) }.accessibilityLabel(text("Sync", "同步"))
                    }
                    ToolbarItem(placement: .topBarTrailing) { Menu { Button { store.selectedDate = .now } label: { Label(text("Today", "今天"), systemImage: "calendar") }; Button { showingSettings = true } label: { Label(text("Settings", "设置"), systemImage: "gearshape") } } label: { Image(systemName: "ellipsis.circle") } }
                    ToolbarItem(placement: .bottomBar) { HStack { Text(store.selectedDate.formatted(date: .abbreviated, time: .omitted)).font(.footnote).foregroundStyle(.secondary); Spacer(); Button { selectedTask = PlannerTask.empty(date: store.dateKey, start: 9 * 60, end: 9 * 60 + 30, deviceID: UserDefaults.standard.string(forKey: "deviceID") ?? "iphone"); showingEditor = true } label: { Label(text("Add task", "添加任务"), systemImage: "plus") } } }
                }
        }
    }

    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
    private var colorScheme: ColorScheme? { store.theme == "system" ? nil : (store.theme == "dark" ? .dark : .light) }
}

private struct InboxPage: View {
    @EnvironmentObject private var store: PlannerStore
    @Binding var selectedTask: PlannerTask?
    @Binding var showingEditor: Bool

    var body: some View {
        NavigationStack {
            List {
                if store.inbox.isEmpty { ContentUnavailableView(text("Inbox is clear", "收集箱已清空"), systemImage: "tray") }
                ForEach(store.inbox) { task in
                    Button { selectedTask = task; showingEditor = true } label: { VStack(alignment: .leading, spacing: 4) { Text(task.title.isEmpty ? text("Untitled task", "未命名任务") : task.title).foregroundStyle(.primary); Text(categoryName(task.category)).font(.caption).foregroundStyle(.secondary) } }
                }
            }
            .navigationTitle(text("Inbox", "收集箱"))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { selectedTask = PlannerTask.empty(deviceID: UserDefaults.standard.string(forKey: "deviceID") ?? "iphone"); showingEditor = true } label: { Image(systemName: "plus") } } }
        }
    }

    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
    private func categoryName(_ value: String) -> String { store.language == "en" ? value.capitalized : ["personal":"个人", "health":"健康", "home":"生活", "social":"关系", "learning":"学习", "errands":"杂事"][value] ?? value }
}

private struct TopThreePage: View {
    @EnvironmentObject private var store: PlannerStore
    @Binding var selectedTask: PlannerTask?
    @Binding var showingEditor: Bool

    var body: some View {
        NavigationStack {
            List {
                Section(text("What matters today", "今天最重要的事")) {
                    let items = store.todayTasks.filter(\.isFocus)
                    if items.isEmpty { ContentUnavailableView(text("No Top 3 yet", "还没有设置今日重点"), systemImage: "sparkles") }
                    ForEach(items) { item in Button { selectedTask = item.task; showingEditor = true } label: { HStack { Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle").foregroundStyle(.indigo); VStack(alignment: .leading) { Text(item.title).foregroundStyle(.primary); Text("\(time(item.start)) – \(time(item.end))\(item.spansNextDay ? " (+1)" : "")").font(.caption).foregroundStyle(.secondary) } } } }
                }
            }
            .navigationTitle(text("Top 3", "今日重点"))
        }
    }
    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
    private func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute % 1440 / 60, minute % 60) }
}

private struct DailyReviewPage: View {
    @EnvironmentObject private var store: PlannerStore
    @Binding var selectedTask: PlannerTask?
    @Binding var showingEditor: Bool

    var body: some View {
        let tasks = store.todayTasks.sorted { ($0.isFocus ? 0 : 1, $0.start) < ($1.isFocus ? 0 : 1, $1.start) }
        let done = tasks.filter(\.isDone)
        let remaining = tasks.filter { !$0.isDone }
        return NavigationStack {
            List {
                Section { Text(encouragement(done: done.count, total: tasks.count)).foregroundStyle(.indigo) }
                Section(text("Progress", "进度")) { LabeledContent(text("Planned", "已计划"), value: "\(tasks.count)"); LabeledContent(text("Completed", "已完成"), value: "\(done.count)"); LabeledContent(text("Unfinished", "未完成"), value: "\(remaining.count)") }
                Section(text("Completed", "已完成")) { ForEach(done) { taskRow($0, unfinished: false) } }
                Section(text("Unfinished", "未完成")) { ForEach(remaining) { taskRow($0, unfinished: true) } }
            }
            .navigationTitle(text("Daily review", "日末回顾"))
        }
    }

    @ViewBuilder private func taskRow(_ occurrence: ScheduledOccurrence, unfinished: Bool) -> some View {
        HStack { VStack(alignment: .leading) { Text(occurrence.title).strikethrough(occurrence.isDone); Text("\(time(occurrence.start)) – \(time(occurrence.end))\(occurrence.isFocus ? " · ★" : "")").font(.caption).foregroundStyle(.secondary) }; Spacer(); if unfinished { Menu { Button(text("Move to tomorrow", "移到明天")) { var task = occurrence.task; task.date = Date.date(fromKey: store.dateKey).addingTimeInterval(24 * 60 * 60).dayKey; store.save(task) }; Button(text("Move to inbox", "放入收集箱")) { store.moveToInbox(occurrence.task) } } label: { Image(systemName: "ellipsis.circle") } } }
        .contentShape(Rectangle()).onTapGesture { selectedTask = occurrence.task; showingEditor = true }
    }

    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
    private func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute % 1440 / 60, minute % 60) }
    private func encouragement(done: Int, total: Int) -> String { if total == 0 { return text("Nothing was scheduled today. Leaving space is valid, too.", "今天没有已计划的任务；留一点空白也是一种安排。") }; if done == total { return text("Wonderful — every planned task is complete.", "太棒了，今天安排的事项已经全部完成。") }; return text("Nice work: \(done) task(s) complete. The rest can be arranged with care.", "做得很好，已经完成 \(done) 项；剩下的也可以从容安排。") }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: PlannerStore
    @Binding var pickingFolder: Bool
    var body: some View { NavigationStack { Form { Section(store.language == "en" ? "Language" : "语言") { Picker("Language", selection: Binding(get: { store.language }, set: store.setLanguage)) { Text("中文").tag("zh"); Text("English").tag("en") }.pickerStyle(.segmented) }; Section(store.language == "en" ? "Appearance" : "外观") { Picker(store.language == "en" ? "Theme" : "主题", selection: Binding(get: { store.theme }, set: store.setTheme)) { Text(store.language == "en" ? "System" : "跟随系统").tag("system"); Text(store.language == "en" ? "Light" : "浅色").tag("light"); Text(store.language == "en" ? "Dark" : "深色").tag("dark") }.pickerStyle(.segmented) }; Section(store.language == "en" ? "Sync" : "同步") { Button(store.syncFolderURL == nil ? (store.language == "en" ? "Choose shared folder" : "选择共享文件夹") : (store.language == "en" ? "Change shared folder" : "更换共享文件夹")) { pickingFolder = true }; Button(store.language == "en" ? "Sync now" : "立即同步") { store.syncNow() }; switch store.syncState { case .localOnly: Text(store.language == "en" ? "Choose an iCloud Drive folder to enable sync." : "选择 iCloud Drive 文件夹后即可启用同步。").foregroundStyle(.secondary); case .syncing: ProgressView(store.language == "en" ? "Syncing" : "正在同步"); case .synced(let date): Text((store.language == "en" ? "Synced " : "已同步 ") + date.formatted(date: .omitted, time: .shortened)).foregroundStyle(.green); case .failure(let error): Text(error).foregroundStyle(.red) } }; Section(store.language == "en" ? "Widget" : "小组件") { Text(store.language == "en" ? "Add Daily Widget from the Home Screen widget gallery. It shows today and opens a task in the app." : "在主屏幕小组件库中添加 Daily Widget；它会显示今天，并可打开对应任务。").foregroundStyle(.secondary) } }.navigationTitle(store.language == "en" ? "Settings" : "设置") } }
}

private struct TaskEditor: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var task: PlannerTask
    init(task: PlannerTask) { _task = State(initialValue: task) }
    var body: some View { NavigationStack { Form { TextField(text("What needs doing?", "要完成什么？"), text: $task.title); Section(text("Schedule", "安排")) { Toggle(text("Schedule it", "排入时间轴"), isOn: Binding(get: { task.isScheduled }, set: { scheduled in if scheduled { task.date = store.dateKey; task.start = 9 * 60; task.end = 9 * 60 + 30 } else { task.date = nil; task.start = nil; task.end = nil } })); if task.isScheduled { DatePicker(text("Date", "日期"), selection: Binding(get: { Date.date(fromKey: task.date ?? store.dateKey) }, set: { task.date = $0.dayKey }), displayedComponents: .date); Stepper(text("Start: ", "开始：") + minuteText(task.start ?? 0), value: Binding(get: { task.start ?? 0 }, set: { task.start = $0; if (task.end ?? 0) <= $0 { task.end = $0 + 30 } }), in: 0...23 * 60 + 45, step: 15); Stepper(text("Duration: ", "时长：") + "\((task.end ?? 0) - (task.start ?? 0)) min", value: Binding(get: { max(15, (task.end ?? 0) - (task.start ?? 0)) }, set: { task.end = (task.start ?? 0) + $0 }), in: 15...24 * 60, step: 15); if (task.end ?? 0) > 24 * 60 { Text(text("Ends next day", "次日结束")).font(.caption).foregroundStyle(.indigo) } } }; Section(text("Details", "详情")) { Picker(text("Category", "分类"), selection: $task.category) { ForEach(["personal", "health", "home", "social", "learning", "errands"], id: \.self) { Text(categoryName($0)).tag($0) } }; Picker(text("Repeat", "重复"), selection: $task.recurrence) { Text(text("Does not repeat", "不重复")).tag("none"); Text(text("Every day", "每天")).tag("daily"); Text(text("Weekdays", "工作日")).tag("weekdays"); Text(text("Every week", "每周")).tag("weekly") }; Toggle(text("Top task", "今日重点"), isOn: $task.focus); TextField("URL", text: $task.url, axis: .vertical).textInputAutocapitalization(.never).keyboardType(.URL); TextField(text("Notes", "备注"), text: $task.notes, axis: .vertical) }; if !task.id.isEmpty { Button(role: .destructive) { store.delete(task); dismiss() } label: { Text(text("Delete task", "删除任务")) } } }.navigationTitle(task.title.isEmpty ? text("New task", "新任务") : text("Edit task", "编辑任务")).toolbar { ToolbarItem(placement: .cancellationAction) { Button(text("Cancel", "取消")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(text("Save", "保存")) { store.save(task); dismiss() }.disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } } } }
    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
    private func minuteText(_ minute: Int) -> String { String(format: "%02d:%02d", minute % 1440 / 60, minute % 60) }
    private func categoryName(_ value: String) -> String { store.language == "en" ? value.capitalized : ["personal":"个人", "health":"健康", "home":"生活", "social":"关系", "learning":"学习", "errands":"杂事"][value] ?? value }
}
