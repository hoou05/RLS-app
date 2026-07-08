import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: ScreeningStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Restleg")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(RestlegTheme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            Text(currentRiskScore == nil ? "Build your first local baseline." : "Latest local risk score.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        RiskScoreDial(
                            score: currentRiskScore,
                            title: riskTitle,
                            subtitle: riskSubtitle
                        )
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

                    VStack(alignment: .leading, spacing: 14) {
                        Label("Questionnaire", systemImage: "checklist")
                            .font(.headline)

                        BaselineQuestionRow(
                            title: "Family history",
                            detail: "RLS reported or diagnosed in close family members.",
                            value: $store.form.familyHistoryRLS
                        )
                        BaselineQuestionRow(
                            title: "Diabetes",
                            detail: "Diabetes is part of your known medical history.",
                            value: $store.form.diabetes
                        )
                        BaselineQuestionRow(
                            title: "Psychiatric medication",
                            detail: "Current or recent psychiatric medication use.",
                            value: $store.form.psychiatricMedication
                        )
                        BaselineQuestionRow(
                            title: "Non-leg symptoms",
                            detail: "Symptoms involve body areas beyond the legs.",
                            value: $store.form.nonLegSymptoms
                        )
                    }
                    .panelStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Health Data", systemImage: "heart.text.square")
                            .font(.headline)
                        Text("The app reads sleep sessions, sleep stages, oxygen, heart rate, age, sex, height, and weight when available. Data stays on this device for local screening.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button {
                            Task {
                                await store.buildBaselineScreening()
                            }
                        } label: {
                            HStack {
                                Label("Import Health & Build Baseline", systemImage: "arrow.down.heart")
                                Spacer()
                                if store.isBuildingBaseline {
                                    ProgressView()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(RestlegTheme.green)
                        .controlSize(.large)
                        .disabled(store.isBuildingBaseline)
                    }
                    .panelStyle()

                    if let message = store.healthImportMessage {
                        Text(message)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let error = store.errorMessage {
                        Text(error)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                    }

                    Text("Screening only. This app does not diagnose RLS or determine whether you have RLS.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .restlegBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var currentRiskScore: Double? {
        store.latestTier2?.riskScore ?? store.baselineResult?.typicalScore
    }

    private var riskTitle: String {
        guard let score = currentRiskScore else {
            return "Risk"
        }
        return RiskLevel(score: score).title
    }

    private var riskSubtitle: String {
        currentRiskScore == nil ? "Baseline needed" : "Latest score"
    }
}

private struct RiskScoreDial: View {
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
                Text(score.map { $0.formatted(.number.precision(.fractionLength(2))) } ?? "--")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
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

private struct BaselineQuestionRow: View {
    let title: String
    let detail: String
    @Binding var value: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker(title, selection: selection) {
                Text("Select").tag(BaselineQuestionChoice.unanswered)
                Text("No").tag(BaselineQuestionChoice.no)
                Text("Yes").tag(BaselineQuestionChoice.yes)
            }
            .pickerStyle(.segmented)
        }
    }

    private var selection: Binding<BaselineQuestionChoice> {
        Binding(
            get: { BaselineQuestionChoice(value) },
            set: { value = $0.boolValue }
        )
    }
}

private enum BaselineQuestionChoice: Hashable {
    case unanswered
    case no
    case yes

    init(_ value: Bool?) {
        switch value {
        case true:
            self = .yes
        case false:
            self = .no
        case nil:
            self = .unanswered
        }
    }

    var boolValue: Bool? {
        switch self {
        case .unanswered:
            return nil
        case .no:
            return false
        case .yes:
            return true
        }
    }
}
