import AppIntents
import Foundation

/// Opens the app straight into voice capture. Used by the lock-screen / Control Center control.
struct OpenQuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a task by voice"
    static var openAppWhenRun = true
    static let requestKey = "quickAddRequestedAt"

    func perform() async throws -> some IntentResult {
        // The app may not be listening yet when it is launched cold, so leave a short-lived note too.
        UserDefaults(suiteName: WidgetSnapshot.appGroupID)?.set(Date().timeIntervalSince1970, forKey: Self.requestKey)
        await MainActor.run { NotificationCenter.default.post(name: .dailyWidgetQuickAdd, object: nil) }
        return .result()
    }

    /// True once for a request made in the last few seconds.
    static func consumePendingRequest() -> Bool {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshot.appGroupID) else { return false }
        let requestedAt = defaults.double(forKey: requestKey)
        guard requestedAt > 0 else { return false }
        defaults.removeObject(forKey: requestKey)
        return Date().timeIntervalSince1970 - requestedAt < 15
    }
}

extension Notification.Name {
    static let dailyWidgetQuickAdd = Notification.Name("dailyWidgetQuickAdd")
}
