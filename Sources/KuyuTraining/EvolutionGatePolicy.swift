import Foundation

public struct EvolutionGateReport: Sendable, Codable, Equatable {
    public let runID: String
    public let generationIndex: Int
    public let accepted: Bool
    public let eliteCandidateIDs: [String]
    public let bestCandidateID: String?
    public let bestFitness: Double?
    public let incumbentCandidateID: String?
    public let incumbentFitness: Double?
    public let bestVsIncumbentDelta: Double?
    public let minimumImprovementOverIncumbent: Double?
    public let rejectionReasons: [String]

    public init(
        runID: String,
        generationIndex: Int,
        accepted: Bool,
        eliteCandidateIDs: [String],
        bestCandidateID: String?,
        bestFitness: Double?,
        incumbentCandidateID: String? = nil,
        incumbentFitness: Double? = nil,
        bestVsIncumbentDelta: Double? = nil,
        minimumImprovementOverIncumbent: Double? = nil,
        rejectionReasons: [String]
    ) {
        self.runID = runID
        self.generationIndex = max(0, generationIndex)
        self.accepted = accepted
        self.eliteCandidateIDs = eliteCandidateIDs
        self.bestCandidateID = bestCandidateID
        self.bestFitness = bestFitness
        self.incumbentCandidateID = incumbentCandidateID
        self.incumbentFitness = incumbentFitness
        self.bestVsIncumbentDelta = bestVsIncumbentDelta
        self.minimumImprovementOverIncumbent = minimumImprovementOverIncumbent
        self.rejectionReasons = rejectionReasons
    }
}

public struct EvolutionGatePolicy: Sendable {
    public let eliteCount: Int
    public let minimumTaskPassRate: Double
    public let maximumSafetyViolationRate: Double
    public let minimumHoldTimeRatio: Double?
    public let minimumRewardAverage: Double?
    public let minimumImprovementOverIncumbent: Double?
    public let minimumNoveltyScore: Double?

    public init(
        eliteCount: Int,
        minimumTaskPassRate: Double = 1.0,
        maximumSafetyViolationRate: Double = 0.0,
        minimumHoldTimeRatio: Double? = nil,
        minimumRewardAverage: Double? = nil,
        minimumImprovementOverIncumbent: Double? = nil,
        minimumNoveltyScore: Double? = nil
    ) {
        self.eliteCount = max(1, eliteCount)
        self.minimumTaskPassRate = minimumTaskPassRate
        self.maximumSafetyViolationRate = maximumSafetyViolationRate
        self.minimumHoldTimeRatio = minimumHoldTimeRatio
        self.minimumRewardAverage = minimumRewardAverage
        self.minimumImprovementOverIncumbent = minimumImprovementOverIncumbent
        self.minimumNoveltyScore = minimumNoveltyScore
    }

    public func report(
        runID: String,
        generationIndex: Int,
        fitness: [FitnessSummary],
        incumbentCandidateID: String? = nil,
        incumbentFitness knownIncumbentFitness: Double? = nil
    ) -> EvolutionGateReport {
        let validFitness = fitness.filter { summary in
            summary.scalarFitness.isFinite
                && summary.rewardAverage.isFinite
                && summary.taskPassRate.isFinite
                && summary.safetyViolationRate.isFinite
        }
        let ranked = validFitness.sorted { lhs, rhs in
            if lhs.scalarFitness == rhs.scalarFitness {
                return lhs.candidateID < rhs.candidateID
            }
            return lhs.scalarFitness > rhs.scalarFitness
        }
        let best = ranked.first
        let passing = ranked.filter { summary in
            candidatePasses(summary)
        }
        let incumbentFitness = knownIncumbentFitness ?? incumbentCandidateID.flatMap { candidateID in
            fitness.first { $0.candidateID == candidateID }?.scalarFitness
        }
        let bestVsIncumbentDelta = zipOptional(best?.scalarFitness, incumbentFitness).map { best, incumbent in
            best - incumbent
        }
        var reasons: [String] = []
        if fitness.isEmpty {
            reasons.append("empty-fitness")
        }
        if validFitness.count != fitness.count {
            reasons.append("non-finite-fitness")
        }
        if passing.isEmpty, !fitness.isEmpty {
            reasons.append("no-candidate-passed-gate")
            reasons.append(contentsOf: validFitness.flatMap(candidateRejectionReasons))
        }
        let eliteIDs = Array(passing.prefix(eliteCount).map(\.candidateID))
        return EvolutionGateReport(
            runID: runID,
            generationIndex: generationIndex,
            accepted: !eliteIDs.isEmpty && reasons.isEmpty,
            eliteCandidateIDs: eliteIDs,
            bestCandidateID: best?.candidateID,
            bestFitness: best?.scalarFitness,
            incumbentCandidateID: incumbentCandidateID,
            incumbentFitness: incumbentFitness,
            bestVsIncumbentDelta: bestVsIncumbentDelta,
            minimumImprovementOverIncumbent: minimumImprovementOverIncumbent,
            rejectionReasons: reasons
        )
    }

    private func candidatePasses(_ summary: FitnessSummary) -> Bool {
        guard summary.taskPassRate >= minimumTaskPassRate else { return false }
        guard summary.safetyViolationRate <= maximumSafetyViolationRate else { return false }
        if let minimumHoldTimeRatio {
            guard let holdTimeRatio = summary.holdTimeRatio,
                  holdTimeRatio >= minimumHoldTimeRatio else {
                return false
            }
        }
        if let minimumRewardAverage {
            guard summary.rewardAverage >= minimumRewardAverage else { return false }
        }
        if let minimumNoveltyScore {
            guard let noveltyScore = summary.noveltyScore,
                  noveltyScore.isFinite,
                  noveltyScore >= minimumNoveltyScore else {
                return false
            }
        }
        return summary.failureReasons.isEmpty
    }

    private func candidateRejectionReasons(_ summary: FitnessSummary) -> [String] {
        var reasons: [String] = []
        if summary.taskPassRate < minimumTaskPassRate {
            reasons.append("task-pass-rate-below-min:\(summary.candidateID):\(summary.taskPassRate)<\(minimumTaskPassRate)")
        }
        if summary.safetyViolationRate > maximumSafetyViolationRate {
            reasons.append("safety-violation-above-max:\(summary.candidateID):\(summary.safetyViolationRate)>\(maximumSafetyViolationRate)")
        }
        if let minimumHoldTimeRatio {
            if let holdTimeRatio = summary.holdTimeRatio {
                if holdTimeRatio < minimumHoldTimeRatio {
                    reasons.append("hold-time-below-min:\(summary.candidateID):\(holdTimeRatio)<\(minimumHoldTimeRatio)")
                }
            } else {
                reasons.append("hold-time-below-min:\(summary.candidateID):missing<\(minimumHoldTimeRatio)")
            }
        }
        if let minimumRewardAverage, summary.rewardAverage < minimumRewardAverage {
            reasons.append("reward-average-below-min:\(summary.candidateID):\(summary.rewardAverage)<\(minimumRewardAverage)")
        }
        if let minimumNoveltyScore {
            if let noveltyScore = summary.noveltyScore {
                if !noveltyScore.isFinite {
                    reasons.append("novelty-below-min:\(summary.candidateID):non-finite<\(minimumNoveltyScore)")
                } else if noveltyScore < minimumNoveltyScore {
                    reasons.append("novelty-below-min:\(summary.candidateID):\(noveltyScore)<\(minimumNoveltyScore)")
                }
            } else {
                reasons.append("novelty-below-min:\(summary.candidateID):missing<\(minimumNoveltyScore)")
            }
        }
        reasons.append(contentsOf: summary.failureReasons.map { "candidate-failure:\(summary.candidateID):\($0)" })
        return reasons
    }
}

private func zipOptional<A, B>(_ lhs: A?, _ rhs: B?) -> (A, B)? {
    guard let lhs, let rhs else { return nil }
    return (lhs, rhs)
}
