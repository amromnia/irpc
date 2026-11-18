import Foundation

@main
struct PlaybackStateCheck {
    static func main() {
        var cold = PlaybackPresentationState()
        cold.observe(playing: false, now: 0, initialMusicKitPlaying: true, mediaStateKnown: false)
        precondition(cold.playing, "An existing Music session must seed the UI before a play command")
        cold.observe(playing: false, now: 0.2, initialMusicKitPlaying: true, mediaStateKnown: false)
        precondition(cold.playing, "An unhydrated MediaPlayer snapshot must not erase the initial MusicKit state")
        cold.observe(playing: false, now: 0.3, initialMusicKitPlaying: true, mediaStateKnown: true)
        precondition(!cold.playing, "A real pause/stop notification must supersede the bootstrap snapshot")
        cold.observe(playing: false, now: 0.4, initialMusicKitPlaying: true, mediaStateKnown: false)
        precondition(!cold.playing, "After hydration, stale MusicKit state must not restart the UI")
        cold.commandAccepted(playing: true, now: 1)
        cold.observe(playing: false, now: 1.1, initialMusicKitPlaying: false, mediaStateKnown: false)
        precondition(cold.playing, "The existing command reconciliation must still work after bootstrap")
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
        print("PASS: cold-launch playing state, hydration, authoritative notifications, 100 pause/resume cycles, delayed system snapshots, external pause, bounded reconciliation, and permission reset")
    }
}
