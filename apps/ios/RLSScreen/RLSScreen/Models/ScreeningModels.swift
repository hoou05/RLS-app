import Foundation
import RLSInference

struct ScreeningForm: Codable, Equatable {
    var sleepSessionEndDate: Date?
    var sleepDurationMinutes = 405.0
    var sleepEfficiency = 80.0
    var wasoMinutes: Double?
    var sleepLatencyMinutes: Double?
    var remLatencyMinutes: Double?
    var awakeStageMinutes: Double?
    var averageSpO2: Double?
    var minimumSpO2: Double?
    var lightSleepMinutes: Double?
    var lightSleepPercent: Double?
    var deepSleepMinutes: Double?
    var deepSleepPercent: Double?
    var remSleepMinutes: Double?
    var remSleepPercent: Double?
    var restingHeartRate = 69.0
    var meanHeartRate = 78.0
    var age = 51.0
    var sex = "female"
    var heightCm = 165.0
    var weightKg = 62.0
    var familyHistoryRLS: Bool?
    var diabetes: Bool?
    var psychiatricMedication: Bool?
    var nonLegSymptoms: Bool?

    var featureInput: RLSFeatureInput {
        RLSFeatureInput(
            sleepDurationMinutes: sleepDurationMinutes,
            sleepEfficiency: sleepEfficiency,
            wasoMinutes: wasoMinutes,
            sleepLatencyMinutes: sleepLatencyMinutes,
            remLatencyMinutes: remLatencyMinutes,
            awakeStageMinutes: awakeStageMinutes,
            averageSpO2: averageSpO2,
            minimumSpO2: minimumSpO2,
            lightSleepMinutes: lightSleepMinutes,
            lightSleepPercent: lightSleepPercent,
            deepSleepMinutes: deepSleepMinutes,
            deepSleepPercent: deepSleepPercent,
            remSleepMinutes: remSleepMinutes,
            remSleepPercent: remSleepPercent,
            restingHeartRate: restingHeartRate,
            meanHeartRate: meanHeartRate,
            age: age,
            sex: sex,
            heightCm: heightCm,
            weightKg: weightKg,
            familyHistoryRLS: familyHistoryRLS,
            diabetes: diabetes,
            psychiatricMedication: psychiatricMedication,
            nonLegSymptoms: nonLegSymptoms
        )
    }
}

struct ScreeningRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let tier: String
    let riskScore: Double
    let riskLevel: String
    let xgboostProbability: Double
    let tabmProbability: Double
    let modelKey: String?
    let scenario: String
    let availableFeatureCount: Int?
    let totalFeatureCount: Int?
    let input: ScreeningForm

    init(prediction: RLSPrediction, input: ScreeningForm) {
        self.id = UUID()
        self.createdAt = Date()
        self.tier = prediction.tier.rawValue
        self.riskScore = prediction.riskScore
        self.riskLevel = RiskLevel(score: prediction.riskScore).rawValue
        self.xgboostProbability = prediction.xgboostProbability
        self.tabmProbability = prediction.tabmProbability ?? .nan
        self.modelKey = prediction.modelKey
        self.scenario = prediction.scenario
        self.availableFeatureCount = prediction.availableFeatureCount
        self.totalFeatureCount = prediction.totalFeatureCount
        self.input = input
    }
}

enum RiskLevel: String {
    case low
    case moderate
    case high

    init(score: Double) {
        if score >= 0.55 {
            self = .high
        } else if score >= 0.32 {
            self = .moderate
        } else {
            self = .low
        }
    }

    var title: String {
        switch self {
        case .low:
            return "Low"
        case .moderate:
            return "Moderate"
        case .high:
            return "High"
        }
    }
}
