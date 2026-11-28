import Foundation

enum MiraVoiceInputEvent {
    case start(UUID), recording(UUID), tick(UUID, Int), denied(UUID), failed(UUID, String)
    case stop, finished(String?), permissionsRequestable
}

enum MiraVoiceInputState: Equatable {
    case idle
    case askingPermission(UUID)
    case denied
    case recording(UUID, elapsed: Int)
    case finishing
    case failed(String)

    func handle(_ event: MiraVoiceInputEvent) -> Self? {
        switch (self, event) {
        case (.idle, .start(let id)), (.failed, .start(let id)): .askingPermission(id)
        case (.askingPermission(let id), .recording(let reply)) where id == reply: .recording(id, elapsed: 0)
        case (.askingPermission(let id), .denied(let reply)) where id == reply: .denied
        case (.askingPermission(let id), .failed(let reply, let reason)) where id == reply: .failed(reason)
        case (.recording(let id, _), .tick(let reply, let elapsed)) where id == reply:
            .recording(id, elapsed: elapsed)
        case (.denied, .permissionsRequestable): .idle
        case (.askingPermission, .stop): .idle
        case (.recording, .stop): .finishing
        case (.finishing, .finished(let reason)): reason.map { .failed($0) } ?? .idle
        default: nil
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .idle, .failed: .useMicrophone
        case .askingPermission, .finishing: .wait
        case .denied: .openSettings
        case .recording: .stopRecording
        }
    }

    var message: String? {
        switch self {
        case .idle: nil
        case .askingPermission: "Checking microphone permission."
        case .denied: "To use voice input, allow Speech Recognition and Microphone in Settings. You can still type."
        case .recording(_, let elapsed): "Recording · \(elapsed) of 60 seconds."
        case .finishing: "Finishing your recording."
        case .failed(let reason): reason
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
}
