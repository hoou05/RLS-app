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

let iterations = Int(CommandLine.arguments.dropFirst().first ?? "20000") ?? 20_000
let warmupIterations = min(1_000, max(100, iterations / 20))

@discardableResult
func time(_ label: String, iterations: Int, operation: () throws -> Double) rethrows -> Double {
    var checksum = 0.0
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<iterations {
        checksum += try operation()
    }
    let elapsedNanos = DispatchTime.now().uptimeNanoseconds - start
    let elapsedSeconds = Double(elapsedNanos) / 1_000_000_000
    let microsPerInference = elapsedSeconds * 1_000_000 / Double(iterations)
    print("\(label): \(iterations) iterations, \(String(format: "%.3f", microsPerInference)) us/inference, checksum=\(String(format: "%.6f", checksum))")
    return microsPerInference
}

for _ in 0..<warmupIterations {
    _ = try engine.predict(input, tier: .tier1)
    _ = try engine.predict(input, tier: .tier2)
}

let tier1 = try time("tier1", iterations: iterations) {
    try engine.predict(input, tier: .tier1).riskScore
}
let tier2 = try time("tier2", iterations: iterations) {
    try engine.predict(input, tier: .tier2).riskScore
}
let both = try time("tier1+tier2", iterations: iterations) {
    let tier1 = try engine.predict(input, tier: .tier1).riskScore
    let tier2 = try engine.predict(input, tier: .tier2).riskScore
    return tier1 + tier2
}

print("summary_us tier1=\(String(format: "%.3f", tier1)) tier2=\(String(format: "%.3f", tier2)) both=\(String(format: "%.3f", both))")
