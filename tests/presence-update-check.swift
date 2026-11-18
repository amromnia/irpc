import Foundation

@main
struct PresenceUpdateCheck {
    static func main() {
        var updates = PresenceUpdatePolicy()
        precondition(PresenceUpdatePolicy.sampleSeconds <= 2)
        precondition(updates.shouldPublish(track: "first|no artwork", now: 0, interval: 30))
        precondition(!updates.shouldPublish(track: "first|no artwork", now: 1, interval: 30))
        precondition(updates.shouldPublish(track: "second|no artwork", now: 2, interval: 30),
                     "New tracks must bypass even the longest resend interval and pending artwork")
        precondition(updates.shouldPublish(track: "second|artwork", now: 3, interval: 30),
                     "Artwork must enrich the current track without delaying its initial publication")
        precondition(updates.shouldPublish(track: nil, now: 4, interval: 30), "Pause/end must publish the transition immediately")
        precondition(!updates.shouldPublish(track: nil, now: 5, interval: 30))
        precondition(updates.shouldPublish(track: "second|artwork", now: 6, interval: 30), "Resume must publish immediately")
        precondition(!updates.shouldPublish(track: "second|artwork", now: 8, interval: 30))
        precondition(updates.shouldPublish(track: "second|artwork", now: 9, interval: 30, force: true),
                     "Native notifications and explicit playback commands must bypass the resend interval")
        precondition(updates.shouldPublish(track: "second|artwork", now: 39, interval: 30))
        updates.reset()
        precondition(updates.shouldPublish(track: "second|artwork", now: 40, interval: 30))
        var timing = PresenceUpdatePolicy()
        precondition(timing.shouldPublish(track: "song", now: 0, interval: 30, position: 0, duration: 0))
        precondition(timing.shouldPublish(track: "song", now: 2, interval: 30, position: 2, duration: 240),
                     "A real duration arriving after hydration must publish immediately")
        precondition(!timing.shouldPublish(track: "song", now: 4, interval: 30, position: 4, duration: 240))
        precondition(timing.shouldPublish(track: "song", now: 5, interval: 30, position: 60, duration: 240),
                     "Seek corrections must bypass the heartbeat")
        precondition(timing.shouldPublish(track: "song", now: 6, interval: 30, position: 0, duration: 240),
                     "Repeat/seek-back must repair an expired or incorrect timer immediately")
        precondition(!timing.shouldPublish(track: "song", now: 7, interval: 30, position: 1, duration: 240))
        print("PASS: two-second sampling, immediate track/pause/resume/artwork changes, notifications, duration hydration, seek corrections, resend interval")
    }
}
