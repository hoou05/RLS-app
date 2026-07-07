import Foundation

#if canImport(CoreML)
import CoreML
#endif

public enum RLSTier: String, Codable, Sendable {
    case tier1
    case tier2
}

public struct RLSFeatureInput: Sendable {
    public var sleepDurationMinutes: Double?
    public var sleepEfficiency: Double?
    public var wasoMinutes: Double?
    public var sleepLatencyMinutes: Double?
    public var remLatencyMinutes: Double?
    public var awakeStageMinutes: Double?
    public var averageSpO2: Double?
    public var minimumSpO2: Double?
    public var lightSleepMinutes: Double?
    public var lightSleepPercent: Double?
    public var deepSleepMinutes: Double?
    public var deepSleepPercent: Double?
    public var remSleepMinutes: Double?
    public var remSleepPercent: Double?
    public var restingHeartRate: Double?
    public var meanHeartRate: Double?
    public var minHeartRate: Double?
    public var maxHeartRate: Double?
    public var age: Double?
    public var sex: String?
    public var heightCm: Double?
    public var weightKg: Double?
    public var familyHistoryRLS: Bool?
    public var diabetes: Bool?
    public var psychiatricMedication: Bool?
    public var nonLegSymptoms: Bool?
    public var experimentFeatures: [String: Double?]

    public init(
        sleepDurationMinutes: Double? = nil,
        sleepEfficiency: Double? = nil,
        wasoMinutes: Double? = nil,
        sleepLatencyMinutes: Double? = nil,
        remLatencyMinutes: Double? = nil,
        awakeStageMinutes: Double? = nil,
        averageSpO2: Double? = nil,
        minimumSpO2: Double? = nil,
        lightSleepMinutes: Double? = nil,
        lightSleepPercent: Double? = nil,
        deepSleepMinutes: Double? = nil,
        deepSleepPercent: Double? = nil,
        remSleepMinutes: Double? = nil,
        remSleepPercent: Double? = nil,
        restingHeartRate: Double? = nil,
        meanHeartRate: Double? = nil,
        minHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        age: Double? = nil,
        sex: String? = nil,
        heightCm: Double? = nil,
        weightKg: Double? = nil,
        familyHistoryRLS: Bool? = nil,
        diabetes: Bool? = nil,
        psychiatricMedication: Bool? = nil,
        nonLegSymptoms: Bool? = nil,
        experimentFeatures: [String: Double?] = [:]
    ) {
        self.sleepDurationMinutes = sleepDurationMinutes
        self.sleepEfficiency = sleepEfficiency
        self.wasoMinutes = wasoMinutes
        self.sleepLatencyMinutes = sleepLatencyMinutes
        self.remLatencyMinutes = remLatencyMinutes
        self.awakeStageMinutes = awakeStageMinutes
        self.averageSpO2 = averageSpO2
        self.minimumSpO2 = minimumSpO2
        self.lightSleepMinutes = lightSleepMinutes
        self.lightSleepPercent = lightSleepPercent
        self.deepSleepMinutes = deepSleepMinutes
        self.deepSleepPercent = deepSleepPercent
        self.remSleepMinutes = remSleepMinutes
        self.remSleepPercent = remSleepPercent
        self.restingHeartRate = restingHeartRate
        self.meanHeartRate = meanHeartRate
        self.minHeartRate = minHeartRate
        self.maxHeartRate = maxHeartRate
        self.age = age
        self.sex = sex
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.familyHistoryRLS = familyHistoryRLS
        self.diabetes = diabetes
        self.psychiatricMedication = psychiatricMedication
        self.nonLegSymptoms = nonLegSymptoms
        self.experimentFeatures = experimentFeatures
    }
}

public struct RLSPrediction: Sendable {
    public let riskScore: Double
    public let xgboostProbability: Double
    public let tabmProbability: Double?
    public let tier: RLSTier
    public let modelKey: String
    public let scenario: String
    public let prevalenceAdjusted: Bool
    public let availableFeatureCount: Int
    public let totalFeatureCount: Int
}

public final class RLSInferenceEngine {
    private let bundle: ModelBundle

    public init(modelBundleURL: URL) throws {
        let data = try Data(contentsOf: modelBundleURL)
        self.bundle = try JSONDecoder().decode(ModelBundle.self, from: data)
    }

    public func predict(_ input: RLSFeatureInput, tier: RLSTier) throws -> RLSPrediction {
        let modelKey = Self.modelKey(for: tier)
        guard let scenario = bundle.tiers[modelKey] ?? bundle.tiers[tier.rawValue] else {
            throw RLSInferenceError.missingTier(tier.rawValue)
        }
        let projected = FeatureProjector.project(input)
        return try predict(input, tier: tier, modelKey: modelKey, scenario: scenario, projected: projected)
    }

    public func predictBestAvailable(_ input: RLSFeatureInput) throws -> RLSPrediction {
        let projected = FeatureProjector.project(input)
        guard let selected = bundle.tiers
            .map({ (key: $0.key, scenario: $0.value) })
            .max(by: { lhs, rhs in
                let lhsAvailable = lhs.scenario.availableFeatureCount(from: projected)
                let rhsAvailable = rhs.scenario.availableFeatureCount(from: projected)
                if lhsAvailable != rhsAvailable {
                    return lhsAvailable < rhsAvailable
                }
                let lhsCoverage = lhs.scenario.featureCoverage(from: projected)
                let rhsCoverage = rhs.scenario.featureCoverage(from: projected)
                if lhsCoverage != rhsCoverage {
                    return lhsCoverage < rhsCoverage
                }
                return lhs.scenario.features.count > rhs.scenario.features.count
            }) else {
            throw RLSInferenceError.missingTier("auto")
        }
        let tier: RLSTier = selected.key == Self.modelKey(for: .tier2) ? .tier2 : .tier1
        return try predict(input, tier: tier, modelKey: selected.key, scenario: selected.scenario, projected: projected)
    }

    private func predict(
        _ input: RLSFeatureInput,
        tier: RLSTier,
        modelKey: String,
        scenario: ScenarioModel,
        projected: [String: Double]
    ) throws -> RLSPrediction {
        let xgbInput = scenario.features.map { projected[$0] ?? .nan }
        let xgbProbability = XGBoostEnsemble(models: scenario.xgboostModels).predictProbability(xgbInput)

        let tabmInput = scenario.prepareTabMInput(from: projected)
        let tabmProbability = TabMModel(weights: scenario.tabmWeights).predictProbability(tabmInput)
        let raw = 0.5 * xgbProbability + 0.5 * tabmProbability
        let score = scenario.applyPrevalenceAdjustment
            ? Self.adjustPrevalence(raw, trainPrevalence: scenario.trainPrevalence, populationPrevalence: bundle.populationPrevalence)
            : raw
        return RLSPrediction(
            riskScore: min(max(score, 0.0), 1.0),
            xgboostProbability: xgbProbability,
            tabmProbability: tabmProbability,
            tier: tier,
            modelKey: modelKey,
            scenario: scenario.scenario,
            prevalenceAdjusted: scenario.applyPrevalenceAdjustment,
            availableFeatureCount: scenario.availableFeatureCount(from: projected),
            totalFeatureCount: scenario.features.count
        )
    }

    private static func modelKey(for tier: RLSTier) -> String {
        switch tier {
        case .tier1:
            return "sleep_heart_basic"
        case .tier2:
            return "sleep_heart_basic_q"
        }
    }

    static func adjustPrevalence(_ modelProbability: Double, trainPrevalence: Double, populationPrevalence: Double) -> Double {
        guard modelProbability > 0, modelProbability < 1 else {
            return modelProbability
        }
        let oddsModel = modelProbability / (1 - modelProbability)
        let oddsTrain = trainPrevalence / (1 - trainPrevalence)
        let likelihoodRatio = oddsModel / oddsTrain
        let oddsPopulation = populationPrevalence / (1 - populationPrevalence)
        let posteriorOdds = likelihoodRatio * oddsPopulation
        return posteriorOdds / (1 + posteriorOdds)
    }
}

public enum RLSInferenceError: Error, Equatable {
    case missingTier(String)
}

private struct FeatureProjector {
    static func project(_ input: RLSFeatureInput) -> [String: Double] {
        let height = input.heightCm ?? .nan
        let weight = input.weightKg ?? .nan
        var bmi = Double.nan
        if height.isFinite, weight.isFinite, height > 0 {
            bmi = weight / pow(height / 100.0, 2)
        }

        let meanHR = input.meanHeartRate ?? .nan
        let restingHR = input.restingHeartRate ?? .nan
        let minHR = input.minHeartRate ?? .nan
        let maxHR = input.maxHeartRate ?? .nan
        var averageMinusMin = Double.nan
        if meanHR.isFinite, minHR.isFinite {
            averageMinusMin = meanHR - minHR
        } else if meanHR.isFinite, restingHR.isFinite {
            averageMinusMin = max(meanHR - restingHR, 0.0)
        }
        let maxMinusAverage = meanHR.isFinite && maxHR.isFinite ? maxHR - meanHR : Double.nan

        var output: [String: Double] = [
            "总睡眠时间/分": input.sleepDurationMinutes ?? .nan,
            "睡眠效率%": input.sleepEfficiency ?? .nan,
            "WASO/分 入睡后清醒时间": input.wasoMinutes ?? .nan,
            "睡眠潜伏期/分": input.sleepLatencyMinutes ?? .nan,
            "REM睡眠潜伏期/分": input.remLatencyMinutes ?? .nan,
            "W期时间": input.awakeStageMinutes ?? .nan,
            "睡眠平均SPO2": input.averageSpO2 ?? .nan,
            "睡眠最低SPO2": input.minimumSpO2 ?? .nan,
            "N1N2时间": input.lightSleepMinutes ?? .nan,
            "N1N2%": input.lightSleepPercent ?? .nan,
            "N3时间": input.deepSleepMinutes ?? .nan,
            "N3%": input.deepSleepPercent ?? .nan,
            "R期时间": input.remSleepMinutes ?? .nan,
            "R%": input.remSleepPercent ?? .nan,
            "平均心率": meanHR,
            "平均-最慢心率差值": averageMinusMin,
            "最快-平均心率差值": maxMinusAverage,
            "性别_男1女0": binarySex(input.sex),
            "身高cm": height,
            "体重Kg": weight,
            "年龄_发病年龄合并": input.age ?? .nan,
            "BMI": bmi,
            "家系（口述或诊断确认家族内有患病）": binary(input.familyHistoryRLS),
            "糖尿病": binary(input.diabetes),
            "精神类药物": binary(input.psychiatricMedication),
            "除腿部以外部位受累": binary(input.nonLegSymptoms),
        ]
        for (key, value) in input.experimentFeatures {
            output[key] = value ?? .nan
        }
        return output
    }

    private static func binary(_ value: Bool?) -> Double {
        guard let value else {
            return .nan
        }
        return value ? 1.0 : 0.0
    }

    private static func binarySex(_ value: String?) -> Double {
        guard let value else {
            return .nan
        }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["1", "true", "yes", "y", "是", "male", "m", "男"].contains(normalized) {
            return 1.0
        }
        if ["0", "false", "no", "n", "否", "female", "f", "女"].contains(normalized) {
            return 0.0
        }
        return .nan
    }
}
