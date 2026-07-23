import Foundation
import KuyuTrainingContracts

public struct EvolutionCandidateAcceptanceRecord: Sendable, Codable, Equatable {
    public let runID: String
    public let generationIndex: Int
    public let candidateID: String
    public let fitness: FitnessSummary
    public let checkpointReference: EvolutionCheckpointReference
    public let incumbentCandidateID: String
    public let incumbentFitness: FitnessSummary
    public let incumbentCheckpointReference: EvolutionCheckpointReference
    public let evaluationContract: EvolutionCandidateAcceptanceEvaluationContract
    public let evidence: [EvolutionCandidateAcceptanceEvidenceReference]
    public let accepted: Bool
    public let rejectionReasons: [String]
    public let completedAt: Date

    public init(
        runID: String,
        generationIndex: Int,
        candidateID: String,
        fitness: FitnessSummary,
        checkpointReference: EvolutionCheckpointReference,
        incumbentCandidateID: String,
        incumbentFitness: FitnessSummary,
        incumbentCheckpointReference: EvolutionCheckpointReference,
        evaluationContract: EvolutionCandidateAcceptanceEvaluationContract,
        evidence: [EvolutionCandidateAcceptanceEvidenceReference],
        accepted: Bool,
        rejectionReasons: [String],
        completedAt: Date = Date()
    ) {
        self.runID = runID
        self.generationIndex = max(0, generationIndex)
        self.candidateID = candidateID
        self.fitness = fitness
        self.checkpointReference = checkpointReference
        self.incumbentCandidateID = incumbentCandidateID
        self.incumbentFitness = incumbentFitness
        self.incumbentCheckpointReference = incumbentCheckpointReference
        self.evaluationContract = evaluationContract
        self.evidence = evidence
        self.accepted = accepted
        self.rejectionReasons = rejectionReasons
        self.completedAt = completedAt
    }
}
