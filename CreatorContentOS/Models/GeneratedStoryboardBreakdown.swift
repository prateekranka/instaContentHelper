import Foundation

struct GeneratedStoryboardBreakdownRow: Identifiable, Hashable, Sendable {
    let id: String
    let sceneNumber: Int
    let timecode: String
    let visualShot: String
    let whatToShow: String
    let audioDialogue: String
    let onScreenText: String
    let onScreenTextPlacement: String?
    let thumbnailURL: URL?
}

enum GeneratedStoryboardBreakdown {
    static func rows(for card: DailyCard) -> [GeneratedStoryboardBreakdownRow] {
        rows(
            for: GeneratedDailyCardDraft(
                id: card.id,
                scheduledDate: card.scheduledDate ?? "",
                status: "published",
                title: card.title,
                whyToday: card.whyToday,
                growthJob: card.whyToday,
                contentPillar: card.sourceNote ?? "Pattern",
                shootability: "easy",
                estimatedShootMinutes: 0,
                energyRequired: "low",
                languageMode: "Natural",
                hook: card.hook,
                sceneList: card.scenes,
                shotTimeline: card.shotTimeline ?? [],
                voiceoverTimeline: card.voiceoverTimeline ?? [],
                onScreenTextTimeline: card.onScreenTextTimeline ?? [],
                script: card.script ?? "",
                noVoiceoverVersion: card.noVoiceoverVersion ?? "",
                onScreenText: card.onScreenText ?? [],
                caption: card.caption ?? "",
                cta: card.cta ?? "",
                hashtags: card.hashtags ?? [],
                coverText: card.coverText ?? "",
                postInstructions: card.postInstructions ?? "",
                brandEventNotes: card.brandEventNotes ?? "",
                backupStory: card.backupStory ?? "",
                backupCaptionOnly: card.backupCaptionOnly ?? "",
                audioOptionNotes: card.audioOptionNotes ?? "",
                creatorFitScore: card.creatorFitScore ?? 0,
                riskNotes: card.riskNotes ?? [],
                assumptions: card.assumptions ?? [],
                sourceNote: card.sourceNote ?? "",
                storyboardThumbnailAssets: card.storyboardThumbnailAssets ?? []
            )
        )
    }

    static func rows(for card: GeneratedDailyCardDraft) -> [GeneratedStoryboardBreakdownRow] {
        let rowCount = [
            card.sceneList.count,
            card.shotTimeline.count,
            card.voiceoverTimeline.count,
            card.onScreenTextTimeline.count,
            card.onScreenText.count
        ]
            .max() ?? 0

        guard rowCount > 0 else { return [] }

        let derivedTimecodes = timecodes(for: card.sceneList)
        let thumbnailsByRow = card.storyboardThumbnailAssets.reduce(into: [Int: StoryboardThumbnailAsset]()) { result, asset in
            result[asset.rowIndex] = asset
        }

        return (0..<rowCount).map { index in
            let scene = element(at: index, in: card.sceneList)
            let shot = element(at: index, in: card.shotTimeline)
            let voiceover = element(at: index, in: card.voiceoverTimeline)
            let text = element(at: index, in: card.onScreenTextTimeline)
            let thumbnailURL = thumbnailsByRow[index]?.publicURL
                .flatMap { URL(string: $0) }

            let timecode = firstPresent(
                shot?.timestamp,
                voiceover?.timestamp,
                text?.timestamp,
                element(at: index, in: derivedTimecodes),
                scene?.duration
            ) ?? "Scene \(index + 1)"

            return GeneratedStoryboardBreakdownRow(
                id: "\(card.id.uuidString)-\(index)-\(timecode)",
                sceneNumber: scene?.number ?? index + 1,
                timecode: timecode,
                visualShot: firstPresent(
                    shot?.shot,
                    shot?.title,
                    scene?.title
                ) ?? "Shot not specified",
                whatToShow: firstPresent(
                    shot?.videoPortion,
                    shot?.detail,
                    shot?.title,
                    scene?.title
                ) ?? "Show the main action clearly.",
                audioDialogue: firstPresent(
                    voiceover?.voiceover,
                    voiceover?.detail,
                    voiceover?.title,
                    scriptLine(from: card.script, at: index)
                ) ?? "No voiceover specified.",
                onScreenText: firstPresent(
                    text?.onScreenText,
                    text?.title,
                    element(at: index, in: card.onScreenText)
                ) ?? "No on-screen text.",
                onScreenTextPlacement: firstPresent(
                    text?.placement,
                    text?.detail
                ),
                thumbnailURL: thumbnailURL
            )
        }
    }

    private static func firstPresent(_ values: String?...) -> String? {
        values.lazy.compactMap { $0?.nilIfBlank }.first
    }

    private static func element<T>(at index: Int, in values: [T]) -> T? {
        values.indices.contains(index) ? values[index] : nil
    }

    private static func scriptLine(from script: String, at index: Int) -> String? {
        let lines = script
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let line = element(at: index, in: lines) {
            return line
        }

        return index == 0 ? script.nilIfBlank : nil
    }

    private static func timecodes(for scenes: [ShotScene]) -> [String] {
        var cursor = 0
        return scenes.map { scene in
            let start = cursor
            cursor += seconds(from: scene.duration) ?? 0
            return "\(format(seconds: start))-\(format(seconds: cursor))"
        }
    }

    private static func seconds(from duration: String) -> Int? {
        let digits = duration.prefix { $0.isNumber }
        return Int(digits)
    }

    private static func format(seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

#if DEBUG
extension GeneratedDailyCardDraft {
    static var storyboardBreakdownFixture: GeneratedDailyCardDraft {
        GeneratedDailyCardDraft(
            id: UUID(uuidString: "1407E44A-1F70-4B96-8EE2-AD1E4E0E34C1") ?? UUID(),
            scheduledDate: "2026-07-01",
            status: "ready",
            title: "The biggest lie women are told after 40",
            whyToday: "A clear myth-busting reel that gives the creator a confident, personal story arc.",
            growthJob: "Build trust through identity-shifting fitness storytelling.",
            contentPillar: "Strength After 40",
            shootability: "Moderate",
            estimatedShootMinutes: 35,
            energyRequired: "medium",
            languageMode: "warm_direct",
            format: "Reel",
            primarySurface: "instagram_reels",
            durationSeconds: 30,
            hook: "The biggest lie women are told after 40? That getting stronger is not for them anymore.",
            saveShareReason: "Followers can save it as a reminder that strength training is still for them.",
            sceneList: [
                ShotScene(number: 1, title: "Confident talking-head hook", duration: "3 sec", symbol: "person.crop.rectangle"),
                ShotScene(number: 2, title: "Reflective b-roll by the window", duration: "3 sec", symbol: "figure.walk"),
                ShotScene(number: 3, title: "Early light-weight gym clip", duration: "3 sec", symbol: "dumbbell"),
                ShotScene(number: 4, title: "Walking into the gym", duration: "3 sec", symbol: "figure.strengthtraining.traditional"),
                ShotScene(number: 5, title: "Tiny dumbbell close-up", duration: "3 sec", symbol: "camera.macro"),
                ShotScene(number: 6, title: "Training and race montage", duration: "3 sec", symbol: "film.stack"),
                ShotScene(number: 7, title: "Confident lesson close-up", duration: "3 sec", symbol: "person.crop.circle"),
                ShotScene(number: 8, title: "Strong action lift", duration: "3 sec", symbol: "figure.strengthtraining.functional"),
                ShotScene(number: 9, title: "Race medal moment", duration: "3 sec", symbol: "medal"),
                ShotScene(number: 10, title: "Soft call-to-action", duration: "3 sec", symbol: "heart")
            ],
            shotTimeline: [
                ProductionTimelineItem(timestamp: "0-3 sec", title: "Talking head close-up", detail: "Look straight into camera with a confident hook.", shot: "Close-up talking head", videoPortion: "Direct eye contact. Calm, grounded face. Minimal background movement."),
                ProductionTimelineItem(timestamp: "3-6 sec", title: "Reflective b-roll", detail: "Cut to a quieter shot looking out or walking slowly.", shot: "B-roll reflective mood", videoPortion: "Soft profile shot that lets the viewer feel the old belief."),
                ProductionTimelineItem(timestamp: "6-9 sec", title: "Earlier gym clip", detail: "Show an older or early clip starting with lighter weights.", shot: "Old photo or early clip", videoPortion: "Light dumbbells, cautious posture, beginner energy."),
                ProductionTimelineItem(timestamp: "9-12 sec", title: "Entering gym", detail: "Show the creator walking into the gym and looking around.", shot: "Wide gym shot", videoPortion: "Slight uncertainty, real and unpolished."),
                ProductionTimelineItem(timestamp: "12-15 sec", title: "Tiny dumbbells", detail: "Film the small weights in hand.", shot: "Close-up hands", videoPortion: "Hands picking up light dumbbells or adjusting grip."),
                ProductionTimelineItem(timestamp: "15-18 sec", title: "Training montage", detail: "Use quick cuts from training, races, and finishing moments.", shot: "Montage", videoPortion: "Three fast clips showing evolution and current strength."),
                ProductionTimelineItem(timestamp: "18-21 sec", title: "Lesson close-up", detail: "Return to talking head with a decisive tone.", shot: "Talking head close-up", videoPortion: "Point gently toward camera or temple."),
                ProductionTimelineItem(timestamp: "21-24 sec", title: "Action lift", detail: "Show effort and movement.", shot: "Strength action shot", videoPortion: "A clean lift, pull, or controlled strength movement."),
                ProductionTimelineItem(timestamp: "24-27 sec", title: "Medal moment", detail: "Show a race finish or strong proud moment.", shot: "Finish-line b-roll", videoPortion: "Medal, smile, or post-race confidence."),
                ProductionTimelineItem(timestamp: "27-30 sec", title: "Closing CTA", detail: "Finish with a soft smile and clear call-to-action.", shot: "Talking head close-up", videoPortion: "Real expression, light smile, calm ending.")
            ],
            voiceoverTimeline: [
                ProductionTimelineItem(timestamp: "0-3 sec", title: "Hook", detail: "", voiceover: "The biggest lie women are told after 40?"),
                ProductionTimelineItem(timestamp: "3-6 sec", title: "Belief", detail: "", voiceover: "That getting stronger is not for them anymore."),
                ProductionTimelineItem(timestamp: "6-9 sec", title: "Admission", detail: "", voiceover: "I believed that too."),
                ProductionTimelineItem(timestamp: "9-12 sec", title: "Fear", detail: "", voiceover: "I was scared of the gym."),
                ProductionTimelineItem(timestamp: "12-15 sec", title: "Start", detail: "", voiceover: "I started small and wondered if I belonged there."),
                ProductionTimelineItem(timestamp: "15-18 sec", title: "Turn", detail: "", voiceover: "But here is what I learned."),
                ProductionTimelineItem(timestamp: "18-21 sec", title: "Lesson", detail: "", voiceover: "Your muscles do not know how old you are."),
                ProductionTimelineItem(timestamp: "21-24 sec", title: "Use", detail: "", voiceover: "They only know whether you use them."),
                ProductionTimelineItem(timestamp: "24-27 sec", title: "Proof", detail: "", voiceover: "I feel stronger in my 60s than I did in my 40s."),
                ProductionTimelineItem(timestamp: "27-30 sec", title: "CTA", detail: "", voiceover: "Do not let your age decide what your body is capable of.")
            ],
            onScreenTextTimeline: [
                ProductionTimelineItem(timestamp: "0-3 sec", title: "Hook text", detail: "", onScreenText: "The biggest lie women are told after 40?"),
                ProductionTimelineItem(timestamp: "3-6 sec", title: "Myth text", detail: "", onScreenText: "Getting stronger is not for them anymore."),
                ProductionTimelineItem(timestamp: "6-9 sec", title: "Belief text", detail: "", onScreenText: "I believed that too."),
                ProductionTimelineItem(timestamp: "9-12 sec", title: "Fear text", detail: "", onScreenText: "I was scared of the gym."),
                ProductionTimelineItem(timestamp: "12-15 sec", title: "Start text", detail: "", onScreenText: "I started small."),
                ProductionTimelineItem(timestamp: "15-18 sec", title: "Turn text", detail: "", onScreenText: "But here is what I learned..."),
                ProductionTimelineItem(timestamp: "18-21 sec", title: "Lesson text", detail: "", onScreenText: "Your muscles do not know how old you are."),
                ProductionTimelineItem(timestamp: "21-24 sec", title: "Use text", detail: "", onScreenText: "They only know whether you use them."),
                ProductionTimelineItem(timestamp: "24-27 sec", title: "Proof text", detail: "", onScreenText: "Stronger in my 60s than in my 40s."),
                ProductionTimelineItem(timestamp: "27-30 sec", title: "CTA text", detail: "", onScreenText: "Do not let your age decide what you are capable of.")
            ],
            script: """
            The biggest lie women are told after 40? That getting stronger is not for them anymore.
            I believed that too.
            I was scared of the gym.
            I started small and wondered if I belonged there.
            But here is what I learned.
            Your muscles do not know how old you are.
            They only know whether you use them.
            I feel stronger in my 60s than I did in my 40s.
            Do not let your age decide what your body is capable of.
            """,
            noVoiceoverVersion: "Use bold captions over the same shots and keep the edit moving every three seconds.",
            onScreenText: [
                "The biggest lie women are told after 40?",
                "Getting stronger is not for them anymore.",
                "I believed that too.",
                "I was scared of the gym.",
                "I started small.",
                "But here is what I learned...",
                "Your muscles do not know how old you are.",
                "They only know whether you use them.",
                "Stronger in my 60s than in my 40s.",
                "Do not let your age decide what you are capable of."
            ],
            caption: "Strength after 40 is not about proving anything. It is about giving your body chances to surprise you.",
            cta: "Save this for the day you need the reminder.",
            hashtags: ["strengthafter40", "womenwholift", "fitnessjourney"],
            coverText: "The biggest lie after 40",
            postInstructions: "Keep it real, natural, and personal. Mix present-day shots with old clips or photos. Use bold, high-contrast captions.",
            brandEventNotes: "",
            backupStory: "Post one mirror selfie or gym clip with the line: I started small too.",
            backupCaptionOnly: "Your age is not the limit. The story you keep repeating might be.",
            audioOptionNotes: "Use a calm but driving audio bed under the voiceover.",
            creatorFitScore: 94,
            riskNotes: [],
            assumptions: ["Creator has access to old race or gym clips."],
            sourceNote: "Inspired by the storyboard reference format supplied for mobile adaptation."
        )
    }
}
#endif
