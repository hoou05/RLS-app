import SwiftUI

struct ModelInfoView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Runtime") {
                    Label("Offline inference", systemImage: "iphone")
                    Label("XGBoost tree evaluator", systemImage: "tree")
                    Label("TabM Swift forward pass", systemImage: "cpu")
                }

                Section("Data") {
                    LabeledContent("Model bundle", value: "RLSModelBundle.json")
                    LabeledContent("Storage", value: "On device")
                    LabeledContent("Network", value: "Not required")
                }

                Section("Clinical Boundary") {
                    Text("This app provides a non-diagnostic screening estimate. It does not determine whether a person has RLS.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Model")
        }
    }
}

