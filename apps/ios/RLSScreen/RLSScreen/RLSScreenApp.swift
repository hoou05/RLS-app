import SwiftUI

@main
struct RLSScreenApp: App {
    @StateObject private var store = ScreeningStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

