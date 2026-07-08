import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: ScreeningStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image("RestlegLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 190, alignment: .leading)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("Build Your Baseline")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(RestlegTheme.ink)
                        Text("Complete the questionnaire, then import Health sleep data. Restleg will run the model on up to 60 recent sleep sessions and summarize the typical screening pattern.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

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
                        .disabled(!store.form.isQuestionnaireComplete || store.isBuildingBaseline)
                    }
                    .panelStyle()

                    if !store.form.isQuestionnaireComplete {
                        Label("Answer all questionnaire items to continue.", systemImage: "info.circle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

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
            .navigationTitle("Restleg")
        }
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
