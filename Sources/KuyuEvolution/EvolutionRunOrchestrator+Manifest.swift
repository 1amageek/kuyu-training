import Foundation

extension EvolutionRunOrchestrator {
    func initialManifest(config: EvolutionRunConfig) -> EvolutionRunManifest {
        EvolutionRunManifest(
            runID: config.runID,
            taskID: config.taskID,
            robotManifestID: config.robotManifestID,
            robotManifestHash: config.robotManifestHash,
            configHash: config.configHash,
            policyID: config.policyID,
            populationSize: config.populationSize,
            generationCount: config.generationCount,
            eliteCount: config.eliteCount,
            workerCount: config.workerCount,
            candidateEvaluationConcurrency: config.candidateEvaluationConcurrency,
            candidateAcceptanceMode: {
                guard let candidateAcceptanceStage else { return .searchGateOnly }
                switch candidateAcceptanceStage.promotionCriterion {
                case .incumbentRelative: return .dedicatedEvaluation
                case .absoluteThreshold: return .dedicatedAbsoluteThreshold
                }
            }(),
            searchEvaluationFidelity: config.searchEvaluationFidelity,
            searchRefinementPolicy: config.searchRefinementPolicy,
            searchStrategy: config.searchStrategy,
            bootstrapSource: config.bootstrapSource,
            worldModelUsage: config.worldModelUsage,
            antitheticSampling: config.antitheticSampling,
            commonRandomSeed: config.commonRandomSeed,
            mutationRate: config.mutationRate,
            mutationNoiseScale: config.mutationNoiseScale,
            parentCheckpointID: config.parentCheckpointID,
            startedAt: Date(),
            terminalState: .running
        )
    }
}
