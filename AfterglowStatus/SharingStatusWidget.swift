import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SharingStatusWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SharingActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: "music.note")
                    .font(.title2).foregroundStyle(tint(context.state))
                    .frame(width: 48, height: 48)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text(context.state.title).font(.headline).lineLimit(1)
                    if !context.state.artist.isEmpty {
                        Text(context.state.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(context.state.status(stale: context.isStale)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if !context.isStale, context.state.playing, let end = context.state.end, end > Date() {
                    Text(timerInterval: Date()...end, countsDown: true)
                        .font(.caption.monospacedDigit()).frame(width: 45)
                }
            }
            .padding(16)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note").foregroundStyle(tint(context.state)).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Text(context.state.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.status(stale: context.isStale))
                        Spacer()
                        if !context.isStale { Text(context.state.accounts == 1 ? "1 account" : "\(context.state.accounts) accounts") }
                    }.font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "music.note").foregroundStyle(context.isStale ? Color.secondary : tint(context.state))
            } compactTrailing: {
                if !context.isStale, context.state.playing, let end = context.state.end, end > Date() {
                    Text(timerInterval: Date()...end, countsDown: true).monospacedDigit().frame(width: 40)
                } else { Image(systemName: context.isStale ? "arrow.clockwise" : "pause.fill") }
            } minimal: {
                Image(systemName: context.isStale ? "arrow.clockwise" : "music.note")
            }
        }
    }
    private func tint(_ state: SharingActivityAttributes.ContentState) -> Color {
        let value = UInt32(state.accentHex, radix: 16) ?? 0xE44950
        return Color(.sRGB, red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }

}
