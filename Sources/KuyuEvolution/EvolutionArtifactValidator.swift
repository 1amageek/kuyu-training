import Foundation
import KuyuTrainingContracts

public struct EvolutionRunArtifactValidator: Sendable {
    public enum ValidationError: Error, Sendable, Equatable {
        case missingFile(String)
        case unsupportedSchemaVersion(Int)
        case unsupportedContractVersion(Int)
        case invalidLine(file: String, line: Int)
        case emptyRunID
        case runIDMismatch(file: String, expected: String, actual: String)
        case nonTerminalManifestState(EvolutionRunTerminalState)
        case duplicateCandidateID(String)
        case duplicateFitnessSummary(String)
        case missingCandidateFitness(String)
        case nonFiniteFitness(candidateID: String)
        case unexpectedFitnessFidelity(candidateID: String)
        case screeningFitnessMissingRejection(candidateID: String)
        case duplicateLineage(String)
        case lineageMismatch(candidateID: String)
        case duplicateIncumbentCandidate(String)
        case invalidIncumbentCandidate(String)
        case duplicateCarryoverCandidate(generationIndex: Int, candidateID: String)
        case invalidCarryoverCandidate(String)
        case eliteCandidateMissing(String)
        case missingCompletedEliteArchive
        case bestCandidateMissing(String)
        case bestCandidateNotElite(String)
        case bestCandidateNotFullScenario(String)
        case bestFitnessMismatch(candidateID: String, archived: Double?, evaluated: Double?)
        case acceptedCheckpointMismatch(String)
        case acceptedCheckpointCandidateMissing(String)
        case qualityDiversityCandidateMissing(String)
        case nonFiniteQualityDiversityCell(String)
        case duplicateEvaluationTrace(String)
        case missingEvaluationTrace(String)
        case invalidEvaluationTrace(String)
        case generationImprovementMismatch(Int)
        case acceptanceModeMismatch(String)
        case duplicateAcceptanceEvaluation(generationIndex: Int, candidateID: String)
        case acceptanceCandidateMissing(String)
        case acceptanceIdentityMismatch(String)
        case nonFiniteAcceptanceFitness(String)
        case invalidAcceptanceContract(candidateID: String, reason: String)
        case invalidAcceptanceEvidence(candidateID: String, reason: String)
        case invalidCheckpointReference(candidateID: String, reason: String)
        case generationAcceptanceMismatch(Int)
    }

    public init() {}

    public func validatedBundle(in artifactDirectory: URL) throws -> EvolutionRunArtifactBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        let contract = try decode(
            EvolutionRunArtifactContract.self,
            fileName: EvolutionRunArtifactContract.fileName,
            directory: artifactDirectory,
            decoder: decoder
        )
        try validate(contract: contract, directory: artifactDirectory)
        let manifest = try decode(
            EvolutionRunManifest.self,
            fileName: "evolution-manifest.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        let generations = try loadJSONLines(
            PopulationGenerationRecord.self,
            fileName: "generations.jsonl",
            directory: artifactDirectory,
            decoder: decoder
        )
        let candidates = try loadJSONLines(
            GenomeCandidate.self,
            fileName: "candidates.jsonl",
            directory: artifactDirectory,
            decoder: decoder
        )
        let fitness = try loadJSONLines(
            FitnessSummary.self,
            fileName: "fitness.jsonl",
            directory: artifactDirectory,
            decoder: decoder
        )
        let eliteArchive = try decode(
            EvolutionEliteArchive.self,
            fileName: "elite-archive.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        let acceptedCheckpoint = try decode(
            EvolutionAcceptedCheckpointDecision.self,
            fileName: EvolutionAcceptedCheckpointDecision.fileName,
            directory: artifactDirectory,
            decoder: decoder
        )
        let qualityDiversityArchive = try decode(
            EvolutionQualityDiversityArchive.self,
            fileName: EvolutionQualityDiversityArchive.fileName,
            directory: artifactDirectory,
            decoder: decoder
        )
        let lineage = try decode(
            [EvolutionLineageRecord].self,
            fileName: "lineage.json",
            directory: artifactDirectory,
            decoder: decoder
        )
        let evaluationTraces = try loadJSONLines(
            EvolutionCandidateEvaluationTrace.self,
            fileName: "evaluation-trace.jsonl",
            directory: artifactDirectory,
            decoder: decoder
        )
        let acceptanceEvaluations = try loadJSONLines(
            EvolutionCandidateAcceptanceRecord.self,
            fileName: "acceptance-evaluations.jsonl",
            directory: artifactDirectory,
            decoder: decoder
        )
        try validate(
            manifest: manifest,
            generations: generations,
            candidates: candidates,
            fitness: fitness,
            eliteArchive: eliteArchive,
            acceptedCheckpoint: acceptedCheckpoint,
            qualityDiversityArchive: qualityDiversityArchive,
            lineage: lineage,
            evaluationTraces: evaluationTraces,
            acceptanceEvaluations: acceptanceEvaluations,
            artifactDirectory: artifactDirectory
        )
        return EvolutionRunArtifactBundle(
            artifactDirectory: artifactDirectory,
            contract: contract,
            manifest: manifest,
            generations: generations,
            candidates: candidates,
            fitness: fitness,
            eliteArchive: eliteArchive,
            acceptedCheckpoint: acceptedCheckpoint,
            qualityDiversityArchive: qualityDiversityArchive,
            lineage: lineage,
            evaluationTraces: evaluationTraces,
            acceptanceEvaluations: acceptanceEvaluations
        )
    }
}
