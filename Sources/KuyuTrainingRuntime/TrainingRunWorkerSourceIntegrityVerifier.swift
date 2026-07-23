import Foundation
import KuyuEvolution
import KuyuTrainingContracts

public struct TrainingRunWorkerSourceIntegrityVerifier: Sendable {
  public enum VerificationError: Error, Sendable, Equatable {
    case missingSourceBundle
    case unpinnedResumeSource(path: String)
    case missingSourceDigest(bundleID: String)
    case invalidSourceDigest(bundleID: String, digest: String)
    case sourceOutsideAllowedRoots(path: String)
    case sourceIntegrityFailure(path: String, reason: String)
    case sourceDigestMismatch(bundleID: String, expected: String, actual: String)
  }

  private let allowedSourceRoots: [URL]

  public init(allowedSourceRoots: [URL]) {
    self.allowedSourceRoots = allowedSourceRoots.map {
      $0.standardizedFileURL.resolvingSymlinksInPath()
    }
  }

  public func verify(_ artifact: TrainingRunWorkerLaunchArtifact) throws {
    switch artifact.operation {
    case .start(let request):
      guard let sourceBundle = request.sourceBundle else {
        throw VerificationError.missingSourceBundle
      }
      try verify(sourceBundle)
    case .resume(let request):
      switch request.source {
      case .artifactRoot(let artifactRoot):
        throw VerificationError.unpinnedResumeSource(path: artifactRoot.path)
      case .checkpoint(let checkpoint):
        try verify(checkpoint)
      case .continuation(let continuation):
        try verify(continuation.checkpoint)
      }
    }
  }

  public func pinnedReference(_ reference: ModelBundleReference) throws -> ModelBundleReference {
    let actual = try contentReference(for: reference)
    return ModelBundleReference(
      bundleID: reference.bundleID,
      kind: reference.kind,
      url: reference.url,
      provenanceURL: reference.provenanceURL,
      contentHash: actual.sha256Digest,
      robotManifestID: reference.robotManifestID,
      observationSchemaID: reference.observationSchemaID,
      actionSchemaID: reference.actionSchemaID
    )
  }

  public func verifiedReference(
    _ reference: ModelBundleReference
  ) throws -> ModelBundleReference {
    try verify(reference)
    return ModelBundleReference(
      bundleID: reference.bundleID,
      kind: reference.kind,
      url: reference.url,
      provenanceURL: reference.provenanceURL,
      contentHash: reference.contentHash?.lowercased(),
      robotManifestID: reference.robotManifestID,
      observationSchemaID: reference.observationSchemaID,
      actionSchemaID: reference.actionSchemaID
    )
  }

  private func verify(_ reference: ModelBundleReference) throws {
    guard let expected = reference.contentHash else {
      throw VerificationError.missingSourceDigest(bundleID: reference.bundleID)
    }
    guard Self.isSHA256Digest(expected) else {
      throw VerificationError.invalidSourceDigest(
        bundleID: reference.bundleID,
        digest: expected
      )
    }
    let actual = try contentReference(for: reference).sha256Digest
    guard actual == expected.lowercased() else {
      throw VerificationError.sourceDigestMismatch(
        bundleID: reference.bundleID,
        expected: expected.lowercased(),
        actual: actual
      )
    }
  }

  private func contentReference(
    for reference: ModelBundleReference
  ) throws -> EvolutionCheckpointReference {
    let checkpoint = reference.url.standardizedFileURL.resolvingSymlinksInPath()
    guard
      let sourceRoot = allowedSourceRoots.first(where: { root in
        Self.isStrictDescendant(checkpoint, of: root)
      })
    else {
      throw VerificationError.sourceOutsideAllowedRoots(path: checkpoint.path)
    }
    do {
      return try EvolutionCheckpointIntegrity().reference(
        checkpointID: reference.bundleID,
        checkpointURL: checkpoint,
        artifactRoot: sourceRoot
      )
    } catch {
      throw VerificationError.sourceIntegrityFailure(
        path: checkpoint.path,
        reason: String(describing: error)
      )
    }
  }

  private static func isStrictDescendant(_ url: URL, of root: URL) -> Bool {
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    return url.path.hasPrefix(rootPath) && url.path != root.path
  }

  private static func isSHA256Digest(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy { byte in
        (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
      }
  }
}
