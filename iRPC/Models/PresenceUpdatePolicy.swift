import Foundation

/// Sample Music frequently; only resend unchanged Discord activity at the chosen interval.
struct PresenceUpdatePolicy {
    static let sampleSeconds: TimeInterval = 2
    private var initialized = false
    private var lastTrack: String?
    private var lastSent: TimeInterval = 0
    private var lastPosition: TimeInterval?
    private var lastDuration: TimeInterval?

    mutating func shouldPublish(track: String?, now: TimeInterval, interval: TimeInterval,
                                force: Bool = false, position: TimeInterval? = nil,
                                duration: TimeInterval? = nil) -> Bool {
        let durationChanged = duration != lastDuration
        var positionCorrected = false
        if let position, let lastPosition, position.isFinite, lastPosition.isFinite,
           abs(position - lastPosition) >= 0.5 {
            // A seek, repeat, or delayed player hydration must not wait for the
            // unchanged-update heartbeat. Normal progress needs no resend.
            positionCorrected = abs(position - lastPosition - max(0, now - lastSent)) > 2
        }
        guard force || !initialized || track != lastTrack || durationChanged || positionCorrected || now - lastSent >= interval else { return false }
        initialized = true
        lastTrack = track
        lastSent = now
        lastPosition = position
        lastDuration = duration
        return true
    }

    mutating func reset() { self = Self() }
}
