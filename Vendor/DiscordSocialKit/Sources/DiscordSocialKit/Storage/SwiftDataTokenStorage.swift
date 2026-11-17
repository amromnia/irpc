#if !IRPC_XTOOL
import Foundation
import SwiftData

@MainActor
public final class SwiftDataTokenStorage: TokenStorage {
    private let context: ModelContext

    public init(context: ModelContext) { self.context = context }

    public func load() throws -> DiscordToken? {
        var request = FetchDescriptor<DiscordToken>(
            sortBy: [SortDescriptor(\DiscordToken.expiresAt, order: .reverse)]
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    public func save(_ token: DiscordToken) throws {
        do {
            for old in try context.fetch(FetchDescriptor<DiscordToken>()) { context.delete(old) }
            context.insert(token)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    public func delete() throws {
        do {
            for token in try context.fetch(FetchDescriptor<DiscordToken>()) { context.delete(token) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
#endif
