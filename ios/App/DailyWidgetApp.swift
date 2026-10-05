import SwiftUI

@main
struct DailyWidgetApp: App {
    @StateObject private var store = PlannerStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onOpenURL { url in store.handleDeepLink(url) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.appBecameActive() }
                    else if phase == .background { store.appEnteredBackground() }
                }
        }
    }
}
