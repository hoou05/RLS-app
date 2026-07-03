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
    public let scenario: String
    public let prevalenceAdjusted: Bool
}

public final class RLSInferenceEngine {
    private let bundle: ModelBundle

    public init(modelBundleURL: URL) throws {
        let data = try Data(contentsOf: modelBundleURL)
        self.bundle = try JSONDecoder().decode(ModelBundle.self, from: data)
    }

    public func predict(_ input: RLSFeatureInput, tier: RLSTier) throws -> RLSPrediction {
        guard let scenario = bundle.tiers[tier.rawValue] else {
            throw RLSInferenceError.missingTier(tier.rawValue)
        }
        let projected = FeatureProjector.project(input)
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
            scenario: scenario.scenario,
            prevalenceAdjusted: scenario.applyPrevalenceAdjustment
        )
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
