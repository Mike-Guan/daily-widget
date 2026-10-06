import AVFoundation
import Speech

/// Live speech-to-text for the quick-add sheet. Recognition is forced on-device: if the phone has
/// no local model for the language, dictation is reported as unavailable instead of using the network.
@MainActor
final class SpeechDictation: ObservableObject {
    enum State: Equatable { case idle, listening, unavailable(String) }

    @Published private(set) var transcript = ""
    @Published private(set) var state: State = .idle

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isListening: Bool { state == .listening }

    func start(english: Bool) async {
        guard state != .listening else { return }
        transcript = ""
        func message(_ en: String, _ zh: String) -> String { english ? en : zh }

        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { state = .unavailable(message("Speech recognition is not allowed. You can type instead.", "没有语音识别权限，可以直接打字。")); return }
        guard await AVAudioApplication.requestRecordPermission() else { state = .unavailable(message("Microphone access is not allowed. You can type instead.", "没有麦克风权限，可以直接打字。")); return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: english ? "en-US" : "zh-CN")), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            state = .unavailable(message("On-device dictation for this language is not available on this iPhone. You can type instead.", "这台 iPhone 暂时不能在本机识别这种语言，可以直接打字。"))
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            request.addsPunctuation = false
            self.request = request

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { throw NSError(domain: "SpeechDictation", code: 1) }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            engine.prepare()
            try engine.start()

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let finished = error != nil || result?.isFinal == true
                Task { @MainActor in
                    guard let self else { return }
                    if let text { self.transcript = text }
                    if finished { self.teardown() }
                }
            }
            state = .listening
        } catch {
            teardown()
            state = .unavailable(message("The microphone could not be started. You can type instead.", "麦克风没有启动成功，可以直接打字。"))
        }
    }

    /// Stops recording and returns what was heard.
    @discardableResult
    func stop() -> String {
        teardown()
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func teardown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if state == .listening { state = .idle }
    }
}
