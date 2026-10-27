@preconcurrency import AVFoundation
import Foundation
import Observation
@preconcurrency import Speech
import UIKit

@MainActor protocol MiraSpeechInputService: AnyObject {
    var recording: Bool { get }
    var requesting: Bool { get }
    var transcript: String { get set }
    var elapsed: Int { get }
    var error: String? { get }
    func start(locale: String) async
    func stop()
}
@MainActor @Observable
final class MiraSpeechInput: MiraSpeechInputService {
    var recording = false
    var requesting = false
    var transcript = ""
    var elapsed = 0
    var error: String?
    private let engine = AVAudioEngine()
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var timer: Task<Void, Never>?
    private var tapInstalled = false
    private var attempt = UUID()
    func start(locale: String) async {
        guard !recording, !requesting else { return }
        let attempt = UUID()
        self.attempt = attempt
        requesting = true
        defer { requesting = false }
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard self.attempt == attempt else { return }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard self.attempt == attempt else { return }
        guard UIApplication.shared.applicationState == .active else {
            error =
                "Recording was interrupted before it started. Tap the microphone when you are ready, or type instead."
            return
        }
        guard speech && microphone else {
            error =
                "Microphone or speech permission is off. You can type instead, or enable access in Settings."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
            recognizer.isAvailable,
            recognizer.supportsOnDeviceRecognition
        else {
            error =
                "On-device speech recognition is unavailable for this language. Use text, or try the other recognition language. No audio was sent to Mira's server."
            return
        }
        do {
            stop()
            let recordingAttempt = self.attempt
            transcript = ""
            error = nil
            elapsed = 0
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            tapInstalled = true
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                let text = result?.bestTranscription.formattedString
                let finished = result?.isFinal == true
                let failed = failure != nil
                Task { @MainActor [weak self] in
                    guard let self, self.recording, self.attempt == recordingAttempt else { return }
                    if let text { self.transcript = text }
                    if finished || failed {
                        self.stop()
                        if self.transcript.isEmpty {
                            self.error = "No speech was recognised. Try again or type your request."
                        }
                    }
                }
            }
            engine.prepare()
            try engine.start()
            recording = true
            timer = Task { [weak self] in
                for second in 1...60 {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self, self.recording, self.attempt == recordingAttempt else { return }
                    self.elapsed = second
                }
                self?.stop()
            }
        } catch {
            stop()
            self.error = "Recording could not start. Text input is always available."
        }
    }
    func stop() {
        attempt = UUID()
        if recording && transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "No speech was recognised. Try again or type your request."
        }
        recording = false
        timer?.cancel()
        timer = nil
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        recognition?.cancel()
        recognition = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
