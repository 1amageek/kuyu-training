import Foundation

public struct TrainingCandidateRefinementPolicy: Sendable, Codable, Equatable {
    public enum ValidationError: Error, Sendable, Equatable {
        case invalidEvaluationFidelity(TrainingEvaluationFidelity.ValidationError)
        case invalidCandidateFraction(Double)
        case invalidMinimumCandidateCount(Int)
    }

    public let evaluationFidelity: TrainingEvaluationFidelity
    public let candidateFraction: Double
    public let minimumCandidateCount: Int
    public let retainsIncumbent: Bool

    private enum CodingKeys: String, CodingKey {
        case evaluationFidelity
        case candidateFraction
        case minimumCandidateCount
        case retainsIncumbent
    }

    public init(
        evaluationFidelity: TrainingEvaluationFidelity = .fullScenario,
        candidateFraction: Double = 0.25,
        minimumCandidateCount: Int = 1,
        retainsIncumbent: Bool = true
    ) {
        self.evaluationFidelity = evaluationFidelity
        self.candidateFraction = candidateFraction
        self.minimumCandidateCount = minimumCandidateCount
        self.retainsIncumbent = retainsIncumbent
    }

    public func validate() throws {
        do {
            try evaluationFidelity.validate()
        } catch let error as TrainingEvaluationFidelity.ValidationError {
            throw ValidationError.invalidEvaluationFidelity(error)
        }
        guard candidateFraction.isFinite,
              candidateFraction > 0,
              candidateFraction <= 1 else {
            throw ValidationError.invalidCandidateFraction(candidateFraction)
        }
        guard minimumCandidateCount > 0 else {
            throw ValidationError.invalidMinimumCandidateCount(minimumCandidateCount)
        }
    }

    public func candidateCount(populationSize: Int, eliteCount: Int) -> Int {
        let populationSize = max(1, populationSize)
        let boundedFraction = candidateFraction.isFinite
            ? min(1, max(0, candidateFraction))
            : 0
        let fractionCount = Int(ceil(Double(populationSize) * boundedFraction))
        return min(
            populationSize,
            max(max(1, eliteCount), max(minimumCandidateCount, fractionCount))
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            evaluationFidelity: try container.decode(
                TrainingEvaluationFidelity.self,
                forKey: .evaluationFidelity
            ),
            candidateFraction: try container.decode(Double.self, forKey: .candidateFraction),
            minimumCandidateCount: try container.decode(Int.self, forKey: .minimumCandidateCount),
            retainsIncumbent: try container.decode(Bool.self, forKey: .retainsIncumbent)
        )
        try validate()
    }

    public func encode(to encoder: any Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(evaluationFidelity, forKey: .evaluationFidelity)
        try container.encode(candidateFraction, forKey: .candidateFraction)
        try container.encode(minimumCandidateCount, forKey: .minimumCandidateCount)
        try container.encode(retainsIncumbent, forKey: .retainsIncumbent)
    }
}
