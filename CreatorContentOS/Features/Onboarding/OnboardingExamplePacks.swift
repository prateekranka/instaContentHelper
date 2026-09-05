import Foundation

enum OnboardingExamplePacks {
    private static let allExamples: [OnboardingTasteExample] = [
        // Books
        OnboardingTasteExample(id: "books-rec-1", interestID: "books", title: "3 underrated books that deserve a screen adaptation", style: .recommendation),
        OnboardingTasteExample(id: "books-op-1", interestID: "books", title: "Books vs. the movie — which is better?", style: .opinion),
        OnboardingTasteExample(id: "books-hum-1", interestID: "books", title: "A day in my life as a book lover and movie fan", style: .personalHumour),
        OnboardingTasteExample(id: "books-rec-2", interestID: "books", title: "What I'm reading this month (honest takes)", style: .recommendation),
        OnboardingTasteExample(id: "books-op-2", interestID: "books", title: "Unpopular opinion: this bestseller didn't land for me", style: .opinion),

        // Movies & TV
        OnboardingTasteExample(id: "movies-rec-1", interestID: "movies-tv", title: "Shows worth your weekend — my short list", style: .recommendation),
        OnboardingTasteExample(id: "movies-op-1", interestID: "movies-tv", title: "Hot take: the finale was actually fine", style: .opinion),
        OnboardingTasteExample(id: "movies-hum-1", interestID: "movies-tv", title: "Things only binge-watchers understand", style: .personalHumour),
        OnboardingTasteExample(id: "movies-rec-2", interestID: "movies-tv", title: "One scene that changed how I watch films", style: .recommendation),
        OnboardingTasteExample(id: "movies-op-2", interestID: "movies-tv", title: "Remakes vs. originals — my verdict", style: .opinion),

        // Fitness & Wellness
        OnboardingTasteExample(id: "fit-rec-1", interestID: "fitness-wellness", title: "A realistic morning routine that actually sticks", style: .recommendation),
        OnboardingTasteExample(id: "fit-op-1", interestID: "fitness-wellness", title: "What I stopped doing at the gym (and why)", style: .opinion),
        OnboardingTasteExample(id: "fit-hum-1", interestID: "fitness-wellness", title: "POV: you said you'd start Monday", style: .personalHumour),
        OnboardingTasteExample(id: "fit-rec-2", interestID: "fitness-wellness", title: "3 stretches that saved my back", style: .recommendation),
        OnboardingTasteExample(id: "fit-op-2", interestID: "fitness-wellness", title: "Wellness trends I think are overrated", style: .opinion),

        // Lifestyle
        OnboardingTasteExample(id: "life-rec-1", interestID: "lifestyle", title: "Small habits that made my week smoother", style: .recommendation),
        OnboardingTasteExample(id: "life-op-1", interestID: "lifestyle", title: "Things I stopped buying to simplify life", style: .opinion),
        OnboardingTasteExample(id: "life-hum-1", interestID: "lifestyle", title: "A chaotic but honest day in my life", style: .personalHumour),
        OnboardingTasteExample(id: "life-rec-2", interestID: "lifestyle", title: "Sunday reset routine — what actually helps", style: .recommendation),
        OnboardingTasteExample(id: "life-op-2", interestID: "lifestyle", title: "Aesthetic vs. practical — where I land", style: .opinion),

        // Food & Cooking
        OnboardingTasteExample(id: "food-rec-1", interestID: "food-cooking", title: "5-ingredient dinners I make on repeat", style: .recommendation),
        OnboardingTasteExample(id: "food-op-1", interestID: "food-cooking", title: "Restaurant dish I'd never order again", style: .opinion),
        OnboardingTasteExample(id: "food-hum-1", interestID: "food-cooking", title: "Cooking fail turned into a win", style: .personalHumour),
        OnboardingTasteExample(id: "food-rec-2", interestID: "food-cooking", title: "Pantry staples worth keeping stocked", style: .recommendation),
        OnboardingTasteExample(id: "food-op-2", interestID: "food-cooking", title: "Fusion food hot take", style: .opinion),

        // Travel
        OnboardingTasteExample(id: "travel-rec-1", interestID: "travel", title: "Hidden spots I'd revisit tomorrow", style: .recommendation),
        OnboardingTasteExample(id: "travel-op-1", interestID: "travel", title: "Overrated tourist stops — skip these", style: .opinion),
        OnboardingTasteExample(id: "travel-hum-1", interestID: "travel", title: "Packing like I haven't learned anything", style: .personalHumour),
        OnboardingTasteExample(id: "travel-rec-2", interestID: "travel", title: "How I plan trips without overplanning", style: .recommendation),
        OnboardingTasteExample(id: "travel-op-2", interestID: "travel", title: "Solo travel vs. group — my preference", style: .opinion),

        // Fashion & Beauty
        OnboardingTasteExample(id: "fashion-rec-1", interestID: "fashion-beauty", title: "Outfits I reach for every week", style: .recommendation),
        OnboardingTasteExample(id: "fashion-op-1", interestID: "fashion-beauty", title: "Trend I'm not buying into", style: .opinion),
        OnboardingTasteExample(id: "fashion-hum-1", interestID: "fashion-beauty", title: "Getting ready vs. how I actually look", style: .personalHumour),
        OnboardingTasteExample(id: "fashion-rec-2", interestID: "fashion-beauty", title: "Products that earned a permanent spot", style: .recommendation),
        OnboardingTasteExample(id: "fashion-op-2", interestID: "fashion-beauty", title: "Drugstore vs. luxury — honest compare", style: .opinion),

        // Business & Career
        OnboardingTasteExample(id: "biz-rec-1", interestID: "business-career", title: "Tools that actually speed up my work", style: .recommendation),
        OnboardingTasteExample(id: "biz-op-1", interestID: "business-career", title: "Career advice I wish I'd ignored", style: .opinion),
        OnboardingTasteExample(id: "biz-hum-1", interestID: "business-career", title: "Monday me vs. Friday me at work", style: .personalHumour),
        OnboardingTasteExample(id: "biz-rec-2", interestID: "business-career", title: "How I structure a focused work block", style: .recommendation),
        OnboardingTasteExample(id: "biz-op-2", interestID: "business-career", title: "Hustle culture — where I draw the line", style: .opinion),

        // Gaming
        OnboardingTasteExample(id: "game-rec-1", interestID: "gaming", title: "Games I'd recommend to a friend right now", style: .recommendation),
        OnboardingTasteExample(id: "game-op-1", interestID: "gaming", title: "This game didn't live up to the hype", style: .opinion),
        OnboardingTasteExample(id: "game-hum-1", interestID: "gaming", title: "One more game before bed (narrator: it wasn't)", style: .personalHumour),
        OnboardingTasteExample(id: "game-rec-2", interestID: "gaming", title: "Beginner-friendly picks I'd start with", style: .recommendation),
        OnboardingTasteExample(id: "game-op-2", interestID: "gaming", title: "Single-player vs. multiplayer — my mood", style: .opinion),

        // Art & Creativity
        OnboardingTasteExample(id: "art-rec-1", interestID: "art-creativity", title: "Creative prompts that got me unstuck", style: .recommendation),
        OnboardingTasteExample(id: "art-op-1", interestID: "art-creativity", title: "Why I stopped chasing perfection", style: .opinion),
        OnboardingTasteExample(id: "art-hum-1", interestID: "art-creativity", title: "Sketch vs. final — the gap is real", style: .personalHumour),
        OnboardingTasteExample(id: "art-rec-2", interestID: "art-creativity", title: "Supplies I'd rebuy without hesitation", style: .recommendation),
        OnboardingTasteExample(id: "art-op-2", interestID: "art-creativity", title: "AI art tools — my honest line", style: .opinion),

        // Parenting
        OnboardingTasteExample(id: "parent-rec-1", interestID: "parenting", title: "Routines that made evenings easier", style: .recommendation),
        OnboardingTasteExample(id: "parent-op-1", interestID: "parenting", title: "Parenting advice I quietly ignored", style: .opinion),
        OnboardingTasteExample(id: "parent-hum-1", interestID: "parenting", title: "What I thought parenting would be vs. today", style: .personalHumour),
        OnboardingTasteExample(id: "parent-rec-2", interestID: "parenting", title: "Books and shows we actually enjoy together", style: .recommendation),
        OnboardingTasteExample(id: "parent-op-2", interestID: "parenting", title: "Screen time rules — what works here", style: .opinion),

        // Custom / generic fallbacks
        OnboardingTasteExample(id: "custom-rec-1", interestID: "custom", title: "Something I learned recently that surprised me", style: .recommendation),
        OnboardingTasteExample(id: "custom-op-1", interestID: "custom", title: "A take I don't see enough people sharing", style: .opinion),
        OnboardingTasteExample(id: "custom-hum-1", interestID: "custom", title: "A day in my life around this topic", style: .personalHumour),
        OnboardingTasteExample(id: "custom-rec-2", interestID: "custom", title: "3 things I'd tell someone just starting", style: .recommendation),
        OnboardingTasteExample(id: "custom-op-2", interestID: "custom", title: "What's overrated in this space", style: .opinion),
    ]

    static func examples(for interestIDs: [String], customSubjects: [String]) -> [OnboardingTasteExample] {
        var pool: [OnboardingTasteExample] = []
        for interestID in interestIDs {
            pool.append(contentsOf: allExamples.filter { $0.interestID == interestID })
        }
        if pool.isEmpty || !customSubjects.isEmpty {
            pool.append(contentsOf: allExamples.filter { $0.interestID == "custom" })
        }
        return pool.isEmpty ? allExamples.filter { $0.interestID == "custom" } : pool
    }

    static func example(by id: String) -> OnboardingTasteExample? {
        allExamples.first { $0.id == id }
    }

    /// Picks three examples with editorial mix (recommendation / opinion / humour when possible).
    static func displayPack(
        interestIDs: [String],
        customSubjects: [String],
        excluding displayedIDs: [String],
        shuffleSeed: Int
    ) -> [OnboardingTasteExample] {
        let pool = examples(for: interestIDs, customSubjects: customSubjects)
            .filter { !displayedIDs.contains($0.id) }
        let fallbackPool = examples(for: interestIDs, customSubjects: customSubjects)

        var selected: [OnboardingTasteExample] = []
        for style in [OnboardingTasteStyle.recommendation, .opinion, .personalHumour] {
            if let match = pick(from: pool.isEmpty ? fallbackPool : pool, style: style, excluding: selected) {
                selected.append(match)
            }
        }

        if selected.count < 3 {
            let remaining = (pool.isEmpty ? fallbackPool : pool)
                .filter { candidate in !selected.contains(where: { $0.id == candidate.id }) }
            var shuffled = seededShuffle(remaining, seed: shuffleSeed)
            while selected.count < 3, !shuffled.isEmpty {
                selected.append(shuffled.removeFirst())
            }
        }

        return Array(selected.prefix(3))
    }

    static func pruneStaleSelections(
        selectedIDs: [String],
        interestIDs: [String],
        customSubjects: [String]
    ) -> [String] {
        let validIDs = Set(examples(for: interestIDs, customSubjects: customSubjects).map(\.id))
        return selectedIDs.filter { validIDs.contains($0) }
    }

    private static func pick(
        from pool: [OnboardingTasteExample],
        style: OnboardingTasteStyle,
        excluding selected: [OnboardingTasteExample]
    ) -> OnboardingTasteExample? {
        pool.first { example in
            example.style == style && !selected.contains(where: { $0.id == example.id })
        }
    }

    private static func seededShuffle<T>(_ items: [T], seed: Int) -> [T] {
        var generator = SeededRandomNumberGenerator(seed: UInt64(bitPattern: Int64(seed)))
        return items.shuffled(using: &generator)
    }
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xDEADBEEF : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
