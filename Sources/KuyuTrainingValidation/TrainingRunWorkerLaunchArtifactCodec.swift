import Foundation
import KuyuTrainingContracts

public struct TrainingRunWorkerLaunchArtifactCodec: Sendable {
  public enum CodecError: Error, Sendable, Equatable {
    case invalidHeader(reason: String)
    case unsupportedSchemaVersion(Int)
    case payloadDecodingFailed(version: Int, reason: String)
    case payloadEncodingFailed(version: Int, reason: String)
    case invalidValue(field: String, reason: String)
  }

  private struct Header: Decodable {
    let schemaVersion: Int
  }

  public init() {}

  public func encode(_ artifact: TrainingRunWorkerLaunchArtifact) throws -> Data {
    let version = TrainingRunWorkerLaunchArtifactWireVersion.current
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .secondsSince1970
    do {
      return try encoder.encode(TrainingRunWorkerLaunchArtifactV4(artifact))
    } catch let error as CodecError {
      throw error
    } catch {
      throw CodecError.payloadEncodingFailed(
        version: version.rawValue,
        reason: String(describing: error)
      )
    }
  }

  public func decode(_ data: Data) throws -> DecodedTrainingRunWorkerLaunchArtifact {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let header: Header
    do {
      header = try decoder.decode(Header.self, from: data)
    } catch {
      throw CodecError.invalidHeader(reason: String(describing: error))
    }
    guard let version = TrainingRunWorkerLaunchArtifactWireVersion(
      rawValue: header.schemaVersion
    ) else {
      throw CodecError.unsupportedSchemaVersion(header.schemaVersion)
    }
    do {
      let artifact = try decoder.decode(
        TrainingRunWorkerLaunchArtifactV4.self,
        from: data
      ).domainArtifact()
      return DecodedTrainingRunWorkerLaunchArtifact(
        sourceVersion: version,
        artifact: artifact
      )
    } catch let error as CodecError {
      throw error
    } catch {
      throw CodecError.payloadDecodingFailed(
        version: version.rawValue,
        reason: String(describing: error)
      )
    }
  }
}
