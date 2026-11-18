import SwiftUI

struct PlaybackButtonStyle: ButtonStyle {
    let animated: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(animated && configuration.isPressed ? 0.90 : 1)
            .rotationEffect(.degrees(animated && configuration.isPressed ? -4 : 0))
            .animation(animated ? .spring(response: 0.3, dampingFraction: 0.6) : nil, value: configuration.isPressed)
    }
}

struct PlaybackSymbol: View {
    let playing: Bool
    let animated: Bool
    var body: some View {
        ZStack {
            Image(systemName: "play.fill")
                .opacity(playing ? 0 : 1)
                .rotationEffect(.degrees(playing ? 90 : 0))
                .scaleEffect(playing ? 0.6 : 1)
            Image(systemName: "pause.fill")
                .opacity(playing ? 1 : 0)
                .rotationEffect(.degrees(playing ? 0 : -90))
                .scaleEffect(playing ? 1 : 0.6)
        }
        .animation(animated ? .spring(response: 0.4, dampingFraction: 0.7) : nil, value: playing)
    }
}
