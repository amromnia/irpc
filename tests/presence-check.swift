import Foundation

@main
struct PresenceCheck {
    static func main() {
        var timeline = PresenceTimeline()
        let now: TimeInterval = 1_800_000_000
        let initial = timeline.timestamps(id: "song", duration: 240, position: 60, now: now)
        let stale = timeline.timestamps(id: "song", duration: 240, position: 60, now: now + 15)
        precondition(initial.end == stale.end, "Identical player samples must not push the countdown deadline forward")
        let corrected = timeline.timestamps(id: "song", duration: 240, position: 80, now: now + 20)
        precondition(corrected.end == initial.end, "Fresh player samples must correct the clock")
        let seek = timeline.timestamps(id: "song", duration: 240, position: 20, now: now + 25)
        precondition(seek.end == UInt64((now + 245) * 1000), "Seeking must reset the countdown")
        let stalled = timeline.timestamps(id: "song", duration: 240, position: 20, now: now + 100)
        precondition(stalled.end == seek.end, "Stale samples must never extend the deadline")
        var ending = PresenceTimeline()
        let almostDone = ending.timestamps(id: "ending", duration: 240, position: 239, now: now)
        let ended = ending.timestamps(id: "ending", duration: 240, position: 239, now: now + 5)
        precondition(ended.end == almostDone.end,
                     "An expired song must keep its original deadline, not extend it to now")
        let farPastEnd = ending.timestamps(id: "ending", duration: 240, position: 239, now: now + 120)
        precondition(farPastEnd.end == almostDone.end && farPastEnd.start == nil,
                     "Stale tracks must stay expired and must never acquire an elapsed counter")
        let repeated = ending.timestamps(id: "ending", duration: 240, position: 0, now: now + 121)
        precondition(repeated.end == UInt64((now + 361) * 1000), "Repeat/seek must accept a new deadline")
        timeline.reset()
        let resumed = timeline.timestamps(id: "song", duration: 240, position: 20, now: now + 100)
        precondition(resumed.end == UInt64((now + 320) * 1000), "Resume must start from the actual player position")
        let unknown = timeline.timestamps(id: "stream", duration: .nan, position: -.infinity, now: now)
        precondition(unknown.end == nil && unknown.start == nil)
        let artwork = URL(string: "https://is1-ssl.mzstatic.com/image/cover.jpg")!
        let cached = URL(string: "https://is2-ssl.mzstatic.com/image/old.jpg")!
        precondition(PresenceTimeline.artwork(provided: artwork, cached: cached) == artwork,
                     "Use the supplied track artwork before a cached/catalog image")
        precondition(PresenceTimeline.artwork(provided: URL(string: "file:///secret"), cached: cached) == cached)
        let deviceArtwork = URL(string: "musicKit://artwork/library/CD8FFE37-8AFF-4881-9577-2722738102B0/600x600")!
        precondition(PublicArtworkPolicy.url(deviceArtwork) == nil,
                     "The reported device-only URL must never be sent to Discord")
        precondition(PublicArtworkPolicy.url(artwork) == artwork)
        precondition(PublicArtworkPolicy.url(URL(string: "http://example.com/image")) == nil)
        precondition(PublicArtworkPolicy.url(URL(string: "https://user:password@example.com/image")) == nil)
        print("PASS: countdown continuity, correction, seek, expiry, pause/resume, and artwork selection")
    }
}
