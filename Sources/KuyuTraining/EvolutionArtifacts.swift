import Foundation

public struct EvolutionRunArtifactContract: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 5
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
        to directory: URL
    ) throws
}

public struct EvolutionArtifactWriter: EvolutionArtifactWriting {
    public init() {}

    public func write(
        manifest: EvolutionRunManifest,
        generations: [PopulationGenerationRecord],
        candidates: [GenomeCandidate],
        fitness: [FitnessSummary],
        eliteArchive: EvolutionEliteArchive,
        qualityDiversityArchive: EvolutionQualityDiversityArchive,
        lineage: [EvolutionLineageRecord],
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
        try encoder.encode(Self.acceptedCheckpointDecision(
            manifest: manifest,
            generations: generations,
            candidates: candidates,
            fitness: fitness,
            eliteArchive: eliteArchive
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
        eliteArchive: EvolutionEliteArchive
    ) -> EvolutionAcceptedCheckpointDecision {
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
        if let minimumImprovementOverIncumbent,
           let incumbentFitness,
           let bestFitness = eliteArchive.bestFitness {
            improvementAccepted = bestFitness > incumbentFitness + minimumImprovementOverIncumbent
        } else {
            improvementAccepted = true
        }
        let accepted = manifest.terminalState == .completed
            && bestCandidate != nil
            && improvementAccepted
            && Self.publishMetricRegressions(best: bestFitnessSummary, incumbent: incumbentFitnessSummary).isEmpty
        var reasons: [String] = []
        if manifest.terminalState != .completed {
            reasons.append(contentsOf: generations.last?.rejectionReasons ?? [])
        }
        let publishMetricRegressions = Self.publishMetricRegressions(
            best: bestFitnessSummary,
            incumbent: incumbentFitnessSummary
        )
        reasons.append(contentsOf: publishMetricRegressions)
        if manifest.terminalState == .completed,
           !improvementAccepted,
           let minimumImprovementOverIncumbent,
           let incumbentFitness,
           let bestFitness = eliteArchive.bestFitness,
           let bestCandidateID = eliteArchive.bestCandidateID {
            reasons.append("incumbent-improvement-below-min:\(bestCandidateID):\(bestFitness)-\(incumbentFitness)<=\(minimumImprovementOverIncumbent)")
        }
        return EvolutionAcceptedCheckpointDecision(
            runID: manifest.runID,
            terminalState: manifest.terminalState,
            accepted: accepted,
            candidateID: accepted ? bestCandidate?.candidateID : nil,
            checkpointID: accepted ? bestCandidate?.checkpointID : nil,
            checkpointURL: accepted ? bestCandidate?.checkpointURL : nil,
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
