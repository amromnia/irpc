import BackgroundTasks
import Combine
import UIKit

@MainActor
final class BackgroundRefreshController: ObservableObject {
    static let shared = BackgroundRefreshController()
    @Published private(set) var status = UserDefaults.standard.string(forKey: "refresh.lastStatus") ?? "Not run"
    private let identifier = Bundle.main.bundleIdentifier! + ".refresh"
    private var registered = false
    private var operation: (@MainActor () async throws -> Void)?

    func register(operation: @escaping @MainActor () async throws -> Void) {
        self.operation = operation
        guard !registered else { return }
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            Task { @MainActor in
                guard let self else { task.setTaskCompleted(success: false); return }
                self.run(task)
            }
        }
    }

    func schedule() {
        guard UserDefaults.standard.bool(forKey: "sharing.backgroundRefresh"),
              UserDefaults.standard.bool(forKey: "sharing.requested") else { cancel(); return }
        guard UIApplication.shared.backgroundRefreshStatus == .available else {
            setStatus("Disabled in iOS Settings")
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { setStatus("Couldn't schedule a refresh") }
    }

    func cancel() { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }

    private func setStatus(_ value: String) {
        status = value
        UserDefaults.standard.set(value, forKey: "refresh.lastStatus")
    }

    private func run(_ task: BGTask) {
        guard let operation else { task.setTaskCompleted(success: false); return }
        schedule()
        let work = Task { @MainActor in
            do {
                try await operation()
                try Task.checkCancellation()
                setStatus("Updated " + Date().formatted(date: .omitted, time: .shortened))
                task.setTaskCompleted(success: true)
            } catch {
                setStatus(Task.isCancelled ? "Expired" : "Refresh failed")
                task.setTaskCompleted(success: false)
            }
        }
        task.expirationHandler = { work.cancel() }
    }
}
