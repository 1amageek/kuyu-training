import Foundation

extension EvolutionRunOrchestrator {
    enum CandidateArtifactRetentionPreparationError: Error, Sendable, CustomStringConvertible {
        case reconciliation(String)
        case invalidLiveSet(String)

        var description: String {
            switch self {
            case .reconciliation(let reason):
                "candidate-artifact-retention-reconcile-failed: \(reason)"
            case .invalidLiveSet(let reason):
                "candidate-artifact-retention-live-set-invalid: \(reason)"
            }
        }
    }

    func prepareCandidateArtifactRetention(
        config: EvolutionRunConfig,
        gatePolicy: EvolutionGatePolicy,
        artifactDirectory: URL,
        expectedRunID: String,
        resume: EvolutionResumeState?
    ) throws {
        do {
            try candidateArtifactRetainer.reconcile(
                in: artifactDirectory,
                expectedRunID: expectedRunID
            )
        } catch {
            throw CandidateArtifactRetentionPreparationError.reconciliation(
                String(describing: error)
            )
        }
        guard let resume else { return }
        let request = EvolutionCandidateArtifactRetentionRequest(
            runID: resume.runID,
            generationIndex: max(0, resume.startGenerationIndex - 1),
            artifactDirectory: artifactDirectory,
            candidates: resume.candidates,
            nextPopulation: resume.currentPopulation,
            bestCandidateID: resume.bestSearchFitness?.candidateID,
            incumbentCandidateID: resume.incumbentCandidateID,
            protectedCandidateIDs: qualityDiversityCandidateIDs(
                config: config,
                fitness: resume.fitness,
                gatePolicy: gatePolicy
            )
        )
        do {
            try candidateArtifactRetainer.recover(request)
        } catch {
            throw CandidateArtifactRetentionPreparationError.invalidLiveSet(
                String(describing: error)
            )
        }
    }

    func qualityDiversityCandidateIDs(
        config: EvolutionRunConfig,
        fitness: [FitnessSummary],
        gatePolicy: EvolutionGatePolicy? = nil
    ) -> [String] {
        guard config.searchStrategy == .qualityDiversity else { return [] }
        let eligibleFitness = gatePolicy.map { policy in
            fitness.filter(policy.candidatePasses)
        } ?? fitness
        return EvolutionQualityDiversityArchiveBuilder()
            .build(runID: config.runID, fitness: eligibleFitness)
            .cells
            .map(\.candidateID)
    }
}
