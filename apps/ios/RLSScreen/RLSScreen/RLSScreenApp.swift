import SwiftUI

@main
struct RLSScreenApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: ScreeningStore

    private let backgroundRefresh = BackgroundRefreshCoordinator.shared

    init() {
        let store = ScreeningStore()
        _store = StateObject(wrappedValue: store)
        backgroundRefresh.register {
            await store.refreshFromHealthIfNeeded(source: "Daily refresh", notify: true)
        }
        backgroundRefresh.scheduleNextRefresh()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    if store.hasCompletedOnboarding {
                        await store.configureAutomation()
                        backgroundRefresh.scheduleNextRefresh()
                    }
                }
                .onChange(of: store.hasCompletedOnboarding) { _, completed in
                    guard completed else {
                        return
                    }
                    Task {
                        await store.configureAutomation()
                        backgroundRefresh.scheduleNextRefresh()
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .background {
                        backgroundRefresh.scheduleNextRefresh()
                    }
                }
        }
    }
}
