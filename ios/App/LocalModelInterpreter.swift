import Foundation
#if canImport(LocalModelKit) && !targetEnvironment(simulator)
import LocalModelKit
#endif

/// The model bundled with the app (ios/Models/TaskModel). Used when Apple Intelligence is not
/// available, so understanding does not depend on the phone's language or region settings.
enum LocalModelInterpreter {
    #if canImport(LocalModelKit) && !targetEnvironment(simulator)
    private static let model: LocalTaskModel? = Bundle.main.url(forResource: "TaskModel", withExtension: nil).map { LocalTaskModel(directory: $0) }

    static var isBundled: Bool { model != nil }

    /// Loads the weights so the first answer does not have to wait for them.
    static func prewarm() {
        guard let model else { return }
        Task.detached(priority: .userInitiated) { try? await model.load() }
    }

    /// Frees the model's memory, e.g. when the app goes to the background.
    static func unload() {
        guard let model else { return }
        Task.detached { await model.unload() }
    }

    static func output(for text: String) async -> ModelTaskOutput? {
        guard let model, let answer = try? await model.respond(instructions: LocalModelPrompt.instructions, prompt: text) else { return nil }
        return LocalModelPrompt.parse(answer)
    }
    #else
    static var isBundled: Bool { false }
    static func prewarm() {}
    static func unload() {}
    static func output(for text: String) async -> ModelTaskOutput? { nil }
    #endif
}
