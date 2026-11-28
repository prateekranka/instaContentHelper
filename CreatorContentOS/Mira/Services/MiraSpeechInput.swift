@preconcurrency import AVFoundation
import Foundation
import Observation
@preconcurrency import Speech
import UIKit

@MainActor protocol MiraSpeechInputService: AnyObject {
    var state: MiraVoiceInputState { get }
    var transcript: String { get set }
    func start(locale: String) async
    func stop()
    func refreshPermissions()
}
@MainActor @Observable
final class MiraSpeechInput: MiraSpeechInputService {
    private(set) var state = MiraVoiceInputState.idle
    var transcript = ""
    private let engine = AVAudioEngine()
    private var recognition: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var timer: Task<Void, Never>?
    private var tapInstalled = false

    @discardableResult
    private func transition(_ event: MiraVoiceInputEvent) -> Bool {
        guard let next = state.handle(event) else { return false }
        state = next
        return true
    }

    func start(locale: String) async {
        let attempt = UUID()
        guard transition(.start(attempt)) else { return }
        let speech = await Self.speechAllowed()
        guard state == .askingPermission(attempt) else { return }
        guard speech else {
            transition(.denied(attempt))
            return
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard state == .askingPermission(attempt) else { return }
        guard microphone else {
            transition(.denied(attempt))
            return
        }
        guard UIApplication.shared.applicationState == .active else {
            transition(.failed(attempt, "The microphone did not start. Try again or type your request."))
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)),
            recognizer.isAvailable,
            recognizer.supportsOnDeviceRecognition
        else {
            transition(.failed(attempt, "Try the other language or type your request."))
            return
        }
        do {
            transcript = ""
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
                    guard let self, case .recording(let current, _) = self.state, current == attempt else { return }
                    if let text { self.transcript = text }
                    if finished || failed { self.stop() }
                }
            }
            engine.prepare()
            try engine.start()
            transition(.recording(attempt))
            timer = Task { [weak self] in
                for second in 1...60 {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard self?.transition(.tick(attempt, second)) == true else { return }
                }
                self?.stop()
            }
        } catch {
            releaseAudio()
            transition(.failed(attempt, "The microphone did not start. Try again or type your request."))
        }
    }

    nonisolated private static func speechAllowed() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { @Sendable status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }

    func refreshPermissions() {
        guard case .denied = state, SFSpeechRecognizer.authorizationStatus() == .authorized else { return }
        let microphone = AVAudioApplication.shared.recordPermission
        guard microphone == .granted || microphone == .undetermined else { return }
        transition(.permissionsRequestable)
    }

    func stop() {
        guard transition(.stop), case .finishing = state else { return }
        releaseAudio()
        let reason = transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Mira did not catch your words. Try again or type your request." : nil
        transition(.finished(reason))
    }

    private func releaseAudio() {
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
