import Foundation

struct MiraInterviewAnswers: Equatable {
    static let questions = [
        "What do you post about?",
        "Who watches your Reels?",
        "What do you want people to get from your Reels?",
        "What words or phrases sound like you?",
        "What do you never do in your Reels?",
        "What are your goals?",
    ]

    static let answerLimit = 1200
    var index = 0
    var values = Array(repeating: "", count: questions.count)
    var answer: String { values[index] }
    var isLast: Bool { index == Self.questions.count - 1 }
    var canAdvance: Bool { !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var transcript: String {
        zip(Self.questions, values).map { "\($0)\n\($1.trimmingCharacters(in: .whitespacesAndNewlines))" }
            .joined(separator: "\n\n")
    }
}

enum MiraBrandInterviewEvent {
    case start
    case edit(String)
    case back
    case next
    case generate(MiraJob)
    case received(UUID)
    case failed(MiraJob, String)
    case reset
}

enum MiraBrandInterview: Equatable {
    case idle
    case answering(MiraInterviewAnswers)
    case generating(MiraInterviewAnswers, MiraJob)
    case failed(MiraInterviewAnswers, MiraJob, String)

    var nextAction: MiraNextAction {
        switch self {
        case .idle: .startBrandInterview
        case .answering(let answers): answers.isLast ? .makeBrandDoc : .nextQuestion
        case .generating: .wait
        case .failed: .retry
        }
    }

    func handle(_ event: MiraBrandInterviewEvent) -> Self? {
        switch (self, event) {
        case (_, .reset):
            return .idle
        case (.idle, .start):
            return .answering(MiraInterviewAnswers())
        case (.answering(var answers), .edit(let text)):
            let prefix = text.utf16.prefix(MiraInterviewAnswers.answerLimit)
            let splitsSurrogate = text.utf16.dropFirst(MiraInterviewAnswers.answerLimit).first.map {
                (0xDC00...0xDFFF).contains($0)
            } == true
            answers.values[answers.index] = String(decoding: prefix.dropLast(splitsSurrogate ? 1 : 0), as: UTF16.self)
            return .answering(answers)
        case (.answering(var answers), .back) where answers.index > 0:
            answers.index -= 1
            return .answering(answers)
        case (.answering(var answers), .next) where answers.canAdvance && !answers.isLast:
            answers.index += 1
            return .answering(answers)
        case (.answering(let answers), .generate(let job)) where answers.canAdvance && answers.isLast:
            return .generating(answers, job)
        case (.failed(let answers, _, _), .generate(let job)):
            return .generating(answers, job)
        case (.failed(let answers, _, _), .back):
            return .answering(answers)
        case (.generating(_, let job), .received(let id)) where job.id == id:
            return .idle
        case (.generating(let answers, let job), .failed(let reply, let message)) where job.id == reply.id:
            return .failed(answers, reply, message)
        default:
            return nil
        }
    }
}
