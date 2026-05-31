import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios

public struct TrainingDatasetExporter {
    public init() {}

    @discardableResult
    public func write(
        entries: [ScenarioLogEntry],
        to directory: URL,
        observationByScenarioKey: [ScenarioKey: TrainingObservationMetadata] = [:],
        provenanceByScenarioKey: [ScenarioKey: TrainingProvenanceManifest] = [:],
        terminalFactsByScenarioKey: [ScenarioKey: ScenarioTerminalFacts] = [:],
        rewardDescriptorByScenarioKey: [ScenarioKey: RewardDescriptor] = [:],
        taskReferenceByScenarioKey: [ScenarioKey: TrainingTaskReferenceMetadata] = [:],
        policyId: String? = nil
    ) throws -> [ScenarioKey: URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let writer = TrainingDatasetWriter()
        var outputs: [ScenarioKey: URL] = [:]

        for entry in entries {
            let subdir = directory.appendingPathComponent(subdirectoryName(for: entry.key), isDirectory: true)
            let url = try writer.write(
                log: entry.log,
                to: subdir,
                observation: observationByScenarioKey[entry.key],
                provenance: provenanceByScenarioKey[entry.key],
                policyId: policyId,
                terminalFacts: terminalFactsByScenarioKey[entry.key],
                rewardDescriptor: rewardDescriptorByScenarioKey[entry.key],
                taskReference: taskReferenceByScenarioKey[entry.key]
            )
            outputs[entry.key] = url
        }

        return outputs
    }

    private func subdirectoryName(for key: ScenarioKey) -> String {
        let raw = key.scenarioId.rawValue
        let sanitized = raw
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        return "\(sanitized)_seed_\(key.seed.rawValue)"
    }
}
