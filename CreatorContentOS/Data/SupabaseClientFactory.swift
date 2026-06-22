import Foundation
import Supabase

struct SupabaseRuntimeConfiguration: Hashable, Sendable {
    var projectURL: URL
    var publishableKey: String
    var deviceToken: String?
}

struct SupabaseClientFactory {
    func makeBootstrapClient(configuration: SupabaseBootstrapConfiguration) -> SupabaseClient {
        makeClient(configuration: configuration.runtimeConfiguration)
    }

    func makeClient(configuration: SupabaseRuntimeConfiguration) -> SupabaseClient {
        var headers = ["x-client": "CreatorContentOS-iOS"]
        if let deviceToken = configuration.deviceToken?.nilIfBlank {
            headers["x-mco-device-token"] = deviceToken
        }

        return SupabaseClient(
            supabaseURL: configuration.projectURL,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                db: .init(schema: "public"),
                global: .init(headers: headers)
            )
        )
    }
}

enum SupabaseContentTable: String, CaseIterable, Sendable {
    case workspaces
    case creators
    case members
    case creatorProfiles = "creator_profiles"
    case weeklySetups = "weekly_setups"
    case weeklyPlans = "weekly_plans"
    case dailyCards = "daily_cards"
    case cardAlternatives = "card_alternatives"
    case sourceReferences = "source_references"
    case referenceExtractions = "reference_extractions"
    case benchmarkCreators = "benchmark_creators"
    case watchlists
    case watchlistBenchmarkCreators = "watchlist_benchmark_creators"
    case patterns
    case trends
    case audioOptions = "audio_options"
    case ideas
    case brandBriefs = "brand_briefs"
    case collabLeads = "collab_leads"
    case keyMoments = "key_moments"
    case feedback
    case learningSummaries = "learning_summaries"
    case postResults = "post_results"
    case archiveEntries = "archive_entries"
    case syncEvents = "sync_events"
}

struct SupabaseRepositoryBundleFactory {
    func makeRepositories(
        context: WorkspaceContext,
        configuration: SupabaseRuntimeConfiguration
    ) -> AppRepositories {
        let client = SupabaseClientFactory().makeClient(configuration: configuration)
        let sourcePulse = SupabaseReferenceRepository(client: client)

        return AppRepositories(
            context: context,
            today: SupabaseTodayCardRepository(client: client),
            weeklyPlans: SupabaseWeeklyPlanRepository(client: client),
            references: sourcePulse,
            referenceImport: SupabaseReferenceImportRepository(client: client),
            weeklyGeneration: SupabaseWeeklyGenerationRepository(
                client: client,
                runtimeConfiguration: configuration
            ),
            intelligence: SupabaseIntelligenceRepository(client: client, references: sourcePulse),
            creatorProfile: SupabaseCreatorProfileRepository(client: client),
            archive: SupabaseArchiveRepository(client: client),
            testerAccess: SupabaseTesterAccessRepository(client: client)
        )
    }
}
