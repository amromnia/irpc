import Foundation

/// One account per installation. Saving replaces the previous credentials atomically.
/// Storage errors must reach the caller; an unreadable store is not an empty store.
@MainActor
public protocol TokenStorage {
    func load() throws -> DiscordToken?
    func save(_ token: DiscordToken) throws
    func delete() throws
}
