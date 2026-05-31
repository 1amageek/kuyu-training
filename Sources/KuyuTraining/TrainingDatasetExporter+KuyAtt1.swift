import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios

public extension TrainingDatasetExporter {
    @discardableResult
    func write(
        output: KuyAtt1RunOutput,
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
        let terminalFactsMap = Dictionary(
            output.result.evaluations.map { evaluation in
                (
                    ScenarioKey(scenarioId: evaluation.scenarioId, seed: evaluation.seed),
                    ScenarioTerminalFacts(evaluation: evaluation)
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
        return try write(
            entries: output.logs,
            to: directory,
            observationByScenarioKey: observationMap,
            provenanceByScenarioKey: provenanceMap,
            terminalFactsByScenarioKey: terminalFactsMap
        )
    }
}
