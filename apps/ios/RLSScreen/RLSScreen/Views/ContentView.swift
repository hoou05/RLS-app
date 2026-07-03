import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ScreeningStore

    var body: some View {
        TabView {
            ScreeningView()
                .tabItem {
                    Label("Screen", systemImage: "waveform.path.ecg")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }

            ModelInfoView()
                .tabItem {
                    Label("Model", systemImage: "cpu")
                }
        }
        .tint(.green)
    }
}

#Preview {
    ContentView()
        .environmentObject(ScreeningStore())
}

