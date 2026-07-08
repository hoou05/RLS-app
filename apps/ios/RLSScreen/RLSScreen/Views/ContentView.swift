import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ScreeningStore

    var body: some View {
        if store.hasCompletedOnboarding {
            TabView {
                ScreeningView()
                    .tabItem {
                        Label("Screen", systemImage: "waveform.path.ecg")
                    }

                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }

                SleepAnalysisView()
                    .tabItem {
                        Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
                    }

                ModelInfoView()
                    .tabItem {
                        Label("Model", systemImage: "cpu")
                    }
            }
            .tint(.green)
        } else {
            OnboardingView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ScreeningStore())
}
