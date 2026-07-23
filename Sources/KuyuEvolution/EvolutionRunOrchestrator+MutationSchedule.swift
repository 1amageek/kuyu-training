import Foundation
import KuyuTrainingContracts

extension EvolutionRunOrchestrator {
    func bestFitnessSummary(
        current: FitnessSummary?,
        candidateFitness: [FitnessSummary]
    ) -> FitnessSummary? {
        candidateFitness.reduce(current) { currentBest, candidate in
            guard candidate.scalarFitness.isFinite else { return currentBest }
            guard let currentBest else { return candidate }
            if candidate.scalarFitness == currentBest.scalarFitness {
                return candidate.candidateID < currentBest.candidateID ? candidate : currentBest
            }
            return candidate.scalarFitness > currentBest.scalarFitness ? candidate : currentBest
        }
    }

    func commonRandomSeed(config: EvolutionRunConfig, generationIndex: Int) -> UInt64 {
        config.commonRandomSeed &+ UInt64(max(0, generationIndex)) &* 1_099_511_628_211
    }

    func nextMutationSchedule(
        config: EvolutionRunConfig,
        currentMutationRate: Double,
        currentMutationNoiseScale: Double,
        gateReport: EvolutionGateReport
    ) -> (mutationRate: Double, mutationNoiseScale: Double) {
        guard config.adaptiveMutation.enabled else {
            return (currentMutationRate, currentMutationNoiseScale)
        }
        let factor = shouldDecayMutation(gateReport: gateReport)
            ? config.adaptiveMutation.decayFactor
            : config.adaptiveMutation.increaseFactor
        let mutationRate = clamp(
            currentMutationRate * factor,
            min: config.adaptiveMutation.minimumMutationRate,
            max: config.adaptiveMutation.maximumMutationRate
        )
        let mutationNoiseScale = clamp(
            currentMutationNoiseScale * factor,
            min: config.adaptiveMutation.minimumNoiseScale,
            max: config.adaptiveMutation.maximumNoiseScale
        )
        return (mutationRate, mutationNoiseScale)
    }

    private func shouldDecayMutation(gateReport: EvolutionGateReport) -> Bool {
        guard gateReport.accepted else { return false }
        guard let bestVsIncumbentDelta = gateReport.bestVsIncumbentDelta else {
            return true
        }
        let minimumImprovement = gateReport.minimumImprovementOverIncumbent ?? 0
        return bestVsIncumbentDelta > minimumImprovement
    }

    func incumbentImproved(gateReport: EvolutionGateReport) -> Bool {
        guard let bestVsIncumbentDelta = gateReport.bestVsIncumbentDelta else {
            return false
        }
        let minimumImprovement = gateReport.minimumImprovementOverIncumbent ?? 0
        return bestVsIncumbentDelta > minimumImprovement
    }
}
