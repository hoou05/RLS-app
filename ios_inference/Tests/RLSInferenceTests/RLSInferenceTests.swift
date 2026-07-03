import XCTest
@testable import RLSInference

final class RLSInferenceTests: XCTestCase {
    func testOfflineTierPredictionsRun() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bundleURL = packageRoot
            .appendingPathComponent("Artifacts")
            .appendingPathComponent("RLSModelBundle.json")
        let engine = try RLSInferenceEngine(modelBundleURL: bundleURL)
        let input = RLSFeatureInput(
            sleepDurationMinutes: 405,
            sleepEfficiency: 80,
            restingHeartRate: 69,
            meanHeartRate: 78,
            age: 51,
            sex: "female",
            heightCm: 165,
            weightKg: 62,
            familyHistoryRLS: true,
            diabetes: false,
            psychiatricMedication: false,
            nonLegSymptoms: nil
        )

        let tier1 = try engine.predict(input, tier: .tier1)
        let tier2 = try engine.predict(input, tier: .tier2)

        XCTAssertGreaterThanOrEqual(tier1.riskScore, 0)
        XCTAssertLessThanOrEqual(tier1.riskScore, 1)
        XCTAssertGreaterThanOrEqual(tier2.riskScore, 0)
        XCTAssertLessThanOrEqual(tier2.riskScore, 1)
        XCTAssertNotNil(tier1.tabmProbability)
        XCTAssertNotNil(tier2.tabmProbability)
    }
}
