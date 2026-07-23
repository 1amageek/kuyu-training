import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public struct TrainingProbeArtifactWriter: Sendable {
    public init() {}

    public func write(result: TrainingProbeResult, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(result.manifest).write(
            to: directory.appendingPathComponent("probe-manifest.json"),
            options: [.atomic]
        )
        try encoder.encode(result.teacher).write(
            to: directory.appendingPathComponent("teacher-run.json"),
            options: [.atomic]
        )
        try encoder.encode(result.initial).write(
            to: directory.appendingPathComponent("initial-run.json"),
            options: [.atomic]
        )
        if let trained = result.trained {
            try encoder.encode(trained).write(
                to: directory.appendingPathComponent("trained-run.json"),
                options: [.atomic]
            )
        }
        try encoder.encode(result.comparison).write(
            to: directory.appendingPathComponent("comparison.json"),
            options: [.atomic]
        )
        try writeProbeMetrics(result.comparison.metricRecords(), to: directory)
        try encoder.encode(result.probeCheckpointDecision).write(
            to: directory.appendingPathComponent("probe-checkpoint-decision.json"),
            options: [.atomic]
        )
        try encoder.encode(result.recoveryRelabelStatus).write(
            to: directory.appendingPathComponent("recovery-relabel-status.json"),
            options: [.atomic]
        )
    }

    private func writeProbeMetrics(_ metrics: [TrainingMetricRecord], to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let records = try metrics.map { record in
            let data = try encoder.encode(record)
            guard let line = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return line
        }
        try (records.joined(separator: "\n") + (records.isEmpty ? "" : "\n")).write(
            to: directory.appendingPathComponent("probe-metrics.jsonl"),
            atomically: true,
            encoding: .utf8
        )
    }
}
