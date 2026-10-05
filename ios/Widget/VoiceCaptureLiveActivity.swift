import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Dynamic Island and Lock Screen strip for dictating a task without opening the app.
struct VoiceCaptureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceCaptureAttributes.self) { context in
            VoiceCaptureStrip(state: context.state)
                .padding(DWSpacing.md)
                .widgetURL(URL(string: context.state.phase == .failed ? "dailywidget://quickadd" : "dailywidget://today"))
                .activityBackgroundTint(Color(.secondarySystemBackground))
                .activitySystemActionForegroundColor(DWColors.accent)
        } dynamicIsland: { context in
            let copy = VoiceCaptureText(state: context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VoiceCaptureMark(state: context.state, size: 22).frame(width: 44, height: 44).background(DWColors.accentSoft, in: Circle()).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) { VoiceCaptureAction(state: context.state).padding(.trailing, 4) }
                DynamicIslandExpandedRegion(.center) {
                    Text(copy.short).font(.caption.weight(.semibold)).foregroundStyle(DWColors.accent).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.headline).font(.headline).foregroundStyle(.white).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        Text(copy.caption).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, DWSpacing.xs).padding(.bottom, DWSpacing.xs)
                }
            } compactLeading: {
                VoiceCaptureMark(state: context.state, size: 18)
            } compactTrailing: {
                if context.state.phase == .listening {
                    Image(systemName: "waveform").font(.caption.weight(.semibold)).foregroundStyle(DWColors.accent).symbolEffect(.variableColor.iterative)
                } else {
                    Text(copy.short).font(.caption2.weight(.semibold)).foregroundStyle(DWColors.accent).lineLimit(1)
                }
            } minimal: {
                VoiceCaptureMark(state: context.state, size: 16)
            }
            .keylineTint(DWColors.accent)
            .widgetURL(URL(string: context.state.phase == .failed ? "dailywidget://quickadd" : "dailywidget://today"))
        }
    }
}

/// "Done" while listening, "Undo" after a task was added.
private struct VoiceCaptureAction: View {
    let state: VoiceCaptureAttributes.ContentState
    var body: some View {
        if state.phase == .listening {
            Button(intent: FinishVoiceCaptureIntent()) { Text(state.english ? "Done" : "说完了").font(DWFont.label) }
                .buttonStyle(.borderedProminent).tint(DWColors.accent)
        } else if state.phase == .added, let taskID = state.taskID {
            Button(intent: UndoAddTaskIntent(taskID: taskID)) { Text(state.english ? "Undo" : "撤销").font(DWFont.label) }
                .buttonStyle(.bordered).tint(DWColors.accent)
        }
    }
}

private struct VoiceCaptureText {
    let state: VoiceCaptureAttributes.ContentState
    private func text(_ english: String, _ chinese: String) -> String { state.english ? english : chinese }

    var short: String {
        switch state.phase {
        case .listening: return text("Listening", "正在听")
        case .understanding: return text("Working", "理解中")
        case .added: return text("Added", "已添加")
        case .changed: return text("Changed", "已修改")
        case .undone: return text("Undone", "已撤销")
        case .failed: return text("Not added", "未添加")
        }
    }

    var headline: String {
        switch state.phase {
        case .listening: return state.transcript.isEmpty ? text("Say what to add", "说出要记的事") : state.transcript
        case .understanding: return state.transcript
        case .added, .changed, .undone: return state.title
        case .failed: return state.title
        }
    }

    var caption: String {
        switch state.phase {
        case .listening: return text("Listening · pause when you are done", "正在听 · 说完停一下就好")
        case .understanding: return text("Working it out", "正在理解")
        case .added: return text("Added · ", "已添加 · ") + state.detail
        case .changed: return text("Changed · ", "已修改 · ") + state.detail
        case .undone: return text("Undone", "已撤销")
        case .failed: return state.transcript.isEmpty ? text("Nothing was added", "没有添加") : state.transcript
        }
    }
}

private struct VoiceCaptureMark: View {
    let state: VoiceCaptureAttributes.ContentState
    let size: CGFloat
    var body: some View {
        switch state.phase {
        case .added, .changed: Image(systemName: "checkmark.circle.fill").font(.system(size: size)).foregroundStyle(DWColors.accent)
        case .failed, .undone: Image(systemName: "xmark.circle").font(.system(size: size)).foregroundStyle(DWColors.muted)
        default: MicGlyph().fill(DWColors.accent).frame(width: size, height: size)
        }
    }
}

private struct VoiceCaptureStrip: View {
    let state: VoiceCaptureAttributes.ContentState

    var body: some View {
        let copy = VoiceCaptureText(state: state)
        HStack(spacing: DWSpacing.sm) {
            VoiceCaptureMark(state: state, size: 20)
                .frame(width: 40, height: 40)
                .background(DWColors.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.headline).font(DWFont.headline).foregroundStyle(.primary).lineLimit(2)
                Text(copy.caption).font(DWFont.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            VoiceCaptureAction(state: state)
        }
    }
}
