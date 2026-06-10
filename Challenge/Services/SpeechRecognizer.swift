import Foundation
import AVFoundation
import Speech
import Observation

@Observable
final class SpeechRecognizer {

    // MARK: - Published state

    var transcript: String = ""
    var isListening: Bool = false
    var levels: [CGFloat]
    var errorMessage: String?
    var authorized: Bool = false

    // MARK: - Private

    private let barCount: Int
    private var sfRecognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    /// Set to true when SFSpeechRecognizer delivers isFinal or errors out.
    private var isFinalized = false

    init(barCount: Int = 32, locale: Locale = Locale(identifier: "ru-RU")) {
        self.barCount = barCount
        self.levels = Array(repeating: 0.04, count: barCount)
        self.sfRecognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Locale

    func setLocale(_ locale: Locale) {
        guard !isListening else { return }
        sfRecognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let speechStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            await MainActor.run { errorMessage = "Speech recognition permission denied." }
            return false
        }
        let micGranted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        guard micGranted else {
            await MainActor.run { errorMessage = "Microphone permission denied." }
            return false
        }
        await MainActor.run { authorized = true }
        return true
    }

    // MARK: - Control

    func start() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        isFinalized = false

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        self.request = req

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            guard let self, let level = Self.normalizedPower(of: buffer) else { return }
            DispatchQueue.main.async { self.pushLevel(level) }
        }

        recognitionTask = sfRecognizer?.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.isFinalized = true
                        self.request = nil
                        self.recognitionTask = nil
                    }
                }
                if error != nil {
                    self.isFinalized = true
                    self.request = nil
                    self.recognitionTask = nil
                    if self.isListening { self.stop() }
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
    }

    func stop() {
        guard isListening || audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognitionTask?.finish()
        request = nil
        recognitionTask = nil
        isListening = false
        isFinalized = true
        levels = Array(repeating: 0.04, count: barCount)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Stop the engine, then wait (up to 3 s) for SFSpeechRecognizer to deliver
    /// the final `isFinal` result before returning the transcript. Use this
    /// before sending the transcript to Gemini.
    func stopAndAwaitFinalTranscript() async -> String {
        guard isListening || audioEngine.isRunning else { return transcript }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognitionTask?.finish()
        isListening = false
        levels = Array(repeating: 0.04, count: barCount)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        // Keep request/recognitionTask alive so the callback can still fire.

        let deadline = Date().addingTimeInterval(3.0)
        while !isFinalized && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        request = nil
        recognitionTask = nil
        return transcript
    }

    func reset() {
        transcript = ""
        isFinalized = false
        levels = Array(repeating: 0.04, count: barCount)
    }

    // MARK: - Helpers

    private func pushLevel(_ value: CGFloat) {
        levels.append(value)
        if levels.count > barCount { levels.removeFirst(levels.count - barCount) }
    }

    private static func normalizedPower(of buffer: AVAudioPCMBuffer) -> CGFloat? {
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return nil }
        var sum: Float = 0
        for i in 0..<frames { let s = channel[i]; sum += s * s }
        let rms = sqrt(sum / Float(frames))
        let db = 20 * log10(max(rms, 1e-7))
        let minDb: Float = -50
        return CGFloat((max(minDb, min(db, 0)) - minDb) / (0 - minDb))
    }
}
