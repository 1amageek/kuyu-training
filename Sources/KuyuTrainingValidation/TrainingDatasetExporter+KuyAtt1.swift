import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

public extension TrainingDatasetExporter {
    @discardableResult
    func write(
        output: TrainingScenarioRunOutput,
        to directory: URL,
        observation: TrainingObservationMetadata? = nil,
        provenance: TrainingProvenanceManifest? = nil
    ) throws -> [ScenarioKey: URL] {
        let observationMap: [ScenarioKey: TrainingObservationMetadata]
        let provenanceMap: [ScenarioKey: TrainingProvenanceManifest]
        if let observation {
            observationMap = Dictionary(output.logs.map { ($0.key, observation) }, uniquingKeysWith: { first, _ in first })
        } else {
            observationMap = [:]
        }
        if let provenance {
            provenanceMap = Dictionary(output.logs.map { ($0.key, provenance) }, uniquingKeysWith: { first, _ in first })
        } else {
            provenanceMap = [:]
        }
        return try write(
            entries: output.logs,
            to: directory,
            observationByScenarioKey: observationMap,
            provenanceByScenarioKey: provenanceMap,
            terminalFactsByScenarioKey: output.terminalFactsByScenarioKey
        )
    }

    @discardableResult
    func write(
        output: KuyAtt1RunOutput,
        to directory: URL,
        observation: TrainingObservationMetadata? = nil,
        provenance: TrainingProvenanceManifest? = nil
    ) throws -> [ScenarioKey: URL] {
        return try write(
            output: TrainingScenarioRunOutput(kuyAtt1: output),
            to: directory,
            observation: observation,
            provenance: provenance
        )
    }
}
