import Foundation

struct OnboardingContextQuestion: Identifiable, Hashable, Sendable {
    let id: String
    let interestIDs: [String]
    let prompt: String
    let placeholder: String
    let isRequired: Bool

    var accessibilityIdentifier: String {
        "onboarding.context.\(id)"
    }
}

enum OnboardingContextQuestions {
    private static let catalog: [OnboardingContextQuestion] = [
        // Books
        OnboardingContextQuestion(
            id: "books-reading",
            interestIDs: ["books"],
            prompt: "What's the last book you read or what are you reading now?",
            placeholder: "I just finished Fourth Wing!",
            isRequired: false
        ),
        // Movies & TV
        OnboardingContextQuestion(
            id: "movies-watching",
            interestIDs: ["movies-tv"],
            prompt: "What shows or movies are you watching and excited about?",
            placeholder: "I'm watching Dune and excited for Wicked.",
            isRequired: false
        ),
        // Fitness
        OnboardingContextQuestion(
            id: "fitness-focus",
            interestIDs: ["fitness-wellness"],
            prompt: "What are you working on in fitness or wellness right now?",
            placeholder: "Building a consistent morning walk habit.",
            isRequired: false
        ),
        OnboardingContextQuestion(
            id: "fitness-style",
            interestIDs: ["fitness-wellness"],
            prompt: "Do you prefer documenting your routine, explaining what you learned, or keeping it entertaining?",
            placeholder: "Mostly documenting with quick tips mixed in.",
            isRequired: false
        ),
        // Lifestyle
        OnboardingContextQuestion(
            id: "lifestyle-moment",
            interestIDs: ["lifestyle"],
            prompt: "What's one thing in your life you're enjoying lately?",
            placeholder: "Slow mornings and cooking more at home.",
            isRequired: false
        ),
        // Food
        OnboardingContextQuestion(
            id: "food-craving",
            interestIDs: ["food-cooking"],
            prompt: "What kind of food or recipes are you into right now?",
            placeholder: "Quick vegetarian bowls and sourdough experiments.",
            isRequired: false
        ),
        // Travel
        OnboardingContextQuestion(
            id: "travel-plans",
            interestIDs: ["travel"],
            prompt: "Any trips coming up or places on your list?",
            placeholder: "Planning a long weekend in Lisbon.",
            isRequired: false
        ),
        // Fashion
        OnboardingContextQuestion(
            id: "fashion-vibe",
            interestIDs: ["fashion-beauty"],
            prompt: "What style or beauty vibe are you into lately?",
            placeholder: "Minimal outfits and dewy skin.",
            isRequired: false
        ),
        // Business
        OnboardingContextQuestion(
            id: "business-focus",
            interestIDs: ["business-career"],
            prompt: "What are you building or focused on at work?",
            placeholder: "Growing a freelance design practice.",
            isRequired: false
        ),
        // Gaming
        OnboardingContextQuestion(
            id: "gaming-playing",
            interestIDs: ["gaming"],
            prompt: "What are you playing or excited to play?",
            placeholder: "Cozy indie games after work.",
            isRequired: false
        ),
        // Art
        OnboardingContextQuestion(
            id: "art-making",
            interestIDs: ["art-creativity"],
            prompt: "What are you making or experimenting with creatively?",
            placeholder: "Watercolour sketches and short animations.",
            isRequired: false
        ),
        // Parenting
        OnboardingContextQuestion(
            id: "parenting-stage",
            interestIDs: ["parenting"],
            prompt: "What's your parenting stage or focus right now?",
            placeholder: "Navigating toddler routines and bedtime.",
            isRequired: false
        ),
        // Custom subjects
        OnboardingContextQuestion(
            id: "custom-topic",
            interestIDs: ["custom"],
            prompt: "What's happening in your world around this topic?",
            placeholder: "Tell us what's current for you.",
            isRequired: false
        ),
        OnboardingContextQuestion(
            id: "custom-angle",
            interestIDs: ["custom"],
            prompt: "What angle would feel most like you?",
            placeholder: "Honest reviews, behind-the-scenes, quick tips…",
            isRequired: false
        ),
    ]

    static func promptedQuestions(
        interestIDs: [String],
        customSubjects: [String]
    ) -> [OnboardingContextQuestion] {
        var matched: [OnboardingContextQuestion] = []
        for interestID in interestIDs {
            matched.append(contentsOf: catalog.filter { $0.interestIDs.contains(interestID) })
        }
        if !customSubjects.isEmpty {
            matched.append(contentsOf: catalog.filter { $0.interestIDs.contains("custom") })
        }

        var seen = Set<String>()
        matched = matched.filter { question in
            guard !seen.contains(question.id) else { return false }
            seen.insert(question.id)
            return true
        }

        if matched.isEmpty {
            matched = Array(catalog.filter { $0.interestIDs.contains("lifestyle") }.prefix(1))
        }

        return selectComplementaryPair(from: matched)
    }

    private static func selectComplementaryPair(
        from questions: [OnboardingContextQuestion]
    ) -> [OnboardingContextQuestion] {
        guard questions.count > 2 else { return questions }

        if questions.count >= 2 {
            let first = questions[0]
            if let second = questions.dropFirst().first(where: { $0.interestIDs != first.interestIDs }) {
                return [first, second]
            }
        }
        return Array(questions.prefix(2))
    }
}
