import Foundation

enum MiraFixtures {
    static var mamta: MiraProfile {
        var profile = MiraProfile()
        profile.name = "Mamta"
        profile.themes = "Training after 60, healthy Indian eating, everyday mindset"
        profile.audience = "People building a sustainable routine"
        profile.language = .hinglish
        profile.avoid = "Big motivational claims and miracle health promises"
        return profile
    }
    static func output(for input: MiraGenerationInput) -> MiraOutput {
        switch input.operation {
        case .ideas:
            let minutes = min(input.constraints.filmingMinutes, 15)
            if !input.recentIdeas.isEmpty {
                let options = [
                    ("What I keep by the door", "Show the one thing you put where you will remember it."),
                    (
                        "A kitchen shortcut I actually use",
                        "Demonstrate one preparation step with ingredients already at home."
                    ),
                    (
                        "A quiet pause before the next task",
                        "Show a brief everyday pause without giving motivational advice."
                    ),
                ]
                return MiraOutput(
                    ideas: options.map { title, visual in
                        MiraIdea(
                            title: title, hook: "One small thing from my day.", visual: visual,
                            fit: "One familiar action and one fixed phone position.",
                            filmingMinutes: min(minutes, 10),
                            setup: "\(input.constraints.location); phone on a stable surface")
                    })
            }
            return MiraOutput(ideas: [
                MiraIdea(
                    title: "One breakfast I actually make",
                    hook: input.profile.language == .english
                        ? "My simple breakfast today." : "Aaj ka simple breakfast.",
                    visual: "Show ingredients, prepare your usual plate, then talk to camera.",
                    fit: "An everyday routine, filmed with your phone at home.", filmingMinutes: minutes,
                    setup: "\(input.constraints.location); phone on a stable shelf; your usual breakfast"),
                MiraIdea(
                    title: "My two-minute movement break", hook: "A small break between everyday tasks.",
                    visual: "Show one gentle movement you already practise, then explain when you do it.",
                    fit:
                        "One fixed phone position and a familiar movement. No exercise or health claims needed.",
                    filmingMinutes: min(minutes, 10),
                    setup: "\(input.constraints.location); clear floor space; stable phone placement"),
                MiraIdea(
                    title: "One thing I prepare the night before",
                    hook: "This saves me one decision in the morning.",
                    visual: "Lay out your usual water bottle, shoes or breakfast ingredients.",
                    fit: "A simple visual story with optional voiceover and no other person needed.",
                    filmingMinutes: min(minutes, 10),
                    setup: "\(input.constraints.location); tabletop; one object you already own"),
            ])
        case .script, .reviseScript:
            let short = input.request.localizedCaseInsensitiveContains("short")
            let hook: String
            let spoken: String
            let caption: String
            switch input.profile.language {
            case .english:
                hook = "Here is one small part of my day."
                spoken =
                    short
                    ? "I keep it simple, with things I already have. This is what works for my routine."
                    : "I keep this part of my routine simple. I use what I already have at home, and give myself a little time. Some days it looks different, and that is fine. This is how I am doing it today."
                caption = "An everyday part of my routine. What do you keep simple?"
            case .hindi:
                hook =
                    input.profile.writingSystem == .devanagari
                    ? "आज की मेरी छोटी सी दिनचर्या।" : "Aaj ki meri chhoti si dincharya."
                spoken =
                    input.profile.writingSystem == .devanagari
                    ? "मैं इसे आसान रखती हूँ। घर में जो है, उसी से शुरुआत करती हूँ। हर दिन एक जैसा नहीं होता। आज मेरे लिए इतना ठीक है।"
                    : "Main ise aasaan rakhti hoon. Ghar mein jo hai, usi se shuruaat karti hoon. Har din ek jaisa nahi hota. Aaj mere liye itna theek hai."
                caption =
                    input.profile.writingSystem == .devanagari
                    ? "मेरी रोज़ की एक छोटी सी बात।" : "Meri roz ki ek chhoti si baat."
            case .hinglish:
                hook =
                    input.profile.writingSystem == .devanagari
                    ? "आज कुछ simple रखते हैं।" : "Aaj kuch simple rakhte hain."
                spoken =
                    input.profile.writingSystem == .devanagari
                    ? "घर पर जो है, उसी से शुरू करती हूँ। कोई perfect routine नहीं है। आज मेरे पास थोड़ा time है, तो इतना कर लेती हूँ। बस, यही मेरा तरीका है।"
                    : "Ghar par jo hai, usi se shuru karti hoon. Koi perfect routine nahi hai. Aaj mere paas thoda time hai, toh itna kar leti hoon. Bas, yahi mera tareeka hai."
                caption =
                    input.profile.writingSystem == .devanagari
                    ? "आज का छोटा सा routine।" : "Aaj ka chhota sa routine."
            }
            return MiraOutput(
                script: MiraScript(
                    hook: hook, spoken: spoken, caption: caption,
                    durationSeconds: short ? 18 : min(30, input.constraints.reelSeconds),
                    language: input.profile.language.rawValue))
        case .storyboard, .reviseShot, .reviseStoryboard:
            guard let script = input.script else {
                return MiraOutput(conflicts: ["Choose and approve a script first."])
            }
            let seconds = script.durationSeconds
            var shots =
                input.storyboard?.shots ?? [
                    MiraShot(
                        purpose: "Introduce the idea", editedSeconds: 5, recordingSeconds: 12,
                        location: input.constraints.location, props: "Phone and a stable shelf",
                        placement:
                            "Stand the phone securely at eye level on a shelf, away from edges. Face a window.",
                        action: "Look at the lens and say the opening line. Pause before and after.",
                        words: script.hook, voiceover: false, onScreenText: "",
                        simplerAlternative: "Sit at a table with the phone supported by heavy books."),
                    MiraShot(
                        purpose: "Show your routine", editedSeconds: max(1, seconds - 10),
                        recordingSeconds: max(18, seconds), location: input.constraints.location,
                        props: "One familiar object from your routine",
                        placement:
                            "Place the phone on a stable table, with the object in frame. Keep the phone away from heat and water.",
                        action:
                            "Film one simple action with your hands. Record the voiceover separately in a quiet place.",
                        words: script.spoken, voiceover: true, onScreenText: "My everyday routine",
                        simplerAlternative: "Keep the camera still and point to the object while seated."),
                    MiraShot(
                        purpose: "Close the thought", editedSeconds: 5, recordingSeconds: 10,
                        location: input.constraints.location, props: "Same setup as the opening",
                        placement: "Return to the same eye-level phone position.",
                        action: "Give a natural closing look, or hold the final scene for five seconds.",
                        words: "", voiceover: false, onScreenText: "",
                        simplerAlternative: "Use a still view of the finished setup."),
                ]
            if let target = input.targetShotID, let index = shots.firstIndex(where: { $0.id == target }) {
                shots[index].placement =
                    "Support the phone securely between heavy books on a stable table. Keep it away from edges."
                shots[index].action = "Stay seated. Film the same action in one fixed view."
            }
            if input.request.lowercased().contains("home") {
                for i in shots.indices { shots[i].location = "Home" }
            }
            let board = MiraStoryboard(
                sourceScriptID: script.id, requirementsRevision: input.brief?.revision ?? 0, shots: shots,
                mappings: [])
            return MiraOutput(
                storyboard: board,
                conflicts: input.brief?.requirements.isEmpty == false
                    ? [
                        "The demo cannot verify a brand mapping. Review the brief manually or use live generation."
                    ] : [])
        case .requirements:
            let original = input.brief?.original ?? ""
            var brief = MiraBrief()
            brief.original = original
            for line in original.split(separator: "\n").map(String.init) where line.contains(":") {
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                brief.requirements.append(
                    MiraRequirement(
                        kind: parts[0], value: parts[1].trimmingCharacters(in: .whitespaces), excerpt: line))
            }
            brief.unresolved = [
                "Demo extraction only reads labelled lines. Confirm every requirement against the original; missing codes and claims remain unresolved."
            ]
            return MiraOutput(brief: brief)
        }
    }
}

struct MiraFixtureGenerationService: MiraGenerationService {
    func start(_ job: MiraJob) async throws -> MiraJob {
        try Task.checkCancellation()
        var result = job
        result.output = MiraFixtures.output(for: job.input)
        result.state = .succeeded
        try MiraValidation.validate(result.output!, for: job.input.operation, input: job.input)
        return result
    }
    func status(_ job: MiraJob) async throws -> MiraJob { try await start(job) }
    func cancel(_ job: MiraJob) async throws -> MiraJob {
        var result = job
        result.state = .cancelled
        return result
    }
}
