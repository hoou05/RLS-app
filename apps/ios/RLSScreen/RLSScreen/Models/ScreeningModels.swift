import Foundation
import RLSInference

struct ScreeningForm: Codable, Equatable {
    var sleepDurationMinutes = 405.0
    var sleepEfficiency = 80.0
    var restingHeartRate = 69.0
    var meanHeartRate = 78.0
    var age = 51.0
    var sex = "female"
    var heightCm = 165.0
    var weightKg = 62.0
    var familyHistoryRLS = true
    var diabetes = false
    var psychiatricMedication = false
    var nonLegSymptoms = false

    var featureInput: RLSFeatureInput {
        RLSFeatureInput(
            sleepDurationMinutes: sleepDurationMinutes,
            sleepEfficiency: sleepEfficiency,
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
    let scenario: String
    let input: ScreeningForm

    init(prediction: RLSPrediction, input: ScreeningForm) {
        self.id = UUID()
        self.createdAt = Date()
        self.tier = prediction.tier.rawValue
        self.riskScore = prediction.riskScore
        self.riskLevel = RiskLevel(score: prediction.riskScore).rawValue
        self.xgboostProbability = prediction.xgboostProbability
        self.tabmProbability = prediction.tabmProbability ?? .nan
        self.scenario = prediction.scenario
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

