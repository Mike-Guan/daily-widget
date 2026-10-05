import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// A small language model that runs entirely on the device from a folder of weights.
/// It is loaded on first use and kept in memory until `unload()`.
public actor LocalTaskModel {
    public enum ModelError: Error { case missingWeights }

    private let directory: URL
    private var container: ModelContainer?

    public init(directory: URL) {
        self.directory = directory
    }

    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path)
    }

    public func load() async throws {
        guard container == nil else { return }
        guard isAvailable else { throw ModelError.missingWeights }
        // Keep MLX's buffer cache small; this model is used for one short answer at a time.
        MLX.GPU.set(cacheLimit: 32 * 1024 * 1024)
        container = try await loadModelContainer(from: directory, using: #huggingFaceTokenizerLoader())
    }

    public func unload() {
        container = nil
        MLX.GPU.clearCache()
    }

    /// One short, deterministic answer. Each call starts a fresh conversation.
    public func respond(instructions: String, prompt: String, maxTokens: Int = 160) async throws -> String {
        try await load()
        guard let container else { throw ModelError.missingWeights }
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: maxTokens, temperature: 0),
            additionalContext: ["enable_thinking": false]
        )
        return try await session.respond(to: prompt)
    }
}
