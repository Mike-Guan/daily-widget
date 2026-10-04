import Foundation
import UserNotifications

/// Keeps local notifications in step with the tasks that want a reminder.
enum ReminderScheduler {
    private static let prefix = "task-reminder-"

    /// Schedules what is wanted and due in the future, and removes reminders whose task was deleted,
    /// completed, unscheduled or moved. Safe to call often.
    static func reconcile(tasks: [PlannerTask], english: Bool) async {
        let center = UNUserNotificationCenter.current()
        let wanted = ReminderPlan.wantedIDs()
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }

        var keep = Set<String>()
        var toSchedule: [(PlannerTask, Date)] = []
        for id in wanted {
            guard let task = byID[id], let fireDate = ReminderPlan.fireDate(for: task) else {
                // The task is gone or can no longer fire; forget it once the file confirms that.
                if byID[id] == nil || byID[id]?.isDeleted == true { ReminderPlan.setWanted(false, taskID: id) }
                continue
            }
            guard fireDate > .now else { continue }
            let existing = pending.first { $0.identifier == prefix + id }
            let existingDate = (existing?.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            if let existingDate, abs(existingDate.timeIntervalSince(fireDate)) < 1, existing?.content.body == task.title { keep.insert(prefix + id) }
            else { toSchedule.append((task, fireDate)) }
        }
        let stale = pending.map(\.identifier).filter { !keep.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        guard !toSchedule.isEmpty else { return }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }

        for (task, fireDate) in toSchedule {
            let content = UNMutableNotificationContent()
            content.title = english ? "Reminder" : "提醒"
            content.body = task.title
            content.sound = .default
            content.userInfo = ["taskID": task.id, "date": task.date ?? ""]
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            try? await center.add(UNNotificationRequest(identifier: prefix + task.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
    }
}
