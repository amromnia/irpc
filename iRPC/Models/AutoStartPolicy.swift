import Foundation

struct AutoStartPolicy {
    private(set) var foreground = false
    private var attempted = false
    mutating func enterForeground() {
        if !foreground { attempted = false }
        foreground = true
    }
    mutating func leaveForeground() { foreground = false }
    mutating func suppress() { attempted = true }
    mutating func rearm() { attempted = false }
    mutating func claim(enabled: Bool, ready: Bool, authorized: Bool) -> Bool {
        guard foreground, enabled, ready, authorized, !attempted else { return false }
        attempted = true
        return true
    }
}
