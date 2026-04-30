import Foundation

public struct EvolutionRunArtifactContract: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 2
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
}
