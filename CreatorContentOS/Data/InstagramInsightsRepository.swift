import Foundation
import Supabase

struct InstagramConnectionStatus: Hashable, Sendable {
    var connected: Bool
    var username: String?
    var accountType: String?
}

/// Reads/writes the creator's Instagram connection + account insights via the
/// instagram-connect / instagram-insights / instagram-disconnect edge functions.
protocol InstagramInsightsRepository: Sendable {
    func connect(code: String, redirectURI: String, context: WorkspaceContext) async throws -> InstagramConnectionStatus
    func fetchInsights(context: WorkspaceContext) async throws -> InstagramInsightsState
    func disconnect(context: WorkspaceContext) async throws
}

struct SupabaseInstagramInsightsRepository: InstagramInsightsRepository {
    let client: SupabaseClient

    func connect(code: String, redirectURI: String, context: WorkspaceContext) async throws -> InstagramConnectionStatus {
        do {
            let response: InstagramConnectResponse = try await client.functions.invoke(
                "instagram-connect",
                options: FunctionInvokeOptions(
                    body: InstagramConnectRequest(
                        creatorID: context.creatorID,
                        code: code,
                        redirectURI: redirectURI
                    )
                )
            )
            if let error = response.error?.nilIfBlank {
                throw RepositoryError.edgeFunction(error)
            }
            return InstagramConnectionStatus(
                connected: response.connected ?? false,
                username: response.username,
                accountType: response.accountType
            )
        } catch {
            if let code = SupabaseFunctionErrorMapper.errorCode(from: error) {
                throw RepositoryError.edgeFunction(code)
            }
            throw error
        }
    }

    func fetchInsights(context: WorkspaceContext) async throws -> InstagramInsightsState {
        do {
            let response: InstagramInsightsResponse = try await client.functions.invoke(
                "instagram-insights",
                options: FunctionInvokeOptions(
                    body: InstagramInsightsRequest(creatorID: context.creatorID)
                )
            )
            if let error = response.error?.nilIfBlank {
                throw RepositoryError.edgeFunction(error)
            }
            return response.toState()
        } catch {
            if let code = SupabaseFunctionErrorMapper.errorCode(from: error) {
                throw RepositoryError.edgeFunction(code)
            }
            throw error
        }
    }

    func disconnect(context: WorkspaceContext) async throws {
        do {
            let response: InstagramDisconnectResponse = try await client.functions.invoke(
                "instagram-disconnect",
                options: FunctionInvokeOptions(
                    body: InstagramDisconnectRequest(creatorID: context.creatorID)
                )
            )
            if let error = response.error?.nilIfBlank {
                throw RepositoryError.edgeFunction(error)
            }
        } catch {
            if let code = SupabaseFunctionErrorMapper.errorCode(from: error) {
                throw RepositoryError.edgeFunction(code)
            }
            throw error
        }
    }
}

/// Sample/offline path: no connection, nothing to fetch.
struct FixtureInstagramInsightsRepository: InstagramInsightsRepository {
    func connect(code: String, redirectURI: String, context: WorkspaceContext) async throws -> InstagramConnectionStatus {
        throw RepositoryError.notConfigured("instagram_not_configured")
    }

    func fetchInsights(context: WorkspaceContext) async throws -> InstagramInsightsState {
        .notConnected
    }

    func disconnect(context: WorkspaceContext) async throws {}
}
