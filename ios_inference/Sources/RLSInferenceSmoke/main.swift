import Foundation
import RLSInference

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

for tier in [RLSTier.tier1, .tier2] {
    let prediction = try engine.predict(input, tier: tier)
    print(
        "\(tier.rawValue) risk=\(prediction.riskScore) xgb=\(prediction.xgboostProbability) tabm=\(prediction.tabmProbability ?? .nan)"
    )
}
