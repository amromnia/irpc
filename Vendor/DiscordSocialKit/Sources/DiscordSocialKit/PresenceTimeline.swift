import Foundation

/// SDK timestamps are milliseconds; the receiving Discord client animates them.
struct PresenceTimeline {
    private var track: String?
    private var sampledPosition: TimeInterval = 0
    private var sampledAt: TimeInterval = 0

    mutating func timestamps(id: String, duration: TimeInterval, position: TimeInterval,
                             now: TimeInterval) -> (start: UInt64, end: UInt64?) {
        let position = position.isFinite ? max(0, position) : 0
        if track != id || abs(position - sampledPosition) >= 0.5 {
            track = id
            sampledPosition = position
            sampledAt = now
        }
        // Predict briefly between observations; a stalled player is not proof
        // that playback is still progressing. Pause/stop explicitly resets this.
        var projected = sampledPosition + min(30, max(0, now - sampledAt))
        let knownDuration = duration.isFinite && duration > 0
        if knownDuration { projected = min(projected, duration) }
        let start = max(0, now - projected)
        return (UInt64(start * 1000), knownDuration ? UInt64((now + max(0, duration - projected)) * 1000) : nil)
    }

    mutating func reset() { track = nil }

    static func artwork(provided: URL?, cached: URL?) -> URL? {
        [provided, cached].compactMap { $0 }.first {
            $0.scheme?.lowercased() == "https" && $0.host != nil
        }
    }
}
