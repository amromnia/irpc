import Foundation

/// Sample Music frequently; only resend unchanged Discord activity at the chosen interval.
struct PresenceUpdatePolicy {
    static let sampleSeconds: TimeInterval = 2
    private var initialized = false
    private var lastTrack: String?
    private var lastSent: TimeInterval = 0

    mutating func shouldPublish(track: String?, now: TimeInterval, interval: TimeInterval,
                                force: Bool = false) -> Bool {
        guard force || !initialized || track != lastTrack || now - lastSent >= interval else { return false }
        initialized = true
        lastTrack = track
        lastSent = now
        return true
    }

    mutating func reset() { self = Self() }
}
