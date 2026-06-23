import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation
public struct AutonomousTrainingPipelineExecutionSynthesizer: Sendable {
    public init() {}

    public func makeReport(
        plan: AutonomousTrainingPipelinePlan,
        completions: [AutonomousTrainingStageCompletion],
        blocks: [AutonomousTrainingStageBlock] = [],
        satisfiedTerminalGates: [AutonomousSafetyGateKind] = []
    ) -> AutonomousTrainingPipelineExecutionReport {
        var completionsByStage: [String: AutonomousTrainingStageCompletion] = [:]
        for completion in completions where completionsByStage[completion.stageID] == nil {
            completionsByStage[completion.stageID] = completion
        }
        var blocksByStage: [String: AutonomousTrainingStageBlock] = [:]
        for block in blocks where blocksByStage[block.stageID] == nil {
            blocksByStage[block.stageID] = block
        }
        let records = plan.stages.map { stage -> AutonomousTrainingStageExecutionRecord in
            if let completion = completionsByStage[stage.stageID] {
                return AutonomousTrainingStageExecutionRecord(
                    stageID: stage.stageID,
                    kind: stage.kind,
                    status: .completed,
                    satisfiedGates: completion.satisfiedGates,
                    evidence: completion.evidence
                )
            }
            if let block = blocksByStage[stage.stageID] {
                return AutonomousTrainingStageExecutionRecord(
                    stageID: stage.stageID,
                    kind: stage.kind,
                    status: .blocked,
                    satisfiedGates: [],
                    evidence: block.evidence,
                    failureReasons: block.failureReasons
                )
            }
            return AutonomousTrainingStageExecutionRecord(
                stageID: stage.stageID,
                kind: stage.kind,
                status: .pending,
                satisfiedGates: [],
                evidence: []
            )
        }
        return AutonomousTrainingPipelineExecutionReport(
            planID: plan.planID,
            domain: plan.domain,
            stageRecords: records,
            satisfiedTerminalGates: satisfiedTerminalGates
        )
    }
}
