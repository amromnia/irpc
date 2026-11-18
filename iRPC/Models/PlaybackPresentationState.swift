import Foundation

/// Successful commands update the UI immediately. Briefly ignore the previous
/// system snapshot until playback notifications/readback catch up.
struct PlaybackPresentationState {
    private(set) var playing = false
    private var awaitingInitialMediaState = true
    private var pending: (playing: Bool, expires: TimeInterval)?

    mutating func commandAccepted(playing: Bool, now: TimeInterval) {
        awaitingInitialMediaState = false
        self.playing = playing
        pending = (playing, now + 1.5)
    }

    mutating func observe(playing: Bool, now: TimeInterval, initialMusicKitPlaying: Bool = false, mediaStateKnown: Bool = true) {
        if awaitingInitialMediaState && !mediaStateKnown {
            self.playing = playing || initialMusicKitPlaying
            return
        }
        awaitingInitialMediaState = false
        if let pending, pending.playing != playing, now < pending.expires { return }
        pending = nil
        self.playing = playing
    }

    mutating func reset() { pending = nil; playing = false; awaitingInitialMediaState = true }
}
