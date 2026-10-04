import SwiftUI
import UIKit

struct TimelineView: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTask: PlannerTask?
    @Binding var showingEditor: Bool
    @Binding var showingQuickCreate: Bool
    @State private var draftStart: Int?
    @State private var draftEnd: Int?
    @State private var isCreateMode = false
    private let startHour = 0
    private let endHour = 24
    private let hourHeight: CGFloat = 68

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summary
                if isCreateMode { createModeBanner }
                ZStack(alignment: .topLeading) {
                    grid
                    currentTimeIndicator
                    tasks
                    if let draftStart, let draftEnd { draftBlock(start: draftStart, end: draftEnd) }
                    if isCreateMode { creationOverlay }
                }
                .frame(height: CGFloat(endHour - startHour) * hourHeight)
                .background(DWColors.surface(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.quaternary))
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 1.0, maximumDistance: 12) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    isCreateMode = true
                }
            }
            .padding()
        }
        .background(DWColors.background(colorScheme).ignoresSafeArea())
        .scrollDisabled(isCreateMode)
        .scrollIndicators(.hidden)
    }

    private var summary: some View {
        let tasks = store.todayTasks
        let done = tasks.filter(\.isDone).count
        return HStack(spacing: 12) {
            Label("\(done) / \(tasks.count)", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.indigo)
            Spacer()
            if let next = tasks.first(where: { !$0.isDone }) { Text(next.title).lineLimit(1).foregroundStyle(.secondary) }
        }
        .dailyWidgetCard()
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(startHour...endHour, id: \.self) { hour in
                HStack(alignment: .top, spacing: 9) {
                    Text(hour == endHour ? "24:00" : "\(hour):00").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing).offset(y: hour == startHour ? 6 : -7)
                    VStack(spacing: 0) { Divider(); Spacer(); Divider().overlay(.quaternary).opacity(0.55); Spacer() }
                }.frame(height: hour == endHour ? 0 : hourHeight)
            }
        }
    }

    private var tasks: some View {
        ForEach(store.todayTasks) { occurrence in
            TimelineTaskCard(occurrence: occurrence, pixelsPerMinute: hourHeight / 60, selectedTask: $selectedTask, showingEditor: $showingEditor)
                .frame(height: max(34, CGFloat(occurrence.end - occurrence.start) * hourHeight / 60), alignment: .top)
                .padding(.leading, 58).padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: y(for: occurrence.start))
        }
    }

    private var createModeBanner: some View {
        HStack { Image(systemName: "hand.draw.fill"); Text(store.language == "en" ? "Create mode · drag a time range" : "创建模式 · 拖动选择时间段").font(.subheadline.weight(.semibold)); Spacer(); Button(store.language == "en" ? "Cancel" : "取消") { cancelCreation() } }
            .foregroundStyle(.indigo).padding(.horizontal, 14).padding(.vertical, 10).background(.indigo.opacity(0.12), in: Capsule())
    }

    private var creationOverlay: some View {
        Color.indigo.opacity(0.035).contentShape(Rectangle()).gesture(createDragGesture)
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
                let task = PlannerTask.empty(date: store.dateKey, start: min(start, end - 15), end: max(start + 15, end), deviceID: UserDefaults.standard.string(forKey: "deviceID") ?? "iphone")
                draftStart = nil; draftEnd = nil; isCreateMode = false; selectedTask = task; showingQuickCreate = true
            }
    }

    @ViewBuilder private var currentTimeIndicator: some View {
        if store.dateKey == Date().dayKey {
            SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
                let components = Calendar.current.dateComponents([.hour, .minute], from: context.date)
                let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                HStack(spacing: 0) { Circle().frame(width: 8, height: 8); Rectangle().frame(height: 2) }.foregroundStyle(.red).offset(x: 54, y: y(for: minute) - 4)
            }
        }
    }

    private func cancelCreation() { draftStart = nil; draftEnd = nil; isCreateMode = false }

    private func draftBlock(start: Int, end: Int) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.indigo.opacity(0.25)).overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.indigo.opacity(0.5))).frame(height: max(34, CGFloat(end - start) * hourHeight / 60)).padding(.leading, 58).padding(.trailing, 10).frame(maxWidth: .infinity, alignment: .leading).offset(y: y(for: start))
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
        HStack(alignment: .top, spacing: 8) {
            Button { store.toggleDone(occurrence) } label: { Image(systemName: occurrence.isDone ? "checkmark.circle.fill" : "circle").foregroundStyle(occurrence.isDone ? .primary : .secondary) }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) { Text(occurrence.title.isEmpty ? (store.language == "en" ? "Untitled task" : "未命名任务") : occurrence.title).font(.subheadline.weight(.semibold)).strikethrough(occurrence.isDone).lineLimit(2); Text("\(time(occurrence.start)) – \(time(occurrence.end))\(occurrence.spansNextDay ? " (+1)" : occurrence.isContinuation ? " · ↳" : "")").font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(color.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottom) { Capsule().fill(color.opacity(0.85)).frame(width: 30, height: 4).padding(4).contentShape(Rectangle()).gesture(resizeGesture) }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { selectedTask = occurrence.task; showingEditor = true }
        .gesture(moveGesture)
    }

    private var color: Color { DWColors.taskColor(mode: occurrence.task.colorMode, token: occurrence.task.colorToken, category: occurrence.category) }
    private func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    private var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.25).sequenced(before: DragGesture())
            .onChanged { value in guard !occurrence.isContinuation, case .second(true, let drag?) = value else { return }; let offset = Int((drag.translation.height / pixelsPerMinute / 15).rounded()) * 15; movedStart = max(0, min(24 * 60 - 15, occurrence.fullStart + offset)) }
            .onEnded { _ in if let start = movedStart { store.move(occurrence, start: start, end: start + (occurrence.fullEnd - occurrence.fullStart)); movedStart = nil } }
    }
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2).onChanged { value in let offset = Int((value.translation.height / pixelsPerMinute / 15).rounded()) * 15; resizedEnd = max(occurrence.start + 15, min(24 * 60, occurrence.end + offset)) }.onEnded { _ in if let end = resizedEnd { store.move(occurrence, start: occurrence.isContinuation ? occurrence.fullStart : occurrence.start, end: occurrence.isContinuation ? 24 * 60 + end : end); resizedEnd = nil } }
    }
}
