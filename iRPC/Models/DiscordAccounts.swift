import Combine
import DiscordSocialKit
import Foundation
#if !IRPC_XTOOL
import SwiftData
#endif

enum AppIdentity {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Afterglow"
    static let applicationID = UInt64(Bundle.main.object(forInfoDictionaryKey: "PresenceDiscordApplicationID") as? String ?? "") ?? 0
}

@MainActor
final class DiscordAccount: ObservableObject, Identifiable {
    let id: Int
    let discord: DiscordManager
    @Published var selected: Bool {
        didSet { UserDefaults.standard.set(selected, forKey: selectionKey) }
    }
    @Published var storageError: String?
    private let selectionKey: String
    private var observation: AnyCancellable?
    #if !IRPC_XTOOL
    private var container: ModelContainer?
    #endif

    init(slot: Int, applicationID: UInt64) {
        id = slot
        selectionKey = "discord.\(applicationID).slot.\(slot).selected"
        selected = UserDefaults.standard.object(forKey: selectionKey) as? Bool ?? true
        discord = DiscordManager(applicationId: applicationID)
        let scope = DiscordCredentialScope(applicationID: applicationID, slot: slot)
        do {
            #if IRPC_XTOOL
            discord.setTokenStorage(KeychainTokenStorage(
                service: scope.service(bundle: Bundle.main.bundleIdentifier!),
                account: scope.account
            ))
            #else
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
            let directory = support.appendingPathComponent("DiscordAccounts", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(scope.storeName,
                url: directory.appendingPathComponent(scope.storeName + ".store"), cloudKitDatabase: .none)
            let container = try ModelContainer(for: DiscordToken.self, configurations: configuration)
            self.container = container
            discord.setTokenStorage(SwiftDataTokenStorage(context: ModelContext(container)))
            #endif
        } catch {
            storageError = "Couldn't open secure account storage."
        }
        observation = discord.objectWillChange.sink { [weak self] in
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }

    var name: String { discord.globalName ?? discord.username ?? "Account \(id)" }
    var ready: Bool { selected && discord.isAuthenticated && discord.isReady }
    var status: String {
        if let storageError { return storageError }
        if let error = discord.errorMessage { return error }
        if discord.isAuthorizing { return "Waiting for Discord…" }
        if discord.isReady && discord.isAuthenticated { return selected ? "Ready to share" : "Sharing off" }
        if discord.isAuthenticated { return "Connecting…" }
        return "Not connected"
    }

    func restore() async {
        guard storageError == nil else { return }
        do {
            if try discord.hasStoredToken() { await discord.setupWithExistingToken() }
        } catch {
            storageError = "Couldn't read saved credentials. Reconnect after unlocking your phone."
        }
    }

    func signOut() {
        do { try discord.signOut(); storageError = nil }
        catch { storageError = "Couldn't remove saved credentials. Try again." }
    }
}
