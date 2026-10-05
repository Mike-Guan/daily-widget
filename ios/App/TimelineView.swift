import SwiftUI
import UIKit

struct TimelineView<Header: View>: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTask: PlannerTask?
    @Binding var showingEditor: Bool
    @Binding var showingQuickCreate: Bool
    @ViewBuilder var header: () -> Header
    @State private var draftStart: Int?
    @State private var draftEnd: Int?
    @State private var isCreateMode = false
    private let startHour = 0
    private let endHour = 24
    private let hourHeight: CGFloat = 68

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DWSpacing.md) {
                header()
                NextUpCard()
                if isCreateMode { createModeBanner }
                ZStack(alignment: .topLeading) {
                    grid
                    currentTimeIndicator
                    tasks
                    if let draftStart, let draftEnd { draftBlock(start: draftStart, end: draftEnd) }
                    if isCreateMode { creationOverlay }
                }
                .frame(height: CGFloat(endHour - startHour) * hourHeight)
                .padding(.vertical, DWSpacing.sm)
                .background(DWColors.surface(colorScheme), in: RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous).stroke(DWColors.line.opacity(colorScheme == .dark ? 0.6 : 1)))
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 1.0, maximumDistance: 12) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    isCreateMode = true
                }
            }
            .padding(.horizontal, DWSpacing.md).padding(.top, DWSpacing.xs).padding(.bottom, DWSpacing.lg)
        }
        .background(DWColors.background(colorScheme).ignoresSafeArea())
        .scrollDisabled(isCreateMode)
        .scrollIndicators(.hidden)
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(startHour...endHour, id: \.self) { hour in
                HStack(alignment: .top, spacing: 9) {
                    Text(String(format: "%02d:00", hour)).font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(DWColors.muted).frame(width: 40, alignment: .trailing).offset(y: -6)
                    VStack(spacing: 0) { Rectangle().fill(DWColors.line).frame(height: 1); Spacer(); Rectangle().fill(DWColors.line.opacity(0.45)).frame(height: 1); Spacer() }
                }.frame(height: hour == endHour ? 0 : hourHeight)
            }
        }
    }

    private var tasks: some View {
        ForEach(store.todayTasks) { occurrence in
            TimelineTaskCard(occurrence: occurrence, pixelsPerMinute: hourHeight / 60, selectedTask: $selectedTask, showingEditor: $showingEditor)
                .frame(height: max(34, CGFloat(occurrence.end - occurrence.start) * hourHeight / 60), alignment: .top)
                .padding(.leading, 53).padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: y(for: occurrence.start))
        }
    }

    private var createModeBanner: some View {
        HStack { Image(systemName: "hand.draw.fill"); Text(store.language == "en" ? "Create mode · drag a time range" : "创建模式 · 拖动选择时间段").font(.subheadline.weight(.semibold)); Spacer(); Button(store.language == "en" ? "Cancel" : "取消") { cancelCreation() } }
            .foregroundStyle(DWColors.accent).padding(.horizontal, 14).frame(minHeight: 44).background(DWColors.accentSoft, in: Capsule())
    }

    private var creationOverlay: some View {
        DWColors.accent.opacity(0.035).contentShape(Rectangle()).gesture(createDragGesture)
    }

    private var createDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                let start = snap(minute(at: value.startLocation.y))
                let end = max(start + 15, snap(minute(at: value.location.y)))
                draftStart = min(start, end - 15); draftEnd = max(start + 15, end)
            }
            .onEnded { value in
                let start = snap(minute(at: value.startLocation.y)); let end = max(start + 15, snap(minute(at: value.location.y)))
                let task = store.newTask(date: store.dateKey, start: min(start, end - 15), end: max(start + 15, end))
                draftStart = nil; draftEnd = nil; isCreateMode = false; selectedTask = task; showingQuickCreate = true
            }
    }

    @ViewBuilder private var currentTimeIndicator: some View {
        if store.dateKey == Date().dayKey {
            SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
                let components = Calendar.current.dateComponents([.hour, .minute], from: context.date)
                let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                HStack(spacing: 0) { Circle().frame(width: 8, height: 8); Rectangle().frame(height: 1.5) }.foregroundStyle(DWColors.now).offset(x: 45, y: y(for: minute) - 4).accessibilityHidden(true)
            }
        }
    }

    private func cancelCreation() { draftStart = nil; draftEnd = nil; isCreateMode = false }

    private func draftBlock(start: Int, end: Int) -> some View {
        RoundedRectangle(cornerRadius: DWRadius.block, style: .continuous).fill(DWColors.accent.opacity(0.22)).overlay(RoundedRectangle(cornerRadius: DWRadius.block, style: .continuous).stroke(DWColors.accent.opacity(0.5))).frame(height: max(34, CGFloat(end - start) * hourHeight / 60)).padding(.leading, 53).padding(.trailing, 10).frame(maxWidth: .infinity, alignment: .leading).offset(y: y(for: start))
    }
    private func y(for minute: Int) -> CGFloat { CGFloat(minute - startHour * 60) * hourHeight / 60 }
    private func minute(at y: CGFloat) -> Int { min(endHour * 60, max(startHour * 60, Int(y / hourHeight * 60) + startHour * 60)) }
    private func snap(_ minute: Int) -> Int { Int((Double(minute) / 15).rounded()) * 15 }
}

private struct TimelineTaskCard: View {
    @EnvironmentObject private var store: PlannerStore
    let occurrence: ScheduledOccurrence
    let pixelsPerMinute: CGFloat
    @Binding var selectedTask: PlannerTask?
    @Binding var showingEditor: Bool
    @State private var originalStart: Int?
    @State private var movedStart: Int?
    @State private var resizedEnd: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            // Blocks of 30 minutes or less only have room for one line.
            let layout = compact ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
            layout {
                Text(occurrence.title.isEmpty ? (store.language == "en" ? "Untitled task" : "未命名任务") : occurrence.title).font(DWFont.headline).foregroundStyle(DWColors.text).strikethrough(occurrence.isDone).lineLimit(compact ? 1 : 2)
                HStack(spacing: 4) {
                    Text(occurrence.isContinuation ? "– \(DWFormat.time(occurrence.end))" : DWFormat.time(occurrence.start))
                    if occurrence.spansNextDay { Image(systemName: "moon.stars").accessibilityLabel(store.language == "en" ? "Ends next day" : "次日结束") }
                    if store.hasReminder(occurrence.task) { Image(systemName: "bell.fill").accessibilityLabel(store.language == "en" ? "Reminder on" : "到点提醒") }
                    if occurrence.isFocus { Image(systemName: "star.fill").accessibilityLabel(store.language == "en" ? "Top task" : "今日重点") }
                }
                .font(DWFont.caption).foregroundStyle(DWColors.muted)
            }
            .padding(.leading, DWSpacing.xs).padding(.vertical, 5)
            Spacer(minLength: 0)
            Button { store.toggleDone(occurrence) } label: { Image(systemName: occurrence.isDone ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(occurrence.isDone ? color : DWColors.muted).frame(width: 44, height: 34).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityLabel(occurrence.isDone ? (store.language == "en" ? "Mark not done" : "标为未完成") : (store.language == "en" ? "Mark done" : "标为完成"))
        }
        .background(color.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: DWRadius.block, style: .continuous))
        .opacity(occurrence.isDone ? 0.5 : 1)
        .overlay(alignment: .bottom) { Capsule().fill(color.opacity(0.85)).frame(width: 30, height: 4).padding(4).contentShape(Rectangle()).gesture(resizeGesture) }
        .contentShape(RoundedRectangle(cornerRadius: DWRadius.block, style: .continuous))
        .onTapGesture { selectedTask = occurrence.task; showingEditor = true }
        .gesture(moveGesture)
    }

    private var compact: Bool { occurrence.end - occurrence.start <= 30 }
    private var color: Color { DWColors.taskColor(mode: occurrence.task.colorMode, token: occurrence.task.colorToken, category: occurrence.category) }
    private var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.25).sequenced(before: DragGesture())
            .onChanged { value in guard !occurrence.isContinuation, case .second(true, let drag?) = value else { return }; let offset = Int((drag.translation.height / pixelsPerMinute / 15).rounded()) * 15; movedStart = max(0, min(24 * 60 - 15, occurrence.fullStart + offset)) }
            .onEnded { _ in if let start = movedStart { store.move(occurrence, start: start, end: start + (occurrence.fullEnd - occurrence.fullStart)); movedStart = nil } }
    }
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2).onChanged { value in let offset = Int((value.translation.height / pixelsPerMinute / 15).rounded()) * 15; resizedEnd = max(occurrence.start + 15, min(24 * 60, occurrence.end + offset)) }.onEnded { _ in if let end = resizedEnd { store.move(occurrence, start: occurrence.isContinuation ? occurrence.fullStart : occurrence.start, end: occurrence.isContinuation ? 24 * 60 + end : end); resizedEnd = nil } }
    }
}

/// Progress ring plus the next thing to do, with a live "in 40 min" countdown.
private struct NextUpCard: View {
    @EnvironmentObject private var store: PlannerStore

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
            let tasks = store.todayTasks
            let done = tasks.filter(\.isDone).count
            let isToday = store.dateKey == Date().dayKey
            let nowMinute = Calendar.current.component(.hour, from: context.date) * 60 + Calendar.current.component(.minute, from: context.date)
            let pending = tasks.filter { !$0.isDone }
            let next = isToday ? (pending.first { $0.end > nowMinute } ?? pending.first) : pending.first
            HStack(spacing: DWSpacing.md) {
                DWProgressRing(completed: done, total: tasks.count)
                if let next {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label(for: next, nowMinute: nowMinute, isToday: isToday)).font(DWFont.label).foregroundStyle(DWColors.accent)
                        Text(next.title.isEmpty ? text("Untitled task", "未命名任务") : next.title).font(DWFont.headline).foregroundStyle(DWColors.text).lineLimit(2)
                        Text(detail(for: next, nowMinute: nowMinute, isToday: isToday)).font(DWFont.caption).foregroundStyle(DWColors.muted)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tasks.isEmpty ? text("Nothing planned", "今天没有安排") : text("All done for today", "今天没有安排了")).font(DWFont.headline).foregroundStyle(DWColors.text)
                        Text(tasks.isEmpty ? text("Press and hold the timeline, or tap the microphone.", "长按时间轴画一段，或点右下角的麦克风。") : text("Leave some room for what matters.", "为重要的事留一点空间。")).font(DWFont.body).foregroundStyle(DWColors.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .dailyWidgetCard()
            .accessibilityElement(children: .combine)
        }
    }

    private func label(for item: ScheduledOccurrence, nowMinute: Int, isToday: Bool) -> String {
        isToday && item.start <= nowMinute && item.end > nowMinute ? text("Now", "正在进行") : text("Next up", "下一件")
    }

    private func detail(for item: ScheduledOccurrence, nowMinute: Int, isToday: Bool) -> String {
        let start = DWFormat.time(item.start)
        guard isToday else { return "\(start) – \(DWFormat.time(item.end))" }
        if item.start > nowMinute { return "\(start) · " + text("in \(duration(item.start - nowMinute))", "还有 \(duration(item.start - nowMinute))") }
        if item.end > nowMinute { return "\(start) · " + text("\(duration(item.end - nowMinute)) left", "还剩 \(duration(item.end - nowMinute))") }
        return "\(start) · " + text("overdue", "已过时间")
    }

    private func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return text("\(rest) min", "\(rest) 分钟") }
        if rest == 0 { return text("\(hours) h", "\(hours) 小时") }
        return text("\(hours) h \(rest) min", "\(hours) 小时 \(rest) 分钟")
    }

    private func text(_ english: String, _ chinese: String) -> String { store.language == "en" ? english : chinese }
}
