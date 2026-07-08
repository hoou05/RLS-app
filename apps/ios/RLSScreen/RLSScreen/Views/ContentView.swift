import Foundation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: ScreeningStore
    @State private var isAgentPresented = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            TabView {
                if store.hasCompletedOnboarding {
                    ScreeningView()
                        .tabItem {
                            Label("Screen", systemImage: "waveform.path.ecg")
                        }
                } else {
                    OnboardingView()
                        .tabItem {
                            Label("Baseline", systemImage: "checklist")
                        }
                }

                SleepHubView()
                    .tabItem {
                        Label("Sleep", systemImage: "chart.line.uptrend.xyaxis")
                    }
            }
            .tint(RestlegTheme.green)

            FloatingAgentButton {
                isAgentPresented = true
            }
        }
        .sheet(isPresented: $isAgentPresented) {
            AgentView()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private enum SleepHubSection: String, Hashable {
    case trends = "Trends"
    case history = "History"
}

private struct SleepHubView: View {
    @State private var section = SleepHubSection.trends

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Sleep view", selection: $section) {
                    Text("Trends").tag(SleepHubSection.trends)
                    Text("History").tag(SleepHubSection.history)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

                Group {
                    if section == .trends {
                        SleepAnalysisView()
                    } else {
                        HistoryView()
                    }
                }
            }
            .restlegBackground()
            .navigationTitle("Sleep")
        }
    }
}

private struct FloatingAgentButton: View {
    @AppStorage("agentButtonX") private var storedX = 0.0
    @AppStorage("agentButtonY") private var storedY = 0.0

    let action: () -> Void

    @State private var position: CGPoint?
    @State private var dragStart: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let buttonSize: CGFloat = 58
            let safeTop = proxy.safeAreaInsets.top + 18
            let safeBottom = proxy.size.height - proxy.safeAreaInsets.bottom - 88
            let safeLeft: CGFloat = 16
            let safeRight = proxy.size.width - buttonSize - 16
            let defaultPosition = CGPoint(x: safeRight, y: safeTop)
            let current = resolvedPosition(defaultPosition: defaultPosition, minX: safeLeft, maxX: safeRight, minY: safeTop, maxY: safeBottom)

            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [RestlegTheme.teal, RestlegTheme.ink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)

                    Image(systemName: "message.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(RestlegTheme.sky.opacity(0.36), in: Circle())
                        .offset(x: 13, y: -13)

                    Circle()
                        .fill(RestlegTheme.mint)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.86), lineWidth: 2)
                        )
                        .offset(x: 17, y: -2)
                }
                .frame(width: buttonSize, height: buttonSize)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 8)
                .accessibilityLabel("Open sleep agent")
            }
            .buttonStyle(.plain)
            .position(x: current.x + buttonSize / 2, y: current.y + buttonSize / 2)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if dragStart == nil {
                            dragStart = current
                        }
                        let origin = dragStart ?? current
                        position = CGPoint(
                            x: clamp(origin.x + value.translation.width, safeLeft, safeRight),
                            y: clamp(origin.y + value.translation.height, safeTop, safeBottom)
                        )
                    }
                    .onEnded { _ in
                        let final = position ?? current
                        storedX = final.x
                        storedY = final.y
                        dragStart = nil
                    }
            )
        }
        .ignoresSafeArea(.keyboard)
    }

    private func resolvedPosition(defaultPosition: CGPoint, minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) -> CGPoint {
        if let position {
            return CGPoint(x: clamp(position.x, minX, maxX), y: clamp(position.y, minY, maxY))
        }
        if storedX > 0 || storedY > 0 {
            return CGPoint(x: clamp(storedX, minX, maxX), y: clamp(storedY, minY, maxY))
        }
        return defaultPosition
    }

    private func clamp(_ value: CGFloat, _ minimum: CGFloat, _ maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}

#Preview {
    ContentView()
        .environmentObject(ScreeningStore())
}

struct AgentView: View {
    @EnvironmentObject private var store: ScreeningStore
    @AppStorage("agentBaseURL") private var baseURL = "http://127.0.0.1:8000"
    @AppStorage("agentBearerToken") private var bearerToken = ""
    @AppStorage("agentEmail") private var email = "demo@example.com"
    @AppStorage("agentAllowExternalModel") private var allowExternalModel = false
    @AppStorage("agentUseBackend") private var useBackend = false

    @State private var password = "password123"
    @State private var question = "I am very nervous and cannot fall asleep these days, what's wrong with me?"
    @State private var selectedMode = SleepAgentMode.question
    @State private var response: SleepAgentResponse?
    @State private var isAsking = false
    @State private var isLoggingIn = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        requestPanel

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let response {
                            AgentResponseView(response: response)
                                .id("agent-response")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: response?.answer) {
                    guard response != nil else { return }
                    withAnimation(.snappy) {
                        reader.scrollTo("agent-response", anchor: .top)
                    }
                }
            }
            .restlegBackground()
            .navigationTitle("Ask or analyze")
        }
    }

    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Agent source", systemImage: "cpu")
                .font(.headline)
            Picker("Agent source", selection: $useBackend) {
                Text("On device").tag(false)
                Text("Backend debug").tag(true)
            }
            .pickerStyle(.segmented)
            Text(useBackend ? "Backend mode is for development. Keep DeepSeek disabled unless you are intentionally testing the structured explanation layer." : "Default mode runs locally in the app. It does not call FastAPI or send Health data off device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private var connectionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Backend connection", systemImage: "server.rack")
                .font(.headline)
            TextField("API base URL", text: $baseURL)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Button {
                Task {
                    await login()
                }
            } label: {
                HStack {
                    Label("Login to backend", systemImage: "person.crop.circle.badge.checkmark")
                    Spacer()
                    if isLoggingIn {
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isLoggingIn || email.isEmpty || password.isEmpty)
            SecureField("Bearer token from /auth/login", text: $bearerToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Toggle("Allow optional DeepSeek explanation layer", isOn: $allowExternalModel)
            Text("Default provider remains the local safety agent. Enable the external layer only for intentional debugging with appropriate privacy controls.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private var requestPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        LinearGradient(colors: [RestlegTheme.teal, RestlegTheme.navy], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask or analyze")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(RestlegTheme.ink)
                    Text("Trends, sleep trouble, RLS symptoms, and safe next steps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Picker("Mode", selection: $selectedMode) {
                Text("Question").tag(SleepAgentMode.question)
                Text("Trend").tag(SleepAgentMode.trend)
                Text("Guide").tag(SleepAgentMode.guide)
            }
            .pickerStyle(.segmented)

            TextEditor(text: $question)
                .frame(minHeight: 110)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(RestlegTheme.panelTint, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(RestlegTheme.border.opacity(0.9))
                )

            HStack {
                Button {
                    Task {
                        await askAgent()
                    }
                } label: {
                    Label(buttonTitle, systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(RestlegTheme.navy)
                .controlSize(.large)
                .disabled(isAsking)

                if isAsking {
                    ProgressView()
                }
            }

            Text("Restleg can organize patterns and next questions. It does not diagnose or prescribe treatment.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .panelStyle()
    }

    private var buttonTitle: String {
        switch selectedMode {
        case .question:
            return isAsking ? "Asking..." : "Ask agent"
        case .trend:
            return isAsking ? "Analyzing..." : "Analyze trend"
        case .guide:
            return isAsking ? "Building guide..." : "Get guide"
        }
    }

    private func askAgent() async {
        errorMessage = nil
        isAsking = true
        defer { isAsking = false }

        print("Restleg local agent request mode=\(selectedMode.rawValue) question=\(question)")
        response = LocalSleepAgent.buildResponse(
            mode: selectedMode,
            question: selectedMode == .question ? question : nil,
            form: store.form,
            history: store.history,
            baseline: store.baselineResult
        )
    }

    private func login() async {
        errorMessage = nil
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            let client = SleepAgentClient(baseURL: baseURL, bearerToken: bearerToken)
            bearerToken = try await client.login(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AgentResponseView: View {
    let response: SleepAgentResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sections = response.answerSections {
                AnswerCard(
                    title: "Answers",
                    systemImage: "text.bubble",
                    items: [
                        ("Trend", sections.trendObservation),
                        ("What this may mean", sections.interpretation),
                    ]
                )
                AdviceCard(sections: sections)
            } else {
                AnswerCard(title: "Answers", systemImage: "text.bubble", items: [("Response", response.answer)])
            }
        }
    }
}

private struct AnswerCard: View {
    let title: String
    let systemImage: String
    let items: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(RestlegTheme.ink)
            ForEach(items, id: \.0) { label, text in
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(RestlegTheme.blue)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .panelStyle()
    }
}

private struct AdviceCard: View {
    let sections: AgentAnswerSections

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Guidance / Advice", systemImage: "checklist")
                .font(.headline)
                .foregroundStyle(RestlegTheme.ink)
            ForEach(sections.lowRiskSuggestions, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !sections.followUpQuestions.isEmpty {
                Divider()
                Text("Questions to consider")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RestlegTheme.blue)
                ForEach(sections.followUpQuestions, id: \.self) { item in
                    Label(item, systemImage: "questionmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(sections.careBoundary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .panelStyle()
    }
}

private struct AgentListSection: View {
    let title: String
    let items: [String]
    let empty: String

    var body: some View {
        DisclosureGroup(title) {
            VStack(alignment: .leading, spacing: 8) {
                if items.isEmpty {
                    Text(empty)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle")
                            .font(.footnote)
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

private enum LocalSleepAgent {
    static func buildResponse(
        mode: SleepAgentMode,
        question: String?,
        form: ScreeningForm,
        history: [ScreeningRecord],
        baseline: BaselineScreeningResult?
    ) -> SleepAgentResponse {
        let normalized = (question ?? "").lowercased()
        let topic = routeTopic(question: normalized, form: form, history: history)
        let redFlags = detectRedFlags(question: normalized, form: form)
        let forbidden = isForbidden(question: normalized)
        let followUps = topic == "rls" ? rlsFollowUps(question: normalized) : []
        let analysis = SleepTrendAnalysis(records: history)
        let sections = answerSections(
            topic: topic,
            mode: mode,
            question: question,
            analysis: analysis,
            form: form,
            baseline: baseline,
            redFlags: redFlags,
            forbidden: forbidden,
            followUps: followUps
        )
        let prescription = educationPrescription(topic: topic, sections: sections, followUps: followUps, baseline: baseline)
        let answer = [
            "Trend observation: \(sections.trendObservation)",
            "What it may mean: \(sections.interpretation)",
            "Low-risk next steps: \(sections.lowRiskSuggestions.joined(separator: " "))",
            "Follow-up questions: \(sections.followUpQuestions.joined(separator: " "))",
            "Care boundary: \(sections.careBoundary)",
        ].joined(separator: "\n\n")

        return SleepAgentResponse(
            mode: mode,
            provider: "on-device-safety-agent",
            plannerProvider: "local-ios-planner",
            hitlRequired: !redFlags.isEmpty || forbidden,
            answer: answer,
            answerSections: sections,
            educationPrescription: prescription,
            rlsFollowUpQuestions: followUps,
            plan: AgentPlan(
                intent: forbidden ? "referral_escalation" : mode.intentName(topic: topic),
                rationale: "The iOS planner routes by question topic, current screening form, local history, red flags, and safety boundary rules.",
                toolSequence: ["analyze_local_sleep_trends", "screen_rls_features", "ask_rls_followup_questions", "build_education_prescription", "enforce_guardrails"],
                hitlRequired: !redFlags.isEmpty || forbidden,
                topic: topic
            ),
            toolTrace: [
                ToolExecution(toolName: "analyze_local_sleep_trends", status: "completed", summary: "\(history.count) local screening records reviewed."),
                ToolExecution(toolName: "screen_rls_features", status: "completed", summary: "Current questionnaire and question text reviewed for RLS-style educational features."),
                ToolExecution(toolName: "enforce_guardrails", status: "completed", summary: "Medication, diagnosis, device setting, and emergency boundaries applied."),
            ],
            guidePoints: sections.lowRiskSuggestions,
            safetyLimits: safetyLimits,
            escalationSignals: escalationSignals,
            dataUsed: dataUsed(history: history, baseline: baseline, form: form),
            redFlags: redFlags,
            rlsScreening: topic == "rls" ? rlsScreening(question: normalized, form: form) : nil,
            knowledgeSources: [
                "On-device sleep guidance boundary summary",
                "RLS five-feature screening summary",
                "General sleep, insomnia, and sleep-breathing guide summaries",
                "Local sleep trend and screening history",
            ],
            externalModelUsed: false,
            externalModelError: nil
        )
    }

    private static let safetyLimits = [
        "Restleg can help with trend review, symptom tracking, low-risk lifestyle suggestions, and notes for a clinician visit.",
        "Not allowed: diagnosis, medication choice or dose, iron treatment instructions, CPAP/device settings, or device purchase decisions.",
        "Clinician review is recommended for severe impairment, breathing pauses, chest pain, drowsy driving, pregnancy, childhood symptoms, anemia, kidney disease, neurologic symptoms, or medication/device questions.",
    ]

    private static let escalationSignals = [
        "Drowsy driving, chest pain, choking awakenings, or witnessed breathing pauses.",
        "Pregnancy, childhood symptoms, anemia or ferritin concerns, kidney disease, neuropathy, or medication-related questions.",
        "Rapid worsening, spreading symptoms, persistent sleep disruption, or major daytime functional impairment.",
    ]

    private static func routeTopic(question: String, form: ScreeningForm, history: [ScreeningRecord]) -> String {
        if question.contains("rls") || question.contains("restleg") || question.contains("restless") || question.contains("leg") || question.contains("腿") || question.contains("不宁腿") {
            return "rls"
        }
        if question.contains("snore") || question.contains("apnea") || question.contains("breathing") || question.contains("打鼾") || question.contains("呼吸") || question.contains("憋醒") {
            return "osa"
        }
        if question.contains("insomnia")
            || question.contains("fall asleep")
            || question.contains("cannot sleep")
            || question.contains("can't sleep")
            || question.contains("nervous")
            || question.contains("anxious")
            || question.contains("anxiety")
            || question.contains("stress")
            || question.contains("wake")
            || question.contains("失眠")
            || question.contains("睡不着")
            || question.contains("紧张")
            || question.contains("焦虑")
            || question.contains("压力")
            || question.contains("入睡") {
            return "insomnia"
        }
        if form.nonLegSymptoms == false || history.contains(where: { RiskLevel(score: $0.riskScore) == .high }) {
            return "rls"
        }
        return "general"
    }

    private static func detectRedFlags(question: String, form: ScreeningForm) -> [String] {
        var flags: [String] = []
        if question.contains("driving") || question.contains("开车") {
            flags.append("Drowsy driving or safety-critical sleepiness")
        }
        if question.contains("chest pain") || question.contains("胸痛") {
            flags.append("Chest pain")
        }
        if question.contains("stop breathing") || question.contains("choking") || question.contains("憋醒") || question.contains("呼吸暂停") {
            flags.append("Possible sleep-breathing warning sign")
        }
        if question.contains("pregnant") || question.contains("怀孕") {
            flags.append("Pregnancy-related symptoms")
        }
        if question.contains("child") || question.contains("儿童") || question.contains("孩子") {
            flags.append("Childhood symptoms")
        }
        if form.minimumSpO2.map({ $0 < 88 }) == true {
            flags.append("Low overnight oxygen value in local form")
        }
        return flags
    }

    private static func isForbidden(question: String) -> Bool {
        let forbiddenTerms = [
            "dose", "dosage", "gabapentin", "pregabalin", "dopamine", "iron supplement", "ferritin", "cpap pressure",
            "prescribe", "diagnose me", "treatment plan", "stop my medication", "buy a device",
            "剂量", "吃多少", "加药", "停药", "补铁", "呼吸机参数", "直接诊断", "治疗方案",
        ]
        return forbiddenTerms.contains { question.contains($0) }
    }

    private static func answerSections(
        topic: String,
        mode: SleepAgentMode,
        question: String?,
        analysis: SleepTrendAnalysis,
        form: ScreeningForm,
        baseline: BaselineScreeningResult?,
        redFlags: [String],
        forbidden: Bool,
        followUps: [RLSFollowUpQuestion]
    ) -> AgentAnswerSections {
        if forbidden {
            return AgentAnswerSections(
                trendObservation: trendObservation(analysis: analysis, baseline: baseline, form: form),
                interpretation: "This is a treatment-level question, so Restleg should not make that decision for you.",
                lowRiskSuggestions: [
                    "Write down symptom timing, triggers, sleep disruption, current medications/supplements, and recent Health data to discuss with a clinician.",
                    "Do not change medication, iron treatment, CPAP settings, or treatment devices based on this app.",
                ],
                followUpQuestions: topic == "rls" ? followUps.map(\.question) : ["What symptom is most disruptive, how often does it occur, and does it affect daytime function?"],
                careBoundary: "For medication, iron, diagnosis, breathing-device settings, pregnancy, childhood symptoms, or severe impairment, please contact a licensed clinician or sleep specialist."
            )
        }

        return AgentAnswerSections(
            trendObservation: trendObservation(mode: mode, analysis: analysis, baseline: baseline, form: form),
            interpretation: interpretation(mode: mode, topic: topic, form: form, analysis: analysis),
            lowRiskSuggestions: lowRiskSuggestions(mode: mode, topic: topic, analysis: analysis),
            followUpQuestions: followUpQuestions(mode: mode, topic: topic, rlsFollowUps: followUps),
            careBoundary: careBoundary(redFlags: redFlags)
        )
    }

    private static func trendObservation(mode: SleepAgentMode, analysis: SleepTrendAnalysis, baseline: BaselineScreeningResult?, form: ScreeningForm) -> String {
        let base = trendObservation(analysis: analysis, baseline: baseline, form: form)
        switch mode {
        case .question:
            return "\(base) I am using this only as background context for your question, not as proof of a diagnosis."
        case .trend:
            return trendFocusedObservation(analysis: analysis, baseline: baseline, form: form)
        case .guide:
            return "\(base) The guide below is built around low-risk sleep habits and tracking steps that are reasonable even when the exact cause is unclear."
        }
    }

    private static func trendObservation(analysis: SleepTrendAnalysis, baseline: BaselineScreeningResult?, form: ScreeningForm) -> String {
        if let avg = analysis.averageSleepDurationMinutes {
            let efficiency = analysis.averageSleepEfficiency.map { ", average sleep efficiency \($0.formatted(.number.precision(.fractionLength(0))))%" } ?? ""
            return "Recent local records average \(SleepTrendAnalysis.formatDuration(minutes: avg)) of sleep\(efficiency). Short-sleep nights: \(analysis.shortSleepNightCount); low-efficiency nights: \(analysis.lowEfficiencyNightCount)."
        }
        if let duration = form.sleepDurationMinutes {
            return "No multi-night trend is available yet. The current form shows \(SleepTrendAnalysis.formatDuration(minutes: duration)) of sleep\(form.sleepEfficiency.map { " and \($0.formatted(.number.precision(.fractionLength(0))))% efficiency" } ?? "")."
        }
        if let baseline {
            return "A baseline exists with \(baseline.validNightCount) usable nights, but recent sleep-duration trend values are limited."
        }
        return "No local sleep trend is available yet. Import Health sleep data or complete screenings after sleep sessions to build a baseline."
    }

    private static func trendFocusedObservation(analysis: SleepTrendAnalysis, baseline: BaselineScreeningResult?, form: ScreeningForm) -> String {
        var parts: [String] = []
        if let avg = analysis.averageSleepDurationMinutes {
            parts.append("Across recent local records, average sleep is \(SleepTrendAnalysis.formatDuration(minutes: avg)).")
        } else {
            parts.append("The app does not yet have enough saved sleep-duration records for a stable multi-night trend.")
        }
        if let efficiency = analysis.averageSleepEfficiency {
            parts.append("Average sleep efficiency is \(efficiency.formatted(.number.precision(.fractionLength(0))))%.")
        }
        if let change = analysis.sleepDurationChangeMinutes {
            parts.append("Compared with earlier records, sleep duration changed by \(SleepTrendAnalysis.formatSignedMinutes(change)).")
        }
        if analysis.shortSleepNightCount > 0 {
            parts.append("\(analysis.shortSleepNightCount) recent night(s) were short-sleep nights.")
        }
        if analysis.lowEfficiencyNightCount > 0 {
            parts.append("\(analysis.lowEfficiencyNightCount) recent night(s) had lower efficiency.")
        }
        if let baseline {
            parts.append("Your local baseline currently includes \(baseline.validNightCount) usable night(s).")
        } else if form.sleepDurationMinutes == nil {
            parts.append("More Health sleep data will make the trend more useful.")
        }
        return parts.joined(separator: " ")
    }

    private static func interpretation(mode: SleepAgentMode, topic: String, form: ScreeningForm, analysis: SleepTrendAnalysis) -> String {
        switch mode {
        case .question:
            return questionInterpretation(topic: topic, form: form, analysis: analysis)
        case .trend:
            return trendInterpretation(topic: topic, analysis: analysis)
        case .guide:
            return guideInterpretation(topic: topic)
        }
    }

    private static func questionInterpretation(topic: String, form: ScreeningForm, analysis: SleepTrendAnalysis) -> String {
        switch topic {
        case "rls":
            return "This could fit an RLS-like pattern if the sensation includes an urge to move, gets worse during rest, improves with movement, is stronger in the evening or night, and is not better explained by cramps, numbness, swelling, joint pain, or medication effects. Restleg cannot confirm a diagnosis."
        case "osa":
            return "Snoring or sleepiness alone does not diagnose obstructive sleep apnea. Breathing pauses, choking awakenings, morning headaches, low oxygen values, or strong daytime sleepiness are reasons to prepare notes for clinical review."
        case "insomnia":
            return "Feeling nervous or stressed can make it harder to fall asleep by keeping the body alert. That does not mean something is seriously wrong, but if this is new, persistent, or affecting daytime function, it is worth tracking the pattern and considering professional support."
        default:
            return "Restleg can explain sleep trends and suggest low-risk tracking steps, while avoiding diagnosis or treatment decisions."
        }
    }

    private static func trendInterpretation(topic: String, analysis: SleepTrendAnalysis) -> String {
        var message = "Trend mode looks for repeated patterns rather than answering a single symptom question."
        if analysis.shortSleepNightCount > 0 || analysis.lowEfficiencyNightCount > 0 {
            message += " Recent records show sleep quantity or efficiency nights worth watching, so compare those nights with symptoms, stress, caffeine/alcohol timing, activity, and daytime function."
        } else {
            message += " If the chart looks stable, the next useful step is to keep collecting data and mark symptom days so pattern links become clearer."
        }
        if topic == "rls" {
            message += " For leg symptoms, the trend is most useful when paired with evening/rest timing and movement-relief notes."
        }
        return message
    }

    private static func guideInterpretation(topic: String) -> String {
        switch topic {
        case "rls":
            return "Guide mode focuses on practical tracking and comfort-support steps for RLS-style leg discomfort while keeping treatment decisions with a clinician."
        case "osa":
            return "Guide mode focuses on recording sleep-breathing warning signs and knowing when formal evaluation is appropriate; it does not screen by device purchase or settings."
        case "insomnia":
            return "Guide mode focuses on calming the sleep window, strengthening regular sleep cues, and avoiding self-medication decisions."
        default:
            return "Guide mode gives a broad sleep-health routine and tracking checklist that stays low-risk and non-diagnostic."
        }
    }

    private static func lowRiskSuggestions(mode: SleepAgentMode, topic: String, analysis: SleepTrendAnalysis) -> [String] {
        switch mode {
        case .question:
            return questionSuggestions(topic: topic, analysis: analysis)
        case .trend:
            return trendSuggestions(topic: topic, analysis: analysis)
        case .guide:
            return guideSuggestions(topic: topic, analysis: analysis)
        }
    }

    private static func questionSuggestions(topic: String, analysis: SleepTrendAnalysis) -> [String] {
        var items = [
            "For the next few nights, write down when the problem starts, what was happening beforehand, and how it affects the next day.",
            "Keep the response low-risk tonight: reduce stimulation, avoid clock-watching, and use a quiet reset if you are awake and tense.",
        ]
        if topic == "rls" {
            items.append("For leg discomfort, note whether there is an urge to move, whether rest makes it worse, whether movement helps, and whether it is stronger in the evening or night.")
        }
        if topic == "osa" {
            items.append("For snoring or breathing concerns, record witnessed pauses, choking awakenings, morning headaches, and daytime sleepiness.")
        }
        if topic == "insomnia" {
            items.append("If worry is driving the problem, move planning out of bed by writing a short next-day list earlier in the evening.")
        }
        if analysis.shortSleepNightCount > 0 {
            items.append("Because recent short-sleep nights appear in local records, compare symptoms and daytime function on shorter versus longer nights.")
        }
        return items
    }

    private static func trendSuggestions(topic: String, analysis: SleepTrendAnalysis) -> [String] {
        var items = [
            "Collect at least 1-2 weeks of sleep sessions before treating a single night as meaningful.",
            "Tag nights with stress, caffeine/alcohol timing, late meals, naps, exercise, leg discomfort, snoring, or awakenings so the trend has context.",
            "Compare short-sleep or low-efficiency nights with daytime sleepiness, mood, concentration, and symptom severity.",
        ]
        if analysis.bedTimeRangeMinutes.map({ $0 > 90 }) == true {
            items.append("Bedtime appears variable; try watching whether a more consistent wake time improves the pattern.")
        }
        if topic == "rls" {
            items.append("For RLS-style symptoms, track whether symptom nights cluster after long sitting, evening rest, poor sleep, or schedule disruption.")
        }
        return items
    }

    private static func guideSuggestions(topic: String, analysis: SleepTrendAnalysis) -> [String] {
        var items = [
            "Keep a consistent wake time, then choose a realistic sleep window instead of forcing extra time in bed.",
            "Build a 30-60 minute wind-down routine with dim light, lower stimulation, and a repeatable cue that the day is ending.",
            "Keep the bedroom cool, dark, quiet, and comfortable; reserve the bed mainly for sleep and intimacy.",
            "Avoid late caffeine and heavy alcohol near bedtime; keep late meals and intense late exercise from crowding the sleep window when possible.",
        ]
        switch topic {
        case "rls":
            items.append("For leg discomfort, gentle stretching or a quiet walk may be reasonable comfort steps; avoid using the app to choose medicines or supplements.")
            items.append("Prepare a clinician note if symptoms are persistent, spreading, or disrupting sleep: timing, movement relief, evening pattern, current medicines, and possible mimics.")
        case "osa":
            items.append("If breathing symptoms are suspected, focus on documenting snoring, witnessed pauses, choking awakenings, oxygen values if available, and daytime sleepiness for clinical review.")
        case "insomnia":
            items.append("If you are awake and frustrated, step away from active problem-solving in bed and return when sleepy.")
            items.append("If insomnia lasts for weeks or affects daytime function, structured behavioral care such as CBT-I is a clinician-supported direction to ask about.")
        default:
            items.append("Review screens, work stress, naps, caffeine, alcohol, light exposure, and schedule regularity before assuming a sleep disorder.")
        }
        if analysis.shortSleepNightCount > 0 {
            items.append("Since short-sleep nights appear in local records, prioritize recovery consistency and watch whether daytime function improves.")
        }
        return items
    }

    private static func followUpQuestions(mode: SleepAgentMode, topic: String, rlsFollowUps: [RLSFollowUpQuestion]) -> [String] {
        switch mode {
        case .question:
            return topic == "rls" ? rlsFollowUps.map(\.question) : defaultFollowUps(topic: topic)
        case .trend:
            return trendFollowUps(topic: topic)
        case .guide:
            return guideFollowUps(topic: topic)
        }
    }

    private static func defaultFollowUps(topic: String) -> [String] {
        switch topic {
        case "osa":
            return ["Has anyone witnessed breathing pauses, choking awakenings, or loud snoring?", "Do you feel sleepy during driving, work, or daily activities?"]
        case "insomnia":
            return ["How many nights per week is this happening, and how long has it been going on?", "Is nervousness mainly before bed, during the day, or after waking at night?", "Are caffeine, alcohol, screens, naps, work stress, or late exercise making it worse?"]
        default:
            return ["What changed recently in schedule, stress, caffeine, alcohol, medications, activity, or sleep environment?", "Which symptom affects your daytime function the most?"]
        }
    }

    private static func trendFollowUps(topic: String) -> [String] {
        var questions = [
            "How many nights of Health sleep data are available, and are there obvious missing nights?",
            "Do the worst sleep nights line up with stress, caffeine, alcohol, naps, late meals, travel, or schedule changes?",
            "Do daytime sleepiness or concentration problems rise after the short-sleep nights?",
        ]
        if topic == "rls" {
            questions.append("Do leg-symptom nights cluster in the evening or after long periods of sitting still?")
        }
        return questions
    }

    private static func guideFollowUps(topic: String) -> [String] {
        switch topic {
        case "rls":
            return ["Which comfort step is easiest to try safely this week: symptom log, evening stretch, short walk, or schedule regularity?", "Are there medication, anemia/iron, kidney, pregnancy, or neurologic concerns that should be reviewed by a clinician?"]
        case "osa":
            return ["Has anyone observed pauses in breathing or choking awakenings?", "Is daytime sleepiness affecting driving, work, or safety?"]
        case "insomnia":
            return ["Which part is hardest right now: falling asleep, staying asleep, early waking, or worry before bed?", "Would a consistent wake time and earlier worry-list routine be realistic this week?"]
        default:
            return ["What is one sleep habit you can change for seven nights without risk?", "Which symptom or sleep metric should Restleg track most closely next?"]
        }
    }

    private static func careBoundary(redFlags: [String]) -> String {
        if redFlags.isEmpty {
            return "If symptoms persist, worsen, affect daytime function, involve breathing pauses, pregnancy/childhood symptoms, anemia/kidney/neurologic concerns, or medication/device questions, consider clinician or sleep-specialist review."
        }
        return "Because Restleg noticed \(redFlags.joined(separator: ", ")), use this app to organize notes and seek timely clinician or sleep-specialist review."
    }

    private static func rlsFollowUps(question: String) -> [RLSFollowUpQuestion] {
        let criteria: [(String, String, String, [String])] = [
            ("urge_to_move", "When the discomfort appears, do you feel a strong urge to move your legs, with or without unpleasant sensations?", "RLS screening starts by clarifying whether an urge to move is present, not only pain or numbness.", ["urge", "move", "想动", "动腿"]),
            ("worse_at_rest", "Does it begin or get worse when you are resting, sitting, or lying still?", "Symptoms provoked by rest fit the educational RLS pattern more than activity-only discomfort.", ["rest", "sitting", "lying", "休息", "躺"]),
            ("relieved_by_movement", "Does walking, stretching, or moving the legs partly or fully relieve the feeling while you keep moving?", "Temporary relief with movement is one of the core RLS screening features.", ["relief", "relieve", "walk", "stretch", "走动", "缓解"]),
            ("evening_or_night", "Is it clearly worse in the evening or at night than earlier in the day?", "An evening or night pattern helps separate RLS-style symptoms from several daytime discomfort patterns.", ["night", "evening", "晚上", "夜里"]),
            ("not_better_explained", "Could cramps, positional discomfort, swelling, neuropathy, joint pain, medication changes, or another condition explain it better?", "RLS should not be concluded when another explanation is more likely.", ["cramp", "neuropathy", "swelling", "joint", "抽筋", "麻", "肿"]),
        ]
        return criteria.map { criterion, prompt, reason, terms in
            RLSFollowUpQuestion(criterion: criterion, question: prompt, whyItMatters: reason, answered: terms.contains { question.contains($0) })
        }
    }

    private static func rlsScreening(question: String, form: ScreeningForm) -> RlsScreeningResult {
        var matched: [String] = []
        if question.contains("urge") || question.contains("move") || question.contains("想动") {
            matched.append("urge_to_move")
        }
        if question.contains("rest") || question.contains("lying") || question.contains("休息") || question.contains("躺") {
            matched.append("worse_at_rest")
        }
        if question.contains("walk") || question.contains("relief") || question.contains("缓解") || question.contains("走") {
            matched.append("relieved_by_movement")
        }
        if question.contains("night") || question.contains("evening") || question.contains("晚上") || question.contains("夜") {
            matched.append("evening_or_night")
        }
        if form.nonLegSymptoms == false {
            matched.append("leg_focused_symptoms")
        }
        let possible = matched.count >= 3
        return RlsScreeningResult(
            status: possible ? "possible_rls_pattern" : "needs_more_information",
            explanation: possible ? "Several RLS-style educational features are present, but this is not a diagnosis." : "More answers are needed before the app can describe whether the pattern is RLS-like.",
            matchedFeatures: matched,
            shouldSeekCare: possible
        )
    }

    private static func educationPrescription(
        topic: String,
        sections: AgentAnswerSections,
        followUps: [RLSFollowUpQuestion],
        baseline: BaselineScreeningResult?
    ) -> HealthEducationPrescription {
        HealthEducationPrescription(
            title: "Restleg sleep guidance",
            targetUser: "For the current app user; generated locally on device.",
            healthProblem: topicDisplay(topic),
            briefSummary: sections.interpretation,
            keySymptomsToTrack: symptomsToTrack(topic: topic),
            riskFactorsToReview: [
                "Short or irregular sleep schedule",
                "Daytime sleepiness or functional impairment",
                "Medication, supplement, pregnancy, anemia, kidney, neurologic, or breathing-related concerns",
            ],
            guidanceItems: sections.lowRiskSuggestions,
            otherGuidance: [
                baseline.map { "Baseline available: \($0.validNightCount) usable nights." } ?? "Build a local baseline from Health sleep data when available.",
                followUps.prefix(2).map(\.question).joined(separator: " "),
            ].filter { !$0.isEmpty },
            useInstructions: "Use together with symptom tracking and clinician discussion. This is not a medical prescription.",
            safetyScope: "Restleg supports trend review, symptom tracking, and next questions. It should not diagnose, recommend medication or supplement dosing, set CPAP/device parameters, or make device purchase decisions."
        )
    }

    private static func symptomsToTrack(topic: String) -> [String] {
        switch topic {
        case "rls":
            return ["Urge to move", "Worse at rest", "Relief with movement", "Evening or night worsening", "Possible mimics such as cramps, numbness, swelling, or joint pain"]
        case "osa":
            return ["Snoring", "Witnessed breathing pauses", "Choking awakenings", "Morning headache", "Daytime sleepiness"]
        case "insomnia":
            return ["Time to fall asleep", "Night awakenings", "Early waking", "Nervousness or worry level before bed", "Caffeine, alcohol, screen, stress, and nap timing"]
        default:
            return ["Sleep duration", "Sleep efficiency", "Bedtime and wake-time regularity", "Daytime sleepiness", "Symptoms affecting sleep"]
        }
    }

    private static func topicDisplay(_ topic: String) -> String {
        switch topic {
        case "rls": return "RLS-style leg discomfort"
        case "osa": return "Possible sleep-breathing warning signs"
        case "insomnia": return "Trouble falling asleep"
        default: return "General sleep trend"
        }
    }

    private static func dataUsed(history: [ScreeningRecord], baseline: BaselineScreeningResult?, form: ScreeningForm) -> [String] {
        var items = ["Current on-device questionnaire/form"]
        if !history.isEmpty {
            items.append("\(history.count) local screening records")
        }
        if let baseline {
            items.append("Local baseline with \(baseline.validNightCount) usable nights")
        }
        if form.sleepDurationMinutes != nil || form.sleepEfficiency != nil {
            items.append("Current sleep duration/efficiency fields")
        }
        return items
    }
}

private extension SleepAgentMode {
    func intentName(topic: String) -> String {
        switch self {
        case .trend:
            return "trend_analysis"
        case .guide:
            return "education_guidance"
        case .question:
            return topic == "general" ? "education_guidance" : "symptom_qa"
        }
    }
}

private final class SleepAgentClient {
    private let baseURL: String
    private let bearerToken: String
    private let session: URLSession

    init(baseURL: String, bearerToken: String, session: URLSession = .shared) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.bearerToken = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    func login(email: String, password: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/auth/login") else {
            throw SleepAgentClientError.invalidBaseURL
        }

        let payload = LoginRequest(email: email, password: password)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SleepAgentClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SleepAgentClientError.http(status: httpResponse.statusCode, body: Self.errorBody(from: data))
        }
        return try JSONDecoder().decode(LoginResponse.self, from: data).accessToken
    }

    func ask(
        mode: SleepAgentMode,
        question: String?,
        includeLatestData: Bool,
        allowExternalModel: Bool
    ) async throws -> SleepAgentResponse {
        guard let url = URL(string: "\(baseURL)/agent/sleep") else {
            throw SleepAgentClientError.invalidBaseURL
        }

        let payload = SleepAgentRequest(
            mode: mode,
            question: question,
            includeLatestData: includeLatestData,
            allowExternalModel: allowExternalModel
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SleepAgentClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw SleepAgentClientError.http(status: httpResponse.statusCode, body: Self.errorBody(from: data))
        }
        return try JSONDecoder().decode(SleepAgentResponse.self, from: data)
    }

    private static func errorBody(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return "No response body."
        }
        return text
    }
}

private enum SleepAgentClientError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Agent API base URL is invalid."
        case .invalidResponse:
            return "Agent API returned an invalid response."
        case let .http(status, body):
            return "Agent API HTTP \(status): \(body)"
        }
    }
}

private enum SleepAgentMode: String, Codable, CaseIterable, Hashable {
    case trend
    case guide
    case question
}

private struct LoginRequest: Encodable {
    let email: String
    let password: String
}

private struct LoginResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct SleepAgentRequest: Encodable {
    let mode: SleepAgentMode
    let question: String?
    let includeLatestData: Bool
    let allowExternalModel: Bool

    enum CodingKeys: String, CodingKey {
        case mode
        case question
        case includeLatestData = "include_latest_data"
        case allowExternalModel = "allow_external_model"
    }
}

private struct SleepAgentResponse: Decodable {
    let mode: SleepAgentMode
    let provider: String
    let plannerProvider: String
    let hitlRequired: Bool
    let answer: String
    let answerSections: AgentAnswerSections?
    let educationPrescription: HealthEducationPrescription?
    let rlsFollowUpQuestions: [RLSFollowUpQuestion]
    let plan: AgentPlan?
    let toolTrace: [ToolExecution]
    let guidePoints: [String]
    let safetyLimits: [String]
    let escalationSignals: [String]
    let dataUsed: [String]
    let redFlags: [String]
    let rlsScreening: RlsScreeningResult?
    let knowledgeSources: [String]
    let externalModelUsed: Bool
    let externalModelError: String?

    enum CodingKeys: String, CodingKey {
        case mode
        case provider
        case plannerProvider = "planner_provider"
        case hitlRequired = "hitl_required"
        case answer
        case answerSections = "answer_sections"
        case educationPrescription = "education_prescription"
        case rlsFollowUpQuestions = "rls_follow_up_questions"
        case plan
        case toolTrace = "tool_trace"
        case guidePoints = "guide_points"
        case safetyLimits = "safety_limits"
        case escalationSignals = "escalation_signals"
        case dataUsed = "data_used"
        case redFlags = "red_flags"
        case rlsScreening = "rls_screening"
        case knowledgeSources = "knowledge_sources"
        case externalModelUsed = "external_model_used"
        case externalModelError = "external_model_error"
    }
}

private struct AgentAnswerSections: Decodable {
    let trendObservation: String
    let interpretation: String
    let lowRiskSuggestions: [String]
    let followUpQuestions: [String]
    let careBoundary: String

    enum CodingKeys: String, CodingKey {
        case trendObservation = "trend_observation"
        case interpretation
        case lowRiskSuggestions = "low_risk_suggestions"
        case followUpQuestions = "follow_up_questions"
        case careBoundary = "care_boundary"
    }
}

private struct HealthEducationPrescription: Decodable {
    let title: String
    let targetUser: String
    let healthProblem: String
    let briefSummary: String
    let keySymptomsToTrack: [String]
    let riskFactorsToReview: [String]
    let guidanceItems: [String]
    let otherGuidance: [String]
    let useInstructions: String
    let safetyScope: String

    enum CodingKeys: String, CodingKey {
        case title
        case targetUser = "target_user"
        case healthProblem = "health_problem"
        case briefSummary = "brief_summary"
        case keySymptomsToTrack = "key_symptoms_to_track"
        case riskFactorsToReview = "risk_factors_to_review"
        case guidanceItems = "guidance_items"
        case otherGuidance = "other_guidance"
        case useInstructions = "use_instructions"
        case safetyScope = "safety_scope"
    }
}

private struct RLSFollowUpQuestion: Decodable, Identifiable {
    let criterion: String
    let question: String
    let whyItMatters: String
    let answered: Bool

    var id: String {
        criterion
    }

    enum CodingKeys: String, CodingKey {
        case criterion
        case question
        case whyItMatters = "why_it_matters"
        case answered
    }
}

private struct AgentPlan: Decodable {
    let intent: String
    let rationale: String
    let toolSequence: [String]
    let hitlRequired: Bool
    let topic: String

    enum CodingKeys: String, CodingKey {
        case intent
        case rationale
        case toolSequence = "tool_sequence"
        case hitlRequired = "hitl_required"
        case topic
    }
}

private struct ToolExecution: Decodable {
    let toolName: String
    let status: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case toolName = "tool_name"
        case status
        case summary
    }
}

private struct RlsScreeningResult: Decodable {
    let status: String
    let explanation: String
    let matchedFeatures: [String]
    let shouldSeekCare: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case explanation
        case matchedFeatures = "matched_features"
        case shouldSeekCare = "should_seek_care"
    }
}
