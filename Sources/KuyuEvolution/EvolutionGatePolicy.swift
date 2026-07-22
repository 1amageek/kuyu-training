import Foundation
import KuyuTrainingContracts

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
    public let maximumAltitudeErrorRatio: Double?
    public let minimumRewardAverage: Double?
    public let minimumImprovementOverIncumbent: Double?
    public let minimumNoveltyScore: Double?

    public init(
        eliteCount: Int,
        minimumTaskPassRate: Double = 1.0,
        maximumSafetyViolationRate: Double = 0.0,
        minimumHoldTimeRatio: Double? = nil,
        maximumAltitudeErrorRatio: Double? = nil,
        minimumRewardAverage: Double? = nil,
        minimumImprovementOverIncumbent: Double? = nil,
        minimumNoveltyScore: Double? = nil
    ) {
        self.eliteCount = max(1, eliteCount)
        self.minimumTaskPassRate = minimumTaskPassRate
        self.maximumSafetyViolationRate = maximumSafetyViolationRate
        self.minimumHoldTimeRatio = minimumHoldTimeRatio
        self.maximumAltitudeErrorRatio = maximumAltitudeErrorRatio
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
        let passing = ranked.filter { summary in
            candidatePasses(summary)
        }
        let best = passing.first
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

    public func acceptanceReport(
        runID: String,
        candidate: FitnessSummary,
        incumbent: FitnessSummary
    ) -> EvolutionGateReport {
        let absoluteReport = report(
            runID: runID,
            generationIndex: candidate.generationIndex,
            fitness: [candidate]
        )
        let fitnessDelta = candidate.scalarFitness - incumbent.scalarFitness
        var reasons = absoluteReport.rejectionReasons
        if let minimumImprovementOverIncumbent,
           fitnessDelta <= minimumImprovementOverIncumbent {
            reasons.append(
                "incumbent-improvement-below-min:\(candidate.candidateID):"
                    + "\(candidate.scalarFitness)-\(incumbent.scalarFitness)"
                    + "<=\(minimumImprovementOverIncumbent)"
            )
        }
        reasons.append(contentsOf: acceptanceMetricRegressions(
            candidate: candidate,
            incumbent: incumbent
        ))
        return EvolutionGateReport(
            runID: runID,
            generationIndex: candidate.generationIndex,
            accepted: absoluteReport.accepted && reasons.isEmpty,
            eliteCandidateIDs: absoluteReport.accepted && reasons.isEmpty
                ? [candidate.candidateID]
                : [],
            bestCandidateID: candidate.candidateID,
            bestFitness: candidate.scalarFitness,
            incumbentCandidateID: incumbent.candidateID,
            incumbentFitness: incumbent.scalarFitness,
            bestVsIncumbentDelta: fitnessDelta,
            minimumImprovementOverIncumbent: minimumImprovementOverIncumbent,
            rejectionReasons: reasons
        )
    }

    /// Curriculum-rung acceptance: the candidate must pass the absolute gate
    /// on acceptance evidence; the incumbent is recorded for transparency but
    /// not compared. See TrainingPromotionCriterion.
    public func absoluteAcceptanceReport(
        runID: String,
        candidate: FitnessSummary,
        incumbent: FitnessSummary
    ) -> EvolutionGateReport {
        let absoluteReport = report(
            runID: runID,
            generationIndex: candidate.generationIndex,
            fitness: [candidate]
        )
        return EvolutionGateReport(
            runID: runID,
            generationIndex: candidate.generationIndex,
            accepted: absoluteReport.accepted,
            eliteCandidateIDs: absoluteReport.accepted ? [candidate.candidateID] : [],
            bestCandidateID: candidate.candidateID,
            bestFitness: candidate.scalarFitness,
            incumbentCandidateID: incumbent.candidateID,
            incumbentFitness: incumbent.scalarFitness,
            bestVsIncumbentDelta: candidate.scalarFitness - incumbent.scalarFitness,
            minimumImprovementOverIncumbent: nil,
            rejectionReasons: absoluteReport.rejectionReasons
        )
    }

    func candidatePasses(_ summary: FitnessSummary) -> Bool {
        candidatePasses(summary, requiresNovelty: true)
    }

    func candidatePassesRefinement(_ summary: FitnessSummary) -> Bool {
        candidatePasses(summary, requiresNovelty: false)
    }

    private func candidatePasses(
        _ summary: FitnessSummary,
        requiresNovelty: Bool
    ) -> Bool {
        guard summary.evaluationFidelity.isFullScenario else { return false }
        guard summary.taskPassRate >= minimumTaskPassRate else { return false }
        guard summary.safetyViolationRate <= maximumSafetyViolationRate else { return false }
        if let minimumHoldTimeRatio {
            guard let holdTimeRatio = summary.holdTimeRatio,
                  holdTimeRatio >= minimumHoldTimeRatio else {
                return false
            }
        }
        if let maximumAltitudeErrorRatio {
            guard let altitudeErrorRatio = summary.altitudeErrorRatio,
                  altitudeErrorRatio <= maximumAltitudeErrorRatio else {
                return false
            }
        }
        if let minimumRewardAverage {
            guard summary.rewardAverage >= minimumRewardAverage else { return false }
        }
        if requiresNovelty, let minimumNoveltyScore {
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
        if !summary.evaluationFidelity.isFullScenario {
            reasons.append("evaluation-fidelity-not-full-scenario:\(summary.candidateID)")
        }
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
        if let maximumAltitudeErrorRatio {
            if let altitudeErrorRatio = summary.altitudeErrorRatio {
                if altitudeErrorRatio > maximumAltitudeErrorRatio {
                    reasons.append("altitude-error-above-max:\(summary.candidateID):\(altitudeErrorRatio)>\(maximumAltitudeErrorRatio)")
                }
            } else {
                reasons.append("altitude-error-above-max:\(summary.candidateID):missing>\(maximumAltitudeErrorRatio)")
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

    private func acceptanceMetricRegressions(
        candidate: FitnessSummary,
        incumbent: FitnessSummary
    ) -> [String] {
        var reasons: [String] = []
        if candidate.taskPassRate < incumbent.taskPassRate {
            reasons.append(
                "acceptance-metric-regression:taskPassRate:"
                    + "\(candidate.taskPassRate)<\(incumbent.taskPassRate)"
            )
        }
        if candidate.safetyViolationRate > incumbent.safetyViolationRate {
            reasons.append(
                "acceptance-metric-regression:safetyViolationRate:"
                    + "\(candidate.safetyViolationRate)>\(incumbent.safetyViolationRate)"
            )
        }
        if let incumbentHoldTimeRatio = incumbent.holdTimeRatio {
            if let candidateHoldTimeRatio = candidate.holdTimeRatio {
                if candidateHoldTimeRatio < incumbentHoldTimeRatio {
                    reasons.append(
                        "acceptance-metric-regression:holdTimeRatio:"
                            + "\(candidateHoldTimeRatio)<\(incumbentHoldTimeRatio)"
                    )
                }
            } else {
                reasons.append("acceptance-metric-regression:holdTimeRatio:missing")
            }
        }
        if let incumbentAltitudeErrorRatio = incumbent.altitudeErrorRatio {
            if let candidateAltitudeErrorRatio = candidate.altitudeErrorRatio {
                if candidateAltitudeErrorRatio > incumbentAltitudeErrorRatio {
                    reasons.append(
                        "acceptance-metric-regression:altitudeErrorRatio:"
                            + "\(candidateAltitudeErrorRatio)>\(incumbentAltitudeErrorRatio)"
                    )
                }
            } else {
                reasons.append("acceptance-metric-regression:altitudeErrorRatio:missing")
            }
        }
        if candidate.rewardAverage < incumbent.rewardAverage {
            reasons.append(
                "acceptance-metric-regression:rewardAverage:"
                    + "\(candidate.rewardAverage)<\(incumbent.rewardAverage)"
            )
        }
        if let incumbentEnergyPenalty = incumbent.energyPenalty {
            if let candidateEnergyPenalty = candidate.energyPenalty {
                if candidateEnergyPenalty > incumbentEnergyPenalty {
                    reasons.append(
                        "acceptance-metric-regression:energyPenalty:"
                            + "\(candidateEnergyPenalty)>\(incumbentEnergyPenalty)"
                    )
                }
            } else {
                reasons.append("acceptance-metric-regression:energyPenalty:missing")
            }
        }
        return reasons
    }
}

private func zipOptional<A, B>(_ lhs: A?, _ rhs: B?) -> (A, B)? {
    guard let lhs, let rhs else { return nil }
    return (lhs, rhs)
}
