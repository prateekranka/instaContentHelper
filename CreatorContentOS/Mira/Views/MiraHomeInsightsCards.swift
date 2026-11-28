import SwiftUI

struct MiraHomeInsightsCards: View {
    let state: MiraHomeInsightsState
    let scope: MiraDailyNoteScope?
    let canPick: Bool
    let onPost: (MiraInsightPost) -> Void

    var body: some View {
        MiraFeedCard {
            MiraSectionTitle(text: "How you're doing")
            switch state {
            case .loading(let owner, _) where owner == scope:
                ProgressView("Checking your Instagram insights")
            case .ready(let owner, let data) where owner == scope:
                if let source = data.sourceLabel { Text(source).font(.caption) }
                ForEach(data.metrics) { metric in
                    VStack(alignment: .leading, spacing: 4) {
                        LabeledContent(metric.label, value: metric.value ?? "Not enough data yet")
                        if metric.value != nil {
                            Text(metric.change ?? "Not enough data yet")
                                .font(.caption).foregroundStyle(MiraTheme.secondaryInk)
                        }
                    }
                }
            default:
                Text("Not enough data yet")
            }
        }
        if case .ready(let owner, let data) = state, owner == scope, !data.posts.isEmpty {
            MiraSectionTitle(text: "What worked")
            ForEach(data.posts.indices, id: \.self) { index in
                let post = data.posts[index]
                MiraFeedCard {
                    Text(post.caption).font(.headline)
                    ForEach(post.counts, id: \.label) { metric in
                        LabeledContent(metric.label, value: metric.value.formatted())
                    }
                    Button(post.nextAction.title) { onPost(post) }
                        .buttonStyle(MiraPrimaryStyle())
                        .disabled(!canPick)
                        .accessibilityIdentifier("mira.home.whatWorked.action.\(index)")
                }
            }
        }
    }
}

struct MiraDailyNoteCard: View {
    let state: MiraDailyNoteState
    let scope: MiraDailyNoteScope?
    let work: MiraDailyNoteWork
    let allowsInstagram: Bool
    let canPick: Bool
    let onAction: (MiraDailyNote.Action) -> Void

    var body: some View {
        switch state {
        case .loading(let owner, _) where owner == scope:
            MiraFeedCard { ProgressView("Mira is checking what matters today") }
        case .ready(let owner, let note, let usesInstagram) where owner == scope && (!usesInstagram || allowsInstagram):
            MiraFeedCard {
                MiraSectionTitle(text: "Mira noticed")
                Text(note.noticed).accessibilityIdentifier("mira.home.dailyNote.text")
                if note.canAct(in: work) {
                    Button(note.buttonText) { onAction(note.action) }
                        .buttonStyle(MiraPrimaryStyle())
                        .disabled(note.action.type == .makeIdea && !canPick)
                        .accessibilityIdentifier("mira.home.dailyNote.action")
                }
            }
        case .unavailable(let owner) where owner == scope:
            Text("Mira couldn’t check what matters today.").foregroundStyle(MiraTheme.secondaryInk)
                .accessibilityIdentifier("mira.home.dailyNote.unavailable")
        default:
            EmptyView()
        }
    }
}

extension InstagramInsightsReport {
    var homeInsightData: MiraHomeInsightData {
        let pair = Array((snapshots ?? []).suffix(2))
        let newest = pair.last
        let baseline = pair.count == 2 ? pair.first : nil
        let metrics = [
            ("followers", "Followers", newest?.followers, baseline?.followers),
            ("reach", "Reach", newest?.reach7d, baseline?.reach7d),
            ("saves", "Saves", newest?.saves7d, baseline?.saves7d),
        ].map { id, label, latest, earlier -> MiraHomeInsightMetric in
            let metric = headline.first { $0.id == id }
            let current = Self.count(latest) ?? Self.count(metric.flatMap { Int($0.value.replacingOccurrences(of: ",", with: "")) })
            let change: String?
            if let current, let earlier = Self.count(earlier) {
                let difference = current - earlier
                change = difference == 0 ? "No change this week" :
                    "\(difference > 0 ? "+" : "−")\(abs(difference).formatted()) this week"
            } else {
                change = metric?.delta
            }
            return .init(label: label, value: current?.formatted(), change: change)
        }
        let posts = Array((newest?.topPosts ?? []).filter { !$0.pattern.isEmpty && !$0.counts.isEmpty }.prefix(5))
        let fallback = MiraInsightSnapshot(followers: rawCount("followers"), reach7d: rawCount("reach"), saves7d: rawCount("saves"))
        let inputSnapshots = (pair.isEmpty ? [fallback] : pair).map { snapshot in
            let safePosts = snapshot.topPosts?.prefix(5).compactMap { post -> MiraInsightPost? in
                guard !post.pattern.isEmpty else { return nil }
                return .init(caption: String(decoding: post.caption.utf16.prefix(2200), as: UTF16.self),
                             views: Self.count(post.views), reach: Self.count(post.reach), likes: Self.count(post.likes),
                             comments: Self.count(post.comments), saves: Self.count(post.saves), shares: Self.count(post.shares))
            }
            return MiraInsightSnapshot(followers: Self.count(snapshot.followers), reach7d: Self.count(snapshot.reach7d),
                                       saves7d: Self.count(snapshot.saves7d), topPosts: safePosts)
        }.filter(\.hasResults)
        let sourceLabel = source == .api ? nil : (source == .sample ? "Sample data" : "Manually entered")
        return .init(metrics: metrics, snapshots: source == .api ? inputSnapshots : [], posts: posts, sourceLabel: sourceLabel)
    }

    private func rawCount(_ id: String) -> Int? {
        headline.first { $0.id == id }.flatMap { Int($0.value.replacingOccurrences(of: ",", with: "")) }
    }

    private static func count(_ value: Int?) -> Int? {
        guard let value, (0...9_007_199_254_740_991).contains(value) else { return nil }
        return value
    }
}
