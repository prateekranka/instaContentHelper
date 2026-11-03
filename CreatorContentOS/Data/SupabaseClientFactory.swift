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
