import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public struct AutonomousTrainingPipelineExecutionValidator: Sendable {
    public init() {}

    public func validate(
        _ report: AutonomousTrainingPipelineExecutionReport,
        plan: AutonomousTrainingPipelinePlan
    ) throws {
        guard report.schemaVersion == AutonomousTrainingPipelineExecutionReport.currentSchemaVersion else {
            throw AutonomousTrainingPipelineExecutionValidationError.schemaVersionMismatch(
                expected: AutonomousTrainingPipelineExecutionReport.currentSchemaVersion,
                actual: report.schemaVersion
            )
        }
        guard report.planID == plan.planID else {
            throw AutonomousTrainingPipelineExecutionValidationError.planIDMismatch(
                expected: plan.planID,
                actual: report.planID
            )
        }
        guard report.domain == plan.domain else {
            throw AutonomousTrainingPipelineExecutionValidationError.domainMismatch(
                expected: plan.domain,
                actual: report.domain
            )
        }
        guard report.stageRecords.count == plan.stages.count else {
            throw AutonomousTrainingPipelineExecutionValidationError.stageCountMismatch(
                expected: plan.stages.count,
                actual: report.stageRecords.count
            )
        }

        let plannedStages = Dictionary(uniqueKeysWithValues: plan.stages.map { ($0.stageID, $0) })
        var seen = Set<String>()
        for record in report.stageRecords {
            guard seen.insert(record.stageID).inserted else {
                throw AutonomousTrainingPipelineExecutionValidationError.duplicateStageRecord(record.stageID)
            }
            guard let planned = plannedStages[record.stageID] else {
                throw AutonomousTrainingPipelineExecutionValidationError.unexpectedStageRecord(record.stageID)
            }
            guard record.kind == planned.kind else {
                throw AutonomousTrainingPipelineExecutionValidationError.stageKindMismatch(
                    stageID: record.stageID,
                    expected: planned.kind,
                    actual: record.kind
                )
            }
            if record.status == .completed {
                guard !record.evidence.isEmpty else {
                    throw AutonomousTrainingPipelineExecutionValidationError.completedStageMissingEvidence(
                        stageID: record.stageID
                    )
                }
                for gate in planned.requiredExitGates where !record.satisfiedGates.contains(gate) {
                    throw AutonomousTrainingPipelineExecutionValidationError.completedStageMissingExitGate(
                        stageID: record.stageID,
                        gate: gate
                    )
                }
                let evidenceGates = Set(record.evidence.compactMap(\.safetyGate))
                for gate in record.satisfiedGates where !evidenceGates.contains(gate) {
                    throw AutonomousTrainingPipelineExecutionValidationError.completedStageMissingGateEvidence(
                        stageID: record.stageID,
                        gate: gate
                    )
                }
            }
            if record.evidence.contains(where: { $0.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                throw AutonomousTrainingPipelineExecutionValidationError.invalidEvidencePath(stageID: record.stageID)
            }
        }

        for stage in plan.stages where !seen.contains(stage.stageID) {
            throw AutonomousTrainingPipelineExecutionValidationError.missingStageRecord(stage.stageID)
        }

        for gate in report.satisfiedTerminalGates where !plan.terminalGates.contains(gate) {
            throw AutonomousTrainingPipelineExecutionValidationError.unexpectedTerminalGate(gate)
        }
    }
}
