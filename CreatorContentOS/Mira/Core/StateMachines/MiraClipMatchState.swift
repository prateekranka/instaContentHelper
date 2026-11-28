import Foundation

enum MiraClipMatchEvent {
    case importClips(MiraStoryboard, [MiraClip])
    case assign(shot: UUID, clip: UUID, board: MiraStoryboard)
}

enum MiraClipMatchState {
    case empty(MiraDelivery)
    case matching(MiraDelivery)
    case matched(MiraDelivery)

    init(record: MiraDelivery, board: MiraStoryboard) {
        if record.clips.isEmpty {
            self = .empty(record)
        } else if !board.shots.isEmpty, board.shots.allSatisfy({ record.plans[board.id]?.assignments[$0.id] != nil }) {
            self = .matched(record)
        } else {
            self = .matching(record)
        }
    }

    var record: MiraDelivery {
        switch self {
        case .empty(let record), .matching(let record), .matched(let record): record
        }
    }

    var nextAction: MiraNextAction {
        switch self {
        case .empty, .matching: .prepareClips
        case .matched: .joinReel
        }
    }

    func handle(_ event: MiraClipMatchEvent) -> Self? {
        var next = record
        switch event {
        case .importClips(let board, let clips):
            var plan = next.plans[board.id] ?? MiraClipPlan()
            for clip in clips where !next.clips.contains(where: {
                $0.id == clip.id || (clip.sourceID != nil && $0.sourceID == clip.sourceID)
            }) {
                next.clips.append(clip)
            }
            let available = next.clips.filter { !plan.assignments.values.contains($0.id) }
            match(available, to: board.shots, plan: &plan)
            next.plans[board.id] = plan
            return Self(record: next, board: board)
        case .assign(let shot, let clip, let board):
            guard board.shots.contains(where: { $0.id == shot }),
                next.clips.contains(where: { $0.id == clip }) else { return nil }
            var plan = next.plans[board.id] ?? MiraClipPlan()
            if let other = plan.assignments.first(where: { $0.value == clip })?.key, other != shot {
                plan.assignments[other] = plan.assignments[shot]
            }
            plan.assignments[shot] = clip
            next.plans[board.id] = plan
            return Self(record: next, board: board)
        }
    }

    private func match(_ clips: [MiraClip], to shots: [MiraShot], plan: inout MiraClipPlan) {
        let orderedShots = shots.enumerated().filter { plan.assignments[$0.element.id] == nil }.sorted {
            if $0.element.editedSeconds != $1.element.editedSeconds { return $0.element.editedSeconds < $1.element.editedSeconds }
            return $0.offset < $1.offset
        }
        let orderedClips = clips.enumerated().sorted {
            if $0.element.seconds != $1.element.seconds { return $0.element.seconds < $1.element.seconds }
            if let first = $0.element.createdAt, let second = $1.element.createdAt, first != second {
                return first < second
            }
            if ($0.element.createdAt == nil) != ($1.element.createdAt == nil) { return $0.element.createdAt != nil }
            return $0.offset < $1.offset
        }
        let dates = clips.compactMap(\.createdAt).sorted()
        let fewerShots = orderedShots.count <= orderedClips.count
        let pairs = orderedPairs(shorter: min(orderedShots.count, orderedClips.count),
            longer: max(orderedShots.count, orderedClips.count)) { row, column in
            let shot = orderedShots[fewerShots ? row : column]
            let clip = orderedClips[fewerShots ? column : row]
            let difference = abs(clip.element.seconds - Double(shot.element.editedSeconds))
            let short = clip.element.seconds + 0.05 < Double(shot.element.editedSeconds)
            let recordedOrder = clip.element.createdAt.flatMap { dates.firstIndex(of: $0) } ?? clip.offset
            return (short ? 10_000 : 0) + min(difference, 1000) * 10
                + Double(abs(shot.offset - recordedOrder)) * 0.2 + Double(abs(shot.offset - clip.offset)) * 0.1
        }
        for (row, column) in pairs {
            let shot = orderedShots[fewerShots ? row : column].element
            let clip = orderedClips[fewerShots ? column : row].element
            plan.assignments[shot.id] = clip.id
        }
    }

    private func orderedPairs(
        shorter: Int, longer: Int, cost: (Int, Int) -> Double
    ) -> [(Int, Int)] {
        guard shorter > 0 else { return [] }
        var totals = Array(repeating: Array(repeating: Double.infinity, count: longer + 1), count: shorter + 1)
        var used = Array(repeating: Array(repeating: false, count: longer + 1), count: shorter + 1)
        totals[0] = Array(repeating: 0, count: longer + 1)
        for row in 1...shorter {
            for column in row...longer {
                let paired = totals[row - 1][column - 1] + cost(row - 1, column - 1)
                let skipped = totals[row][column - 1]
                used[row][column] = paired < skipped
                totals[row][column] = min(paired, skipped)
            }
        }
        var row = shorter
        var column = longer
        var pairs: [(Int, Int)] = []
        while row > 0 && column > 0 {
            if used[row][column] {
                pairs.append((row - 1, column - 1))
                row -= 1
            }
            column -= 1
        }
        return pairs
    }
}
