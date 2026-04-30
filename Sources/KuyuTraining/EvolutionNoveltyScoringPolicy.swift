import Foundation

public struct EvolutionNoveltyScoringPolicy: Sendable {
    public init() {}

    public func score(
        currentGeneration: [FitnessSummary],
        archive: [FitnessSummary]
    ) -> [FitnessSummary] {
        currentGeneration.map { summary in
            if let noveltyScore = summary.noveltyScore, noveltyScore.isFinite {
                return summary
            }
            return copy(summary, noveltyScore: noveltyScore(for: summary, currentGeneration: currentGeneration, archive: archive))
        }
    }

    private func noveltyScore(
        for summary: FitnessSummary,
        currentGeneration: [FitnessSummary],
        archive: [FitnessSummary]
    ) -> Double {
        let references = (archive + currentGeneration).filter { other in
            other.candidateID != summary.candidateID
        }
        guard !references.isEmpty else { return 1 }
        let descriptor = behaviorDescriptor(for: summary)
        let nearest = references
            .map { distance(descriptor, behaviorDescriptor(for: $0)) }
            .min() ?? 1
        return nearest.isFinite ? nearest : 0
    }

    private func behaviorDescriptor(for summary: FitnessSummary) -> [String: Double] {
        var descriptor = summary.behaviorDescriptor.filter { $0.value.isFinite }
        descriptor["taskPassRate"] = summary.taskPassRate
        descriptor["holdTimeRatio"] = summary.holdTimeRatio ?? 0
        descriptor["safetyViolationRate"] = summary.safetyViolationRate
        descriptor["rewardAverage"] = summary.rewardAverage
        return descriptor.filter { $0.value.isFinite }
    }

    private func distance(_ lhs: [String: Double], _ rhs: [String: Double]) -> Double {
        let keys = Set(lhs.keys).union(rhs.keys)
        guard !keys.isEmpty else { return 0 }
        let squared = keys.reduce(0.0) { partial, key in
            let delta = (lhs[key] ?? 0) - (rhs[key] ?? 0)
            return partial + delta * delta
        }
        return sqrt(squared / Double(keys.count))
    }

    private func copy(_ summary: FitnessSummary, noveltyScore: Double) -> FitnessSummary {
        FitnessSummary(
            runID: summary.runID,
            generationIndex: summary.generationIndex,
            candidateID: summary.candidateID,
            taskID: summary.taskID,
            scalarFitness: summary.scalarFitness,
            rewardAverage: summary.rewardAverage,
            taskPassRate: summary.taskPassRate,
            safetyViolationRate: summary.safetyViolationRate,
            holdTimeRatio: summary.holdTimeRatio,
            energyPenalty: summary.energyPenalty,
            noveltyScore: noveltyScore,
            teacherDelta: summary.teacherDelta,
            workerThroughput: summary.workerThroughput,
            behaviorDescriptor: summary.behaviorDescriptor,
            failureReasons: summary.failureReasons
        )
    }
}
