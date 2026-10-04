import SwiftUI
import UniformTypeIdentifiers

private enum AppTab: Hashable { case today, inbox, topThree, review }

struct ContentView: View {
    @EnvironmentObject private var store: PlannerStore
    @State private var selectedTask: PlannerTask?
    @State private var showingEditor = false
    @State private var showingQuickCreate = false
    @State private var showingSettings = false
    @State private var pickingSyncFolder = false
    @State private var tab: AppTab = .today
    @State private var showSyncFolderPrompt = false
    @State private var showingCalendar = false

    var body: some View {
        TabView(selection: $tab) {
            todayPage.tabItem { Label(text("Today", "今天"), systemImage: "calendar") }.tag(AppTab.today)
            InboxPage(selectedTask: $selectedTask, showingEditor: $showingEditor).tabItem { Label(text("Inbox", "收集箱"), systemImage: "tray") }.badge(store.inbox.count).tag(AppTab.inbox)
            TopThreePage(selectedTask: $selectedTask, showingEditor: $showingEditor).tabItem { Label(text("Top 3", "今日重点"), systemImage: "sparkles") }.tag(AppTab.topThree)
            DailyReviewPage(selectedTask: $selectedTask, showingEditor: $showingEditor).tabItem { Label(text("Review", "日末回顾"), systemImage: "arrow.counterclockwise") }.tag(AppTab.review)
        }
        .preferredColorScheme(colorScheme)
        .sheet(isPresented: $showingEditor) { if let task = selectedTask { TaskEditor(task: task) } }
        .sheet(isPresented: $showingQuickCreate) { if let task = selectedTask { QuickCreateSheet(task: task, selectedTask: $selectedTask, showingEditor: $showingEditor) } }
        .sheet(isPresented: $showingSettings) { SettingsView() }
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

    private var todayPage: some View {
        NavigationStack {
            TimelineView(selectedTask: $selectedTask, showingEditor: $showingEditor, showingQuickCreate: $showingQuickCreate)
                .tint(.indigo)
                .navigationTitle(selectedDateTitle)
                .safeAreaInset(edge: .top, spacing: 0) { syncStatusBanner }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button { showingCalendar = true } label: { Image(systemName: "calendar") }.accessibilityLabel(text("Choose date", "选择日期")) }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { store.setLanguage(store.language == "en" ? "zh" : "en") } label: { Text(store.language == "en" ? "中" : "EN").font(.caption.weight(.bold)) }.accessibilityLabel(text("Switch language", "切换语言"))
                        Button { store.setTheme(store.theme == "system" ? "light" : store.theme == "light" ? "dark" : "system") } label: { Image(systemName: store.theme == "dark" ? "moon.fill" : store.theme == "light" ? "sun.max.fill" : "circle.lefthalf.filled") }.accessibilityLabel(text("Change theme", "切换主题"))
                        Button { if !store.syncNow() { showSyncFolderPrompt = true } } label: {
                            if isSyncing { ProgressView().controlSize(.small) }
                            else { Image(systemName: store.syncFolderURL == nil ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath.circle.fill").foregroundStyle(store.syncFolderURL == nil ? Color.secondary : Color.green) }
                        }
                        .disabled(isSyncing)
                        .accessibilityLabel(text("Sync", "同步"))
                    }
                    ToolbarItem(placement: .topBarTrailing) { Menu { Button { store.selectedDate = .now } label: { Label(text("Today", "今天"), systemImage: "calendar") }; Button { showingSettings = true } label: { Label(text("Settings", "设置"), systemImage: "gearshape") } } label: { Image(systemName: "ellipsis.circle") } }
                }
        }
    }

    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
    private var colorScheme: ColorScheme? { store.theme == "system" ? nil : (store.theme == "dark" ? .dark : .light) }
    private var selectedDateTitle: String { store.dateKey == Date().dayKey ? text("Today", "今天") : store.selectedDate.formatted(.dateTime.month(.abbreviated).day().weekday(.wide)) }
    private var isSyncing: Bool { store.syncState == .syncing }

    @ViewBuilder private var syncStatusBanner: some View {
        switch store.syncState {
        case .syncing:
            Label { Text(text("Syncing…", "正在同步…")) } icon: { ProgressView().controlSize(.small) }
                .foregroundStyle(.secondary)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .padding(.vertical, 6)
        case .synced(let date):
            Label(text("Synced " + date.formatted(date: .omitted, time: .shortened), "已同步 " + date.formatted(date: .omitted, time: .shortened)), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption.weight(.semibold))
                .padding(.vertical, 6)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(2)
                .padding(.horizontal, 16).padding(.vertical, 6)
        case .localOnly:
            EmptyView()
        }
    }
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
        HStack { VStack(alignment: .leading) { Text(occurrence.title).strikethrough(occurrence.isDone); Text("\(time(occurrence.start)) – \(time(occurrence.end))\(occurrence.isFocus ? " · ★" : "")").font(.caption).foregroundStyle(.secondary) }; Spacer(); if unfinished { Menu { Button(text("Move to inbox", "放入收集箱")) { store.moveToInbox(occurrence.task) } } label: { Image(systemName: "ellipsis.circle") } } }
        .contentShape(Rectangle()).onTapGesture { selectedTask = occurrence.task; showingEditor = true }
    }

    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
    private func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute % 1440 / 60, minute % 60) }
    private func encouragement(done: Int, total: Int) -> String { if total == 0 { return text("Nothing was scheduled today. Leaving space is valid, too.", "今天没有已计划的任务；留一点空白也是一种安排。") }; if done == total { return text("Wonderful — every planned task is complete.", "太棒了，今天安排的事项已经全部完成。") }; return text("Nice work: \(done) task(s) complete. The rest can be arranged with care.", "做得很好，已经完成 \(done) 项；剩下的也可以从容安排。") }
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
    var body: some View { NavigationStack { Form { TextField(text("What needs doing?", "要完成什么？"), text: $task.title); Section(text("Schedule", "安排")) { Toggle(text("Schedule it", "排入时间轴"), isOn: Binding(get: { task.isScheduled }, set: { scheduled in if scheduled { task.date = store.dateKey; task.start = 9 * 60; task.end = 9 * 60 + 30 } else { task.date = nil; task.start = nil; task.end = nil } })); if task.isScheduled { DatePicker(text("Date", "日期"), selection: Binding(get: { Date.date(fromKey: task.date ?? store.dateKey) }, set: { task.date = $0.dayKey }), displayedComponents: .date); Stepper(text("Start: ", "开始：") + minuteText(task.start ?? 0), value: Binding(get: { task.start ?? 0 }, set: { task.start = $0; if (task.end ?? 0) <= $0 { task.end = $0 + 30 } }), in: 0...23 * 60 + 45, step: 15); Stepper(text("Duration: ", "时长：") + "\((task.end ?? 0) - (task.start ?? 0)) min", value: Binding(get: { max(15, (task.end ?? 0) - (task.start ?? 0)) }, set: { task.end = (task.start ?? 0) + $0 }), in: 15...24 * 60, step: 15); if (task.end ?? 0) > 24 * 60 { Text(text("Ends next day", "次日结束")).font(.caption).foregroundStyle(.indigo) } } }; Section(text("Details", "详情")) { Picker(text("Category", "分类"), selection: $task.category) { ForEach(["personal", "health", "home", "social", "learning", "errands"], id: \.self) { Text(categoryName($0)).tag($0) } }; Picker(text("Color", "颜色"), selection: colorSelection) { Text(text("Follow category", "跟随分类")).tag("auto"); Text(text("Indigo", "靛蓝")).tag("indigo"); Text(text("Sky", "天蓝")).tag("sky"); Text(text("Mint", "薄荷绿")).tag("mint"); Text(text("Amber", "琥珀黄")).tag("amber"); Text(text("Rose", "玫瑰粉")).tag("rose"); Text(text("Violet", "紫罗兰")).tag("violet"); Text(text("Coral", "珊瑚橙")).tag("coral") }; Picker(text("Repeat", "重复"), selection: $task.recurrence) { Text(text("Does not repeat", "不重复")).tag("none"); Text(text("Every day", "每天")).tag("daily"); Text(text("Weekdays", "工作日")).tag("weekdays"); Text(text("Every week", "每周")).tag("weekly") }; Toggle(text("Top task", "今日重点"), isOn: $task.focus); TextField("URL", text: $task.url, axis: .vertical).textInputAutocapitalization(.never).keyboardType(.URL); TextField(text("Notes", "备注"), text: $task.notes, axis: .vertical) }; if !task.id.isEmpty { Button(role: .destructive) { store.delete(task); dismiss() } label: { Text(text("Delete task", "删除任务")) } } }.navigationTitle(task.title.isEmpty ? text("New task", "新任务") : text("Edit task", "编辑任务")).toolbar { ToolbarItem(placement: .cancellationAction) { Button(text("Cancel", "取消")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(text("Save", "保存")) { store.save(task); dismiss() }.disabled(task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } } } }
    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
    private var colorSelection: Binding<String> { Binding(get: { task.colorMode == "custom" ? (task.colorToken ?? "indigo") : "auto" }, set: { value in task.colorMode = value == "auto" ? "category" : "custom"; task.colorToken = value == "auto" ? nil : value }) }
    private func minuteText(_ minute: Int) -> String { String(format: "%02d:%02d", minute % 1440 / 60, minute % 60) }
    private func categoryName(_ value: String) -> String { store.language == "en" ? value.capitalized : ["personal":"个人", "health":"健康", "home":"生活", "social":"关系", "learning":"学习", "errands":"杂事"][value] ?? value }
}
