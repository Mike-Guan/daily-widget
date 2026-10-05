import Foundation
import LocalModelKit

// Development tool: run sentences through the bundled model on the Mac.
// usage: localmodel-probe <model directory> <instructions file> <sentence>...
let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    print("usage: localmodel-probe <model directory> <instructions file> <sentence>...")
    exit(2)
}
let model = LocalTaskModel(directory: URL(fileURLWithPath: arguments[1]))
let instructions = try String(contentsOfFile: arguments[2], encoding: .utf8)
for sentence in arguments.dropFirst(3) {
    let started = Date()
    do {
        let answer = try await model.respond(instructions: instructions, prompt: sentence)
        print("IN  \(sentence)\nOUT \(answer.replacingOccurrences(of: "\n", with: " "))\n    \(String(format: "%.2f", Date().timeIntervalSince(started)))s")
    } catch {
        print("IN  \(sentence)\nERR \(error)")
    }
}
