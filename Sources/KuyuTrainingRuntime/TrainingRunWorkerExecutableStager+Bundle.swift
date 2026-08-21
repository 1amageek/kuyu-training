import Foundation

extension TrainingRunWorkerExecutableStager {
  func executableBundleIdentity(
    for source: TrainingRunWorkerExecutableSource
  ) throws -> TrainingRunWorkerExecutableBundleIdentity? {
    guard let root = source.bundleRootURL else { return nil }
    return try executableBundleIdentity(at: root)
  }

  func validateSeparatedBundlePaths(
    source: TrainingRunWorkerExecutableSource,
    stagingDirectory: URL
  ) throws {
    guard let sourceRoot = source.bundleRootURL else { return }
    let canonicalSource = sourceRoot.standardizedFileURL
      .resolvingSymlinksInPath()
    let canonicalDestination = stagingDirectory.standardizedFileURL
      .resolvingSymlinksInPath()
    guard !Self.contains(canonicalSource, canonicalDestination),
      !Self.contains(canonicalDestination, canonicalSource)
    else {
      throw StageError.overlappingExecutableBundlePaths(
        source: sourceRoot.path,
        destination: stagingDirectory.path
      )
    }
  }

  func executableBundleIdentity(
    at root: URL
  ) throws -> TrainingRunWorkerExecutableBundleIdentity {
    do {
      return try TrainingRunWorkerExecutableBundleIdentity.validated(root)
    } catch let error as CancellationError {
      throw error
    } catch {
      throw StageError.invalidExecutableBundle(
        path: root.path,
        reason: String(describing: error)
      )
    }
  }

  private static func contains(_ root: URL, _ candidate: URL) -> Bool {
    let rootPath = root.path
    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    return candidate.path == rootPath || candidate.path.hasPrefix(rootPrefix)
  }
}
