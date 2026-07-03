import Foundation

struct XGBoostModel: Decodable {
    let baseScoreMargin: Double
    let trees: [XGBoostNode]

    enum CodingKeys: String, CodingKey {
        case baseScoreMargin = "base_score_margin"
        case trees
    }
}

struct XGBoostNode: Decodable {
    let nodeID: Int
    let splitIndex: Int?
    let splitCondition: Double?
    let yes: Int?
    let no: Int?
    let missing: Int?
    let leaf: Double?
    let children: [XGBoostNode]

    enum CodingKeys: String, CodingKey {
        case nodeID = "nodeid"
        case splitIndex = "split_index"
        case splitCondition = "split_condition"
        case yes
        case no
        case missing
        case leaf
        case children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.nodeID = try container.decode(Int.self, forKey: .nodeID)
        self.splitIndex = try container.decodeIfPresent(Int.self, forKey: .splitIndex)
        self.splitCondition = try container.decodeIfPresent(Double.self, forKey: .splitCondition)
        self.yes = try container.decodeIfPresent(Int.self, forKey: .yes)
        self.no = try container.decodeIfPresent(Int.self, forKey: .no)
        self.missing = try container.decodeIfPresent(Int.self, forKey: .missing)
        self.leaf = try container.decodeIfPresent(Double.self, forKey: .leaf)
        self.children = try container.decodeIfPresent([XGBoostNode].self, forKey: .children) ?? []
    }
}

struct XGBoostEnsemble {
    let models: [XGBoostModel]

    func predictProbability(_ features: [Double]) -> Double {
        guard !models.isEmpty else {
            return 0.0
        }
        let probabilities = models.map { model in
            sigmoid(model.predictMargin(features))
        }
        return probabilities.reduce(0.0, +) / Double(probabilities.count)
    }

    private func sigmoid(_ value: Double) -> Double {
        1.0 / (1.0 + exp(-value))
    }
}

private extension XGBoostModel {
    func predictMargin(_ features: [Double]) -> Double {
        baseScoreMargin + trees.reduce(0.0) { $0 + $1.predictLeaf(features) }
    }
}

private extension XGBoostNode {
    func predictLeaf(_ features: [Double]) -> Double {
        if let leaf {
            return leaf
        }
        let value = splitIndex.flatMap { idx in features.indices.contains(idx) ? features[idx] : nil } ?? .nan
        if value.isNaN {
            guard let missingNode = missing, let child = child(with: missingNode) else {
                return 0.0
            }
            return child.predictLeaf(features)
        }
        let nextNodeID = value < (splitCondition ?? 0.0) ? yes : no
        guard let nextNodeID, let child = child(with: nextNodeID) else {
            return 0.0
        }
        return child.predictLeaf(features)
    }

    func child(with nodeID: Int) -> XGBoostNode? {
        children.first { $0.nodeID == nodeID }
    }

}
