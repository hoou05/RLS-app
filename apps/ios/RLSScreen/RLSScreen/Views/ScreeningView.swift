import SwiftUI

struct ScreeningView: View {
    @EnvironmentObject private var store: ScreeningStore
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        ScreeningHeroView(score: currentRiskScore)
                            .id("screen-top")

                        if let baseline = store.baselineResult {
                            BaselineSummaryPanel(baseline: baseline)
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
                            withAnimation(.snappy) {
                                proxy.scrollTo("screen-top", anchor: .top)
                            }
                        } label: {
                            Label("Run Screening", systemImage: "play.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(RestlegTheme.navy)
                        .controlSize(.large)

                        AppSafetyFooter()
                    }
                    .padding(16)
                }
            }
            .restlegBackground()
            .toolbar(.hidden, for: .navigationBar)
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

    private var currentRiskScore: Double? {
        latestRecord?.riskScore ?? store.baselineResult?.typicalScore
    }

    private var latestRecord: ScreeningRecord? {
        store.latestTier2 ?? store.latestTier1
    }
}

private struct BaselineSummaryPanel: View {
    let baseline: BaselineScreeningResult

    private var level: RiskLevel {
        baseline.riskLevel ?? .low
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("60-day baseline")
                        .font(.headline)
                    Text(level.title)
                        .font(.system(size: 34, weight: .bold))
                }
                Spacer()
                Text(baseline.typicalScore ?? 0, format: .percent.precision(.fractionLength(1)))
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
            }

            ProgressView(value: baseline.typicalScore ?? 0)
                .tint(color(for: level))

            HStack(spacing: 10) {
                MetricPill(title: "Usable nights", value: "\(baseline.validNightCount)")
                MetricPill(title: "Data quality", value: baseline.dataQuality.title)
                MetricPill(title: "High nights", value: "\(baseline.highRiskNightCount)")
            }

            if let meanScore = baseline.meanScore, let p75Score = baseline.p75Score {
                Text("Mean \(meanScore, format: .percent.precision(.fractionLength(1))) / P75 \(p75Score, format: .percent.precision(.fractionLength(1)))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let dateRangeLabel = baseline.dateRangeLabel {
                Text(dateRangeLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
    }

    private func color(for level: RiskLevel) -> Color {
        switch level {
        case .low:
            return RestlegTheme.green
        case .moderate:
            return .orange
        case .high:
            return .red
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

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RestlegTheme.panelTint, in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension MetricPill {
    init(title: String, value: Double) {
        self.title = title
        self.value = value.formatted(.percent.precision(.fractionLength(1)))
    }
}

private struct ScreeningHeroView: View {
    let score: Double?

    private var levelTitle: String {
        guard let score else { return "Risk" }
        return RiskLevel(score: score).title
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Restleg")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(RestlegTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(score == nil ? "Run screening to update your score." : "Latest screening score.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HeroRiskDial(score: score, title: levelTitle, subtitle: score == nil ? "Baseline needed" : "Current")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [RestlegTheme.panelTint, .white.opacity(0.96)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(spacing: 12) {
                    Capsule()
                        .fill(RestlegTheme.sky.opacity(0.46))
                        .frame(width: 180, height: 8)
                    Capsule()
                        .fill(RestlegTheme.teal.opacity(0.18))
                        .frame(width: 130, height: 8)
                }
                .rotationEffect(.degrees(-18))
                .offset(x: 74, y: 42)
            }
        }
    }
}

private struct HeroRiskDial: View {
    let score: Double?
    let title: String
    let subtitle: String

    private var progress: Double {
        min(max(score ?? 0, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [RestlegTheme.sky, RestlegTheme.blue, RestlegTheme.navy],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: RestlegTheme.navy.opacity(0.22), radius: 18, x: 0, y: 10)

            Circle()
                .stroke(RestlegTheme.sky.opacity(0.55), lineWidth: 10)
                .padding(5)

            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: 7)
                .padding(18)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(18)

            VStack(spacing: 2) {
                Text(score.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "--")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.74)
                Text(title)
                    .font(.caption.weight(.bold))
                Text(subtitle)
                    .font(.caption2)
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
        }
        .frame(width: 142, height: 142)
        .accessibilityLabel("Risk score")
    }
}
