// swift-tools-version: 6.2
import PackageDescription

// Wraps the MLX language-model stack behind one small type, so the app's Xcode project only
// has to know about this local package.
let package = Package(
    name: "LocalModelKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LocalModelKit", targets: ["LocalModelKit"]),
        .executable(name: "localmodel-probe", targets: ["localmodel-probe"]),
    ],
    dependencies: [
        // The FoundationModels bridge needs the iOS 27 SDK; we only use the plain LLM libraries.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.32.3"), traits: []),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "LocalModelKit",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(name: "localmodel-probe", dependencies: ["LocalModelKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
