import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: ScreeningStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.history.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock",
                        description: Text("Completed screenings will appear here.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    HStack {
                        Label("Prediction History", systemImage: "clock.arrow.circlepath")
                            .font(.headline)
                            .foregroundStyle(RestlegTheme.ink)
                        Spacer()
                        Button(role: .destructive) {
                            store.clearHistory()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .panelStyle()

                    ForEach(store.history) { record in
                        HistoryRow(record: record)
                    }
                }
            }
            .padding(16)
        }
    }
}

private struct HistoryRow: View {
    let record: ScreeningRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.riskLevel.capitalized)
                    .font(.headline)
                    .foregroundStyle(RestlegTheme.ink)
                Spacer()
                Text(record.riskScore, format: .percent.precision(.fractionLength(1)))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(RestlegTheme.blue)
            }

            HStack {
                Text(record.createdAt, format: .dateTime.month().day().hour().minute())
                Spacer()
                Text(record.scenario)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .panelStyle()
    }
}
