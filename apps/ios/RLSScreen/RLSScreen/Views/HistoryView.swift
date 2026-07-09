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
                AppSafetyFooter()
            }
            .padding(16)
        }
    }
}

private struct HistoryRow: View {
    let record: ScreeningRecord
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.riskLevel.capitalized)
                            .font(.headline)
                            .foregroundStyle(RestlegTheme.ink)

                        Text(record.createdAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(record.riskScore, format: .percent.precision(.fractionLength(1)))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(RestlegTheme.blue)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                HistoryDetail(record: record)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .panelStyle()
    }
}

private struct HistoryDetail: View {
    let record: ScreeningRecord

    private var form: ScreeningForm {
        record.input
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            DetailSection(title: "Result", systemImage: "gauge.with.dots.needle.bottom.50percent") {
                DetailGrid(items: [
                    .init("Risk score", percent(record.riskScore)),
                    .init("Risk level", record.riskLevel.capitalized),
                ])
            }

            DetailSection(title: "Sleep", systemImage: "bed.double") {
                DetailGrid(items: [
                    .init("Sleep end", dateTime(form.sleepSessionEndDate)),
                    .init("Duration", minutes(form.sleepDurationMinutes)),
                    .init("Efficiency", percentNumber(form.sleepEfficiency)),
                    .init("Latency", minutes(form.sleepLatencyMinutes)),
                    .init("WASO", minutes(form.wasoMinutes)),
                ])
            }

            DetailSection(title: "Sleep Architecture", systemImage: "rectangle.3.group") {
                DetailGrid(items: [
                    .init("REM latency", minutes(form.remLatencyMinutes)),
                    .init("Awake stage", minutes(form.awakeStageMinutes)),
                    .init("SpO2 avg", percentNumber(form.averageSpO2)),
                    .init("SpO2 min", percentNumber(form.minimumSpO2)),
                    .init("N1N2", stage(form.lightSleepMinutes, form.lightSleepPercent)),
                    .init("N3", stage(form.deepSleepMinutes, form.deepSleepPercent)),
                    .init("REM", stage(form.remSleepMinutes, form.remSleepPercent)),
                ])
            }

            DetailSection(title: "Wearable Signals", systemImage: "waveform.path.ecg") {
                DetailGrid(items: [
                    .init("Resting HR", bpm(form.restingHeartRate)),
                    .init("Mean HR", bpm(form.meanHeartRate)),
                ])
            }

        }
    }

    private func dateTime(_ value: Date?) -> String {
        guard let value else {
            return "Missing"
        }
        return value.formatted(date: .abbreviated, time: .shortened)
    }

    private func minutes(_ value: Double?) -> String {
        number(value, unit: "min")
    }

    private func bpm(_ value: Double?) -> String {
        number(value, unit: "bpm")
    }

    private func percent(_ value: Double?) -> String {
        guard let value else {
            return "Missing"
        }
        return value.formatted(.percent.precision(.fractionLength(1)))
    }

    private func percentNumber(_ value: Double?) -> String {
        number(value, unit: "%")
    }

    private func number(_ value: Double?, unit: String) -> String {
        guard let value else {
            return "Missing"
        }
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
    }

    private func stage(_ minutes: Double?, _ percent: Double?) -> String {
        switch (minutes, percent) {
        case let (minutes?, percent?):
            return "\(minutes.formatted(.number.precision(.fractionLength(0...1)))) min / \(percent.formatted(.number.precision(.fractionLength(0...1))))%"
        case let (minutes?, nil):
            return "\(minutes.formatted(.number.precision(.fractionLength(0...1)))) min"
        case let (nil, percent?):
            return "\(percent.formatted(.number.precision(.fractionLength(0...1))))%"
        case (nil, nil):
            return "Missing"
        }
    }

}

private struct DetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(RestlegTheme.ink)
            content
        }
    }
}

private struct DetailGrid: View {
    let items: [DetailItem]

    var body: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(RestlegTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RestlegTheme.panelTint, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct DetailItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }
}
