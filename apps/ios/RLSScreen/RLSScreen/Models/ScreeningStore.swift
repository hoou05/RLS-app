import Foundation
import RLSInference

@MainActor
final class ScreeningStore: ObservableObject {
    @Published var form = ScreeningForm()
    @Published private(set) var latestTier1: ScreeningRecord?
    @Published private(set) var latestTier2: ScreeningRecord?
    @Published private(set) var history: [ScreeningRecord] = []
    @Published private(set) var baselineResult: BaselineScreeningResult?
    @Published var errorMessage: String?
    @Published private(set) var isImportingHealthData = false
    @Published private(set) var isBuildingBaseline = false
    @Published private(set) var healthImportMessage: String?

    private var engine: RLSInferenceEngine?
    private let healthDataProvider: HealthDataProvider
    private let notificationManager: NotificationManager
    private let historyURL: URL
    private let baselineURL: URL
    private var isAutomationConfigured = false

    private static let lastAutomatedSleepEndDateKey = "lastAutomatedSleepEndDate"
    static let baselineWindowDays = 60
    static let baselineNightLimit = 60

    init(
        healthDataProvider: HealthDataProvider = HealthKitDataProvider(),
        notificationManager: NotificationManager = .shared
    ) {
        self.healthDataProvider = healthDataProvider
        self.notificationManager = notificationManager
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RLSScreen", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.historyURL = directory.appendingPathComponent("screening-history.json")
        self.baselineURL = directory.appendingPathComponent("baseline-screening.json")
        self.history = Self.loadHistory(from: historyURL)
        self.baselineResult = Self.loadBaseline(from: baselineURL)
        self.engine = Self.makeEngine()
    }

    var hasCompletedOnboarding: Bool {
        baselineResult != nil
    }

    func runScreening() {
        errorMessage = nil
        do {
            _ = try runPrediction(input: form)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importHealthData() async {
        errorMessage = nil
        healthImportMessage = nil
        isImportingHealthData = true
        defer { isImportingHealthData = false }

        do {
            try await healthDataProvider.requestAuthorization()
            let result = try await healthDataProvider.latestScreeningForm(current: form)
            form = result.form

            let imported = result.importedFieldNames.joined(separator: ", ")
            let notes = result.notes.isEmpty ? "" : " \(result.notes.joined(separator: "; "))."
            if result.missingFieldNames.isEmpty {
                healthImportMessage = "Imported from Health: \(imported).\(notes)"
            } else {
                let missing = result.missingFieldNames.joined(separator: ", ")
                healthImportMessage = "Imported from Health: \(imported). Missing: \(missing).\(notes)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func buildBaselineScreening() async {
        errorMessage = nil
        healthImportMessage = nil

        applyDirectImportQuestionnaireDefaultsIfNeeded()

        guard let engine else {
            errorMessage = ScreeningStoreError.modelBundleUnavailable.localizedDescription
            return
        }

        isBuildingBaseline = true
        defer { isBuildingBaseline = false }

        do {
            try await healthDataProvider.requestAuthorization()
            let result = try await healthDataProvider.recentScreeningForms(
                current: form,
                limit: Self.baselineNightLimit,
                lookbackDays: Self.baselineWindowDays
            )

            let predictions = try result.forms.map { form in
                (try engine.predict(form.featureInput, tier: .tier2), form)
            }

            guard !predictions.isEmpty else {
                throw HealthDataProviderError.missingReadableData
            }

            let baseline = BaselineScreeningResult(
                windowDays: Self.baselineWindowDays,
                requestedNightLimit: Self.baselineNightLimit,
                predictions: predictions
            )
            baselineResult = baseline
            let healthRecords = predictions.map { prediction, form in
                ScreeningRecord(
                    prediction: prediction,
                    input: form,
                    createdAt: form.sleepSessionEndDate ?? Date()
                )
            }
            .sorted { lhs, rhs in
                (lhs.input.sleepSessionEndDate ?? lhs.createdAt) > (rhs.input.sleepSessionEndDate ?? rhs.createdAt)
            }
            history = Array(healthRecords.prefix(30))
            latestTier1 = history.first
            latestTier2 = history.first

            if let latestForm = result.forms.first {
                form = latestForm
            }

            saveHistory()
            saveBaseline()

            let imported = result.importedFieldNames.joined(separator: ", ")
            let notes = result.notes.isEmpty ? "" : " \(result.notes.joined(separator: "; "))."
            healthImportMessage = "Built baseline from \(baseline.validNightCount) sleep sessions. Imported: \(imported).\(notes)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func configureAutomation() async {
        guard !isAutomationConfigured else {
            return
        }
        isAutomationConfigured = true
        await notificationManager.requestAuthorization()

        do {
            try await healthDataProvider.requestAuthorization()
            try await healthDataProvider.startSleepDataObservation { [weak self] in
                await self?.refreshFromHealthIfNeeded(source: "HealthKit", notify: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func refreshFromHealthIfNeeded(source: String, notify: Bool) async -> Bool {
        do {
            try await healthDataProvider.requestAuthorization()
            let result = try await healthDataProvider.latestScreeningForm(current: form)
            guard let sleepEndDate = result.form.sleepSessionEndDate else {
                return false
            }
            guard isNewSleepSession(sleepEndDate) else {
                return false
            }

            form = result.form
            let record = try runPrediction(input: result.form)
            markSleepSessionProcessed(sleepEndDate)
            healthImportMessage = "\(source) updated screening from sleep ending \(Self.shortDateTimeFormatter.string(from: sleepEndDate))."

            if notify {
                await notificationManager.notifyScreeningUpdated(record: record)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearHistory() {
        history = []
        latestTier1 = nil
        latestTier2 = nil
        saveHistory()
    }

    func resetBaseline() {
        baselineResult = nil
        try? FileManager.default.removeItem(at: baselineURL)
    }

    private func runPrediction(input: ScreeningForm) throws -> ScreeningRecord {
        guard let engine else {
            throw ScreeningStoreError.modelBundleUnavailable
        }
        let tier1 = try engine.predict(input.featureInput, tier: .tier1)
        let selected = try engine.predictBestAvailable(input.featureInput)
        let tier1Record = ScreeningRecord(prediction: tier1, input: input)
        let selectedRecord = ScreeningRecord(prediction: selected, input: input)
        latestTier1 = tier1Record
        latestTier2 = selectedRecord
        history.insert(selectedRecord, at: 0)
        history = Array(history.prefix(30))
        saveHistory()
        return selectedRecord
    }

    private func isNewSleepSession(_ sleepEndDate: Date) -> Bool {
        guard let latestProcessed = latestProcessedSleepEndDate() else {
            return true
        }
        return sleepEndDate > latestProcessed
    }

    private func latestProcessedSleepEndDate() -> Date? {
        let storedInterval = UserDefaults.standard.double(forKey: Self.lastAutomatedSleepEndDateKey)
        let storedDate = storedInterval > 0 ? Date(timeIntervalSinceReferenceDate: storedInterval) : nil
        let historyDate = history.compactMap { $0.input.sleepSessionEndDate }.max()

        switch (storedDate, historyDate) {
        case let (stored?, history?):
            return max(stored, history)
        case let (stored?, nil):
            return stored
        case let (nil, history?):
            return history
        case (nil, nil):
            return nil
        }
    }

    private func markSleepSessionProcessed(_ sleepEndDate: Date) {
        UserDefaults.standard.set(
            sleepEndDate.timeIntervalSinceReferenceDate,
            forKey: Self.lastAutomatedSleepEndDateKey
        )
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder.rlsHistory.encode(history)
            try data.write(to: historyURL, options: [.atomic])
        } catch {
            errorMessage = "History could not be saved."
        }
    }

    private func saveBaseline() {
        do {
            let data = try JSONEncoder.rlsHistory.encode(baselineResult)
            try data.write(to: baselineURL, options: [.atomic])
        } catch {
            errorMessage = "Baseline could not be saved."
        }
    }

    private static func loadHistory(from url: URL) -> [ScreeningRecord] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder.rlsHistory.decode([ScreeningRecord].self, from: data)) ?? []
    }

    private static func loadBaseline(from url: URL) -> BaselineScreeningResult? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder.rlsHistory.decode(BaselineScreeningResult.self, from: data)
    }

    private static func makeEngine() -> RLSInferenceEngine? {
        guard let url = Bundle.main.url(forResource: "RLSModelBundle", withExtension: "json") else {
            return nil
        }
        return try? RLSInferenceEngine(modelBundleURL: url)
    }

    private func applyDirectImportQuestionnaireDefaultsIfNeeded() {
        if form.familyHistoryRLS == nil {
            form.familyHistoryRLS = false
        }
        if form.diabetes == nil {
            form.diabetes = false
        }
        if form.psychiatricMedication == nil {
            form.psychiatricMedication = false
        }
        if form.nonLegSymptoms == nil {
            form.nonLegSymptoms = false
        }
    }
}

enum ScreeningStoreError: LocalizedError {
    case modelBundleUnavailable

    var errorDescription: String? {
        switch self {
        case .modelBundleUnavailable:
            return "Model bundle could not be loaded."
        }
    }
}

private extension ScreeningStore {
    static var shortDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension JSONEncoder {
    static var rlsHistory: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var rlsHistory: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
