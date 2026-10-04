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

    /// The model's raw answer, or why there is none. Loading (slow the first time) is reported separately from answering.
    static func run(_ text: String) async -> Run {
        guard let model else { return Run(answer: nil, error: "model files are not in the app bundle", loadSeconds: 0, answerSeconds: 0) }
        let started = Date()
        do { try await model.load() } catch { return Run(answer: nil, error: "load failed: \(error)", loadSeconds: Date().timeIntervalSince(started), answerSeconds: 0) }
        let loaded = Date()
        do {
            let answer = try await model.respond(instructions: LocalModelPrompt.instructions, prompt: text)
            return Run(answer: answer, error: nil, loadSeconds: loaded.timeIntervalSince(started), answerSeconds: Date().timeIntervalSince(loaded))
        } catch {
            return Run(answer: nil, error: "generation failed: \(error)", loadSeconds: loaded.timeIntervalSince(started), answerSeconds: Date().timeIntervalSince(loaded))
        }
    }
    #else
    static var isBundled: Bool { false }
    static func prewarm() {}
    static func unload() {}
    static func run(_ text: String) async -> Run { Run(answer: nil, error: "the bundled model does not run in the simulator", loadSeconds: 0, answerSeconds: 0) }
    #endif

    struct Run: Sendable {
        var answer: String?
        var error: String?
        var loadSeconds: TimeInterval
        var answerSeconds: TimeInterval
    }
}
