import Foundation

/// Both the OAuth client and local account slot identify a credential store.
public struct DiscordCredentialScope {
    public let applicationID: UInt64
    public let slot: Int
    public init(applicationID: UInt64, slot: Int) {
        precondition(applicationID > 0 && (1...2).contains(slot))
        self.applicationID = applicationID
        self.slot = slot
    }
    public var account: String { "slot-\(slot)" }
    public var storeName: String { "discord-\(applicationID)-slot-\(slot)" }
    public func service(bundle: String) -> String { "\(bundle).discord.\(applicationID)" }
}
