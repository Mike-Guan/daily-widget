import SwiftUI
import UIKit

struct TimelineView<Header: View>: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedTask: PlannerTask?
    @Binding var showingEditor: Bool
    @Binding var showingQuickCreate: Bool
    @ViewBuilder var header: () -> Header
    /// The block being created, moved or resized, with its live times.
    @State private var drag: TimelineDrag?
    /// The task showing its resize handles, by occurrence id.
    @State private var selectedID: String?
    /// Global y of the top of the 24 hour grid, and the visible part of the scroll view.
    @State private var gridTop: CGFloat = 0
    @State private var viewport: CGRect = .zero
    /// Global y of the finger during a drag, so the block keeps up while the timeline scrolls.
    @State private var fingerY: CGFloat?
    /// -1 scrolls up, 1 scrolls down, 0 stops.
    @State private var autoScroll = 0
    @GestureState private var isDragging = false
    @GestureState private var pressed: String? = nil
    private let hourHeight: CGFloat = 68
    private static var slots: Range<Int> { 0..<(TimeDrag.dayEnd / TimeDrag.step) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DWSpacing.md) {
                    header()
                    NextUpCard()
                    ZStack(alignment: .topLeading) {
                        grid
                        emptySlots
                        pressHint
                        currentTimeIndicator
                        tasks
                        if let drag, case .create = drag.kind { draftBlock(drag) }
                        handles
                        if let drag { timeBubble(drag) }
                    }
                    .frame(height: 24 * hourHeight)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { gridTop = $0 }
                    .padding(.vertical, DWSpacing.sm)
                    .background(DWColors.surface(colorScheme), in: RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous).stroke(DWColors.line.opacity(colorScheme == .dark ? 0.6 : 1)))
                }
                .padding(.horizontal, DWSpacing.md).padding(.top, DWSpacing.xs).padding(.bottom, DWSpacing.lg)
            }
            .onGeometryChange(for: CGRect.self) { geometry in
                let frame = geometry.frame(in: .global), insets = geometry.safeAreaInsets
                return CGRect(x: frame.minX, y: frame.minY + insets.top, width: frame.width, height: frame.height - insets.top - insets.bottom)
            } action: { viewport = $0 }
            .task(id: autoScroll) {
                while autoScroll != 0, !Task.isCancelled {
                    scrollStep(proxy)
                    try? await Task.sleep(for: .milliseconds(90))
                }
            }
        }
        .background(DWColors.background(colorScheme).ignoresSafeArea())
        .scrollDisabled(drag != nil)
        .scrollIndicators(.hidden)
        .onChange(of: gridTop) { if let fingerY, drag != nil { follow(globalY: fingerY) } }
        .onChange(of: store.dateKey) { selectedID = nil }
        .onChange(of: isDragging) { _, active in
            // A gesture that was cancelled (a call, the app going away) ends without onEnded.
            guard !active else { return }
            DispatchQueue.main.async { if drag != nil { endDrag(commit: false) } }
        }
    }

    private var grid: some View {
        VStack(spacing: 0) {
            ForEach(0...24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 9) {
                    Text(String(format: "%02d:00", hour)).font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(DWColors.muted).frame(width: 40, alignment: .trailing).offset(y: -6)
                    VStack(spacing: 0) { Rectangle().fill(DWColors.line).frame(height: 1); Spacer(); Rectangle().fill(DWColors.line.opacity(0.45)).frame(height: 1); Spacer() }
                }.frame(height: hour == 24 ? 0 : hourHeight)
            }
        }
    }

    /// One row per 15 minutes. Holding a row starts a new block there; the rows are also the
    /// scroll targets for auto scrolling.
    private var emptySlots: some View {
        VStack(spacing: 0) {
            ForEach(Self.slots, id: \.self) { slot in
                Color.clear
                    .frame(height: hourHeight / 4)
                    .contentShape(Rectangle())
                    .id(slotID(slot))
                    .onTapGesture { withAnimation(animation) { selectedID = nil } }
                    .gesture(holdGesture(key: slotID(slot)) { beginCreate(at: slot * TimeDrag.step) })
                    .accessibilityHidden(true)
            }
        }
    }

    /// While a finger rests on empty space, a 30 minute outline tightens around it.
    @ViewBuilder private var pressHint: some View {
        if let pressed, pressed.hasPrefix("slot-"), let slot = Int(pressed.dropFirst(5)) {
            block(start: slot * TimeDrag.step, end: slot * TimeDrag.step + TimeDrag.newLength) {
                RoundedRectangle(cornerRadius: DWRadius.block, style: .continuous).stroke(DWColors.accent.opacity(0.7), lineWidth: 2)
            }
            .transition(reduceMotion ? .opacity : .scale(scale: 1.15).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    private var tasks: some View {
        ForEach(store.todayTasks) { occurrence in
            let moving = drag?.occurrence?.id == occurrence.id
            let lifted = moving && drag?.kind == .move
            let times = moving ? (drag?.start ?? occurrence.start, min(drag?.end ?? occurrence.end, TimeDrag.dayEnd)) : (occurrence.start, occurrence.end)
            if lifted { ghost(occurrence) }
            TimelineTaskCard(occurrence: occurrence, start: times.0, isSelected: selectedID == occurrence.id, isPressed: pressed == occurrence.id)
                .frame(height: height(times.0, times.1), alignment: .top)
                .contentShape(RoundedRectangle(cornerRadius: DWRadius.block, style: .continuous))
                .onTapGesture { tap(occurrence) }
                .gesture(holdGesture(key: occurrence.id) { beginMove(occurrence) })
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { open(occurrence) }
                .scaleEffect(lifted ? 1.03 : 1)
                .shadow(color: .black.opacity(lifted ? 0.18 : 0), radius: lifted ? 12 : 0, y: lifted ? 6 : 0)
                .padding(.leading, 53).padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: y(for: times.0))
                .zIndex(lifted ? 3 : selectedID == occurrence.id ? 2 : 1)
                .animation(reduceMotion ? nil : .interactiveSpring(response: 0.18, dampingFraction: 0.85), value: times.0)
        }
    }

    /// The dashed outline left where a lifted task started.
    private func ghost(_ occurrence: ScheduledOccurrence) -> some View {
        block(start: occurrence.start, end: occurrence.end) {
            RoundedRectangle(cornerRadius: DWRadius.block, style: .continuous).stroke(color(of: occurrence).opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        }
        .allowsHitTesting(false)
    }

    /// Top and bottom handles of the selected task: a small bar with a 44 point target.
    @ViewBuilder private var handles: some View {
        if drag?.kind != .move, let occurrence = store.todayTasks.first(where: { $0.id == selectedID }) {
            let start = drag?.occurrence?.id == occurrence.id ? drag?.start ?? occurrence.start : occurrence.start
            let end = drag?.occurrence?.id == occurrence.id ? drag?.end ?? occurrence.end : occurrence.end
            handle(occurrence, top: true).offset(y: y(for: start) - 22)
            if !occurrence.spansNextDay { handle(occurrence, top: false).offset(y: y(for: start) + height(start, min(end, TimeDrag.dayEnd)) - 22) }
        }
    }

    private func handle(_ occurrence: ScheduledOccurrence, top: Bool) -> some View {
        Capsule().fill(color(of: occurrence)).frame(width: 36, height: 5)
            .frame(width: 88, height: 44)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { value in
                        if drag == nil { beginResize(occurrence, top: top) }
                        if drag?.originY == nil { drag?.originY = value.startLocation.y - gridTop }
                        follow(globalY: value.location.y)
                    }
                    .onEnded { _ in endDrag(commit: true) }
            )
            .accessibilityHidden(true)
            .padding(.leading, 53).padding(.trailing, 10)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func draftBlock(_ drag: TimelineDrag) -> some View {
        block(start: drag.start, end: drag.end) {
            RoundedRectangle(cornerRadius: DWRadius.block, style: .continuous).fill(DWColors.accent.opacity(0.22))
                .overlay(RoundedRectangle(cornerRadius: DWRadius.block, style: .continuous).stroke(DWColors.accent, lineWidth: 1.5))
                .overlay(alignment: .topLeading) { Text(range(drag.start, drag.end)).font(DWFont.caption.weight(.bold)).foregroundStyle(DWColors.accent).padding(.horizontal, DWSpacing.xs).padding(.vertical, 5) }
        }
        .allowsHitTesting(false)
    }

    /// The live time range, above the block on the right.
    private func timeBubble(_ drag: TimelineDrag) -> some View {
        Text(range(drag.start, drag.end))
            .font(DWFont.caption.weight(.bold)).foregroundStyle(DWColors.surface(colorScheme))
            .padding(.horizontal, DWSpacing.xs).padding(.vertical, DWSpacing.xxs)
            .background(DWColors.text, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 14)
            .offset(y: max(0, y(for: drag.start) - 26))
            .zIndex(4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func block<Content: View>(start: Int, end: Int, @ViewBuilder content: () -> Content) -> some View {
        content().frame(height: height(start, min(end, TimeDrag.dayEnd)))
            .padding(.leading, 53).padding(.trailing, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(y: y(for: start))
    }

    @ViewBuilder private var currentTimeIndicator: some View {
        if store.dateKey == Date().dayKey {
            SwiftUI.TimelineView(.periodic(from: .now, by: 60)) { context in
                let components = Calendar.current.dateComponents([.hour, .minute], from: context.date)
                let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                HStack(spacing: 0) { Circle().frame(width: 8, height: 8); Rectangle().frame(height: 1.5) }.foregroundStyle(DWColors.now).offset(x: 45, y: y(for: minute) - 4).accessibilityHidden(true)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: Gestures

    /// Hold still for 0.4 s, then drag. Moving before that scrolls the timeline instead.
    private func holdGesture(key: String, begin: @escaping () -> Void) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4, maximumDistance: 8)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($pressed) { value, state, transaction in
                guard case .first(true) = value else { return }
                state = key
                transaction.animation = reduceMotion ? nil : .easeOut(duration: 0.4)
            }
            .updating($isDragging) { value, state, _ in if case .second(true, _) = value { state = true } }
            .onChanged { value in
                guard case .second(true, let dragValue) = value else { return }
                if drag == nil { begin() }
                guard let dragValue else { return }
                if drag?.originY == nil { drag?.originY = dragValue.startLocation.y - gridTop }
                follow(globalY: dragValue.location.y)
            }
            .onEnded { _ in endDrag(commit: true) }
    }

    private func beginCreate(at minute: Int) {
        let times = TimeDrag.create(anchor: minute, finger: Double(minute))
        start(TimelineDrag(kind: .create(anchor: times.start), occurrence: nil, start: times.start, end: times.end))
    }

    private func beginMove(_ occurrence: ScheduledOccurrence) {
        // The part of a task that runs on past midnight is moved from the day it starts.
        guard !occurrence.isContinuation else { return }
        start(TimelineDrag(kind: .move, occurrence: occurrence, start: occurrence.fullStart, end: occurrence.fullEnd))
    }

    private func beginResize(_ occurrence: ScheduledOccurrence, top: Bool) {
        drag = TimelineDrag(kind: top ? .resizeTop : .resizeBottom, occurrence: occurrence, start: occurrence.fullStart, end: occurrence.fullEnd)
    }

    private func start(_ newDrag: TimelineDrag) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(animation) { selectedID = nil; drag = newDrag }
    }

    /// Recomputes the block from where the finger is now on the grid.
    private func follow(globalY: CGFloat) {
        guard var current = drag else { return }
        fingerY = globalY
        let fingerY = globalY - gridTop
        let finger = Double(fingerY / hourHeight * 60)
        let delta = Double((fingerY - (current.originY ?? fingerY)) / hourHeight * 60)
        let times: (start: Int, end: Int)
        switch current.kind {
        case .create(let anchor): times = TimeDrag.create(anchor: anchor, finger: finger)
        case .move: times = TimeDrag.move(start: current.occurrence?.fullStart ?? current.start, end: current.occurrence?.fullEnd ?? current.end, by: delta)
        case .resizeTop, .resizeBottom:
            times = TimeDrag.resize(start: current.occurrence?.fullStart ?? current.start, end: current.occurrence?.fullEnd ?? current.end, top: current.kind == .resizeTop, by: delta)
        }
        if times.start != current.start || times.end != current.end {
            UISelectionFeedbackGenerator().selectionChanged()
            current.start = times.start; current.end = times.end
            drag = current
        }
        let edge: CGFloat = 56
        let direction = globalY < viewport.minY + edge ? -1 : globalY > viewport.maxY - edge ? 1 : 0
        if direction != autoScroll { autoScroll = direction }
    }

    private func endDrag(commit: Bool) {
        guard let finished = drag else { return }
        drag = nil; fingerY = nil; autoScroll = 0
        guard commit else { return }
        switch finished.kind {
        case .create:
            selectedTask = store.newTask(date: store.dateKey, start: finished.start, end: finished.end)
            showingQuickCreate = true
        case .move, .resizeTop, .resizeBottom:
            guard let occurrence = finished.occurrence else { return }
            store.move(occurrence, start: finished.start, end: finished.end, offersUndo: true)
            if finished.kind != .move { selectedID = occurrence.id }
        }
    }

    /// Scrolls one 15 minute row past the visible edge the finger is resting on.
    private func scrollStep(_ proxy: ScrollViewProxy) {
        let step = Double(TimeDrag.step)
        if autoScroll < 0 {
            let top = Double((viewport.minY - gridTop) / hourHeight * 60)
            guard top > 0 else { return }
            withAnimation(.linear(duration: 0.09)) { proxy.scrollTo(slotID(max(0, Int(top / step) - 1)), anchor: .top) }
        } else {
            let bottom = Double((viewport.maxY - gridTop) / hourHeight * 60)
            guard bottom < Double(TimeDrag.dayEnd) else { return }
            withAnimation(.linear(duration: 0.09)) { proxy.scrollTo(slotID(min(Self.slots.upperBound - 1, Int(bottom / step) + 1)), anchor: .bottom) }
        }
    }

    /// First tap selects and shows the handles; a tap on the selected task opens it.
    private func tap(_ occurrence: ScheduledOccurrence) {
        if occurrence.isContinuation || selectedID == occurrence.id { open(occurrence) }
        else { withAnimation(animation) { selectedID = occurrence.id } }
    }

    private func open(_ occurrence: ScheduledOccurrence) {
        selectedID = nil
        selectedTask = occurrence.task
        showingEditor = true
    }

    private var animation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.15) }
    private func slotID(_ slot: Int) -> String { "slot-\(slot)" }
    private func color(of occurrence: ScheduledOccurrence) -> Color { DWColors.taskColor(mode: occurrence.task.colorMode, token: occurrence.task.colorToken, category: occurrence.category) }
    private func range(_ start: Int, _ end: Int) -> String { "\(DWFormat.time(start))–\(DWFormat.time(end))" }
    private func height(_ start: Int, _ end: Int) -> CGFloat { max(34, CGFloat(end - start) * hourHeight / 60) }
    private func y(for minute: Int) -> CGFloat { CGFloat(minute) * hourHeight / 60 }
}

private struct TimelineDrag: Equatable {
    enum Kind: Equatable { case create(anchor: Int), move, resizeTop, resizeBottom }

    var kind: Kind
    /// The task as it was before the drag; nil while creating.
    var occurrence: ScheduledOccurrence?
    var start: Int
    var end: Int
    /// Grid y of the finger when the drag began.
    var originY: CGFloat?
}

private struct TimelineTaskCard: View {
    @EnvironmentObject private var store: PlannerStore
    let occurrence: ScheduledOccurrence
    /// Where the card starts now, which differs from the task while it is dragged.
    let start: Int
    let isSelected: Bool
    let isPressed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            // Blocks of 30 minutes or less only have room for one line.
            let layout = compact ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
            layout {
                Text(occurrence.title.isEmpty ? (store.language == "en" ? "Untitled task" : "未命名任务") : occurrence.title).font(DWFont.headline).foregroundStyle(DWColors.text).strikethrough(occurrence.isDone).lineLimit(compact ? 1 : 2)
                HStack(spacing: 4) {
                    Text(occurrence.isContinuation ? "– \(DWFormat.time(occurrence.end))" : DWFormat.time(start))
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
        .overlay { if isSelected { RoundedRectangle(cornerRadius: DWRadius.block, style: .continuous).stroke(color, lineWidth: 2) } }
        .opacity(occurrence.isDone ? 0.5 : 1)
        .scaleEffect(isPressed ? 0.97 : 1)
    }

    private var compact: Bool { occurrence.end - occurrence.start <= 30 }
    private var color: Color { DWColors.taskColor(mode: occurrence.task.colorMode, token: occurrence.task.colorToken, category: occurrence.category) }
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
