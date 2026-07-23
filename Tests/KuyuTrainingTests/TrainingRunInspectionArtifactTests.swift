import Foundation
import KuyuCore
import KuyuPhysics
import KuyuScenarios
import Testing
@testable import KuyuTraining

@Suite("Training run inspection artifact")
struct TrainingRunInspectionArtifactTests {
    @Test func roundTripPersistsFullEvaluationProfile() throws {
        let profile = makeProfile(rateLimitPerSecond: 200, smoothingTimeConstant: nil)
        let artifact = try makeArtifact(profile: profile)

        let data = try JSONEncoder().encode(artifact)
        let decoded = try JSONDecoder().decode(TrainingRunInspectionArtifact.self, from: data)

        #expect(decoded.profile == profile)
        #expect(decoded.profileID == "quadref-attitude-test-v1")
        #expect(decoded.profile.policyMotorNerveSettings.rateLimitPerSecond == 200)
        #expect(decoded.profile.policyMotorNerveSettings.smoothingTimeConstant == nil)
        #expect(decoded.execution.actionRealization == .temporalCTBR(.canonical))
        #expect(decoded.execution.parameters == .baseline)
        try TrainingRunInspectionArtifactValidator().validate(decoded)
    }

    @Test func validatorRejectsInvalidProfileMotorNerveContract() throws {
        let artifact = try makeArtifact(
            profile: makeProfile(rateLimitPerSecond: 0, smoothingTimeConstant: nil)
        )

        #expect {
            try TrainingRunInspectionArtifactValidator().validate(artifact)
        } throws: { error in
            guard case TrainingRunInspectionArtifactValidator.ValidationError.invalidProfileContract(
                let reason
            ) = error else {
                return false
            }
            return reason.contains("policy-motor-nerve-invalid-rate-limit")
        }
    }

    private func makeArtifact(
        profile: TaskEvaluationProfile
    ) throws -> TrainingRunInspectionArtifact {
        TrainingRunInspectionArtifact(
            runID: "inspection-run",
            origin: .trainingIteration,
            iteration: 3,
            candidateID: "candidate-3",
            checkpointPath: "/tmp/candidate-3.manasbundle",
            checkpointDigest: String(repeating: "a", count: 64),
            checkpointRole: .candidate,
            profile: profile,
            execution: TrainingRunInspectionArtifact.ExecutionDescriptor(
                actionContractSchemaID: "reference-quadrotor-body-rate-control-action-v1",
                actionRealization: .temporalCTBR(.canonical),
                parameters: .baseline,
                schedule: try SimulationSchedule.baseline(cutPeriodSteps: 2),
                determinism: .tier1Baseline,
                robotManifestID: "quadref-v0",
                motorNerveSettings: profile.policyMotorNerveSettings
            ),
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            targetSampleRateHz: 20,
            scenarios: [
                TrainingRunInspectionArtifact.Scenario(
                    scenarioID: "KUY-ATT-1/SCN-1",
                    seed: 1001,
                    configHash: String(repeating: "b", count: 64),
                    passed: true,
                    failureReason: nil,
                    failureTime: nil,
                    sourceStepCount: 1,
                    sourceTimeStep: 0.002,
                    sourcePhysicsTimeStep: 0.001,
                    sourceControlPeriodSteps: 2,
                    samples: [
                        TrainingRunInspectionArtifact.Sample(
                            step: try makeStep(),
                            safetyCost: 0,
                            constraintViolationIDs: []
                        ),
                    ]
                ),
            ]
        )
    }

    private func makeProfile(
        rateLimitPerSecond: Double,
        smoothingTimeConstant: Double?
    ) -> TaskEvaluationProfile {
        TaskEvaluationProfile(
            family: .referenceQuadrotor,
            profileID: "quadref-attitude-test-v1",
            task: "attitude",
            observationChannelCount: 16,
            baseEvaluationSuiteIDs: [1],
            regressionSuiteIDs: [6, 7, 8],
            baselineMotorNerveSettings: TaskMotorNerveSettings(
                rateLimitPerSecond: 100,
                smoothingTimeConstant: nil
            ),
            policyMotorNerveSettings: TaskMotorNerveSettings(
                rateLimitPerSecond: rateLimitPerSecond,
                smoothingTimeConstant: smoothingTimeConstant
            ),
            minimumRewardAverage: nil,
            minimumTaskPassRate: 1,
            minimumHoldTimeRatio: nil,
            maximumAltitudeErrorRatio: nil,
            failOnTruncation: false,
            requiresReferenceTaskPass: true,
            requiresParentCheckpointEvaluation: false
        )
    }

    private func makeStep() throws -> WorldStepLog {
        WorldStepLog(
            time: try WorldTime(stepIndex: 0, time: 0),
            events: [.timeAdvance],
            sensorSamples: [],
            driveIntents: [],
            reflexCorrections: [],
            actuatorValues: [],
            actuatorTelemetry: ActuatorTelemetrySnapshot(channels: []),
            safetyTrace: try SafetyTrace(omegaMagnitude: 0, tiltRadians: 0),
            plantState: PlantStateSnapshot(
                root: RigidBodySnapshot(
                    id: "root",
                    position: Axis3(x: 0, y: 0, z: 2),
                    velocity: Axis3(x: 0, y: 0, z: 0),
                    orientation: QuaternionSnapshot(w: 1, x: 0, y: 0, z: 0),
                    angularVelocity: Axis3(x: 0, y: 0, z: 0)
                )
            ),
            disturbances: DisturbanceSnapshot(
                forceWorld: Axis3(x: 0, y: 0, z: 0),
                torqueBody: Axis3(x: 0, y: 0, z: 0)
            )
        )
    }
}
