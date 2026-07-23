import Foundation
import KuyuTrainingContracts

public struct TrainingRunWorkerProgressArtifact: Codable, Equatable, Sendable {
  public enum ValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidSequence(UInt64)
    case invalidLaunchDigest(String)
    case attemptIdentityMismatch(
      expected: TrainingRunWorkerAttemptIdentity,
      actual: TrainingRunWorkerAttemptIdentity
    )
    case invalidTimestamp
    case invalidMetric(name: String, value: Double)
    case invalidProgressFraction(Double)
  }

  public static let currentSchemaVersion = 1
  public static let directoryName = "TRAINING_RUN_WORKER_PROGRESS"

  public let schemaVersion: Int
  public let sequence: UInt64
  public let workerAttemptIdentity: TrainingRunWorkerAttemptIdentity
  public let event: TrainingRunProgressEvent

  public init(
    schemaVersion: Int = Self.currentSchemaVersion,
    sequence: UInt64,
    workerAttemptIdentity: TrainingRunWorkerAttemptIdentity,
    event: TrainingRunProgressEvent
  ) {
    self.schemaVersion = schemaVersion
    self.sequence = sequence
    self.workerAttemptIdentity = workerAttemptIdentity
    self.event = event
  }

  public func validate(
    expectedWorkerAttemptIdentity: TrainingRunWorkerAttemptIdentity
  ) throws {
    guard schemaVersion == Self.currentSchemaVersion else {
      throw ValidationError.unsupportedSchemaVersion(schemaVersion)
    }
    guard sequence > 0 else {
      throw ValidationError.invalidSequence(sequence)
    }
    guard Self.isSHA256Digest(workerAttemptIdentity.launchSHA256Digest) else {
      throw ValidationError.invalidLaunchDigest(workerAttemptIdentity.launchSHA256Digest)
    }
    guard workerAttemptIdentity == expectedWorkerAttemptIdentity else {
      throw ValidationError.attemptIdentityMismatch(
        expected: expectedWorkerAttemptIdentity,
        actual: workerAttemptIdentity
      )
    }
    guard event.timestamp.timeIntervalSince1970.isFinite else {
      throw ValidationError.invalidTimestamp
    }
    if let progressFraction = event.progressFraction {
      guard progressFraction.isFinite, (0...1).contains(progressFraction) else {
        throw ValidationError.invalidProgressFraction(progressFraction)
      }
    }
    let metrics: [(String, Double?)] = [
      ("fitness", event.fitness),
      ("rewardAverage", event.rewardAverage),
      ("taskPassRate", event.taskPassRate),
      ("safetyViolationRate", event.safetyViolationRate),
      ("holdTimeRatio", event.holdTimeRatio),
      ("altitudeErrorRatio", event.altitudeErrorRatio),
      ("workerThroughput", event.workerThroughput),
    ]
    for (name, value) in metrics {
      if let value, !value.isFinite {
        throw ValidationError.invalidMetric(name: name, value: value)
      }
    }
  }

  private static func isSHA256Digest(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
      }
  }
}
