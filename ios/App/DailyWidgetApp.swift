import SwiftUI

@main
struct DailyWidgetApp: App {
    @StateObject private var store = PlannerStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .onOpenURL { url in store.handleDeepLink(url) }
        }
    }
}
