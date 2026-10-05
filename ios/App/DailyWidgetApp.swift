import SwiftUI

@main
struct DailyWidgetApp: App {
    @StateObject private var store = PlannerStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Widgets and the lock-screen control start listening through these, with the app in the background.
        if #available(iOS 18.0, *) { RecordTaskIntent.start = { await BackgroundVoiceCapture.shared.start() } }
        FinishVoiceCaptureIntent.finish = { await BackgroundVoiceCapture.shared.finishNow() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onOpenURL { url in store.handleDeepLink(url) }
                .onReceive(NotificationCenter.default.publisher(for: .dailyWidgetTasksChanged)) { _ in store.reload() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.appBecameActive(); TaskInterpreter.prewarm() }
                    else if phase == .background { store.appEnteredBackground(); LocalModelInterpreter.unload() }
                }
        }
    }
}
