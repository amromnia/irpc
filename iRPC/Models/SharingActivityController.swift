import ActivityKit
import Combine
import UIKit

@MainActor
final class SharingActivityController: ObservableObject {
    static let shared = SharingActivityController()
    @Published private(set) var error: String?
    private var desired: (Bool, SharingActivityAttributes.ContentState)?
    private var worker: Task<Void, Never>?
    private var lastState: SharingActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast
    private var lastAttempt = Date.distantPast

    func update(enabled: Bool, state: SharingActivityAttributes.ContentState) {
        if !enabled && Activity<SharingActivityAttributes>.activities.isEmpty && worker == nil {
            lastState = nil
            lastAttempt = .distantPast
            error = nil
            return
        }
        if enabled, let lastState,
           lastState.title == state.title, lastState.artist == state.artist,
           lastState.playing == state.playing, lastState.sharing == state.sharing,
           lastState.acknowledged == state.acknowledged, lastState.accounts == state.accounts,
           lastState.accentHex == state.accentHex,
           abs((lastState.end ?? .distantPast).timeIntervalSince(state.end ?? .distantPast)) < 2,
           lastUpdate.timeIntervalSinceNow > -30 { return }
        desired = (enabled, state)
        guard worker == nil else { return }
        worker = Task {
            while let (enabled, state) = desired {
                desired = nil
                await apply(enabled: enabled, state: state)
            }
            worker = nil
        }
    }

    private func apply(enabled: Bool, state: SharingActivityAttributes.ContentState) async {
        let activities = Activity<SharingActivityAttributes>.activities
        if !enabled {
            for activity in activities {
                await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
            lastState = nil
            lastAttempt = .distantPast
            error = nil
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            error = "Live Activities are disabled in iOS Settings."
            return
        }
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(90))
        do {
            if let activity = activities.first(where: { $0.activityState == .active || $0.activityState == .stale }) {
                await activity.update(content)
            } else {
                // Respect dismissal until sharing is stopped or the preference is toggled.
                guard lastState == nil, UIApplication.shared.applicationState == .active,
                      lastAttempt.timeIntervalSinceNow < -30 else { return }
                lastAttempt = Date()
                _ = try Activity.request(attributes: SharingActivityAttributes(), content: content, pushType: nil)
            }
            lastState = state
            lastUpdate = Date()
            error = nil
        } catch { self.error = "Couldn't start the Live Activity." }
    }
}
