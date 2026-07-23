import Foundation
import KuyuTrainingContracts

public struct EvolutionCandidateAcceptanceRequest: Sendable, Equatable {
    public let config: EvolutionRunConfig
    public let candidate: GenomeCandidate
    public let incumbentCandidate: GenomeCandidate
    public let searchFitness: FitnessSummary
    public let artifactDirectory: URL
    public let workerCount: Int

    public init(
        config: EvolutionRunConfig,
        candidate: GenomeCandidate,
        incumbentCandidate: GenomeCandidate,
        searchFitness: FitnessSummary,
        artifactDirectory: URL,
        workerCount: Int
    ) {
        self.config = config
        self.candidate = candidate
        self.incumbentCandidate = incumbentCandidate
        self.searchFitness = searchFitness
        self.artifactDirectory = artifactDirectory
        self.workerCount = max(1, workerCount)
    }
}
