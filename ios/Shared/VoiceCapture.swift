import ActivityKit
import AppIntents
import Foundation

/// The Live Activity shown while a task is being dictated without opening the app: the Dynamic
/// Island and Lock Screen strip that says "listening", then what was added.
struct VoiceCaptureAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable { case listening, understanding, added, changed, undone, failed }
        var phase: Phase
        /// What has been heard so far.
        var transcript = ""
        /// The task's title once it has been understood, or a short reason when `phase` is `failed`.
        var title = ""
        /// "明天 15:00–15:30" or "收集箱 · 未定时间".
        var detail = ""
        var taskID: String?
        var english = false
    }
}

/// Starts listening in the background. Used by the widgets' microphone and the lock-screen control.
/// The system runs it in the app's process and keeps the app recording while the Live Activity is up.
@available(iOS 18.0, *)
struct RecordTaskIntent: AudioRecordingIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Add a task by voice"
    static var description = IntentDescription("Listens without opening the app and adds what you say as a task.")
    static var openAppWhenRun = false

    /// Set by the app at launch; nil in the widget extension, where this intent never runs.
    @MainActor static var start: (() async -> Void)?

    func perform() async throws -> some IntentResult {
        let hook = await Self.start
        VoiceCaptureLog.note(hook == nil ? "record intent ran, but not in the app (no start hook)" : "record intent ran in the app")
        await hook?()
        return .result()
    }
}

/// A short trail of what background voice capture did, kept in the App Group so the app's Settings
/// can show it. Each line says which process wrote it.
enum VoiceCaptureLog {
    private static let key = "voiceCaptureLog"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshot.appGroupID) }

    static func note(_ message: String) {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
        var lines = defaults?.stringArray(forKey: key) ?? []
        lines.append("\(formatter.string(from: .now)) [\(ProcessInfo.processInfo.processName)] \(message)")
        defaults?.set(Array(lines.suffix(14)), forKey: key)
    }

    static var lines: [String] { defaults?.stringArray(forKey: key) ?? [] }
}

/// "Done" on the Live Activity: stop listening now instead of waiting for a pause.
struct FinishVoiceCaptureIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Finish dictating"
    static var isDiscoverable = false
    static var openAppWhenRun = false

    @MainActor static var finish: (() async -> Void)?

    func perform() async throws -> some IntentResult {
        await Self.finish?()
        return .result()
    }
}

/// Takes back a task that was just added by voice. It is tombstoned, like any delete, so sync agrees.
struct UndoAddTaskIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Undo add task"
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Parameter(title: "Task ID") var taskID: String
    init() {}
    init(taskID: String) { self.taskID = taskID }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let repository = TaskRepository.shared else { throw UndoError.storageUnavailable }
        let english = (WidgetSnapshot.stored(in: repository.directory)?.language ?? "zh") == "en"
        try repository.mutate { tasks in
            guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
            tasks[index].deletedAt = ISO8601DateFormatter().string(from: .now)
            tasks[index].touch(deviceID: "siri")
        }
        // If this came from the Live Activity, say so there and let it go.
        for activity in Activity<VoiceCaptureAttributes>.activities where activity.content.state.taskID == taskID {
            var state = activity.content.state
            state.phase = .undone
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(.now + 3))
        }
        return .result(dialog: IntentDialog(stringLiteral: english ? "Removed." : "已撤销。"))
    }

    enum UndoError: LocalizedError {
        case storageUnavailable
        var errorDescription: String? { "Daily Widget could not open its storage. Open the app once and try again." }
    }
}
