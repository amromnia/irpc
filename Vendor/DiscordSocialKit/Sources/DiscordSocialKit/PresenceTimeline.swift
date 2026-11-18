import Foundation

/// SDK timestamps are milliseconds; the receiving Discord client animates them.
struct PresenceTimeline {
    private var track: String?
    private var sampledPosition: TimeInterval = 0
    private var sampledAt: TimeInterval = 0

    mutating func timestamps(id: String, duration: TimeInterval, position: TimeInterval,
                             now: TimeInterval) -> (start: UInt64?, end: UInt64?) {
        let position = position.isFinite ? max(0, position) : 0
        if track != id || abs(position - sampledPosition) >= 0.5 {
            track = id
            sampledPosition = position
            sampledAt = now
        }
        // Identical samples never move the deadline, even after it has expired.
        // Only a new track, seek, or advancing player sample can correct it.
        guard duration.isFinite, duration > 0 else { return (nil, nil) }
        let end = max(0, sampledAt + max(0, duration - sampledPosition))
        // End-only timestamps avoid Discord falling back to an elapsed counter.
        return (nil, UInt64(end * 1000))
    }

    mutating func reset() { track = nil }

    static func artwork(provided: URL?, cached: URL?) -> URL? {
        [provided, cached].compactMap { $0 }.first {
            $0.scheme?.lowercased() == "https" && $0.host != nil
        }
    }
}
