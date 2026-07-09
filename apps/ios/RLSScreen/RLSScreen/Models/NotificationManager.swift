import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private init() {}

    func requestAuthorization() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Notification permission is optional; automatic screening still works without alerts.
        }
    }

    func notifyScreeningUpdated(record: ScreeningRecord) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Sleep screening updated"
        content.body = "New sleep data was analyzed. Open RestLeg to review the result."
        content.sound = .default
        content.badge = 1
        content.userInfo = [
            "screeningRecordID": record.id.uuidString,
            "scenario": record.scenario,
        ]

        let request = UNNotificationRequest(
            identifier: "sleep-screening-\(record.id.uuidString)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
