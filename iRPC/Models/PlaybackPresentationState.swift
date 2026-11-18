import Foundation

/// Successful commands update the UI immediately. Briefly ignore the previous
/// system snapshot until playback notifications/readback catch up.
struct PlaybackPresentationState {
    private(set) var playing = false
    private var pending: (playing: Bool, expires: TimeInterval)?

    mutating func commandAccepted(playing: Bool, now: TimeInterval) {
        self.playing = playing
        pending = (playing, now + 1.5)
    }

    mutating func observe(playing: Bool, now: TimeInterval) {
        if let pending, pending.playing != playing, now < pending.expires { return }
        pending = nil
        self.playing = playing
    }

    mutating func reset() { pending = nil; playing = false }
}
