import SwiftUI

enum Field: Hashable {
    case sleepDuration
    case sleepEfficiency
    case waso
    case sleepLatency
    case remLatency
    case awakeStage
    case averageSpO2
    case minimumSpO2
    case lightSleepMinutes
    case lightSleepPercent
    case deepSleepMinutes
    case deepSleepPercent
    case remSleepMinutes
    case remSleepPercent
    case restingHeartRate
    case meanHeartRate
    case age
    case height
    case weight
}

struct InputSectionView: View {
    @Binding var form: ScreeningForm
    var focusedField: FocusState<Field?>.Binding

    var body: some View {
        VStack(spacing: 16) {
            GroupBox("Wearable Signals") {
                VStack(spacing: 12) {
                    NumberField(
                        title: "Sleep duration",
                        unit: "min",
                        help: "Total time asleep in the latest major sleep session.",
                        value: $form.sleepDurationMinutes,
                        field: .sleepDuration,
                        focusedField: focusedField
                    )
                    NumberField(
                        title: "Sleep efficiency",
                        unit: "%",
                        help: "Percent of the sleep window spent asleep.",
                        value: $form.sleepEfficiency,
                        field: .sleepEfficiency,
                        focusedField: focusedField
                    )
                    NumberField(
                        title: "Resting heart rate",
                        unit: "bpm",
                        help: "Most recent resting heart rate available from Health.",
                        value: $form.restingHeartRate,
                        field: .restingHeartRate,
                        focusedField: focusedField
                    )
                    NumberField(
                        title: "Mean heart rate",
                        unit: "bpm",
                        help: "Average heart rate over the recent wearable window.",
                        value: $form.meanHeartRate,
                        field: .meanHeartRate,
                        focusedField: focusedField
                    )
                }
            }

            GroupBox("Sleep Architecture") {
                VStack(spacing: 12) {
                    OptionalNumberField(
                        title: "WASO",
                        unit: "min",
                        help: "Wake time after sleep onset, computed between first sleep and final sleep.",
                        value: $form.wasoMinutes,
                        field: .waso,
                        focusedField: focusedField
                    )
                    OptionalNumberField(
                        title: "Sleep latency",
                        unit: "min",
                        help: "Minutes from the start of the sleep session to first asleep sample.",
                        value: $form.sleepLatencyMinutes,
                        field: .sleepLatency,
                        focusedField: focusedField
                    )
                    OptionalNumberField(
                        title: "REM latency",
                        unit: "min",
                        help: "Minutes from first asleep sample to first REM sample.",
                        value: $form.remLatencyMinutes,
                        field: .remLatency,
                        focusedField: focusedField
                    )
                    OptionalNumberField(
                        title: "Awake stage",
                        unit: "min",
                        help: "Time explicitly marked awake inside the sleep session.",
                        value: $form.awakeStageMinutes,
                        field: .awakeStage,
                        focusedField: focusedField
                    )
                    OptionalNumberField(
                        title: "Average SpO2",
                        unit: "%",
                        help: "Average oxygen saturation during the sleep session when Health has blood oxygen samples.",
                        value: $form.averageSpO2,
                        field: .averageSpO2,
                        focusedField: focusedField
                    )
                    OptionalNumberField(
                        title: "Minimum SpO2",
                        unit: "%",
                        help: "Lowest oxygen saturation during the sleep session when Health has blood oxygen samples.",
                        value: $form.minimumSpO2,
                        field: .minimumSpO2,
                        focusedField: focusedField
                    )
                    OptionalNumberField(
                        title: "Core/N1N2",
                        unit: "min",
                        help: "Apple Core or unspecified sleep mapped to the model's N1N2 sleep feature.",
                        value: $form.lightSleepMinutes,
                        field: .lightSleepMinutes,
                        focusedField: focusedField
                    )
                    OptionalNumberField(
                        title: "Core/N1N2",
                        unit: "%",
                        help: "Share of total sleep spent in Apple Core or unspecified sleep.",
                        value: $form.lightSleepPercent,
                        field: .lightSleepPercent,
                        focusedField: focusedField
                    )
                    OptionalNumberField(
                        title: "Deep/N3",
                        unit: "min",
                        help: "Apple Deep sleep mapped to the model's N3 sleep feature.",
                        value: $form.deepSleepMinutes,
                        field: .deepSleepMinutes,
                        focusedField: focusedField
                    )
                    OptionalNumberField(
                        title: "Deep/N3",
                        unit: "%",
                        help: "Share of total sleep spent in Apple Deep sleep.",
                        value: $form.deepSleepPercent,
                        field: .deepSleepPercent,
                        focusedField: focusedField
                    )
                    OptionalNumberField(
                        title: "REM/R",
                        unit: "min",
                        help: "Apple REM sleep mapped to the model's R-stage feature.",
                        value: $form.remSleepMinutes,
                        field: .remSleepMinutes,
                        focusedField: focusedField
                    )
                    OptionalNumberField(
                        title: "REM/R",
                        unit: "%",
                        help: "Share of total sleep spent in Apple REM sleep.",
                        value: $form.remSleepPercent,
                        field: .remSleepPercent,
                        focusedField: focusedField
                    )
                }
            }

            GroupBox("Profile") {
                VStack(spacing: 12) {
                    Picker("Sex", selection: $form.sex) {
                        Text("Female").tag("female")
                        Text("Male").tag("male")
                    }
                    .pickerStyle(.segmented)

                    NumberField(
                        title: "Age",
                        unit: "yr",
                        help: "Age in years, imported from Health date of birth when available.",
                        value: $form.age,
                        field: .age,
                        focusedField: focusedField
                    )
                    NumberField(
                        title: "Height",
                        unit: "cm",
                        help: "Height used with weight to derive BMI for models that include body profile features.",
                        value: $form.heightCm,
                        field: .height,
                        focusedField: focusedField
                    )
                    NumberField(
                        title: "Weight",
                        unit: "kg",
                        help: "Weight used with height to derive BMI for models that include body profile features.",
                        value: $form.weightKg,
                        field: .weight,
                        focusedField: focusedField
                    )
                }
            }

            GroupBox("Questionnaire") {
                VStack(spacing: 8) {
                    TernaryQuestionRow(
                        title: "Family history",
                        help: "Whether RLS has been reported or diagnosed in close family members.",
                        value: $form.familyHistoryRLS
                    )
                    TernaryQuestionRow(
                        title: "Diabetes",
                        help: "Whether diabetes is part of the user's known medical history.",
                        value: $form.diabetes
                    )
                    TernaryQuestionRow(
                        title: "Psychiatric medication",
                        help: "Whether psychiatric medication use is present, as represented in the experiment feature set.",
                        value: $form.psychiatricMedication
                    )
                    TernaryQuestionRow(
                        title: "Non-leg symptoms",
                        help: "Whether symptoms involve body areas beyond the legs.",
                        value: $form.nonLegSymptoms
                    )
                }
            }
        }
    }
}

private struct NumberField: View {
    let title: String
    let unit: String
    let help: String
    @Binding var value: Double
    let field: Field
    var focusedField: FocusState<Field?>.Binding

    var body: some View {
        HStack {
            FieldTitle(title: title, help: help)
            Spacer()
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused(focusedField, equals: field)
                .frame(width: 88)
                .textFieldStyle(.roundedBorder)
            Text(unit)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }
}

private struct OptionalNumberField: View {
    let title: String
    let unit: String
    let help: String
    @Binding var value: Double?
    let field: Field
    var focusedField: FocusState<Field?>.Binding

    var body: some View {
        HStack {
            FieldTitle(title: title, help: help)
            Spacer()
            TextField("Missing", text: textBinding)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused(focusedField, equals: field)
                .frame(width: 88)
                .textFieldStyle(.roundedBorder)
            Text(unit)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: {
                guard let value else {
                    return ""
                }
                return value.formatted(.number.precision(.fractionLength(0...1)))
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                value = trimmed.isEmpty ? nil : Double(trimmed)
            }
        )
    }
}

private struct TernaryQuestionRow: View {
    let title: String
    let help: String
    @Binding var value: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldTitle(title: title, help: help)
            Picker(title, selection: selection) {
                Text("Unknown").tag(QuestionnaireChoice.unknown)
                Text("No").tag(QuestionnaireChoice.no)
                Text("Yes").tag(QuestionnaireChoice.yes)
            }
            .pickerStyle(.segmented)
        }
    }

    private var selection: Binding<QuestionnaireChoice> {
        Binding(
            get: { QuestionnaireChoice(value) },
            set: { value = $0.boolValue }
        )
    }
}

private enum QuestionnaireChoice: Hashable {
    case unknown
    case no
    case yes

    init(_ value: Bool?) {
        switch value {
        case true:
            self = .yes
        case false:
            self = .no
        case nil:
            self = .unknown
        }
    }

    var boolValue: Bool? {
        switch self {
        case .unknown:
            return nil
        case .no:
            return false
        case .yes:
            return true
        }
    }
}

private struct FieldTitle: View {
    let title: String
    let help: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            FeatureHelpButton(title: title, message: help)
        }
    }
}

private struct FeatureHelpButton: View {
    let title: String
    let message: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) details")
        .alert(title, isPresented: $isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}
