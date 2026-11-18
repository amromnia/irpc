import ActivityKit
import Foundation

struct SharingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var playing: Bool
        var sharing: Bool
        var acknowledged: Bool
        var accounts: Int
        var accentHex: String
        var end: Date?

        func status(stale: Bool) -> String {
            if stale { return "Open Afterglow to update" }
            if !sharing { return "Not sharing" }
            if !playing { return "Paused" }
            return acknowledged ? "Sharing" : "Connecting"
        }
    }
}
