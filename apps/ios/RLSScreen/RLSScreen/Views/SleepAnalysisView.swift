import Charts
import SwiftUI

struct SleepAnalysisView: View {
    @EnvironmentObject private var store: ScreeningStore

    private var analysis: SleepTrendAnalysis {
        SleepTrendAnalysis(records: store.history)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.history.isEmpty {
                    ContentUnavailableView(
                        "No Sleep History",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Run screenings or import Health sleep data to start building trends.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    TrendSummaryPanel(analysis: analysis)
                    TrendOverviewPanel(analysis: analysis)
                    SleepDurationChart(analysis: analysis)
                    RiskScoreChart(analysis: analysis)
                    SleepStagesPanel(analysis: analysis)
                    InsightPanel(insights: analysis.insights)
                }
            }
            .padding(16)
        }
    }
}

private struct TrendSummaryPanel: View {
    let analysis: SleepTrendAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Trend Analysis", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(RestlegTheme.ink)

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Use this as a pattern check, not a diagnosis. If sleep disruption persists or daytime function is affected, bring these notes to a clinician.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private var summary: String {
        var parts: [String] = []
        if let avg = analysis.averageSleepDurationMinutes {
            parts.append("Recent records average \(SleepTrendAnalysis.formatDuration(minutes: avg)) of sleep.")
        }
        if let efficiency = analysis.averageSleepEfficiency {
            parts.append("Average efficiency is \(efficiency.formatted(.number.precision(.fractionLength(0))))%.")
        }
        if let change = analysis.sleepDurationChangeMinutes {
            parts.append("Sleep duration is \(SleepTrendAnalysis.formatSignedMinutes(change)) versus prior records.")
        }
        if analysis.shortSleepNightCount > 0 {
            parts.append("\(analysis.shortSleepNightCount) recent night(s) were short-sleep nights.")
        }
        if analysis.lowEfficiencyNightCount > 0 {
            parts.append("\(analysis.lowEfficiencyNightCount) recent night(s) had lower sleep efficiency.")
        }
        return parts.isEmpty ? "Trend data is present, but key sleep metrics are still limited. Continue collecting a few more nights for a clearer pattern." : parts.joined(separator: " ")
    }
}

private struct TrendOverviewPanel: View {
    let analysis: SleepTrendAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Latest \(analysis.recentSamples.count) Records", systemImage: "calendar")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                TrendMetricTile(
                    title: "Avg Sleep",
                    value: analysis.averageSleepDurationMinutes.map(SleepTrendAnalysis.formatDuration) ?? "No data",
                    footnote: changeFootnote
                )
                TrendMetricTile(
                    title: "Efficiency",
                    value: analysis.averageSleepEfficiency.map { $0.formatted(.number.precision(.fractionLength(0))) + "%" } ?? "No data",
                    footnote: "\(analysis.lowEfficiencyNightCount) low-efficiency nights"
                )
                TrendMetricTile(
                    title: "Risk",
                    value: analysis.averageRiskScore.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "No data",
                    footnote: "\(analysis.highRiskNightCount) high-band screenings"
                )
                TrendMetricTile(
                    title: "Bedtime Range",
                    value: analysis.bedTimeRangeMinutes.map { SleepTrendAnalysis.formatDuration(minutes: Double($0)) } ?? "No data",
                    footnote: "Estimated from sleep end time"
                )
            }
        }
        .panelStyle()
    }

    private var changeFootnote: String {
        guard let change = analysis.sleepDurationChangeMinutes else {
            return "Need prior records for change"
        }
        return "\(SleepTrendAnalysis.formatSignedMinutes(change)) vs prior records"
    }
}

private struct SleepDurationChart: View {
    let analysis: SleepTrendAnalysis

    private var points: [TrendPoint] {
        analysis.samples.compactMap { sample in
            guard let sleepDurationHours = sample.sleepDurationHours else {
                return nil
            }
            return TrendPoint(id: "\(sample.id)-duration", date: sample.date, value: sleepDurationHours)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sleep Duration", systemImage: "bed.double")
                .font(.headline)

            if points.isEmpty {
                MissingMetricView(text: "No sleep duration values in saved records.")
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Hours", point.value)
                    )
                    .foregroundStyle(RestlegTheme.teal)

                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Hours", point.value)
                    )
                    .foregroundStyle(RestlegTheme.teal)

                    RuleMark(y: .value("Reference", 6.5))
                        .foregroundStyle(.orange.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartYAxisLabel("Hours")
                .frame(height: 190)
            }
        }
        .panelStyle()
    }
}

private struct RiskScoreChart: View {
    let analysis: SleepTrendAnalysis

    private var points: [TrendPoint] {
        analysis.samples.map { sample in
            TrendPoint(id: "\(sample.id)-risk", date: sample.date, value: sample.riskScore)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Screening Risk", systemImage: "waveform.path.ecg")
                .font(.headline)

            Chart(points) { point in
                AreaMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Score", point.value)
                )
                .foregroundStyle(.orange.opacity(0.18))

                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Score", point.value)
                )
                .foregroundStyle(.orange)

                PointMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Score", point.value)
                )
                .foregroundStyle(.orange)
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let score = value.as(Double.self) {
                            Text(score, format: .percent.precision(.fractionLength(0)))
                        }
                    }
                }
            }
            .frame(height: 190)
        }
        .panelStyle()
    }
}

private struct SleepStagesPanel: View {
    let analysis: SleepTrendAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Sleep Detail", systemImage: "list.bullet.clipboard")
                .font(.headline)

            VStack(spacing: 10) {
                DetailMetricRow(
                    title: "Deep sleep",
                    value: analysis.averageDeepSleepPercent.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "No data"
                )
                DetailMetricRow(
                    title: "REM sleep",
                    value: analysis.averageREMSleepPercent.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "No data"
                )
                DetailMetricRow(
                    title: "Resting heart rate",
                    value: analysis.averageRestingHeartRate.map { $0.formatted(.number.precision(.fractionLength(0))) + " bpm" } ?? "No data"
                )
            }
        }
        .panelStyle()
    }
}

private struct InsightPanel: View {
    let insights: [SleepTrendInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Insights", systemImage: "sparkle.magnifyingglass")
                .font(.headline)

            ForEach(insights) { insight in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: insight.systemImage)
                        .font(.headline)
                        .foregroundStyle(color(for: insight.severity))
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(insight.title)
                            .font(.subheadline.weight(.semibold))
                        Text(insight.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Trend analysis is for tracking patterns only. It does not diagnose sleep disorders or RLS.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private func color(for severity: SleepTrendInsight.Severity) -> Color {
        switch severity {
        case .stable:
            return RestlegTheme.green
        case .watch:
            return .orange
        case .attention:
            return .red
        }
    }
}

private struct TrendMetricTile: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .leading)
        .padding(12)
        .background(RestlegTheme.panelTint, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DetailMetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}

private struct MissingMetricView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            .background(RestlegTheme.panelTint, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TrendPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
}
