import Foundation
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement

extension LearningProjectTemplate {
    static func localCompute(
        workerCount: Int,
        candidateEvaluationConcurrency: Int
    ) -> LearningProjectComputeProfile {
        let concurrency = max(100, candidateEvaluationConcurrency)
        return LearningProjectComputeProfile(
            preset: .local,
            workerCount: 1,
            candidateEvaluationConcurrency: concurrency,
            requiresMetal: true,
            targetAccelerator: .metal,
            usesMachineOptimizedParallelism: true,
            minimumPopulationSize: concurrency,
            estimatedDiskBytes: nil
        )
    }

    static func genericSafetyGate(failOnTruncation: Bool) -> LearningProjectEvaluationGate {
        LearningProjectEvaluationGate(
            minimumRewardAverage: nil,
            minimumTaskPassRate: 1,
            minimumHoldTimeRatio: nil,
            maximumAltitudeErrorRatio: nil,
            failOnTruncation: failOnTruncation,
            requiredSafetyGates: [
                .modelBundleValidated,
                .deterministicReplayValidated,
                .scenarioRegressionPassed,
                .stressRegressionPassed,
                .safetyEnvelopeValidated,
                .telemetryComplete,
                .artifactLineageComplete
            ]
        )
    }

    static func multirotorBlueprintObservationContract(schemaID: String) -> LearningProjectObservationContract {
        LearningProjectObservationContract(
            schemaID: schemaID,
            channelCount: 16,
            channels: [
                LearningProjectObservationChannel(index: 0, name: "roll", unit: "rad", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 1, name: "pitch", unit: "rad", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 2, name: "yawRate", unit: "rad/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 3, name: "velocityX", unit: "m/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 4, name: "velocityY", unit: "m/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 5, name: "velocityZ", unit: "m/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 6, name: "targetDeltaX", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 7, name: "targetDeltaY", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 8, name: "targetDeltaZ", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 9, name: "constraintPressure", unit: nil, isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 10, name: "windEstimateX", unit: "m/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 11, name: "windEstimateY", unit: "m/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 12, name: "previousMotor0", unit: "normalized", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 13, name: "previousMotor1", unit: "normalized", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 14, name: "previousMotor2", unit: "normalized", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 15, name: "previousMotor3", unit: "normalized", isStateChannel: true, isStressable: true),
            ]
        )
    }

    static func multirotorBlueprintDirectDriveActionContract() -> LearningProjectActionContract {
        LearningProjectActionContract(
            schemaID: "multirotor-direct-drive-action-v1",
            kind: .continuous,
            driveCount: 4,
            actuatorCount: 4,
            isBounded: true,
            channels: LearningProjectActionContract.indexedBoundedChannels(
                prefix: "motorDrive",
                count: 4,
                unit: "normalized",
                lowerBound: 0,
                upperBound: 1,
                transform: .sigmoid
            )
        )
    }

    static func convergenceGoal(
        maxGenerationBudget: Int,
        patienceGenerations: Int
    ) -> LearningProjectConvergenceGoal {
        LearningProjectConvergenceGoal(
            kind: .convergence,
            targetTaskPassRate: 1,
            targetHoldTimeRatio: 1,
            maximumSafetyViolationRate: 0,
            minimumFitnessImprovement: 0.001,
            minimumTaskPassRateImprovement: 0.001,
            minimumHoldTimeRatioImprovement: 0.001,
            patienceGenerations: patienceGenerations,
            maxGenerationBudget: maxGenerationBudget
        )
    }

    static func validationGateGoal() -> LearningProjectConvergenceGoal {
        LearningProjectConvergenceGoal(
            kind: .validationGate,
            targetTaskPassRate: 1,
            targetHoldTimeRatio: 1,
            maximumSafetyViolationRate: 0,
            minimumFitnessImprovement: 0,
            minimumTaskPassRateImprovement: 0,
            minimumHoldTimeRatioImprovement: 0,
            patienceGenerations: 1,
            maxGenerationBudget: 1
        )
    }

    static func aerialNavigationObservation() -> LearningProjectObservationContract {
        LearningProjectObservationContract(
            schemaID: "aerial-navigation-observation-v1",
            channelCount: 10,
            channels: [
                LearningProjectObservationChannel(index: 0, name: "gyroX", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 1, name: "gyroY", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 2, name: "gyroZ", unit: "rad/s", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 3, name: "accelX", unit: "m/s^2", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 4, name: "accelY", unit: "m/s^2", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 5, name: "accelZ", unit: "m/s^2", isStateChannel: false, isStressable: true),
                LearningProjectObservationChannel(index: 6, name: "altitudeZ", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 7, name: "verticalVelocityZ", unit: "m/s", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 8, name: "targetDeltaXY", unit: "m", isStateChannel: true, isStressable: true),
                LearningProjectObservationChannel(index: 9, name: "constraintPressure", unit: nil, isStateChannel: false, isStressable: true)
            ]
        )
    }
}
