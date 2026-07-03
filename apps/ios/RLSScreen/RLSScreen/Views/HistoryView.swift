import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: ScreeningStore

    var body: some View {
        NavigationStack {
            List {
                if store.history.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock",
                        description: Text("Completed screenings will appear here.")
                    )
                } else {
                    ForEach(store.history) { record in
                        HistoryRow(record: record)
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !store.history.isEmpty {
                    Button(role: .destructive) {
                        store.clearHistory()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
            }
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
                Spacer()
                Text(record.riskScore, format: .percent.precision(.fractionLength(1)))
                    .font(.headline.monospacedDigit())
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
        .padding(.vertical, 4)
    }
}

