import Combine
import DiscordSocialKit
import Foundation
import MusicKit
import MediaPlayer
import MusadoraKit
import NowPlayingKit
import UIKit

@MainActor
final class PresenceStore: ObservableObject {
    @Published private(set) var accounts: [DiscordAccount] = []
    @Published private(set) var playback = NowPlayingData(id: "", title: "Not playing", artist: "")
    @Published private(set) var musicAuthorized = MusicAuthorization.currentStatus == .authorized
    @Published private(set) var playing = false
    @Published private(set) var recentPlayback = false
    @Published private(set) var observedAt = Date()
    @Published private(set) var currentArtwork: Artwork?
    @Published private(set) var artworkDiagnostics = "Not checked"
    @Published private(set) var checkingArtwork = false
    private var entryArtworkURL: URL?
    private var songArtworkURL: URL?
    private var publishing = false
    @Published private(set) var controllingPlayback = false
    private var currentSong: Song?
    private var discordArtworkKey: String?
    private var discordArtworkURL: URL?
    private var discordArtworkCheckedAt = Date.distantPast
    private var discordArtworkStatus = "Not checked"
    private var sharingGeneration = 0
    @Published private(set) var artworkTint: UIColor?
    private var artworkColorTrack = ""
    @Published var liveActivityEnabled = UserDefaults.standard.bool(forKey: "sharing.liveActivity") {
        didSet {
            UserDefaults.standard.set(liveActivityEnabled, forKey: "sharing.liveActivity")
            updateLiveActivity()
        }
    }
    @Published private(set) var sharing = false
    @Published private(set) var restoring = false
    @Published var error: String?
    private let music = NowPlayingManager.shared
    private var observations: [Int: AnyCancellable] = [:]
    private var registry = AccountRegistry()
    private let registryKey = "discord.\(AppIdentity.applicationID).accounts.v1"
    private var registryAvailable = true
    private var started = false
    private var readingPlayback = false
    private var loadedHistory = false
    private var hasFreshPlayback = false
    private var duplicateRejections: Set<Int> = []
    private var autoStartPolicy = AutoStartPolicy()
    private var lastForegroundPublish = Date.distantPast
    @Published var autoStart = UserDefaults.standard.bool(forKey: "sharing.autoStart") {
        didSet {
            UserDefaults.standard.set(autoStart, forKey: "sharing.autoStart")
            autoStartPolicy.rearm()
            tryAutoStart()
        }
    }
    @Published var backgroundRefresh = UserDefaults.standard.bool(forKey: "sharing.backgroundRefresh") {
        didSet {
            UserDefaults.standard.set(backgroundRefresh, forKey: "sharing.backgroundRefresh")
            BackgroundRefreshController.shared.schedule()
        }
    }
    var pollingSeconds: Int {
        let value = UserDefaults.standard.integer(forKey: "sharing.pollSeconds")
        return [5, 15, 30].contains(value) ? value : 15
    }

    init() {
        guard AppIdentity.applicationID != 0 else {
            error = "This build needs a Discord application ID."
            return
        }
        do {
            if let saved = UserDefaults.standard.data(forKey: registryKey) {
                registry = try AccountRegistry(data: saved)
                accounts = registry.slots.map { DiscordAccount(slot: $0, applicationID: AppIdentity.applicationID) }
            } else {
                // Discover credentials from the former fixed slots once, without
                // deleting existing stores or creating empty rows on new installs.
                for slot in 1...2 {
                    let account = DiscordAccount(slot: slot, applicationID: AppIdentity.applicationID)
                    let exists: Bool
                    do { exists = try account.discord.hasStoredToken() }
                    catch { exists = true } // Retain inaccessible stores for a later unlock/retry.
                    if exists { accounts.append(account) }
                    else { account.discord.shutdown() }
                }
                registry = AccountRegistry(legacySlots: accounts.map(\.id))
                try saveRegistry()
            }
            for account in accounts { observe(account) }
        } catch {
            registryAvailable = false
            self.error = "Couldn't read the saved account list. Existing credentials were left unchanged."
        }
    }

    private func saveRegistry() throws {
        UserDefaults.standard.set(try registry.data(), forKey: registryKey)
    }

    private func observe(_ account: DiscordAccount) {
        observations[account.id] = account.objectWillChange.sink { [weak self, weak account] in
            Task { @MainActor in
                guard let self, let account, self.accounts.contains(where: { $0.id == account.id }) else { return }
                self.objectWillChange.send()
                if self.sharing && account.ready && !account.discord.isRunning {
                    account.discord.isRunning = true
                } else if !account.selected && account.discord.isRunning {
                    account.discord.stopPresenceUpdates()
                }
                self.rejectDuplicateAccounts()
                self.tryAutoStart()
                self.updateLiveActivity()
            }
        }
    }

    @discardableResult
    func addAccount() -> DiscordAccount? {
        guard registryAvailable, !authorizing else { return nil }
        do {
            let slot = try registry.add()
            try saveRegistry()
            let account = DiscordAccount(slot: slot, applicationID: AppIdentity.applicationID)
            accounts.append(account)
            observe(account)
            return account
        } catch {
            self.error = "Couldn't add the account."
            return nil
        }
    }

    @discardableResult
    func removeAccount(_ account: DiscordAccount) -> Bool {
        guard account.signOut() else { error = account.storageError; return false }
        account.discord.shutdown()
        observations.removeValue(forKey: account.id)?.cancel()
        accounts.removeAll { $0.id == account.id }
        registry.remove(account.id)
        do { try saveRegistry() } catch { self.error = "Couldn't save the account list." }
        if accounts.isEmpty && sharing { stopSharing() }
        return true
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
        tryAutoStart()
    }

    func requestMusicAccess() async {
        musicAuthorized = await music.authorize() == .authorized
        if musicAuthorized { error = nil; await refreshPlayback(); tryAutoStart() }
        else { error = "Allow Music access in Settings to share what you're listening to." }
    }

    func connect(_ account: DiscordAccount) {
        guard !authorizing, account.storageError == nil else { return }
        error = nil
        duplicateRejections.remove(account.id)
        account.discord.authorize()
    }

    func refreshPlayback() async {
        guard !readingPlayback else { return }
        musicAuthorized = MusicAuthorization.currentStatus == .authorized
        guard musicAuthorized else { playing = false; return }
        hasFreshPlayback = false
        readingPlayback = true
        defer { readingPlayback = false; updateLiveActivity() }
        playing = SystemMusicPlayer.shared.state.playbackStatus == .playing
        do {
            let current = try await music.getCurrentPlayback()
            let entryArtwork = SystemMusicPlayer.shared.queue.currentEntry?.artwork
            var songArtwork: Artwork?
            currentSong = nil
            if let item = SystemMusicPlayer.shared.queue.currentEntry?.item {
                switch item {
                case .song(let song): currentSong = song; songArtwork = song.artwork
                case .musicVideo(let video): songArtwork = video.artwork
                @unknown default: break
                }
            }
            currentArtwork = entryArtwork ?? songArtwork
            entryArtworkURL = entryArtwork?.url(width: 600, height: 600)
            songArtworkURL = songArtwork?.url(width: 600, height: 600)
            let resolvedURL = entryArtworkURL ?? songArtworkURL
            playback = NowPlayingData(id: current.id, title: current.title, artist: current.artist,
                album: current.album, artworkURL: resolvedURL, playbackTime: current.playbackTime, duration: current.duration)
            hasFreshPlayback = true
            recentPlayback = false
            observedAt = Date()
            if artworkColorTrack != current.id {
                artworkColorTrack = current.id
                artworkTint = nil
                refreshArtworkColor()
            }
        } catch NowPlayingError.noCurrentEntry {
            currentSong = nil
            if !loadedHistory {
                loadedHistory = true
                let songs = try? await MHistory.recentlyPlayedSongs(limit: 1)
                if let recent = songs?.first {
                    recentPlayback = true
                    playback = NowPlayingData(id: recent.id.rawValue, title: recent.title, artist: recent.artistName,
                                              album: recent.albumTitle, artworkURL: recent.artwork?.url(width: 600, height: 600),
                                              duration: recent.duration ?? 0)
                    currentArtwork = recent.artwork
                    entryArtworkURL = nil
                    songArtworkURL = recent.artwork?.url(width: 600, height: 600)
                }
            }
        } catch {
            self.error = "Couldn't read the current song. Check Music access and try again."
        }
    }

    func refreshArtworkColor() {
        guard UserDefaults.standard.string(forKey: "appearance.vaporColorSource") == "artwork" else { return }
        if let color = currentArtwork?.backgroundColor {
            artworkTint = UIColor(cgColor: color)
            return
        }
        // Library artwork can be device-local, so use MediaPlayer's native image.
        guard let item = MPMusicPlayerController.systemMusicPlayer.nowPlayingItem,
              item.title == playback.title,
              let image = item.artwork?.image(at: CGSize(width: 32, height: 32)),
              let cgImage = image.cgImage else { return }
        var pixel = [UInt8](repeating: 0, count: 4)
        let sampled = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        if sampled, pixel[3] > 0 {
            let alpha = CGFloat(pixel[3])
            artworkTint = UIColor(red: CGFloat(pixel[0]) / alpha, green: CGFloat(pixel[1]) / alpha,
                                  blue: CGFloat(pixel[2]) / alpha, alpha: 1)
        }
    }

    private func updateLiveActivity() {
        let accepted = readyAccounts.contains { ($0.discord.lastPresenceAcknowledgedAt ?? .distantPast).timeIntervalSinceNow > -90 }
        let state = SharingActivityAttributes.ContentState(title: String(playback.title.prefix(160)), artist: String(playback.artist.prefix(160)),
            playing: playing, sharing: sharing, acknowledged: accepted, accounts: readyAccounts.count,
            accentHex: UserDefaults.standard.string(forKey: "appearance.accent") ?? "E44950",
            end: playing && playback.duration.isFinite && playback.playbackTime.isFinite && playback.duration > playback.playbackTime
                ? observedAt.addingTimeInterval(playback.duration - playback.playbackTime) : nil)
        SharingActivityController.shared.update(enabled: liveActivityEnabled && sharing, state: state)
    }

    /// Library artwork is a device resource. Resolve catalog relationships from
    /// the Song itself; a library ID must not be sent to a catalog-ID endpoint.
    private func resolveDiscordArtwork(force: Bool = false) async -> URL? {
        let key = playback.id + "|" + (playback.artworkURL?.absoluteString ?? "")
        if !force, key == discordArtworkKey,
           Date().timeIntervalSince(discordArtworkCheckedAt) < (discordArtworkURL == nil ? 60 : 3600) {
            return discordArtworkURL
        }
        var resolved = PublicArtworkPolicy.url(playback.artworkURL)
        var status = resolved == nil ? "No catalog song available for this entry" : "Public MusicKit artwork"
        if resolved == nil, let song = currentSong {
            do {
                let catalog = try await song.with([.albums], preferredSource: .catalog)
                resolved = PublicArtworkPolicy.url(catalog.artwork?.url(width: 600, height: 600))
                    ?? catalog.albums?.compactMap { PublicArtworkPolicy.url($0.artwork?.url(width: 600, height: 600)) }.first
                status = resolved == nil ? "Catalog lookup supplied no public artwork" : "Public catalog artwork"
            } catch {
                let failure = error as NSError
                status = "Catalog lookup failed: \(failure.domain) \(failure.code)"
            }
        }
        // Do not replace diagnostics/cache for a song that changed during the lookup.
        guard key == playback.id + "|" + (playback.artworkURL?.absoluteString ?? "") else { return nil }
        discordArtworkKey = key
        discordArtworkURL = resolved
        discordArtworkStatus = status
        discordArtworkCheckedAt = Date()
        return resolved
    }

    private func diagnosticURL(_ url: URL?) -> String? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string
    }

    func diagnoseArtwork() async {
        guard !checkingArtwork else { return }
        checkingArtwork = true
        defer { checkingArtwork = false }
        await refreshPlayback()
        let publicArtwork = await resolveDiscordArtwork(force: true)
        var lines = [
            "Track: \(playback.title) — \(playback.artist)",
            "Music authorization: \(MusicAuthorization.currentStatus)",
            "Queue-entry artwork URL: \(diagnosticURL(entryArtworkURL) ?? "nil")",
            "Song artwork URL: \(diagnosticURL(songArtworkURL) ?? "nil")",
            "Native Artwork object: \(currentArtwork == nil ? "nil" : "present")",
            "Discord artwork: \(discordArtworkStatus)",
            "Discord image URL: \(diagnosticURL(publicArtwork) ?? "nil")"
        ]
        lines.append("Renderer: MusicKit.ArtworkImage")
        if entryArtworkURL?.scheme?.lowercased() == "musickit" {
            lines.append("Local library artwork renders on this phone; Discord cannot fetch it.")
        }
        guard let url = publicArtwork else {
            lines.append("No public image URL is currently available for Discord.")
            artworkDiagnostics = lines.joined(separator: "\n")
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 15))
            if let http = response as? HTTPURLResponse {
                lines.append("HTTP: \(http.statusCode), type: \(http.mimeType ?? "unknown"), bytes: \(data.count)")
            }
            if let image = UIImage(data: data) {
                lines.append("Image decoded: \(Int(image.size.width))×\(Int(image.size.height))")
            } else { lines.append("UIImage could not decode the response.") }
        } catch {
            lines.append("Image request error: \((error as NSError).domain) \((error as NSError).code)")
        }
        artworkDiagnostics = lines.joined(separator: "\n")
    }

    func togglePlaybackAndSharing(minutes: Int) async {
        guard !controllingPlayback else { return }
        controllingPlayback = true
        defer { controllingPlayback = false }
        autoStartPolicy.suppress()
        let player = SystemMusicPlayer.shared
        if sharing && player.state.playbackStatus == .playing {
            player.pause()
            stopSharing()
            await refreshPlayback()
            return
        }
        guard musicAuthorized, !readyAccounts.isEmpty else { return }
        let generation = sharingGeneration
        do {
            if player.state.playbackStatus != .playing { try await player.play() }
            guard generation == sharingGeneration, !Task.isCancelled else { return }
            await refreshPlayback()
            if !sharing { startSharing(minutes: minutes) }
            else { try await poll() }
        } catch {
            self.error = "Couldn't resume Music. Choose a song in Apple Music and try again."
        }
    }

    func skipTrack(previous: Bool) async {
        guard !controllingPlayback, musicAuthorized else { return }
        controllingPlayback = true
        defer { controllingPlayback = false }
        sharingGeneration += 1
        let player = SystemMusicPlayer.shared
        do {
            if previous && player.playbackTime > 3 { player.playbackTime = 0 }
            else if previous { try await player.skipToPreviousEntry() }
            else { try await player.skipToNextEntry() }
            await refreshPlayback()
            if sharing { try await poll() }
        } catch { self.error = "Couldn't change tracks. Check the queue in Apple Music." }
    }

    private func startSharing(minutes: Int) {
        guard musicAuthorized, !readyAccounts.isEmpty else { return }
        error = nil
        sharing = true
        updateLiveActivity()
        UserDefaults.standard.set(true, forKey: "sharing.requested")
        for account in readyAccounts { account.discord.isRunning = true }
        if #available(iOS 26.0, *) {
            do {
                try BackgroundController.shared.start(minutes: minutes, update: poll, onStop: { [weak self] in
                    self?.finishSession()
                })
            } catch {
                // Auto-start can still publish while open if iOS declines an
                // immediate continued-processing request. No fake background assertion.
                self.error = "Background session unavailable. Sharing while the app is open."
            }
        }
        BackgroundRefreshController.shared.schedule()
        if !BackgroundController.shared.isRunning { Task { try? await poll() } }
    }

    func stopSharing() {
        sharingGeneration += 1
        autoStartPolicy.suppress()
        UserDefaults.standard.set(false, forKey: "sharing.requested")
        sharing = false
        updateLiveActivity()
        BackgroundRefreshController.shared.cancel()
        BackgroundController.shared.stop()
        for account in accounts { account.discord.stopPresenceUpdates() }
    }

    private func finishSession() {
        defer { updateLiveActivity() }
        if backgroundRefresh && UserDefaults.standard.bool(forKey: "sharing.requested") {
            BackgroundRefreshController.shared.schedule()
        } else {
            sharing = false
            UserDefaults.standard.set(false, forKey: "sharing.requested")
            for account in accounts { account.discord.stopPresenceUpdates() }
        }
    }

    func enteredForeground() {
        updateLiveActivity()
        autoStartPolicy.enterForeground()
        tryAutoStart()
    }

    func enteredBackground() {
        autoStartPolicy.leaveForeground()
        if !BackgroundController.shared.isRunning && !backgroundRefresh && sharing { stopSharing() }
        BackgroundRefreshController.shared.schedule()
    }

    private func tryAutoStart() {
        guard UIApplication.shared.applicationState == .active, !BackgroundController.shared.isRunning,
              autoStartPolicy.claim(enabled: autoStart, ready: !readyAccounts.isEmpty, authorized: musicAuthorized) else { return }
        let stored = UserDefaults.standard.integer(forKey: "presence.sessionMinutes")
        startSharing(minutes: [30, 120, 240].contains(stored) ? stored : 120)
    }

    func tick() async {
        guard autoStartPolicy.foreground else { return }
        await refreshPlayback()
        tryAutoStart()
        if sharing, !BackgroundController.shared.isRunning,
           Date().timeIntervalSince(lastForegroundPublish) >= Double(pollingSeconds) {
            lastForegroundPublish = Date()
            try? await poll()
        }
    }

    func performBackgroundRefresh() async throws {
        guard backgroundRefresh, UserDefaults.standard.bool(forKey: "sharing.requested") else { return }
        guard !BackgroundController.shared.isRunning else { return }
        await start()
        try Task.checkCancellation()
        guard backgroundRefresh, UserDefaults.standard.bool(forKey: "sharing.requested") else { throw CancellationError() }
        sharing = true
        // Token restoration is asynchronous inside the SDK. Wait a bounded time
        // for a selected client; never open an interactive OAuth flow in a refresh.
        for _ in 0..<40 {
            try Task.checkCancellation()
            if !readyAccounts.isEmpty { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard !readyAccounts.isEmpty else {
            throw NSError(domain: AppIdentity.name, code: 2, userInfo: [NSLocalizedDescriptionKey: "No account connected"])
        }
        guard backgroundRefresh, UserDefaults.standard.bool(forKey: "sharing.requested") else { throw CancellationError() }
        for account in readyAccounts { account.discord.isRunning = true }
        let requested = Date()
        try await poll()
        if !playing { return }
        for _ in 0..<20 {
            try Task.checkCancellation()
            if readyAccounts.contains(where: { ($0.discord.lastPresenceAcknowledgedAt ?? .distantPast) >= requested }) { return }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        throw NSError(domain: AppIdentity.name, code: 3, userInfo: [NSLocalizedDescriptionKey: "No Discord acknowledgement"])
    }

    private func poll() async throws {
        guard !publishing else { return }
        publishing = true
        defer { publishing = false }
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
        let trackID = playback.id
        let generation = sharingGeneration
        let entryID = SystemMusicPlayer.shared.queue.currentEntry?.id
        let publicArtwork = await resolveDiscordArtwork()
        await refreshPlayback()
        try Task.checkCancellation()
        guard sharing, hasFreshPlayback, generation == sharingGeneration, playback.id == trackID,
              entryID == SystemMusicPlayer.shared.queue.currentEntry?.id,
              SystemMusicPlayer.shared.state.playbackStatus == .playing else { return }
        let snapshot = playback
        // Each account owns an SDK client and credentials. One Music sample is
        // delivered to every selected client independently.
        await withTaskGroup(of: Void.self) { group in
            for account in readyAccounts {
                group.addTask { @MainActor in
                    guard !Task.isCancelled else { return }
                    await account.discord.updateRichPresence(
                        id: snapshot.id, title: snapshot.title, artist: snapshot.artist,
                        duration: snapshot.duration, currentTime: snapshot.playbackTime,
                        artworkURL: publicArtwork
                    )
                }
            }
        }
    }

    private func rejectDuplicateAccounts() {
        var users: Set<UInt64> = []
        for account in accounts where account.discord.isAuthenticated && account.discord.userId != 0 {
            guard !users.insert(account.discord.userId).inserted else { continue }
            guard duplicateRejections.insert(account.id).inserted else { continue }
            account.signOut()
            error = "That Discord user is already connected. Switch Discord accounts before connecting another."
        }
    }
}
