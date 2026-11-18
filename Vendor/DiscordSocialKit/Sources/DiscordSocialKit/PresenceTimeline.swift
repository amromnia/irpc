import Foundation

/// SDK timestamps are milliseconds; the receiving Discord client animates them.
struct PresenceTimeline {
    private var track: String?
    private var sampledPosition: TimeInterval = 0
    private var sampledAt: TimeInterval = 0

    mutating func timestamps(id: String, duration: TimeInterval, position: TimeInterval,
                             now: TimeInterval) -> (start: UInt64?, end: UInt64?) {
        // Do not invent a position/duration while Music is hydrating, or pair
        // a new track with an out-of-range time left over from the previous one.
        guard duration.isFinite, duration > 0, position.isFinite,
              position >= 0, position <= duration else { return (nil, nil) }
        if track != id || abs(position - sampledPosition) >= 0.5 {
            track = id
            sampledPosition = position
            sampledAt = now
        }
        // Identical samples never move the deadline, even after it has expired.
        // Only a new track, seek, or advancing player sample can correct it.
        let start = max(0, sampledAt - sampledPosition)
        let end = start + duration
        // Listening uses both endpoints for a complete music progress range.
        // Expiry switches to a timestamp-free waiting card, not a count-up.
        return (UInt64(start * 1000), UInt64(end * 1000))
    }

    mutating func reset() { track = nil }

    static func artwork(provided: URL?, cached: URL?) -> URL? {
        [provided, cached].compactMap { $0 }.first {
            $0.scheme?.lowercased() == "https" && $0.host != nil
        }
    }
}

/// A transition gets one deadline. Repeated stale/missing samples cannot renew it.
struct PresenceTransition {
    private(set) var deadline: TimeInterval?

    mutating func begin(now: TimeInterval, timeout: TimeInterval) -> Bool {
        guard deadline == nil else { return false }
        deadline = now + timeout
        return true
    }

    mutating func reset() { deadline = nil }
}
