import Combine
import DiscordSocialKit
import Foundation
import MusicKit
import MusadoraKit
import NowPlayingKit

@MainActor
final class PresenceStore: ObservableObject {
    let accounts: [DiscordAccount]
    @Published private(set) var playback = NowPlayingData(id: "", title: "Your next favorite, on repeat.", artist: "")
    @Published private(set) var musicAuthorized = MusicAuthorization.currentStatus == .authorized
    @Published private(set) var playing = false
    @Published private(set) var recentPlayback = false
    @Published private(set) var observedAt = Date()
    @Published private(set) var sharing = false
    @Published private(set) var restoring = false
    @Published var error: String?
    private let music = NowPlayingManager.shared
    private var observations: Set<AnyCancellable> = []
    private var started = false
    private var readingPlayback = false
    private var loadedHistory = false
    private var hasFreshPlayback = false
    private var duplicateHandled = false

    init() {
        guard AppIdentity.applicationID != 0 else {
            accounts = []
            error = "This build needs a Discord application ID."
            return
        }
        accounts = (1...2).map { DiscordAccount(slot: $0, applicationID: AppIdentity.applicationID) }
        for account in accounts {
            account.objectWillChange.sink { [weak self, weak account] in
                Task { @MainActor in
                    guard let self, let account else { return }
                    self.objectWillChange.send()
                    if self.sharing && account.ready && !account.discord.isRunning {
                        account.discord.isRunning = true
                    } else if !account.selected && account.discord.isRunning {
                        account.discord.stopPresenceUpdates()
                    }
                    self.rejectDuplicateAccount()
                }
            }.store(in: &observations)
        }
    }

    var readyAccounts: [DiscordAccount] { accounts.filter(\.ready) }
    var authorizing: Bool { accounts.contains { $0.discord.isAuthorizing } }

    func start() async {
        guard !started else { return }
        started = true
        restoring = true
        for account in accounts { await account.restore() }
        restoring = false
        await refreshPlayback()
    }

    func requestMusicAccess() async {
        musicAuthorized = await music.authorize() == .authorized
        if musicAuthorized { error = nil; await refreshPlayback() }
        else { error = "Allow Music access in Settings to share what you're listening to." }
    }

    func connect(_ account: DiscordAccount) {
        guard !authorizing, account.storageError == nil else { return }
        error = nil
        duplicateHandled = false
        account.discord.authorize()
    }

    func refreshPlayback() async {
        guard !readingPlayback else { return }
        musicAuthorized = MusicAuthorization.currentStatus == .authorized
        guard musicAuthorized else { playing = false; return }
        hasFreshPlayback = false
        readingPlayback = true
        defer { readingPlayback = false }
        playing = SystemMusicPlayer.shared.state.playbackStatus == .playing
        do {
            playback = try await music.getCurrentPlayback()
            hasFreshPlayback = true
            recentPlayback = false
            observedAt = Date()
        } catch NowPlayingError.noCurrentEntry {
            if !loadedHistory {
                loadedHistory = true
                let songs = try? await MHistory.recentlyPlayedSongs(limit: 1)
                if let recent = songs?.first {
                    recentPlayback = true
                    playback = NowPlayingData(id: recent.id.rawValue, title: recent.title, artist: recent.artistName,
                                              album: recent.albumTitle, artworkURL: recent.artwork?.url(width: 600, height: 600),
                                              duration: recent.duration ?? 0)
                }
            }
        } catch {
            self.error = "Couldn't read the current song. Check Music access and try again."
        }
    }

    func toggleSharing(minutes: Int) {
        if sharing { stopSharing(); return }
        guard musicAuthorized, !readyAccounts.isEmpty else { return }
        error = nil
        sharing = true
        for account in readyAccounts { account.discord.isRunning = true }
        if #available(iOS 26.0, *) {
            do {
                try BackgroundController.shared.start(minutes: minutes, update: poll, onStop: { [weak self] in
                    self?.finishSharing()
                })
            } catch {
                finishSharing()
                self.error = error.localizedDescription
            }
        } else {
            for account in readyAccounts { account.discord.startPresenceUpdates() }
        }
    }

    func stopSharing() {
        BackgroundController.shared.stop()
        finishSharing()
    }

    private func finishSharing() {
        sharing = false
        for account in accounts { account.discord.stopPresenceUpdates() }
    }

    func tick() async {
        await refreshPlayback()
        if #unavailable(iOS 26.0), sharing { try? await poll() }
    }

    private func poll() async throws {
        try Task.checkCancellation()
        guard sharing else { throw CancellationError() }
        guard MusicAuthorization.currentStatus == .authorized else {
            throw NSError(domain: AppIdentity.name, code: 1, userInfo: [NSLocalizedDescriptionKey: "Music access is unavailable."])
        }
        await refreshPlayback()
        try Task.checkCancellation()
        guard sharing else { throw CancellationError() }
        guard playing else {
            for account in accounts { account.discord.clearPlayback() }
            return
        }
        guard hasFreshPlayback, !playback.id.isEmpty else { return }
        let snapshot = playback
        // Each account owns an SDK client and credentials. One Music sample is
        // delivered to both; one disconnected account doesn't stop the other.
        await withTaskGroup(of: Void.self) { group in
            for account in readyAccounts {
                group.addTask { @MainActor in
                    guard !Task.isCancelled else { return }
                    await account.discord.updateRichPresence(
                        id: snapshot.id, title: snapshot.title, artist: snapshot.artist,
                        duration: snapshot.duration, currentTime: snapshot.playbackTime,
                        artworkURL: snapshot.artworkURL
                    )
                }
            }
        }
    }

    private func rejectDuplicateAccount() {
        guard !duplicateHandled, accounts.count == 2, accounts[0].discord.userId != 0,
              accounts[0].discord.userId == accounts[1].discord.userId,
              accounts[1].discord.isAuthenticated else { return }
        duplicateHandled = true
        accounts[1].signOut()
        error = "That Discord account is already connected. Switch to your other account in Discord, then connect Account 2."
    }
}
