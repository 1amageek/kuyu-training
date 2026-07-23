import Foundation
import KuyuScenarios
import KuyuTrainingContracts
import KuyuEvolution
import KuyuReinforcement
import KuyuTrainingValidation

public struct TrainingProbeRunDiagnostics: Sendable, Codable, Equatable {
    public let eventCount: Int
    public let driveSampleCount: Int
    public let actuatorSampleCount: Int
    public let averageDriveActivation: Double?
    public let maxDriveActivation: Double?
    public let averageDriveActivationByIndex: [Double]?
    public let maxDriveActivationByIndex: [Double]?
    public let averageActuatorValue: Double?
    public let maxActuatorValue: Double?
    public let averageActuatorValueByIndex: [Double]?
    public let maxActuatorValueByIndex: [Double]?
    public let averageReflexClampMultiplier: Double?
    public let averageReflexDamping: Double?
    public let averageReflexDelta: Double?
    public let averageMotorRawOutput: Double?
    public let averageMotorSaturatedOutput: Double?
    public let averageMotorFinalOutput: Double?
    public let maxMotorFinalOutput: Double?
    public let averageMotorFinalOutputByIndex: [Double]?
    public let maxMotorFinalOutputByIndex: [Double]?
    public let minAltitudeZ: Double?
    public let maxAltitudeZ: Double?
    public let finalAltitudeZ: Double?
    public let minVerticalVelocityZ: Double?
    public let maxVerticalVelocityZ: Double?
    public let finalVerticalVelocityZ: Double?
    public let failureReasons: [String]

    public init(output: TrainingScenarioRunOutput) {
        let events = output.logs.flatMap(\.log.events)
        let driveActivations = events.flatMap { event in
            event.driveIntents.map(\.activation)
        }
        let driveActivationsByIndex = events.flatMap(\.driveIntents).map { drive in
            IndexedDouble(index: Int(drive.index.rawValue), value: drive.activation)
        }
        let actuatorValues = events.flatMap { event in
            event.actuatorValues.map(\.value)
        }
        let actuatorValuesByIndex = events.flatMap(\.actuatorValues).map { actuator in
            IndexedDouble(index: Int(actuator.index.rawValue), value: actuator.value)
        }
        let corrections = events.flatMap(\.reflexCorrections)
        let rawMotorOutputs = events.flatMap { event in
            event.motorNerveTrace?.uRaw ?? []
        }
        let saturatedMotorOutputs = events.flatMap { event in
            event.motorNerveTrace?.uSat ?? []
        }
        let finalMotorOutputs = events.flatMap { event in
            event.motorNerveTrace?.uOut ?? []
        }
        let finalMotorOutputsByIndex = events.flatMap { event in
            (event.motorNerveTrace?.uOut ?? []).enumerated().map { index, value in
                IndexedDouble(index: index, value: value)
            }
        }
        let altitudes = events.map { $0.plantState.root.position.z }
        let verticalVelocities = events.map { $0.plantState.root.velocity.z }
        let evaluationFailures = output.summary.evaluations.flatMap(\.failures)
        let logFailures = output.logs.compactMap { entry in
            entry.log.failureReason?.rawValue
        }

        self.eventCount = events.count
        self.driveSampleCount = driveActivations.count
        self.actuatorSampleCount = actuatorValues.count
        self.averageDriveActivation = Self.average(driveActivations)
        self.maxDriveActivation = driveActivations.max()
        self.averageDriveActivationByIndex = Self.averageByIndex(driveActivationsByIndex)
        self.maxDriveActivationByIndex = Self.maxByIndex(driveActivationsByIndex)
        self.averageActuatorValue = Self.average(actuatorValues)
        self.maxActuatorValue = actuatorValues.max()
        self.averageActuatorValueByIndex = Self.averageByIndex(actuatorValuesByIndex)
        self.maxActuatorValueByIndex = Self.maxByIndex(actuatorValuesByIndex)
        self.averageReflexClampMultiplier = Self.average(corrections.map(\.clampMultiplier))
        self.averageReflexDamping = Self.average(corrections.map(\.damping))
        self.averageReflexDelta = Self.average(corrections.map(\.delta))
        self.averageMotorRawOutput = Self.average(rawMotorOutputs)
        self.averageMotorSaturatedOutput = Self.average(saturatedMotorOutputs)
        self.averageMotorFinalOutput = Self.average(finalMotorOutputs)
        self.maxMotorFinalOutput = finalMotorOutputs.max()
        self.averageMotorFinalOutputByIndex = Self.averageByIndex(finalMotorOutputsByIndex)
        self.maxMotorFinalOutputByIndex = Self.maxByIndex(finalMotorOutputsByIndex)
        self.minAltitudeZ = altitudes.min()
        self.maxAltitudeZ = altitudes.max()
        self.finalAltitudeZ = altitudes.last
        self.minVerticalVelocityZ = verticalVelocities.min()
        self.maxVerticalVelocityZ = verticalVelocities.max()
        self.finalVerticalVelocityZ = verticalVelocities.last
        self.failureReasons = Array(Set(evaluationFailures + logFailures)).sorted()
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func averageByIndex(_ values: [IndexedDouble]) -> [Double]? {
        let grouped = groupedByIndex(values)
        guard !grouped.isEmpty else { return nil }
        return grouped.map { average($0) ?? 0 }
    }

    private static func maxByIndex(_ values: [IndexedDouble]) -> [Double]? {
        let grouped = groupedByIndex(values)
        guard !grouped.isEmpty else { return nil }
        return grouped.map { $0.max() ?? 0 }
    }

    private static func groupedByIndex(_ values: [IndexedDouble]) -> [[Double]] {
        let maxIndex = values.map(\.index).max() ?? -1
        guard maxIndex >= 0 else { return [] }
        var grouped = Array(repeating: [Double](), count: maxIndex + 1)
        for value in values where value.index >= 0 {
            grouped[value.index].append(value.value)
        }
        return grouped
    }

    private struct IndexedDouble {
        let index: Int
        let value: Double
    }
}
