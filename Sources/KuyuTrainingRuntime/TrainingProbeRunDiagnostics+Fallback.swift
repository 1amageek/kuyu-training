import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

extension TrainingProbeRunDiagnostics {
    static var empty: TrainingProbeRunDiagnostics {
        TrainingProbeRunDiagnostics(
            eventCount: 0,
            driveSampleCount: 0,
            actuatorSampleCount: 0,
            averageDriveActivation: nil,
            maxDriveActivation: nil,
            averageDriveActivationByIndex: nil,
            maxDriveActivationByIndex: nil,
            averageActuatorValue: nil,
            maxActuatorValue: nil,
            averageActuatorValueByIndex: nil,
            maxActuatorValueByIndex: nil,
            averageReflexClampMultiplier: nil,
            averageReflexDamping: nil,
            averageReflexDelta: nil,
            averageMotorRawOutput: nil,
            averageMotorSaturatedOutput: nil,
            averageMotorFinalOutput: nil,
            maxMotorFinalOutput: nil,
            averageMotorFinalOutputByIndex: nil,
            maxMotorFinalOutputByIndex: nil,
            minAltitudeZ: nil,
            maxAltitudeZ: nil,
            finalAltitudeZ: nil,
            minVerticalVelocityZ: nil,
            maxVerticalVelocityZ: nil,
            finalVerticalVelocityZ: nil,
            failureReasons: []
        )
    }

    init(
        eventCount: Int,
        driveSampleCount: Int,
        actuatorSampleCount: Int,
        averageDriveActivation: Double?,
        maxDriveActivation: Double?,
        averageDriveActivationByIndex: [Double]?,
        maxDriveActivationByIndex: [Double]?,
        averageActuatorValue: Double?,
        maxActuatorValue: Double?,
        averageActuatorValueByIndex: [Double]?,
        maxActuatorValueByIndex: [Double]?,
        averageReflexClampMultiplier: Double?,
        averageReflexDamping: Double?,
        averageReflexDelta: Double?,
        averageMotorRawOutput: Double?,
        averageMotorSaturatedOutput: Double?,
        averageMotorFinalOutput: Double?,
        maxMotorFinalOutput: Double?,
        averageMotorFinalOutputByIndex: [Double]?,
        maxMotorFinalOutputByIndex: [Double]?,
        minAltitudeZ: Double?,
        maxAltitudeZ: Double?,
        finalAltitudeZ: Double?,
        minVerticalVelocityZ: Double?,
        maxVerticalVelocityZ: Double?,
        finalVerticalVelocityZ: Double?,
        failureReasons: [String]
    ) {
        self.eventCount = eventCount
        self.driveSampleCount = driveSampleCount
        self.actuatorSampleCount = actuatorSampleCount
        self.averageDriveActivation = averageDriveActivation
        self.maxDriveActivation = maxDriveActivation
        self.averageDriveActivationByIndex = averageDriveActivationByIndex
        self.maxDriveActivationByIndex = maxDriveActivationByIndex
        self.averageActuatorValue = averageActuatorValue
        self.maxActuatorValue = maxActuatorValue
        self.averageActuatorValueByIndex = averageActuatorValueByIndex
        self.maxActuatorValueByIndex = maxActuatorValueByIndex
        self.averageReflexClampMultiplier = averageReflexClampMultiplier
        self.averageReflexDamping = averageReflexDamping
        self.averageReflexDelta = averageReflexDelta
        self.averageMotorRawOutput = averageMotorRawOutput
        self.averageMotorSaturatedOutput = averageMotorSaturatedOutput
        self.averageMotorFinalOutput = averageMotorFinalOutput
        self.maxMotorFinalOutput = maxMotorFinalOutput
        self.averageMotorFinalOutputByIndex = averageMotorFinalOutputByIndex
        self.maxMotorFinalOutputByIndex = maxMotorFinalOutputByIndex
        self.minAltitudeZ = minAltitudeZ
        self.maxAltitudeZ = maxAltitudeZ
        self.finalAltitudeZ = finalAltitudeZ
        self.minVerticalVelocityZ = minVerticalVelocityZ
        self.maxVerticalVelocityZ = maxVerticalVelocityZ
        self.finalVerticalVelocityZ = finalVerticalVelocityZ
        self.failureReasons = failureReasons
    }
}
