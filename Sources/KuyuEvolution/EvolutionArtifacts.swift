import Foundation
import KuyuTrainingContracts

public struct EvolutionRunArtifactContract: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 12
    public static let currentContractVersion = 1
    public static let fileName = "evolution-contract.json"

    public let schemaVersion: Int
    public let contractVersion: Int
    public let producer: String
    public let requiredFiles: [String]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        contractVersion: Int = Self.currentContractVersion,
        producer: String = "KuyuTraining",
        requiredFiles: [String] = [
            "evolution-manifest.json",
            "generations.jsonl",
            "candidates.jsonl",
            "fitness.jsonl",
            "elite-archive.json",
            EvolutionAcceptedCheckpointDecision.fileName,
            "quality-diversity-archive.json",
            "lineage.json",
            "evaluation-trace.jsonl",
            "acceptance-evaluations.jsonl",
        ]
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.producer = producer
        self.requiredFiles = requiredFiles
    }
}

public struct EvolutionAcceptedCheckpointDecision: Sendable, Codable, Equatable {
    public static let fileName = "accepted-checkpoint.json"

    public let runID: String
    public let terminalState: EvolutionRunTerminalState
    public let accepted: Bool
    public let candidateID: String?
    public let checkpointID: String?
    public let checkpointURL: URL?
    public let checkpointReference: EvolutionCheckpointReference?
    public let scalarFitness: Double?
    public let bestCandidateID: String?
    public let bestCheckpointID: String?
    public let bestCheckpointURL: URL?
    public let bestFitness: Double?
    public let incumbentCandidateID: String?
    public let incumbentFitness: Double?
    public let bestVsIncumbentDelta: Double?
    public let minimumImprovementOverIncumbent: Double?
    public let publishMetricRegressions: [String]
    public let reasons: [String]

    public init(
        runID: String,
        terminalState: EvolutionRunTerminalState,
        accepted: Bool,
        candidateID: String?,
        checkpointID: String?,
        checkpointURL: URL?,
        checkpointReference: EvolutionCheckpointReference? = nil,
        scalarFitness: Double?,
        bestCandidateID: String? = nil,
        bestCheckpointID: String? = nil,
        bestCheckpointURL: URL? = nil,
        bestFitness: Double? = nil,
        incumbentCandidateID: String?,
        incumbentFitness: Double?,
        bestVsIncumbentDelta: Double?,
        minimumImprovementOverIncumbent: Double? = nil,
        publishMetricRegressions: [String] = [],
        reasons: [String]
    ) {
        self.runID = runID
        self.terminalState = terminalState
        self.accepted = accepted
        self.candidateID = candidateID
        self.checkpointID = checkpointID
        self.checkpointURL = checkpointURL
        self.checkpointReference = checkpointReference
        self.scalarFitness = scalarFitness
        self.bestCandidateID = bestCandidateID
        self.bestCheckpointID = bestCheckpointID
        self.bestCheckpointURL = bestCheckpointURL
        self.bestFitness = bestFitness
        self.incumbentCandidateID = incumbentCandidateID
        self.incumbentFitness = incumbentFitness
        self.bestVsIncumbentDelta = bestVsIncumbentDelta
        self.minimumImprovementOverIncumbent = minimumImprovementOverIncumbent
        self.publishMetricRegressions = publishMetricRegressions
        self.reasons = reasons
    }
}

public struct EvolutionEliteArchive: Sendable, Codable, Equatable {
    public let runID: String
    public let eliteCandidateIDs: [String]
    public let bestCandidateID: String?
    public let bestFitness: Double?

    public init(
        runID: String,
        eliteCandidateIDs: [String],
        bestCandidateID: String?,
        bestFitness: Double?
    ) {
        self.runID = runID
        self.eliteCandidateIDs = eliteCandidateIDs
        self.bestCandidateID = bestCandidateID
        self.bestFitness = bestFitness
    }
}

public struct EvolutionLineageRecord: Sendable, Codable, Equatable {
    public let runID: String
    public let generationIndex: Int
    public let candidateID: String
    public let genomeID: String
    public let parentCandidateIDs: [String]

    public init(
        runID: String,
        generationIndex: Int,
        candidateID: String,
        genomeID: String,
        parentCandidateIDs: [String]
    ) {
        self.runID = runID
        self.generationIndex = max(0, generationIndex)
        self.candidateID = candidateID
        self.genomeID = genomeID
        self.parentCandidateIDs = parentCandidateIDs
    }
}

public protocol EvolutionArtifactWriting {
    func write(
        manifest: EvolutionRunManifest,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive,
        qualityDiversityArchive: EvolutionQualityDiversityArchive,
        lineage: [EvolutionLineageRecord],
        evaluationTraces: [EvolutionCandidateEvaluationTrace],
        acceptanceEvaluations: [EvolutionCandidateAcceptanceRecord],
        to directory: URL
    ) throws
}

public struct EvolutionArtifactWriter: EvolutionArtifactWriting {
    public enum WriteError: Error, Sendable, Equatable {
        case acceptedCheckpointReferenceMissing(String)
    }

    public init() {}

    public func write(
        manifest: EvolutionRunManifest,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive,
        qualityDiversityArchive: EvolutionQualityDiversityArchive,
        lineage: [EvolutionLineageRecord],
        evaluationTraces: [EvolutionCandidateEvaluationTrace],
        acceptanceEvaluations: [EvolutionCandidateAcceptanceRecord],
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        try encoder.encode(EvolutionRunArtifactContract()).write(
            to: directory.appendingPathComponent(EvolutionRunArtifactContract.fileName),
            options: [.atomic]
        )
        try encoder.encode(manifest).write(
            to: directory.appendingPathComponent("evolution-manifest.json"),
            options: [.atomic]
        )
        try encoder.encode(eliteArchive).write(
            to: directory.appendingPathComponent("elite-archive.json"),
            options: [.atomic]
        )
        try encoder.encode(try Self.acceptedCheckpointDecision(
            manifest: manifest,
            generations: generations,
            candidates: candidates,
            fitness: fitness,
            eliteArchive: eliteArchive,
            acceptanceEvaluations: acceptanceEvaluations,
            artifactDirectory: directory
        )).write(
            to: directory.appendingPathComponent(EvolutionAcceptedCheckpointDecision.fileName),
            options: [.atomic]
        )
        try encoder.encode(qualityDiversityArchive).write(
            to: directory.appendingPathComponent(EvolutionQualityDiversityArchive.fileName),
            options: [.atomic]
        )
        try encoder.encode(lineage).write(
            to: directory.appendingPathComponent("lineage.json"),
            options: [.atomic]
        )
        try writeJSONLines(generations, to: directory.appendingPathComponent("generations.jsonl"))
        try writeJSONLines(candidates, to: directory.appendingPathComponent("candidates.jsonl"))
        try writeJSONLines(fitness, to: directory.appendingPathComponent("fitness.jsonl"))
        try writeJSONLines(evaluationTraces, to: directory.appendingPathComponent("evaluation-trace.jsonl"))
        try writeJSONLines(
            acceptanceEvaluations,
            to: directory.appendingPathComponent("acceptance-evaluations.jsonl")
        )
    }

    private func writeJSONLines<T: Encodable>(_ records: [T], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        let lines = try records.map { record in
            let data = try encoder.encode(record)
            guard let line = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return line
        }
        try (lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")).write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
    }

    private static func acceptedCheckpointDecision(
        manifest: EvolutionRunManifest,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive,
        acceptanceEvaluations: [EvolutionCandidateAcceptanceRecord],
        artifactDirectory: URL
    ) throws -> EvolutionAcceptedCheckpointDecision {
        let bestCandidate = eliteArchive.bestCandidateID.flatMap { candidateID in
            candidates.first { $0.candidateID == candidateID }
        }
        let bestFitnessSummary = eliteArchive.bestCandidateID.flatMap { candidateID in
            fitness.first { $0.candidateID == candidateID }
        }
        let incumbentCandidate = candidates.first { $0.isIncumbent == true }
        let incumbentFitnessSummary = incumbentCandidate.flatMap { candidate in
            fitness.first { $0.candidateID == candidate.candidateID }
        }
        let incumbentFitness = incumbentFitnessSummary?.scalarFitness
        let bestVsIncumbentDelta = zipOptional(
            eliteArchive.bestFitness,
            incumbentFitness
        ).map { best, incumbent in best - incumbent }
        let minimumImprovementOverIncumbent = generations.last?.minimumImprovementOverIncumbent
        let improvementAccepted: Bool
        switch manifest.candidateAcceptanceMode {
        case .searchGateOnly:
            if let minimumImprovementOverIncumbent,
               let incumbentFitness,
               let bestFitness = eliteArchive.bestFitness {
                improvementAccepted = bestFitness > incumbentFitness + minimumImprovementOverIncumbent
            } else {
                improvementAccepted = true
            }
        case .dedicatedEvaluation, .dedicatedAbsoluteThreshold:
            improvementAccepted = true
        }
        let candidateAcceptanceSatisfied: Bool
        switch manifest.candidateAcceptanceMode {
        case .searchGateOnly:
            candidateAcceptanceSatisfied = false
        case .dedicatedEvaluation, .dedicatedAbsoluteThreshold:
            candidateAcceptanceSatisfied = eliteArchive.bestCandidateID.map { candidateID in
                acceptanceEvaluations.contains { record in
                    record.candidateID == candidateID && record.accepted
                }
            } ?? false
        }
        let publishMetricRegressions = manifest.candidateAcceptanceMode == .searchGateOnly
            ? Self.publishMetricRegressions(best: bestFitnessSummary, incumbent: incumbentFitnessSummary)
            : []
        let accepted = manifest.terminalState == .completed
            && bestCandidate != nil
            && improvementAccepted
            && candidateAcceptanceSatisfied
            && publishMetricRegressions.isEmpty
        var reasons: [String] = []
        if manifest.terminalState != .completed {
            reasons.append(contentsOf: generations.last?.rejectionReasons ?? [])
        }
        reasons.append(contentsOf: publishMetricRegressions)
        if manifest.terminalState == .completed,
           manifest.candidateAcceptanceMode == .searchGateOnly {
            reasons.append("dedicated-acceptance-required")
        }
        if manifest.candidateAcceptanceMode == .dedicatedEvaluation,
           let bestCandidateID = eliteArchive.bestCandidateID,
           !candidateAcceptanceSatisfied {
            let acceptanceReasons = acceptanceEvaluations
                .filter { $0.candidateID == bestCandidateID }
                .flatMap(\.rejectionReasons)
            reasons.append(contentsOf: acceptanceReasons.map { "acceptance:\($0)" })
        }
        if manifest.terminalState == .completed,
           manifest.candidateAcceptanceMode == .searchGateOnly,
           !improvementAccepted,
           let minimumImprovementOverIncumbent,
           let incumbentFitness,
           let bestFitness = eliteArchive.bestFitness,
           let bestCandidateID = eliteArchive.bestCandidateID {
            reasons.append("incumbent-improvement-below-min:\(bestCandidateID):\(bestFitness)-\(incumbentFitness)<\(minimumImprovementOverIncumbent)")
        }
        let checkpointReference: EvolutionCheckpointReference?
        if accepted, let bestCandidate,
           let checkpointID = bestCandidate.checkpointID,
           let checkpointURL = bestCandidate.checkpointURL {
            switch manifest.candidateAcceptanceMode {
            case .searchGateOnly:
                checkpointReference = try EvolutionCheckpointIntegrity().reference(
                    checkpointID: checkpointID,
                    checkpointURL: checkpointURL,
                    artifactRoot: artifactDirectory
                )
            case .dedicatedEvaluation, .dedicatedAbsoluteThreshold:
                guard let reference = acceptanceEvaluations.first(where: {
                    $0.candidateID == bestCandidate.candidateID && $0.accepted
                })?.checkpointReference else {
                    throw WriteError.acceptedCheckpointReferenceMissing(bestCandidate.candidateID)
                }
                try EvolutionCheckpointIntegrity().validate(
                    reference,
                    expectedCheckpointID: checkpointID,
                    expectedCheckpointURL: checkpointURL,
                    artifactRoot: artifactDirectory
                )
                checkpointReference = reference
            }
        } else {
            checkpointReference = nil
        }
        return EvolutionAcceptedCheckpointDecision(
            runID: manifest.runID,
            terminalState: manifest.terminalState,
            accepted: accepted,
            candidateID: accepted ? bestCandidate?.candidateID : nil,
            checkpointID: accepted ? bestCandidate?.checkpointID : nil,
            checkpointURL: accepted ? bestCandidate?.checkpointURL : nil,
            checkpointReference: checkpointReference,
            scalarFitness: accepted ? eliteArchive.bestFitness : nil,
            bestCandidateID: bestCandidate?.candidateID,
            bestCheckpointID: bestCandidate?.checkpointID,
            bestCheckpointURL: bestCandidate?.checkpointURL,
            bestFitness: eliteArchive.bestFitness,
            incumbentCandidateID: incumbentCandidate?.candidateID,
            incumbentFitness: incumbentFitness,
            bestVsIncumbentDelta: bestVsIncumbentDelta,
            minimumImprovementOverIncumbent: minimumImprovementOverIncumbent,
            publishMetricRegressions: publishMetricRegressions,
            reasons: reasons
        )
    }

    private static func publishMetricRegressions(
        best: FitnessSummary?,
        incumbent: FitnessSummary?
    ) -> [String] {
        guard let best, let incumbent else { return [] }
        var reasons: [String] = []
        if best.taskPassRate < incumbent.taskPassRate {
            reasons.append("publish-metric-regression:taskPassRate:\(best.taskPassRate)<\(incumbent.taskPassRate)")
        }
        if best.safetyViolationRate > incumbent.safetyViolationRate {
            reasons.append("publish-metric-regression:safetyViolationRate:\(best.safetyViolationRate)>\(incumbent.safetyViolationRate)")
        }
        if let bestHoldTimeRatio = best.holdTimeRatio,
           let incumbentHoldTimeRatio = incumbent.holdTimeRatio,
           bestHoldTimeRatio < incumbentHoldTimeRatio {
            reasons.append("publish-metric-regression:holdTimeRatio:\(bestHoldTimeRatio)<\(incumbentHoldTimeRatio)")
        }
        if !best.failureReasons.isEmpty {
            reasons.append("publish-metric-regression:failureReasons:\(best.failureReasons.joined(separator: ","))")
        }
        return reasons
    }
}

private func zipOptional<A, B>(_ lhs: A?, _ rhs: B?) -> (A, B)? {
    guard let lhs, let rhs else { return nil }
    return (lhs, rhs)
}
