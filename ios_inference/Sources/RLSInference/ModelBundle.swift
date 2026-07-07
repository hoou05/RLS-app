import Foundation

struct ModelBundle: Decodable {
    let schemaVersion: Int
    let generatedBy: String
    let populationPrevalence: Double
    let tiers: [String: ScenarioModel]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedBy = "generated_by"
        case populationPrevalence = "population_prevalence"
        case tiers
    }
}

struct ScenarioModel: Decodable {
    let scenario: String
    let features: [String]
    let tabmFeatures: [String]
    let trainPrevalence: Double
    let applyPrevalenceAdjustment: Bool
    let tabmMedians: [Double]
    let tabmWeights: TabMWeights
    let quantileReferences: [Double]
    let quantileValuesByFeature: [[Double]]
    let xgboostModels: [XGBoostModel]

    enum CodingKeys: String, CodingKey {
        case scenario
        case features
        case tabmFeatures = "tabm_features"
        case trainPrevalence = "train_prevalence"
        case applyPrevalenceAdjustment = "apply_prevalence_adjustment"
        case tabmMedians = "tabm_medians"
        case tabmWeights = "tabm_weights"
        case quantileReferences = "quantile_references"
        case quantileValuesByFeature = "quantile_values_by_feature"
        case xgboostModels = "xgboost_models"
    }

    func prepareTabMInput(from projected: [String: Double]) -> [Double] {
        let raw = tabmFeatures.map { projected[$0] ?? .nan }
        var transformed = Array(repeating: 0.0, count: raw.count)
        for idx in raw.indices {
            let wasMissing = raw[idx].isNaN
            let filled = wasMissing ? tabmMedians[idx] : raw[idx]
            transformed[idx] = wasMissing ? 0.0 : QuantileTransformer.transform(
                filled,
                quantiles: quantileValuesByFeature[idx],
                references: quantileReferences
            )
        }
        return transformed
    }

    func availableFeatureCount(from projected: [String: Double]) -> Int {
        features.reduce(0) { count, feature in
            guard let value = projected[feature], value.isFinite else {
                return count
            }
            return count + 1
        }
    }

    func featureCoverage(from projected: [String: Double]) -> Double {
        guard !features.isEmpty else {
            return 0
        }
        return Double(availableFeatureCount(from: projected)) / Double(features.count)
    }
}
