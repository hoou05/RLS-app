import SwiftUI

enum Field: Hashable {
    case sleepDuration
    case sleepEfficiency
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
                        value: $form.sleepDurationMinutes,
                        field: .sleepDuration,
                        focusedField: focusedField
                    )
                    NumberField(
                        title: "Sleep efficiency",
                        unit: "%",
                        value: $form.sleepEfficiency,
                        field: .sleepEfficiency,
                        focusedField: focusedField
                    )
                    NumberField(
                        title: "Resting heart rate",
                        unit: "bpm",
                        value: $form.restingHeartRate,
                        field: .restingHeartRate,
                        focusedField: focusedField
                    )
                    NumberField(
                        title: "Mean heart rate",
                        unit: "bpm",
                        value: $form.meanHeartRate,
                        field: .meanHeartRate,
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

                    NumberField(title: "Age", unit: "yr", value: $form.age, field: .age, focusedField: focusedField)
                    NumberField(title: "Height", unit: "cm", value: $form.heightCm, field: .height, focusedField: focusedField)
                    NumberField(title: "Weight", unit: "kg", value: $form.weightKg, field: .weight, focusedField: focusedField)
                }
            }

            GroupBox("Questionnaire") {
                VStack(spacing: 8) {
                    Toggle("Family history", isOn: $form.familyHistoryRLS)
                    Toggle("Diabetes", isOn: $form.diabetes)
                    Toggle("Psychiatric medication", isOn: $form.psychiatricMedication)
                    Toggle("Non-leg symptoms", isOn: $form.nonLegSymptoms)
                }
            }
        }
    }
}

private struct NumberField: View {
    let title: String
    let unit: String
    @Binding var value: Double
    let field: Field
    var focusedField: FocusState<Field?>.Binding

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
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

