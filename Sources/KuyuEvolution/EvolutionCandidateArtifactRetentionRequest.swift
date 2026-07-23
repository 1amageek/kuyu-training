import Foundation

public struct EvolutionCandidateArtifactRetentionRequest: Sendable {
    public let runID: String
    public let generationIndex: Int
    public let artifactDirectory: URL
    public let candidates: [GenomeCandidate]
    public let nextPopulation: EvolutionPopulation
    public let bestCandidateID: String?
    public let incumbentCandidateID: String?
    public let protectedCandidateIDs: [String]

    public init(
        runID: String,
        generationIndex: Int,
        artifactDirectory: URL,
        candidates: [GenomeCandidate],
        nextPopulation: EvolutionPopulation,
        bestCandidateID: String?,
        incumbentCandidateID: String? = nil,
        protectedCandidateIDs: [String] = []
    ) {
        self.runID = runID
        self.generationIndex = generationIndex
        self.artifactDirectory = artifactDirectory
        self.candidates = candidates
        self.nextPopulation = nextPopulation
        self.bestCandidateID = bestCandidateID
        self.incumbentCandidateID = incumbentCandidateID
        self.protectedCandidateIDs = protectedCandidateIDs
    }
}
