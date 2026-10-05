import SwiftUI
import UIKit

/// Haptics for the timeline's drags: a thump when something is picked up, a tick per 15-minute step, a tap on drop.
private enum TimelineHaptics {
    static func lift() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func step() { UISelectionFeedbackGenerator().selectionChanged() }
    static func drop() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

/// Press and hold, then drag, as one gesture. On iOS 18 and later this is a UIKit long-press
/// recognizer: once it has recognised the hold it owns the touch, so the scroll view cannot take the
/// drag away half-way. iOS 17 falls back to SwiftUI's long press followed by a drag.
private struct HoldAndDragModifier: ViewModifier {
    var minimumDuration: TimeInterval
    var onBegan: (CGPoint) -> Void
    var onChanged: (_ location: CGPoint, _ translation: CGSize) -> Void
    var onEnded: () -> Void
    @State private var fallbackActive = false

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(HoldAndDragRecognizer(minimumDuration: minimumDuration, onBegan: onBegan, onChanged: onChanged, onEnded: onEnded))
        } else {
            content.gesture(
                LongPressGesture(minimumDuration: minimumDuration, maximumDistance: 10).sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onChanged { value in
                        guard case .second(true, let drag?) = value else { return }
                        if !fallbackActive { fallbackActive = true; onBegan(drag.startLocation) }
                        onChanged(drag.location, drag.translation)
                    }
                    .onEnded { _ in if fallbackActive { fallbackActive = false; onEnded() } }
            )
        }
    }
}

@available(iOS 18.0, *)
private struct HoldAndDragRecognizer: UIGestureRecognizerRepresentable {
    var minimumDuration: TimeInterval
    var onBegan: (CGPoint) -> Void
    var onChanged: (_ location: CGPoint, _ translation: CGSize) -> Void
    var onEnded: () -> Void

    final class Coordinator { var start = CGPoint.zero }
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        recognizer.allowableMovement = 10
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.minimumPressDuration = minimumDuration
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let location = context.converter.localLocation
        // The distance is measured on screen, not in the view's own space: a block that follows the
        // finger moves its own coordinate system along with it.
        let onScreen = context.converter.location(in: .global)
        switch recognizer.state {
        case .began:
            context.coordinator.start = onScreen
            onBegan(location)
        case .changed:
            onChanged(location, CGSize(width: onScreen.x - context.coordinator.start.x, height: onScreen.y - context.coordinator.start.y))
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }
}

private extension View {
    func holdAndDrag(minimumDuration: TimeInterval, onBegan: @escaping (CGPoint) -> Void, onChanged: @escaping (_ location: CGPoint, _ translation: CGSize) -> Void, onEnded: @escaping () -> Void) -> some View {
        modifier(HoldAndDragModifier(minimumDuration: minimumDuration, onBegan: onBegan, onChanged: onChanged, onEnded: onEnded))
    }
}

struct TimelineView<Header: View>: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selectedTask: PlannerTask?
    @Binding var showingEditor: Bool
    @Binding var showingQuickCreate: Bool
    @ViewBuilder var header: () -> Header
    /// The block being drawn, in minutes from midnight.
    @State private var draft: ClosedRange<Int>?
    /// True while any drag on the timeline is in progress; scrolling is off for that time.
    @State private var isInteracting = false
    /// Where the hold began while a new block is being drawn.
    @State private var createAnchorY: CGFloat?
    private var isToday: Bool { store.dateKey == Date().dayKey }
    private var nowMinute: Int { Calendar.current.component(.hour, from: .now) * 60 + Calendar.current.component(.minute, from: .now) }
    private let startHour = 0
    private let endHour = 24
    private let hourHeight: CGFloat = 68

    var body: some View {
        ScrollViewReader { proxy in
            scroller
                // Open on the present: today's page starts with the red line in view instead of at midnight.
                .onAppear { scrollToNow(proxy, animated: false) }
                .onChange(of: store.dateKey) { _, _ in scrollToNow(proxy, animated: true) }
                .onChange(of: scenePhase) { _, phase in if phase == .active { scrollToNow(proxy, animated: true) } }
        }
    }

    /// Brings the current time to about a quarter of the way down the screen. Other days are left where they are.
    private func scrollToNow(_ proxy: ScrollViewProxy, animated: Bool) {
        guard store.dateKey == Date().dayKey, !isInteracting else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if animated && !reduceMotion { withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(nowAnchorID, anchor: .top) } }
            else { proxy.scrollTo(nowAnchorID, anchor: .top) }
        }
    }

    private let nowAnchorID = "timeline-now"

    /// An invisible mark 90 minutes before now (or at the first unfinished task, if that is earlier) for `scrollToNow`.
    private var nowAnchor: some View {
        let now = nowMinute
        let firstOpen = store.todayTasks.first { !$0.isDone && $0.end > now - 90 }?.start ?? now
        let minute = max(startHour * 60, min(now - 90, firstOpen - 30))
        return VStack(spacing: 0) {
            Color.clear.frame(height: y(for: minute))
            Color.clear.frame(height: 1).id(nowAnchorID)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var scroller: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DWSpacing.sm) {
                ZStack(alignment: .topLeading) {
                    grid
                    nowAnchor
                    currentTimeIndicator
                    tasks
                    if let draft { draftBlock(draft).transition(reduceMotion ? .opacity : .scale(scale: 0.94, anchor: .top).combined(with: .opacity)) }
                }
                .frame(height: CGFloat(endHour - startHour) * hourHeight)
                .contentShape(Rectangle())
                // Press and hold on an empty spot, then drag, in one motion. Locations are in this view's own space, so y maps straight to minutes.
                .holdAndDrag(minimumDuration: 0.35, onBegan: { location in
                    isInteracting = true
                    createAnchorY = location.y
                    TimelineHaptics.lift()
                    setDraft(anchorY: location.y, currentY: location.y)
                }, onChanged: { location, _ in
                    setDraft(anchorY: createAnchorY ?? location.y, currentY: location.y)
                }, onEnded: finishCreating)
                .padding(.vertical, DWSpacing.sm)
                .background(DWColors.surface(colorScheme), in: RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DWRadius.card, style: .continuous).stroke(DWColors.line.opacity(colorScheme == .dark ? 0.6 : 1)))
            }
            .padding(.horizontal, DWSpacing.md).padding(.top, DWSpacing.xs).padding(.bottom, DWSpacing.lg)
        }
        .background(DWColors.background(colorScheme).ignoresSafeArea())
        .scrollDisabled(isInteracting)
        .scrollIndicators(.hidden)
        // The date, title and next-up card stay put; only the timeline scrolls under them.
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: DWSpacing.sm) {
                header()
                NextUpCard()
            }
            .padding(.horizontal, DWSpacing.md).padding(.top, DWSpacing.xs).padding(.bottom, DWSpacing.sm)
            .background(DWColors.background(colorScheme).ignoresSafeArea(edges: .top))
        }
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
            TimelineTaskCard(occurrence: occurrence, pixelsPerMinute: hourHeight / 60, originMinute: startHour * 60, isInteracting: $isInteracting, selectedTask: $selectedTask, showingEditor: $showingEditor)
        }
    }

    // MARK: Draw a new block

    private func finishCreating() {
        isInteracting = false
        createAnchorY = nil
        guard let range = draft else { return }
        TimelineHaptics.drop()
        selectedTask = store.newTask(date: store.dateKey, start: range.lowerBound, end: range.upperBound)
        showingQuickCreate = true
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { draft = nil }
    }

    /// The block starts in the quarter-hour under the finger and is 30 minutes long; dragging down
    /// stretches its end, dragging up past the start stretches its beginning.
    private func setDraft(anchorY: CGFloat, currentY: CGFloat) {
        let last = endHour * 60
        let anchor = min(last - 30, Int(minute(at: anchorY) / 15) * 15)
        let current = minute(at: currentY)
        var start = anchor, end = anchor + 30
        if current > end { end = min(last, Int((Double(current) / 15).rounded(.up)) * 15) }
        else if current < anchor { start = max(startHour * 60, Int(current / 15) * 15) }
        let range = start...end
        guard range != draft else { return }
        if draft != nil { TimelineHaptics.step() }
        withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.2, dampingFraction: 0.86)) { draft = range }
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

    private func draftBlock(_ range: ClosedRange<Int>) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(DWColors.accent).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.language == "en" ? "New task" : "新任务").font(DWFont.headline).foregroundStyle(DWColors.accent)
                Text("\(DWFormat.time(range.lowerBound)) – \(DWFormat.time(range.upperBound))").font(DWFont.caption).foregroundStyle(DWColors.accent)
            }
            .padding(.leading, DWSpacing.xs).padding(.vertical, 5)
            Spacer(minLength: 0)
        }
        .frame(height: max(34, CGFloat(range.upperBound - range.lowerBound) * hourHeight / 60), alignment: .top)
        .background(DWColors.accent.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: DWRadius.block, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DWRadius.block, style: .continuous).strokeBorder(DWColors.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .shadow(color: DWColors.accent.opacity(0.25), radius: 10, y: 4)
        .padding(.leading, 53).padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: y(for: range.lowerBound))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func y(for minute: Int) -> CGFloat { CGFloat(minute - startHour * 60) * hourHeight / 60 }
    private func minute(at y: CGFloat) -> Int { min(endHour * 60, max(startHour * 60, Int(y / hourHeight * 60) + startHour * 60)) }
}

/// A task on the timeline. Tap opens it. Press and hold, then drag, moves it; the grip at the bottom
/// edge changes its length. Either way the block follows the finger in 15-minute steps and shows
/// its new time while it moves.
private struct TimelineTaskCard: View {
    @EnvironmentObject private var store: PlannerStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let occurrence: ScheduledOccurrence
    let pixelsPerMinute: CGFloat
    /// The minute drawn at the top of the timeline (not always midnight).
    var originMinute = 0
    @Binding var isInteracting: Bool
    @Binding var selectedTask: PlannerTask?
    @Binding var showingEditor: Bool
    /// Start while the block is being moved.
    @State private var movingStart: Int?
    /// End while the block is being resized.
    @State private var resizingEnd: Int?
    @State private var lifted = false

    private var length: Int { occurrence.end - occurrence.start }
    private var liveStart: Int { movingStart ?? occurrence.start }
    private var liveEnd: Int { resizingEnd ?? (movingStart.map { $0 + length } ?? occurrence.end) }
    private var isActive: Bool { lifted || resizingEnd != nil }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            // Blocks of 30 minutes or less only have room for one line.
            let layout = compact ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
            layout {
                Text(occurrence.title.isEmpty ? (store.language == "en" ? "Untitled task" : "未命名任务") : occurrence.title).font(DWFont.headline).foregroundStyle(DWColors.text).strikethrough(occurrence.isDone).lineLimit(compact ? 1 : 2)
                HStack(spacing: 4) {
                    Text(timeLabel).fontWeight(isActive ? .bold : .regular).foregroundStyle(isActive ? color : DWColors.muted)
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
        .frame(height: max(34, CGFloat(liveEnd - liveStart) * pixelsPerMinute), alignment: .top)
        .background(color.opacity(isActive ? 0.3 : 0.16))
        .clipShape(RoundedRectangle(cornerRadius: DWRadius.block, style: .continuous))
        .overlay(alignment: .bottom) { resizeGrip }
        .opacity(occurrence.isDone && !isActive ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: DWRadius.block, style: .continuous))
        .onTapGesture { selectedTask = occurrence.task; showingEditor = true }
        .holdAndDrag(minimumDuration: 0.3, onBegan: { _ in beginMove() }, onChanged: { _, translation in move(by: translation.height) }, onEnded: endMove)
        .scaleEffect(lifted && !reduceMotion ? 1.03 : 1)
        .shadow(color: .black.opacity(isActive ? 0.18 : 0), radius: isActive ? 12 : 0, y: isActive ? 6 : 0)
        .padding(.leading, 53).padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: CGFloat(liveStart - originMinute) * pixelsPerMinute)
        .zIndex(isActive ? 10 : 0)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.86), value: liveStart)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.86), value: liveEnd)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.75), value: lifted)
        .accessibilityAction(named: store.language == "en" ? "Move 15 minutes later" : "推后 15 分钟") { nudge(15) }
        .accessibilityAction(named: store.language == "en" ? "Move 15 minutes earlier" : "提前 15 分钟") { nudge(-15) }
    }

    /// The bottom edge: a wide touch strip with a small visible grip.
    private var resizeGrip: some View {
        Capsule().fill(color.opacity(resizingEnd != nil ? 1 : 0.7)).frame(width: 36, height: 4).padding(.bottom, 3)
            // A short block keeps most of its height for moving; only its lowest edge resizes.
            .frame(maxWidth: .infinity, minHeight: liveEnd - liveStart <= 30 ? 10 : 18, alignment: .bottom)
            .contentShape(Rectangle())
            .highPriorityGesture(resizeGesture)
    }

    private var timeLabel: String {
        if isActive { return "\(DWFormat.time(liveStart)) – \(DWFormat.time(liveEnd))" }
        return occurrence.isContinuation ? "– \(DWFormat.time(occurrence.end))" : DWFormat.time(occurrence.start)
    }

    private var compact: Bool { liveEnd - liveStart <= 30 }
    private var color: Color { DWColors.taskColor(mode: occurrence.task.colorMode, token: occurrence.task.colorToken, category: occurrence.category) }

    private func steps(_ translation: CGFloat) -> Int { Int((translation / pixelsPerMinute / 15).rounded()) * 15 }

    /// Press and hold lifts the block; dragging then moves it. The part of a task that runs over from yesterday stays put.
    private func beginMove() {
        guard !occurrence.isContinuation else { return }
        lifted = true
        isInteracting = true
        TimelineHaptics.lift()
    }

    private func move(by distance: CGFloat) {
        guard lifted else { return }
        let start = max(0, min(24 * 60 - 15, occurrence.start + steps(distance)))
        if start != liveStart { TimelineHaptics.step(); movingStart = start }
    }

    private func endMove() {
        defer { lifted = false; movingStart = nil; isInteracting = false }
        guard lifted, let start = movingStart, start != occurrence.start else { return }
        TimelineHaptics.drop()
        store.move(occurrence, start: start, end: start + (occurrence.fullEnd - occurrence.fullStart))
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if resizingEnd == nil { isInteracting = true; TimelineHaptics.lift() }
                let end = max(occurrence.start + 15, min(24 * 60, occurrence.end + steps(value.translation.height)))
                if end != liveEnd || resizingEnd == nil { if resizingEnd != nil { TimelineHaptics.step() }; resizingEnd = end }
            }
            .onEnded { _ in
                defer { resizingEnd = nil; isInteracting = false }
                guard let end = resizingEnd, end != occurrence.end else { return }
                TimelineHaptics.drop()
                store.move(occurrence, start: occurrence.isContinuation ? occurrence.fullStart : occurrence.start, end: occurrence.isContinuation ? 24 * 60 + end : end)
            }
    }

    private func nudge(_ minutes: Int) {
        guard !occurrence.isContinuation else { return }
        let start = max(0, min(24 * 60 - 15, occurrence.fullStart + minutes))
        store.move(occurrence, start: start, end: start + (occurrence.fullEnd - occurrence.fullStart))
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
