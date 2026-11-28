import Foundation

enum MiraValidation {
    static func matchesDialogue(_ board: MiraStoryboard, script: MiraScript) -> Bool {
        func normalize(_ text: String) -> String {
            text.replacingOccurrences(of: "[‘’]", with: "'", options: .regularExpression)
                .replacingOccurrences(of: "[“”]", with: "\"", options: .regularExpression)
                .replacingOccurrences(
                    of: #"[\u0009-\u000d\u0020\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+"#,
                    with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " "))
        }
        let hook = normalize(script.hook)
        let spoken = normalize(script.spoken)
        let expected = spoken.utf16.starts(with: hook.utf16)
            ? spoken : [hook, spoken].filter { !$0.isEmpty }.joined(separator: " ")
        let actual = board.shots.map { normalize($0.words) }.filter { !$0.isEmpty }.joined(separator: " ")
        return !board.shots.isEmpty && actual.utf16.elementsEqual(expected.utf16)
    }

    static func validate(_ output: MiraOutput, for operation: MiraOperation, input: MiraGenerationInput?)
        throws
    {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw MiraError.invalid(message) }
        }
        if !output.conflicts.isEmpty, output.ideas == nil, output.script == nil, output.storyboard == nil,
            output.brief == nil
        {
            if operation != .todayIdea { return }
        }
        switch operation {
        case .todayIdea:
            guard let idea = output.ideas?.first, output.ideas?.count == 1,
                let script = output.script, let board = output.storyboard, let input
            else { throw MiraError.invalid("The Reel card was incomplete.") }
            try require(output.brief == nil && output.conflicts.isEmpty, "The Reel card has conflicts.")
            try require(
                !idea.title.isEmpty && !idea.hook.isEmpty && !idea.visual.isEmpty && !idea.fit.isEmpty
                    && !idea.setup.isEmpty && idea.filmingMinutes > 0
                    && idea.filmingMinutes <= input.constraints.filmingMinutes,
                "Idea details were incomplete or did not fit the filming time.")
            try require(
                (3...5).contains(board.shots.count) && board.shots.allSatisfy { $0.frameType != nil },
                "Expected three to five shots with a picture for each shot.")
            try require(script.language == input.profile.language.rawValue, "The script language is incorrect.")
            try validate(MiraOutput(script: script), for: .script, input: input)
            var boardInput = input
            boardInput.script = script
            try validate(MiraOutput(storyboard: board), for: .storyboard, input: boardInput)
        case .ideas:
            guard let ideas = output.ideas else { throw MiraError.invalid("Ideas were missing.") }
            try require(
                ideas.count == 3 && Set(ideas.map { $0.title.lowercased() }).count == 3
                    && Set(ideas.map(\.id)).count == 3, "Expected three distinct ideas.")
            for idea in ideas {
                try require(
                    !idea.title.isEmpty && !idea.hook.isEmpty && !idea.visual.isEmpty && !idea.fit.isEmpty
                        && !idea.setup.isEmpty, "Idea details were incomplete.")
                try require(
                    idea.filmingMinutes > 0
                        && idea.filmingMinutes <= (input?.constraints.filmingMinutes ?? 180),
                    "Idea exceeds available filming time.")
            }
        case .script, .reviseScript:
            guard let script = output.script else { throw MiraError.invalid("Script was missing.") }
            try require(
                !script.hook.isEmpty && !script.spoken.isEmpty && !script.caption.isEmpty
                    && !script.language.isEmpty, "Script sections were incomplete.")
            try require((5...180).contains(script.durationSeconds), "Script duration is invalid.")
            if let input {
                try require(
                    script.durationSeconds <= input.constraints.reelSeconds + 5,
                    "Script is longer than the target Reel.")
                let words = (script.hook + " " + script.spoken).split(whereSeparator: { $0.isWhitespace })
                    .count
                try require(
                    Double(words) / Double(script.durationSeconds) <= 3.4,
                    "The script is too dense to speak comfortably.")
            }
        case .storyboard, .reviseShot, .reviseStoryboard:
            guard let board = output.storyboard else { throw MiraError.invalid("Shot list was missing.") }
            try require(
                !board.shots.isEmpty && board.shots.count <= 16
                    && Set(board.shots.map(\.id)).count == board.shots.count, "Shot identities are invalid.")
            for shot in board.shots {
                try require(
                    shot.editedSeconds > 0 && shot.recordingSeconds >= shot.editedSeconds
                        && shot.recordingSeconds <= 180, "Shot duration is invalid.")
                try require(
                    !shot.placement.isEmpty && !shot.action.isEmpty && !shot.purpose.isEmpty
                        && !shot.location.isEmpty, "Filming instructions were incomplete.")
            }
            let total = board.shots.reduce(0) { $0 + $1.editedSeconds }
            if let input {
                try require(
                    board.sourceScriptID == input.script?.id
                        && board.requirementsRevision == (input.brief?.revision ?? 0),
                    "Shot list source revision is invalid.")
                try require(
                    abs(total - (input.script?.durationSeconds ?? input.constraints.reelSeconds)) <= 5,
                    "Shot timings do not fit the script.")
                try require(
                    board.shots.reduce(0) { $0 + $1.recordingSeconds } <= input.constraints.filmingMinutes
                        * 60, "Recording time exceeds the available time.")
                let requirements = input.brief?.requirements ?? []
                for mapping in board.mappings {
                    try require(
                        requirements.contains { $0.id == mapping.requirementID },
                        "Unknown brand requirement mapping.")
                    try require(
                        mapping.shotIDs.allSatisfy { id in board.shots.contains { $0.id == id } },
                        "Unknown shot mapping.")
                    if !mapping.scriptExcerpt.isEmpty {
                        try require(
                            [
                                input.script?.hook ?? "", input.script?.spoken ?? "",
                                input.script?.caption ?? "",
                            ].contains(where: { $0.contains(mapping.scriptExcerpt) }),
                            "Mapped words are not in the script.")
                    }
                }
                for requirement in requirements {
                    try require(
                        board.mappings.contains {
                            $0.requirementID == requirement.id
                                && (!$0.shotIDs.isEmpty || !$0.scriptExcerpt.isEmpty)
                        } || !output.conflicts.isEmpty, "A confirmed requirement is unmapped.")
                }
                if operation == .reviseShot {
                    guard let target = input.targetShotID, let previous = input.storyboard?.shots,
                        previous.contains(where: { $0.id == target })
                    else {
                        throw MiraError.invalid("Unknown shot revision target.")
                    }
                    try require(
                        board.shots.map(\.id) == previous.map(\.id),
                        "A single-shot revision must keep the same shots in order.")
                    try require(
                        zip(previous, board.shots).allSatisfy { $0.id == target || $0 == $1 },
                        "An unrelated shot changed.")
                }
            }
        case .requirements:
            guard let brief = output.brief, let source = input?.brief?.original else {
                throw MiraError.invalid("Brief extraction was missing its source.")
            }
            try require(brief.original == source, "Original brief must be preserved.")
            for requirement in brief.requirements {
                try require(
                    !requirement.excerpt.isEmpty && source.contains(requirement.excerpt)
                        && !requirement.value.isEmpty && source.contains(requirement.value),
                    "A requirement has no exact source excerpt and value.")
            }
        }
    }
}
