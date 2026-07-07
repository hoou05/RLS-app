import Foundation
import RLSInference

@MainActor
final class ScreeningStore: ObservableObject {
    @Published var form = ScreeningForm()
    @Published private(set) var latestTier1: ScreeningRecord?
    @Published private(set) var latestTier2: ScreeningRecord?
    @Published private(set) var history: [ScreeningRecord] = []
    @Published var errorMessage: String?
    @Published private(set) var isImportingHealthData = false
    @Published private(set) var healthImportMessage: String?

    private var engine: RLSInferenceEngine?
    private let healthDataProvider: HealthDataProvider
    private let historyURL: URL

    init(healthDataProvider: HealthDataProvider = HealthKitDataProvider()) {
        self.healthDataProvider = healthDataProvider
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RLSScreen", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.historyURL = directory.appendingPathComponent("screening-history.json")
        self.history = Self.loadHistory(from: historyURL)
        self.engine = Self.makeEngine()
    }

    func runScreening() {
        errorMessage = nil
        guard let engine else {
            errorMessage = "Model bundle could not be loaded."
            return
        }
        do {
            let tier1 = try engine.predict(form.featureInput, tier: .tier1)
            let tier2 = try engine.predict(form.featureInput, tier: .tier2)
            let tier1Record = ScreeningRecord(prediction: tier1, input: form)
            let tier2Record = ScreeningRecord(prediction: tier2, input: form)
            latestTier1 = tier1Record
            latestTier2 = tier2Record
            history.insert(tier2Record, at: 0)
            history = Array(history.prefix(30))
            saveHistory()
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

    func clearHistory() {
        history = []
        latestTier1 = nil
        latestTier2 = nil
        saveHistory()
    }

    private func saveHistory() {
        do {
            let data = try JSONEncoder.rlsHistory.encode(history)
            try data.write(to: historyURL, options: [.atomic])
        } catch {
            errorMessage = "History could not be saved."
        }
    }

    private static func loadHistory(from url: URL) -> [ScreeningRecord] {
        guard let data = try? Data(contentsOf: url) else {
            return []
        }
        return (try? JSONDecoder.rlsHistory.decode([ScreeningRecord].self, from: data)) ?? []
    }

    private static func makeEngine() -> RLSInferenceEngine? {
        guard let url = Bundle.main.url(forResource: "RLSModelBundle", withExtension: "json") else {
            return nil
        }
        return try? RLSInferenceEngine(modelBundleURL: url)
    }
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
