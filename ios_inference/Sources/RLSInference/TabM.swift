import Foundation

struct TabMWeights: Decodable {
    let k: Int
    let activation: String
    let blocks: [TabMBlockWeights]
    let output: TabMOutputWeights
}

struct TabMBlockWeights: Decodable {
    let weight: [[Double]]
    let r: [[Double]]
    let s: [[Double]]
    let bias: [[Double]]
}

struct TabMOutputWeights: Decodable {
    let weight: [[[Double]]]
    let bias: [[Double]]
}

struct TabMModel {
    let weights: TabMWeights

    func predictProbability(_ features: [Double]) -> Double {
        var x = Array(repeating: features, count: weights.k)
        for block in weights.blocks {
            x = apply(block: block, to: x)
        }
        let logits = applyOutput(to: x)
        let probabilities = logits.map { pair -> Double in
            let maxLogit = max(pair[0], pair[1])
            let exp0 = exp(pair[0] - maxLogit)
            let exp1 = exp(pair[1] - maxLogit)
            return exp1 / (exp0 + exp1)
        }
        return probabilities.reduce(0.0, +) / Double(probabilities.count)
    }

    private func apply(block: TabMBlockWeights, to input: [[Double]]) -> [[Double]] {
        var output = Array(
            repeating: Array(repeating: 0.0, count: block.weight.count),
            count: input.count
        )
        for ensembleIndex in input.indices {
            for outIndex in block.weight.indices {
                var value = 0.0
                for inIndex in input[ensembleIndex].indices {
                    value += input[ensembleIndex][inIndex] *
                        block.r[ensembleIndex][inIndex] *
                        block.weight[outIndex][inIndex]
                }
                value = value * block.s[ensembleIndex][outIndex] + block.bias[ensembleIndex][outIndex]
                output[ensembleIndex][outIndex] = max(value, 0.0)
            }
        }
        return output
    }

    private func applyOutput(to input: [[Double]]) -> [[Double]] {
        var output = Array(repeating: Array(repeating: 0.0, count: 2), count: input.count)
        for ensembleIndex in input.indices {
            for outIndex in 0..<2 {
                var value = weights.output.bias[ensembleIndex][outIndex]
                for inIndex in input[ensembleIndex].indices {
                    value += input[ensembleIndex][inIndex] * weights.output.weight[ensembleIndex][inIndex][outIndex]
                }
                output[ensembleIndex][outIndex] = value
            }
        }
        return output
    }
}
