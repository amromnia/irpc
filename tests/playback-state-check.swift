import Foundation

@main
struct PlaybackStateCheck {
    static func main() {
        var state = PlaybackPresentationState()
        var now: TimeInterval = 100
        state.observe(playing: true, now: now)
        precondition(state.playing)
        for _ in 0..<100 {
            now += 3
            state.commandAccepted(playing: false, now: now)
            state.observe(playing: true, now: now + 0.1) // Previous play snapshot arrives after pause.
            precondition(!state.playing)
            state.observe(playing: false, now: now + 0.2)
            now += 0.3
            state.commandAccepted(playing: true, now: now)
            state.observe(playing: false, now: now + 0.1) // Previous pause snapshot arrives after resume.
            precondition(state.playing, "Resume must restart the button and vapor without relaunching")
            state.observe(playing: true, now: now + 0.2)
            precondition(state.playing)
        }
        now += 3
        state.commandAccepted(playing: true, now: now)
        state.observe(playing: false, now: now + 2)
        precondition(!state.playing, "A failed/interrupted start must not leave a permanent optimistic state")
        state.observe(playing: true, now: now + 3)
        state.observe(playing: false, now: now + 4)
        precondition(!state.playing, "External pauses must update the UI")
        state.commandAccepted(playing: true, now: now + 5)
        state.reset()
        precondition(!state.playing)
        print("PASS: 100 pause/resume cycles, delayed system snapshots, external pause, bounded reconciliation, and permission reset")
    }
}
