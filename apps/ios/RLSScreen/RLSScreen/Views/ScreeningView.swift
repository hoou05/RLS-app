import SwiftUI

struct ScreeningView: View {
    @EnvironmentObject private var store: ScreeningStore
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let record = store.latestTier2 {
                        ResultSummaryView(record: record)
                    } else {
                        EmptyResultView()
                    }

                    HealthImportView()

                    if let message = store.healthImportMessage {
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error = store.errorMessage {
                        Text(error)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    InputSectionView(form: $store.form, focusedField: $focusedField)

                    Button {
                        focusedField = nil
                        store.runScreening()
                    } label: {
                        Label("Run Screening", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("RLS Screen")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
        }
    }
}

private struct HealthImportView: View {
    @EnvironmentObject private var store: ScreeningStore

    var body: some View {
        Button {
            Task {
                await store.importHealthData()
            }
        } label: {
            HStack {
                Label("Fill from Health", systemImage: "heart.text.square.fill")
                Spacer()
                if store.isImportingHealthData {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(store.isImportingHealthData)
    }
}

private struct EmptyResultView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No screening result", systemImage: "waveform.path.ecg")
                .font(.headline)
            Text("Screening only. This app does not diagnose RLS or determine whether you have RLS.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}

private struct ResultSummaryView: View {
    let record: ScreeningRecord

    private var level: RiskLevel {
        RiskLevel(score: record.riskScore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.title)
                        .font(.system(size: 34, weight: .bold))
                    Text(record.modelLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.riskScore, format: .percent.precision(.fractionLength(1)))
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
            }

            ProgressView(value: record.riskScore)
                .tint(color(for: level))

            HStack(spacing: 10) {
                MetricPill(title: "XGBoost", value: record.xgboostProbability)
                MetricPill(title: "TabM", value: record.tabmProbability)
            }

            if let coverage = record.coverageLabel {
                Label(coverage, systemImage: "checklist.checked")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("Screening only. Consult a clinician if symptoms persist or concern you.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private func color(for level: RiskLevel) -> Color {
        switch level {
        case .low:
            return .green
        case .moderate:
            return .orange
        case .high:
            return .red
        }
    }
}

private extension ScreeningRecord {
    var modelLabel: String {
        if let modelKey {
            return "Auto model: \(modelKey)"
        }
        return scenario
    }

    var coverageLabel: String? {
        guard let availableFeatureCount, let totalFeatureCount, totalFeatureCount > 0 else {
            return nil
        }
        return "\(availableFeatureCount) of \(totalFeatureCount) model features available"
    }
}

private struct MetricPill: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value, format: .percent.precision(.fractionLength(1)))
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}
