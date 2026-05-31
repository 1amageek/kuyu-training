import Foundation
import KuyuPhysics

public struct RoArmM1JointTargetTrainingGoal: Codable, Sendable, Equatable {
    public static let canonical = RoArmM1JointTargetTrainingGoal(
        goalID: "roarm-m1-arm-gripper-target-tracking-v1",
        robotManifestID: "roarm-m1-v0",
        task: "roArmM1ArmGripperTargetTracking",
        taskProfileID: "roArmM1ArmGripperTargetTracking-v1",
        requiredReadinessLevel: .dynamicSimulation,
        observationSchemaID: "roarm-m1-arm-gripper-observation-25ch-v1",
        actionSchemaID: "roarm-m1-arm-gripper-action-v1",
        targetMeanAbsoluteErrorRadians: 1.2,
        targetMaximumAbsoluteErrorRadians: 3.2,
        minimumMovementRadians: 0.02,
        requireFiniteRecords: true,
        requireNoJointLimitViolations: true,
        efficiencyTechniques: [
            LearningProjectEfficiencyTechnique(
                techniqueID: "roarm-m1-teacher-trajectory-bootstrap-v1",
                kind: .teacherTrajectoryBootstrap,
                sourceTitle: "Learning Contact-Rich Manipulation Skills with Guided Policy Search",
                sourceURL: "https://arxiv.org/abs/1501.05611",
                implementationGoal: "Use deterministic Kuyu teacher trajectories as supervised labels before any policy-gradient refinement.",
                artifactRequirement: "records.jsonl contains driveIntents and actionValues for each arm and gripper target step."
            ),
            LearningProjectEfficiencyTechnique(
                techniqueID: "roarm-m1-hindsight-goal-relabeling-v1",
                kind: .hindsightGoalRelabeling,
                sourceTitle: "Hindsight Experience Replay",
                sourceURL: "https://arxiv.org/abs/1707.01495",
                implementationGoal: "Duplicate achieved arm poses and gripper clamp states as successful hold-goals so sparse target failures still produce useful goal-conditioned records.",
                artifactRequirement: "training report records the hindsightRecordCount and each relabeled record has zero target-error channels."
            ),
            LearningProjectEfficiencyTechnique(
                techniqueID: "roarm-m1-model-based-state-tuples-v1",
                kind: .modelBasedWarmStart,
                sourceTitle: "PILCO: A Model-Based and Data-Efficient Approach to Policy Search",
                sourceURL: "https://icml.cc/Conferences/2011/papers/323_icmlpaper.pdf",
                implementationGoal: "Persist state, action, and next-state-compatible tuples for a dynamics warm-start before expensive rollout search.",
                artifactRequirement: "records.jsonl includes physicsState, actualState, actionValues, reward, and continueValue."
            ),
            LearningProjectEfficiencyTechnique(
                techniqueID: "roarm-m1-dynamics-domain-randomization-v1",
                kind: .domainRandomization,
                sourceTitle: "Domain Randomization for Transferring Deep Neural Networks from Simulation to the Real World",
                sourceURL: "https://arxiv.org/abs/1703.06907",
                implementationGoal: "Broaden servo, inertia, mass, friction, and latency parameters only after the smoke goal is stable.",
                artifactRequirement: "template policy contract declares the randomized dynamics parameter ranges."
            ),
            LearningProjectEfficiencyTechnique(
                techniqueID: "roarm-m1-residual-refinement-v1",
                kind: .residualPolicyRefinement,
                sourceTitle: "Residual Reinforcement Learning for Robot Control",
                sourceURL: "https://arxiv.org/abs/1812.03201",
                implementationGoal: "Keep the MotorNerve and physics teacher as the base controller and train only residual corrections in later contact phases.",
                artifactRequirement: "later policies must identify the base action and residual action dimensions separately."
            )
        ]
    )

    public let goalID: String
    public let robotManifestID: String
    public let task: String
    public let taskProfileID: String
    public let requiredReadinessLevel: ReadinessLevel
    public let observationSchemaID: String
    public let actionSchemaID: String
    public let targetMeanAbsoluteErrorRadians: Double
    public let targetMaximumAbsoluteErrorRadians: Double
    public let minimumMovementRadians: Double
    public let requireFiniteRecords: Bool
    public let requireNoJointLimitViolations: Bool
    public let efficiencyTechniques: [LearningProjectEfficiencyTechnique]

    public init(
        goalID: String,
        robotManifestID: String,
        task: String,
        taskProfileID: String,
        requiredReadinessLevel: ReadinessLevel,
        observationSchemaID: String,
        actionSchemaID: String,
        targetMeanAbsoluteErrorRadians: Double,
        targetMaximumAbsoluteErrorRadians: Double,
        minimumMovementRadians: Double,
        requireFiniteRecords: Bool,
        requireNoJointLimitViolations: Bool,
        efficiencyTechniques: [LearningProjectEfficiencyTechnique]
    ) {
        self.goalID = goalID
        self.robotManifestID = robotManifestID
        self.task = task
        self.taskProfileID = taskProfileID
        self.requiredReadinessLevel = requiredReadinessLevel
        self.observationSchemaID = observationSchemaID
        self.actionSchemaID = actionSchemaID
        self.targetMeanAbsoluteErrorRadians = targetMeanAbsoluteErrorRadians
        self.targetMaximumAbsoluteErrorRadians = targetMaximumAbsoluteErrorRadians
        self.minimumMovementRadians = minimumMovementRadians
        self.requireFiniteRecords = requireFiniteRecords
        self.requireNoJointLimitViolations = requireNoJointLimitViolations
        self.efficiencyTechniques = efficiencyTechniques
    }
}
