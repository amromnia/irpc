import BackgroundTasks
import Combine
import UIKit

@MainActor
final class BackgroundController: ObservableObject {
    static let shared = BackgroundController()
    static var interval: UInt64 {
        let seconds = UserDefaults.standard.integer(forKey: "sharing.pollSeconds")
        return UInt64([5, 15, 30].contains(seconds) ? seconds : 15) * 1_000_000_000
    }

    @Published private(set) var isRunning = false
    @Published private(set) var status = "Start a sharing session. iOS may stop it early."

    private let identifier = Bundle.main.bundleIdentifier! + ".presence"
    private var registered = false
    private var sessionMinutes = 30
    private var worker: Task<Void, Never>?
    private var activeTask: BGTask?
    private var update: (@MainActor () async throws -> Void)?
    private var onStop: (@MainActor () -> Void)?

    private init() {}

    func register() {
        guard #available(iOS 26.0, *), !registered else { return }
        registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier, using: .main
        ) { [weak self] task in
            Task { @MainActor in
                guard let self, let task = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.run(task)
            }
        }
    }

    func start(minutes: Int, update: @escaping @MainActor () async throws -> Void,
               onStop: @escaping @MainActor () -> Void) throws {
        guard !isRunning else { return }
        guard #available(iOS 26.0, *) else {
            throw SessionError.unavailable
        }
        guard registered, UIApplication.shared.applicationState == .active else {
            throw SessionError.notReady
        }
        let minutes = [30, 120, 240].contains(minutes) ? minutes : 30
        self.sessionMinutes = minutes
        self.update = update
        self.onStop = onStop
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "Sharing Apple Music",
            subtitle: "\(minutes)-minute listening session"
        )
        request.strategy = .fail
        isRunning = true
        status = "Starting sharing session…"
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            isRunning = false
            self.update = nil
            self.onStop = nil
            throw error
        }
    }

    func stop(success: Bool = true, message: String = "Sharing stopped.") {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        worker?.cancel()
        worker = nil
        activeTask?.setTaskCompleted(success: success)
        activeTask = nil
        update = nil
        isRunning = false
        status = message
        let callback = onStop
        onStop = nil
        callback?()
    }

    @available(iOS 26.0, *)
    private func run(_ task: BGContinuedProcessingTask) {
        guard isRunning, activeTask == nil, let update else {
            task.setTaskCompleted(success: false)
            return
        }
        activeTask = task
        task.expirationHandler = { [weak self, weak task] in
            Task { @MainActor in
                guard let self, let task, self.activeTask === task else { return }
                self.stop(success: false, message: "iOS ended the session. Tap Start to try again.")
            }
        }
        let interval = Self.interval
        let checkCount = Int64(sessionMinutes * 60) / Int64(interval / 1_000_000_000)
        let minutes = sessionMinutes
        task.progress.totalUnitCount = checkCount
        worker = Task { @MainActor [weak self] in
            do {
                for step in 1...checkCount {
                    try Task.checkCancellation()
                    try await update()
                    try Task.checkCancellation()
                    self?.status = "Sharing Apple Music with Discord (up to \(minutes) minutes)."
                    try await Task.sleep(nanoseconds: interval)
                    task.progress.completedUnitCount = step
                }
                guard let self, self.activeTask === task else { return }
                self.stop(message: "\(minutes)-minute session complete. Tap Start to share again.")
            } catch is CancellationError {
                // The stop/expiration path already completes the system task.
            } catch {
                guard let self, self.activeTask === task else { return }
                self.stop(success: false, message: "Sharing stopped: \(error.localizedDescription)")
            }
        }
    }

    private enum SessionError: LocalizedError {
        case unavailable, notReady

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Background sharing requires iOS 26 or later."
            case .notReady: return "Open the app to start sharing."
            }
        }
    }
}
