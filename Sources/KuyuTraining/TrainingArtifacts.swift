import Foundation

public protocol MetricsWriting {
    func write(
        manifest: LearningRunManifest,
        metrics: [TrainingMetricRecord],
        convergence: ConvergenceSummary,
        checkpointDecision: CheckpointDecision,
        to directory: URL
    ) throws
}

public struct TrainingRunArtifactContract: Sendable, Codable, Equatable {
    public static let currentSchemaVersion = 1
    public static let currentContractVersion = 1
    public static let fileName = "artifact-contract.json"

    public let schemaVersion: Int
    public let contractVersion: Int
    public let producer: String
    public let requiredFiles: [String]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        contractVersion: Int = Self.currentContractVersion,
        producer: String = "KuyuTraining",
        requiredFiles: [String] = [
            "manifest.json",
            "metrics.jsonl",
            "convergence.json",
            "checkpoint-decision.json",
        ]
    ) {
        self.schemaVersion = schemaVersion
        self.contractVersion = contractVersion
        self.producer = producer
        self.requiredFiles = requiredFiles
    }
}

public struct TrainingArtifactWriter: MetricsWriting {
    public init() {}

    public func write(
        manifest: LearningRunManifest,
        metrics: [TrainingMetricRecord],
        convergence: ConvergenceSummary,
        checkpointDecision: CheckpointDecision,
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        try encoder.encode(TrainingRunArtifactContract()).write(
            to: directory.appendingPathComponent(TrainingRunArtifactContract.fileName),
            options: [.atomic]
        )
        try encoder.encode(manifest).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        try encoder.encode(convergence).write(
            to: directory.appendingPathComponent("convergence.json"),
            options: [.atomic]
        )
        try encoder.encode(checkpointDecision).write(
            to: directory.appendingPathComponent("checkpoint-decision.json"),
            options: [.atomic]
        )

        let jsonlEncoder = JSONEncoder()
        jsonlEncoder.dateEncodingStrategy = .iso8601
        let records = try metrics.map { record in
            let data = try jsonlEncoder.encode(record)
            guard let line = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return line
        }
        try (records.joined(separator: "\n") + (records.isEmpty ? "" : "\n")).write(
            to: directory.appendingPathComponent("metrics.jsonl"),
            atomically: true,
            encoding: .utf8
        )
    }
}
