import BackgroundTasks
import Foundation

final class BackgroundRefreshCoordinator {
    static let shared = BackgroundRefreshCoordinator()
    static let refreshIdentifier = "com.hoou05.restleg.screen.refresh"

    private var isRegistered = false
    private var refreshHandler: (() async -> Void)?

    private init() {}

    func register(refreshHandler: @escaping () async -> Void) {
        self.refreshHandler = refreshHandler
        guard !isRegistered else {
            return
        }
        isRegistered = true
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshIdentifier,
            using: nil
        ) { [weak self] task in
            guard let task = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self?.handle(task)
        }
    }

    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        request.earliestBeginDate = Self.nextMorningRefreshDate()
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // The system may reject duplicate or unavailable requests. The next foreground
            // activation or HealthKit observer callback will schedule again.
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        scheduleNextRefresh()

        let refreshTask = Task {
            await refreshHandler?()
            task.setTaskCompleted(success: !Task.isCancelled)
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }
    }

    private static func nextMorningRefreshDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let todayMorning = calendar.date(
            bySettingHour: 8,
            minute: 0,
            second: 0,
            of: now
        ) ?? now.addingTimeInterval(12 * 3_600)

        if todayMorning > now.addingTimeInterval(30 * 60) {
            return todayMorning
        }
        return calendar.date(byAdding: .day, value: 1, to: todayMorning) ?? now.addingTimeInterval(24 * 3_600)
    }
}
