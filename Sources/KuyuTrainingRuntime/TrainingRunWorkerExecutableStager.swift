import Foundation

public struct TrainingRunWorkerExecutableStager: Sendable {
  public enum StageError: Error, Sendable, Equatable {
    case stagingDirectoryExists(String)
    case directoryCreationFailed(path: String, reason: String)
    case cloneFailed(source: String, destination: String, code: Int32)
    case copyFailed(source: String, destination: String, reason: String)
    case sourceChanged(String)
    case stagedExecutableMismatch(String)
    case invalidExecutableBundle(path: String, reason: String)
    case overlappingExecutableBundlePaths(source: String, destination: String)
    case executableBundleChanged(String)
    case stagedExecutableBundleMismatch(String)
    case resourceBundlesUnsupportedForExecutableBundle
    case duplicateResourceBundle(String)
    case invalidResourceBundle(path: String, reason: String)
    case resourceBundleChanged(String)
    case stagedResourceBundleMismatch(String)
    case unsupportedEntry(String)
    case unsafeSymbolicLink(String)
    case permissionUpdateFailed(path: String, code: Int32)
  }

  public static let stagingDirectoryName = "WORKER_EXECUTABLE"

  private struct Layout {
    let sourceRoot: URL
    let destinationRoot: URL
    let executableURL: URL
    let resourceBundleDirectory: URL
    let stagedSource: TrainingRunWorkerExecutableSource
  }

  let cloner: any TrainingRunWorkerSourceSnapshotCloning

  public init(
    cloner: any TrainingRunWorkerSourceSnapshotCloning =
      POSIXTrainingRunWorkerSourceSnapshotCloner()
  ) {
    self.cloner = cloner
  }

  func stage(
    sourceExecutableURL: URL,
    expectedIdentity: TrainingRunWorkerExecutableIdentity,
    resourceBundles: [TrainingRunWorkerResourceBundle] = [],
    in launchDirectory: URL
  ) throws -> URL {
    try stage(
      source: TrainingRunWorkerExecutableSource(
        executableURL: sourceExecutableURL
      ),
      expectedIdentity: expectedIdentity,
      resourceBundles: resourceBundles,
      in: launchDirectory
    ).executableURL
  }

  func stage(
    source: TrainingRunWorkerExecutableSource,
    expectedIdentity: TrainingRunWorkerExecutableIdentity,
    resourceBundles: [TrainingRunWorkerResourceBundle] = [],
    in launchDirectory: URL
  ) throws -> TrainingRunWorkerExecutableSource {
    if source.isBundle, !resourceBundles.isEmpty {
      throw StageError.resourceBundlesUnsupportedForExecutableBundle
    }
    let stagingDirectory = launchDirectory.appendingPathComponent(
      Self.stagingDirectoryName,
      isDirectory: true
    )
    try validateSeparatedBundlePaths(
      source: source,
      stagingDirectory: stagingDirectory
    )
    let pinnedExecutableBundle = try executableBundleIdentity(for: source)
    let pinnedResourceBundles = try pin(resourceBundles)
    guard !FileManager.default.fileExists(atPath: stagingDirectory.path) else {
      throw StageError.stagingDirectoryExists(stagingDirectory.path)
    }
    do {
      try FileManager.default.createDirectory(
        at: stagingDirectory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
    } catch {
      throw StageError.directoryCreationFailed(
        path: stagingDirectory.path,
        reason: String(describing: error)
      )
    }
    let layout = try layout(
      source: source,
      stagingDirectory: stagingDirectory
    )
    try materialize(source: layout.sourceRoot, destination: layout.destinationRoot)
    if !pinnedResourceBundles.isEmpty {
      do {
        try FileManager.default.createDirectory(
          at: layout.resourceBundleDirectory,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700]
        )
      } catch {
        throw StageError.directoryCreationFailed(
          path: layout.resourceBundleDirectory.path,
          reason: String(describing: error)
        )
      }
    }
    for resource in pinnedResourceBundles {
      let destination = layout.resourceBundleDirectory.appendingPathComponent(
        resource.name,
        isDirectory: true
      )
      if !FileManager.default.fileExists(atPath: destination.path) {
        try materialize(source: resource.sourceURL, destination: destination)
      }
    }
    try makeReadOnly(stagingDirectory)

    let sourceAfterStaging = try TrainingRunWorkerExecutableIdentity.validated(
      source.executableURL
    ).identity
    guard sourceAfterStaging == expectedIdentity else {
      throw StageError.sourceChanged(source.executableURL.path)
    }
    let stagedIdentity = try TrainingRunWorkerExecutableIdentity.validated(
      layout.executableURL
    ).identity
    guard stagedIdentity.byteCount == expectedIdentity.byteCount,
      stagedIdentity.sha256Digest == expectedIdentity.sha256Digest
    else {
      throw StageError.stagedExecutableMismatch(layout.executableURL.path)
    }
    if let pinnedExecutableBundle,
      let sourceRoot = source.bundleRootURL,
      let stagedRoot = layout.stagedSource.bundleRootURL
    {
      let sourceAfterStaging = try executableBundleIdentity(at: sourceRoot)
      guard sourceAfterStaging == pinnedExecutableBundle else {
        throw StageError.executableBundleChanged(sourceRoot.path)
      }
      let stagedBundle = try executableBundleIdentity(at: stagedRoot)
      guard stagedBundle == pinnedExecutableBundle else {
        throw StageError.stagedExecutableBundleMismatch(stagedRoot.path)
      }
    }
    for resource in pinnedResourceBundles {
      let sourceAfterStaging = try resourceIdentity(
        at: resource.sourceURL,
        name: resource.name
      )
      guard Self.matches(sourceAfterStaging, resource.identity) else {
        throw StageError.resourceBundleChanged(resource.sourceURL.path)
      }
      let destination = layout.resourceBundleDirectory.appendingPathComponent(
        resource.name,
        isDirectory: true
      )
      let stagedResource = try resourceIdentity(at: destination, name: resource.name)
      guard Self.matches(stagedResource, resource.identity) else {
        throw StageError.stagedResourceBundleMismatch(destination.path)
      }
    }
    return layout.stagedSource
  }

  func stagedExecutableURL(
    sourceExecutableURL: URL,
    in launchDirectory: URL
  ) throws -> URL {
    try stagedSource(
      source: TrainingRunWorkerExecutableSource(
        executableURL: sourceExecutableURL
      ),
      in: launchDirectory
    ).executableURL
  }

  func stagedSource(
    source: TrainingRunWorkerExecutableSource,
    in launchDirectory: URL
  ) throws -> TrainingRunWorkerExecutableSource {
    let stagingDirectory = launchDirectory.appendingPathComponent(
      Self.stagingDirectoryName,
      isDirectory: true
    )
    return try layout(
      source: source,
      stagingDirectory: stagingDirectory
    ).stagedSource
  }

  private func layout(
    source: TrainingRunWorkerExecutableSource,
    stagingDirectory: URL
  ) throws -> Layout {
    if let sourceRoot = source.bundleRootURL,
      let executableRelativePath = source.executableRelativePath
    {
      let destinationRoot = stagingDirectory.appendingPathComponent(
        "bundle",
        isDirectory: true
      )
      let stagedSource = try TrainingRunWorkerExecutableSource(
        bundleRootURL: destinationRoot,
        executableRelativePath: executableRelativePath
      )
      return Layout(
        sourceRoot: sourceRoot,
        destinationRoot: destinationRoot,
        executableURL: stagedSource.executableURL,
        resourceBundleDirectory: stagingDirectory,
        stagedSource: stagedSource
      )
    }

    let executable = source.executableURL.standardizedFileURL
    let macOSDirectory = executable.deletingLastPathComponent()
    let contentsDirectory = macOSDirectory.deletingLastPathComponent()
    let applicationBundle = contentsDirectory.deletingLastPathComponent()
    if macOSDirectory.lastPathComponent == "MacOS",
      contentsDirectory.lastPathComponent == "Contents",
      applicationBundle.pathExtension == "app"
    {
      let destinationBundle = stagingDirectory.appendingPathComponent(
        applicationBundle.lastPathComponent,
        isDirectory: true
      )
      let destinationExecutable = destinationBundle
        .appendingPathComponent("Contents", isDirectory: true)
        .appendingPathComponent("MacOS", isDirectory: true)
        .appendingPathComponent(executable.lastPathComponent, isDirectory: false)
      return Layout(
        sourceRoot: applicationBundle,
        destinationRoot: destinationBundle,
        executableURL: destinationExecutable,
        resourceBundleDirectory: destinationBundle
          .appendingPathComponent("Contents", isDirectory: true)
          .appendingPathComponent("Resources", isDirectory: true),
        stagedSource: TrainingRunWorkerExecutableSource(
          executableURL: destinationExecutable
        )
      )
    }
    let destination = stagingDirectory.appendingPathComponent(
      "worker",
      isDirectory: false
    )
    return Layout(
      sourceRoot: executable,
      destinationRoot: destination,
      executableURL: destination,
      resourceBundleDirectory: stagingDirectory,
      stagedSource: TrainingRunWorkerExecutableSource(
        executableURL: destination
      )
    )
  }

}
