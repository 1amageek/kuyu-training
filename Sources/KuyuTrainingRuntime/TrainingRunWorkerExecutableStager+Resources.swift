import Foundation
import KuyuEvolution

struct TrainingRunWorkerPinnedResourceBundle {
  let sourceURL: URL
  let name: String
  let identity: EvolutionCheckpointReference
}

extension TrainingRunWorkerExecutableStager {
  func pin(
    _ resourceBundles: [TrainingRunWorkerResourceBundle]
  ) throws -> [TrainingRunWorkerPinnedResourceBundle] {
    var names = Set<String>()
    return try resourceBundles.map { resource in
      let source = resource.sourceURL.standardizedFileURL
      let name = source.lastPathComponent
      guard source.isFileURL,
        source.pathExtension == "bundle",
        !name.isEmpty,
        name != ".",
        name != ".."
      else {
        throw StageError.invalidResourceBundle(
          path: resource.sourceURL.absoluteString,
          reason: "expected a file URL ending in .bundle"
        )
      }
      guard names.insert(name.lowercased()).inserted else {
        throw StageError.duplicateResourceBundle(name)
      }
      return TrainingRunWorkerPinnedResourceBundle(
        sourceURL: source,
        name: name,
        identity: try resourceIdentity(at: source, name: name)
      )
    }
  }

  func resourceIdentity(
    at url: URL,
    name: String
  ) throws -> EvolutionCheckpointReference {
    do {
      return try EvolutionCheckpointIntegrity().reference(
        checkpointID: name,
        checkpointURL: url,
        artifactRoot: url.deletingLastPathComponent()
      )
    } catch let error as CancellationError {
      throw error
    } catch {
      throw StageError.invalidResourceBundle(
        path: url.path,
        reason: String(describing: error)
      )
    }
  }

  static func matches(
    _ lhs: EvolutionCheckpointReference,
    _ rhs: EvolutionCheckpointReference
  ) -> Bool {
    lhs.sha256Digest == rhs.sha256Digest
      && lhs.fileCount == rhs.fileCount
      && lhs.byteCount == rhs.byteCount
  }
}
