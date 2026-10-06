import ActivityKit
import AVFoundation
import Foundation
import Speech
import UIKit
import WidgetKit

/// Dictates one task while the app stays in the background. Started by `RecordTaskIntent` from a
/// widget or the lock-screen control; progress and the result are shown in a Live Activity.
@MainActor
final class BackgroundVoiceCapture {
    static let shared = BackgroundVoiceCapture()

    /// Stop this long after the last new word.
    private let pauseToFinish: TimeInterval = 1.8
    /// Give up if nothing at all is heard for this long.
    private let waitForSpeech: TimeInterval = 7
    /// Never listen longer than this.
    private let maximumLength: TimeInterval = 25

    private let dictation = SpeechDictation()
    private var activity: Activity<VoiceCaptureAttributes>?
    private var watcher: Task<Void, Never>?
    private var english = false

    /// Starts listening. While already listening, the same action ends it: tap once to start, again to stop.
    func start() async {
        guard watcher == nil else { await finishNow(); return }
        english = (TaskRepository.shared.flatMap { WidgetSnapshot.stored(in: $0.directory)?.language } ?? "zh") == "en"
        do {
            activity = try Activity.request(attributes: VoiceCaptureAttributes(), content: content(.init(phase: .listening, english: english)))
            VoiceCaptureLog.note("live activity started")
        } catch {
            VoiceCaptureLog.note("live activity failed: \(error) · enabled=\(ActivityAuthorizationInfo().areActivitiesEnabled)")
        }
        VoiceCaptureLog.note("app state=\(UIApplication.shared.applicationState.rawValue) speech=\(SFSpeechRecognizer.authorizationStatus().rawValue) mic=\(AVAudioApplication.shared.recordPermission == .granted)")

        // Permission sheets cannot be shown from the background, so both must already be granted.
        guard SFSpeechRecognizer.authorizationStatus() == .authorized, AVAudioApplication.shared.recordPermission == .granted else {
            await finish(with: .init(phase: .failed, title: english ? "Open the app and tap the microphone once to allow it" : "先打开 App 点一次麦克风，允许后再用", english: english), keepFor: 8)
            return
        }
        // From the background the microphone is only granted once the system has registered the
        // Live Activity, which can lag the request by a moment, so try a few times before giving up.
        for attempt in 1...4 {
            await dictation.start(english: english, fromBackground: true)
            if dictation.isListening { if attempt > 1 { VoiceCaptureLog.note("microphone started on attempt \(attempt)") }; break }
            VoiceCaptureLog.note("attempt \(attempt) failed · \(dictation.lastFailure)")
            try? await Task.sleep(for: .milliseconds(350))
        }
        setListening(dictation.isListening)
        guard dictation.isListening else {
            var reason = english ? "Could not start listening" : "没能开始听"
            if case .unavailable(let message) = dictation.state { reason = message }
            VoiceCaptureLog.note("dictation did not start: \(reason)")
            await finish(with: .init(phase: .failed, title: english ? "Could not listen from here. Tap to open the app and speak." : "这里没能开始听，点一下打开 App 再说", english: english), keepFor: 10)
            return
        }

        watcher = Task { [weak self] in
            guard let self else { return }
            let started = Date()
            var lastText = ""
            var lastChange = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                let text = self.dictation.transcript
                if text != lastText {
                    lastText = text
                    lastChange = Date()
                    await self.activity?.update(self.content(.init(phase: .listening, transcript: text, english: self.english)))
                }
                let quiet = Date().timeIntervalSince(lastChange)
                let stopped = !self.dictation.isListening
                if stopped || (!text.isEmpty && quiet > self.pauseToFinish) || (text.isEmpty && quiet > self.waitForSpeech) || Date().timeIntervalSince(started) > self.maximumLength { break }
            }
            if !Task.isCancelled { await self.complete() }
        }
    }

    /// "Done" was tapped on the Live Activity.
    func finishNow() async {
        guard watcher != nil else { return }
        watcher?.cancel()
        await complete()
    }

    private func setListening(_ listening: Bool) {
        VoiceCaptureStatus.isListening = listening
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadControls(ofKind: VoiceCaptureStatus.controlKind) }
    }

    private func complete() async {
        watcher = nil
        let sentence = dictation.stop()
        setListening(false)
        VoiceCaptureLog.note("heard: \(sentence.isEmpty ? "(nothing)" : sentence)")
        guard !sentence.isEmpty else {
            await finish(with: .init(phase: .failed, title: english ? "Nothing was heard" : "没有听到内容", english: english), keepFor: 4)
            return
        }
        await activity?.update(content(.init(phase: .understanding, transcript: sentence, english: english)))
        guard let repository = TaskRepository.shared else {
            await finish(with: .init(phase: .failed, title: english ? "Storage is unavailable" : "存储不可用", english: english), keepFor: 6)
            return
        }

        // The bundled model needs more memory than a background launch gets, so rules and Apple's model only.
        let draft = await TaskInterpreter.interpret(sentence, english: english, allowBundledModel: false)
        let outcome = VoiceCommand.resolve(text: sentence, draft: draft, tasks: (try? repository.load()) ?? [], deviceID: "voice")
        let task = outcome.task
        if case .changed(let previous, let current) = outcome, previous == current {
            await finish(with: .init(phase: .failed, transcript: sentence, title: english ? "Did not catch the new time" : "没听清要改到什么时候", english: english), keepFor: 6)
            return
        }
        do {
            if case .added = outcome, draft.wantsReminder { ReminderPlan.setWanted(true, taskID: task.id) }
            let tasks = try repository.upsert(task)
            VoiceCaptureLog.note("saved: \(task.title) \(task.date ?? "inbox") \(task.start.map(String.init) ?? "-")")
            await ReminderScheduler.reconcile(tasks: tasks, english: english)
            NotificationCenter.default.post(name: .dailyWidgetTasksChanged, object: nil)
            let summary = AddTaskSummary(draft: TaskDraft(title: task.title, date: task.date, start: task.start, end: task.end, category: task.category, recurrence: task.recurrence, source: draft.source, wantsReminder: draft.wantsReminder), english: english)
            var state = VoiceCaptureAttributes.ContentState(phase: .added, transcript: sentence, title: task.title, detail: summary.when, taskID: task.id, english: english)
            if case .changed = outcome { state.phase = .changed; state.taskID = nil }
            await finish(with: state, keepFor: 8)
        } catch {
            await finish(with: .init(phase: .failed, transcript: sentence, title: error.localizedDescription, english: english), keepFor: 8)
        }
    }

    private func content(_ state: VoiceCaptureAttributes.ContentState) -> ActivityContent<VoiceCaptureAttributes.ContentState> {
        ActivityContent(state: state, staleDate: nil)
    }

    private func finish(with state: VoiceCaptureAttributes.ContentState, keepFor seconds: TimeInterval) async {
        watcher = nil
        dictation.stop()
        setListening(false)
        await activity?.end(content(state), dismissalPolicy: .after(.now + seconds))
        activity = nil
    }
}

extension Notification.Name {
    /// Tasks were written by something other than the visible app UI (background voice capture).
    static let dailyWidgetTasksChanged = Notification.Name("dailyWidgetTasksChanged")
}
