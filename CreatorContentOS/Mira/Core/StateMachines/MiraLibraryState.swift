import Foundation

enum MiraLibraryOpenFailure: LocalizedError, Equatable {
    case damaged
    case restored
    case newerVersion
    case unavailable(String)

    var errorDescription: String? { message }

    var message: String {
        switch self {
        case .damaged:
            "Saved work could not be read. It has been preserved for recovery. Mira will not replace it with an empty document."
        case .restored:
            "Recovered your last safe save. Try opening saved work again. Any damaged document is kept for recovery."
        case .newerVersion:
            "This library was saved by a newer Mira version. It has not been changed."
        case .unavailable(let reason): reason
        }
    }
}

enum MiraLibraryEvent {
    case open, opened, openFailed(MiraLibraryOpenFailure)
    case saved, saveFailed(String), reportError(String), dismissError
}

enum MiraLibraryState {
    case unopened
    case opening
    case openFailed(MiraLibraryOpenFailure)
    case loaded(saveMessage: String?, alert: String?)

    func handle(_ event: MiraLibraryEvent) -> Self? {
        switch (self, event) {
        case (.unopened, .open), (.openFailed, .open): .opening
        case (.opening, .opened): .loaded(saveMessage: nil, alert: nil)
        case (.opening, .openFailed(let reason)): .openFailed(reason)
        case (.loaded(_, let alert), .saved): .loaded(saveMessage: nil, alert: alert)
        case (.loaded(_, let alert), .saveFailed(let message)): .loaded(saveMessage: message, alert: alert)
        case (.loaded(let message, _), .reportError(let error)): .loaded(saveMessage: message, alert: error)
        case (.loaded(let message, _), .dismissError): .loaded(saveMessage: message, alert: nil)
        default: nil
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .unopened, .opening: .wait
        case .openFailed(.newerVersion): .updateApp
        case .openFailed: .tryOpeningLibrary
        case .loaded: .continueWork
        }
    }

    var alert: String? {
        if case .loaded(_, let alert) = self { return alert }
        return nil
    }
}
