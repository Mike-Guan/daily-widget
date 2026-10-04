import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns one sentence into a `TaskDraft`. Uses the on-device Apple Intelligence model when the
/// phone has it; otherwise, or when the model is slow or fails, the rule parser alone. Nothing
/// leaves the device either way.
enum TaskInterpreter {
    /// How long the model may think before the rules answer instead.
    static let timeout: Duration = .seconds(4)

    /// The bundled model is slower to load than Apple's, so it gets longer.
    static let bundledModelTimeout: Duration = .seconds(8)

    /// - Parameter allowBundledModel: false for Siri and the Action Button, which run in the
    ///   background with too little memory to load the bundled model.
    static func interpret(_ text: String, english: Bool, now: Date = .now, allowBundledModel: Bool = true) async -> TaskDraft {
        let model = await modelOutput(for: text, english: english, now: now, allowBundledModel: allowBundledModel)
        return TaskUnderstanding.draft(text: text, model: model, now: now)
    }

    /// Why the model is or is not in use, for Settings.
    static func status(english: Bool) -> String {
        if !appleModelAvailable, LocalModelInterpreter.isBundled {
            return english ? "Using the model bundled with the app (Qwen3.5-0.8B). It runs on this iPhone and does not need Apple Intelligence." : "正在使用 App 自带的本机模型（Qwen3.5-0.8B）理解，不联网，也不需要开启 Apple 智能。"
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return english ? "On-device AI is on." : "正在使用本机 AI 理解。"
            case .unavailable(.appleIntelligenceNotEnabled):
                return english ? "Apple Intelligence is off, so rules are used. An app cannot turn it on or ask for it: open the Settings app, go back to the top level, open Apple Intelligence & Siri, turn on Apple Intelligence, and come back once the model has downloaded." : "Apple 智能未开启，目前用规则解析。App 不能替你开启，也不会弹窗：请打开系统“设置”，回到最上层，进入“Apple 智能与 Siri”，打开“Apple 智能”，等模型下载完成后回来。"
            case .unavailable(.modelNotReady):
                return english ? "The on-device model is still downloading; rules are used for now." : "本机模型还在下载，暂时用规则解析。"
            case .unavailable(.deviceNotEligible):
                return english ? "This device has no on-device model; rules are used." : "这台设备不支持本机模型，使用规则解析。"
            case .unavailable:
                return english ? "The on-device model is unavailable; rules are used." : "本机模型不可用，使用规则解析。"
            }
        }
        #endif
        return english ? "On-device AI needs iOS 26; rules are used." : "本机 AI 需要 iOS 26，目前用规则解析。"
    }

    /// True when the model exists on this phone but the user has to turn Apple Intelligence on (or wait for the download).
    static var needsUserSetup: Bool {
        if LocalModelInterpreter.isBundled { return false }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .unavailable(.appleIntelligenceNotEnabled), .unavailable(.modelNotReady): return true
            default: return false
            }
        }
        #endif
        return false
    }

    /// Loads the model ahead of the first request so the user does not wait for it.
    static func prewarm() {
        if !appleModelAvailable { LocalModelInterpreter.prewarm(); return }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability {
            LanguageModelSession(instructions: "").prewarm()
        }
        #endif
    }

    private static var appleModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    /// Apple's model when the phone has it; otherwise the model bundled with the app.
    private static func modelOutput(for text: String, english: Bool, now: Date, allowBundledModel: Bool) async -> ModelTaskOutput? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), appleModelAvailable {
            return await firstResult(within: timeout) { await generate(text: text, english: english, now: now) }
        }
        #endif
        if allowBundledModel, LocalModelInterpreter.isBundled {
            return await firstResult(within: bundledModelTimeout) { await LocalModelInterpreter.output(for: text) }
        }
        return nil
    }

    /// The operation's result, or nil once the time is up. Does not wait for a slow operation to finish.
    private static func firstResult(within limit: Duration, _ operation: @escaping @Sendable () async -> ModelTaskOutput?) async -> ModelTaskOutput? {
        let gate = ResumeOnce()
        return await withCheckedContinuation { continuation in
            Task { let value = await operation(); if await gate.claim() { continuation.resume(returning: value) } }
            Task { try? await Task.sleep(for: limit); if await gate.claim() { continuation.resume(returning: nil) } }
        }
    }

    private actor ResumeOnce {
        private var claimed = false
        func claim() -> Bool { if claimed { return false }; claimed = true; return true }
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable(description: "One task extracted from a spoken sentence")
    struct GeneratedTask {
        @Guide(description: "Short task name copied word for word from the sentence, without the day, the time, the duration, or lead-ins such as 帮我添加一个, 提醒我, remind me to")
        var title: String
        @Guide(description: "The words for the day exactly as said, such as 10月23日, 下周三, 明天, Friday. Empty string if no day was said")
        var dateText: String
        @Guide(description: "The words for the clock time exactly as said, such as 下午三点, 晚上8点半, 3pm. Empty string if no time was said")
        var timeText: String
        @Guide(description: "Length in minutes, or 0 if the sentence does not say", .range(0...480))
        var durationMinutes: Int
        @Guide(description: "True if the user asked to be reminded (提醒我, remind me)")
        var wantsReminder: Bool
        @Guide(description: "Best matching category", .anyOf(["personal", "health", "home", "social", "learning", "errands"]))
        var category: String
        @Guide(description: "Repeat rule; none unless the sentence says every day, weekdays or every week", .anyOf(["none", "daily", "weekdays", "weekly"]))
        var recurrence: String
    }

    @available(iOS 26.0, *)
    private static func generate(text: String, english: Bool, now: Date) async -> ModelTaskOutput? {
        let instructions = """
        You label the parts of one sentence the user dictated in Chinese or English to add a task. \
        Copy words from the sentence exactly; never translate, rephrase, calculate dates or invent anything. \
        If a part was not said, return an empty string for it.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let task = try await session.respond(to: text, generating: GeneratedTask.self, options: GenerationOptions(temperature: 0)).content
            return ModelTaskOutput(title: task.title, dateText: task.dateText.isEmpty ? nil : task.dateText, timeText: task.timeText.isEmpty ? nil : task.timeText, durationMinutes: task.durationMinutes <= 0 ? nil : task.durationMinutes, wantsReminder: task.wantsReminder, category: task.category, recurrence: task.recurrence)
        } catch {
            return nil
        }
    }
    #endif
}
