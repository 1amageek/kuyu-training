import Darwin
import Foundation
import Synchronization
import Testing

@testable import KuyuTraining
@testable import KuyuTrainingRuntime

@Suite("Training run worker executable bundle")
struct TrainingRunWorkerExecutableBundleTests {
  @Test(.timeLimit(.minutes(1)))
  func stagerPreservesTheExactReadOnlyBundleTreeAndRelativeExecutable() async throws {
    let directory = try temporaryDirectory("worker-executable-bundle")
    let source = try executableBundle(in: directory)
    let expectedExecutable = try TrainingRunWorkerExecutableIdentity.validated(
      source.executableURL
    ).identity
    let expectedBundle = try TrainingRunWorkerExecutableBundleIdentity.validated(
      try #require(source.bundleRootURL)
    )
    let launchDirectory = try launchDirectory(in: directory)

    let staged = try TrainingRunWorkerExecutableStager().stage(
      source: source,
      expectedIdentity: expectedExecutable,
      in: launchDirectory
    )

    let stagedRoot = try #require(staged.bundleRootURL)
    #expect(staged.executableRelativePath == "bin/worker")
    #expect(
      staged.executableURL
        == launchDirectory
          .appendingPathComponent(
            TrainingRunWorkerExecutableStager.stagingDirectoryName,
            isDirectory: true
          )
          .appendingPathComponent("bundle", isDirectory: true)
          .appendingPathComponent("bin/worker", isDirectory: false)
    )
    #expect(
      try TrainingRunWorkerExecutableBundleIdentity.validated(stagedRoot)
        == expectedBundle
    )
    #expect(try permissions(at: stagedRoot) & 0o222 == 0)
    #expect(try permissions(at: staged.executableURL) & 0o222 == 0)
    #expect(try permissions(at: staged.executableURL) & 0o111 != 0)
    let stagedLibrary = stagedRoot.appendingPathComponent(
      "lib/libRuntime.dylib",
      isDirectory: false
    )
    #expect(try permissions(at: stagedLibrary) & 0o222 == 0)

    try Data("replaced-source-library".utf8).write(
      to: try #require(source.bundleRootURL).appendingPathComponent(
        "lib/libRuntime.dylib",
        isDirectory: false
      )
    )
    #expect(
      try String(contentsOf: stagedLibrary, encoding: .utf8)
        == "runtime-library"
    )

    let process = TrainingRunWorkerChildProcess()
    _ = try await process.start(
      executableURL: staged.executableURL,
      arguments: [],
      standardOutputURL: directory.appendingPathComponent("stdout.log"),
      standardErrorURL: directory.appendingPathComponent("stderr.log")
    )
    #expect(await process.waitForExit().status == 0)
  }

  @Test(.timeLimit(.minutes(1)))
  func stagerRejectsSourceBundleMutationDuringClone() throws {
    let directory = try temporaryDirectory("worker-source-bundle-mutation")
    let source = try executableBundle(in: directory)
    let sourceRoot = try #require(source.bundleRootURL)
    let sourceLibrary = sourceRoot.appendingPathComponent(
      "lib/libRuntime.dylib",
      isDirectory: false
    )
    let expectedExecutable = try TrainingRunWorkerExecutableIdentity.validated(
      source.executableURL
    ).identity
    let stager = TrainingRunWorkerExecutableStager(
      cloner: MutatingExecutableBundleCloner(
        mutation: .source(sourceLibrary)
      )
    )

    #expect(
      throws: TrainingRunWorkerExecutableStager.StageError
        .executableBundleChanged(sourceRoot.path)
    ) {
      _ = try stager.stage(
        source: source,
        expectedIdentity: expectedExecutable,
        in: try launchDirectory(in: directory)
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func stagerPropagatesCancellationDuringBundleClone() throws {
    let directory = try temporaryDirectory("worker-bundle-cancellation")
    let source = try executableBundle(in: directory)
    let expectedExecutable = try TrainingRunWorkerExecutableIdentity.validated(
      source.executableURL
    ).identity

    #expect {
      _ = try TrainingRunWorkerExecutableStager(
        cloner: CancellingExecutableBundleCloner()
      ).stage(
        source: source,
        expectedIdentity: expectedExecutable,
        in: try launchDirectory(in: directory)
      )
    } throws: { error in
      error is CancellationError
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func stagerRejectsChangedStagedBundleTree() throws {
    let directory = try temporaryDirectory("worker-staged-bundle-mutation")
    let source = try executableBundle(in: directory)
    let expectedExecutable = try TrainingRunWorkerExecutableIdentity.validated(
      source.executableURL
    ).identity
    let launchDirectory = try launchDirectory(in: directory)
    let stagedRoot = launchDirectory
      .appendingPathComponent(
        TrainingRunWorkerExecutableStager.stagingDirectoryName,
        isDirectory: true
      )
      .appendingPathComponent("bundle", isDirectory: true)
    let stager = TrainingRunWorkerExecutableStager(
      cloner: MutatingExecutableBundleCloner(
        mutation: .destination("lib/libRuntime.dylib")
      )
    )

    #expect(
      throws: TrainingRunWorkerExecutableStager.StageError
        .stagedExecutableBundleMismatch(stagedRoot.path)
    ) {
      _ = try stager.stage(
        source: source,
        expectedIdentity: expectedExecutable,
        in: launchDirectory
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func launcherPreflightsSourceAndStagedBundlesBeforeSpawn() async throws {
    let directory = try temporaryDirectory("worker-bundle-preflight")
    let executableSource = try executableBundle(in: directory)
    let launchRoot = directory.appendingPathComponent("launches", isDirectory: true)
    let artifact = try launchArtifact(in: directory)
    let preflight = RejectingSecondBundlePreflight()
    let launcher = TrainingRunWorkerProcessLauncher(
      configuration: TrainingRunWorkerProcessConfiguration(
        executableSource: executableSource,
        launchRootDirectory: launchRoot
      ),
      executableBundlePreflight: preflight
    )

    await #expect(throws: BundlePreflightFixtureError.stagedBundleRejected) {
      _ = try await launcher.launch(artifact)
    }

    let invocations = preflight.recordedInvocations()
    #expect(invocations.count == 2)
    #expect(invocations.first?.rootURL == executableSource.bundleRootURL)
    #expect(invocations.first?.executableRelativePath == "bin/worker")
    let stagedRoot = TrainingRunWorkerLaunchArtifactStore(
      rootDirectory: launchRoot
    ).launchDirectory(for: artifact.launchID)
      .appendingPathComponent(
        TrainingRunWorkerExecutableStager.stagingDirectoryName,
        isDirectory: true
      )
      .appendingPathComponent("bundle", isDirectory: true)
    #expect(invocations.last?.rootURL == stagedRoot)
    #expect(invocations.last?.executableRelativePath == "bin/worker")
  }

  @Test(.timeLimit(.minutes(1)))
  func executableBundleRejectsSeparateResourceInjection() throws {
    let directory = try temporaryDirectory("worker-bundle-resource-injection")
    let source = try executableBundle(in: directory)
    let resource = directory.appendingPathComponent("extra.bundle", isDirectory: true)
    try FileManager.default.createDirectory(
      at: resource,
      withIntermediateDirectories: true
    )
    try Data("extra".utf8).write(
      to: resource.appendingPathComponent("resource.bin", isDirectory: false)
    )
    let expectedExecutable = try TrainingRunWorkerExecutableIdentity.validated(
      source.executableURL
    ).identity

    #expect(
      throws: TrainingRunWorkerExecutableStager.StageError
        .resourceBundlesUnsupportedForExecutableBundle
    ) {
      _ = try TrainingRunWorkerExecutableStager().stage(
        source: source,
        expectedIdentity: expectedExecutable,
        resourceBundles: [TrainingRunWorkerResourceBundle(sourceURL: resource)],
        in: try launchDirectory(in: directory)
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func stagerRejectsLaunchDirectoriesInsideTheSourceBundle() throws {
    let directory = try temporaryDirectory("worker-overlapping-bundle")
    let source = try executableBundle(in: directory)
    let sourceRoot = try #require(source.bundleRootURL)
    let launchDirectory = sourceRoot.appendingPathComponent(
      "launch",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: launchDirectory,
      withIntermediateDirectories: false
    )
    let expectedExecutable = try TrainingRunWorkerExecutableIdentity.validated(
      source.executableURL
    ).identity
    let destination = launchDirectory.appendingPathComponent(
      TrainingRunWorkerExecutableStager.stagingDirectoryName,
      isDirectory: true
    )

    #expect(
      throws: TrainingRunWorkerExecutableStager.StageError
        .overlappingExecutableBundlePaths(
          source: sourceRoot.path,
          destination: destination.path
        )
    ) {
      _ = try TrainingRunWorkerExecutableStager().stage(
        source: source,
        expectedIdentity: expectedExecutable,
        in: launchDirectory
      )
    }
  }

  private func executableBundle(
    in directory: URL
  ) throws -> TrainingRunWorkerExecutableSource {
    let root = directory.appendingPathComponent("runtime", isDirectory: true)
    let executable = root.appendingPathComponent("bin/worker", isDirectory: false)
    let library = root.appendingPathComponent(
      "lib/libRuntime.dylib",
      isDirectory: false
    )
    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
      at: library.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.copyItem(
      at: URL(fileURLWithPath: "/usr/bin/true", isDirectory: false),
      to: executable
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: executable.path
    )
    try Data("runtime-library".utf8).write(to: library)
    return try TrainingRunWorkerExecutableSource(
      bundleRootURL: root,
      executableRelativePath: "bin/worker"
    )
  }

  private func launchArtifact(
    in directory: URL
  ) throws -> TrainingRunWorkerLaunchArtifact {
    let sourceParent = directory.appendingPathComponent("sources", isDirectory: true)
    let sourceRoot = sourceParent.appendingPathComponent("model", isDirectory: true)
    try FileManager.default.createDirectory(
      at: sourceRoot,
      withIntermediateDirectories: true
    )
    try Data("model".utf8).write(
      to: sourceRoot.appendingPathComponent("model.json", isDirectory: false)
    )
    let source = try TrainingRunWorkerSourceIntegrityVerifier(
      allowedSourceRoots: [sourceParent]
    ).pinnedReference(
      ModelBundleReference(
        bundleID: "source",
        kind: .source,
        url: sourceRoot
      )
    )
    return TrainingRunWorkerLaunchArtifact(
      operation: .start(
        TrainingRunRequest(
          runID: TrainingRunID("bundle-preflight"),
          artifactRoot: directory.appendingPathComponent("artifacts", isDirectory: true),
          taskProfileID: "lift",
          policyContract: ReferenceQuadrotorLearningContracts
            .temporalCTBRPolicyContract(),
          actionContract: ReferenceQuadrotorLearningContracts
            .bodyRateActionContract(),
          sourceBundle: source
        )
      )
    )
  }

  private func launchDirectory(in directory: URL) throws -> URL {
    let launchDirectory = directory.appendingPathComponent(
      "launch-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: launchDirectory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    return launchDirectory
  }

  private func temporaryDirectory(_ label: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(label)-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  private func permissions(at url: URL) throws -> UInt16 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    return permissions.uint16Value
  }
}

private struct MutatingExecutableBundleCloner:
  TrainingRunWorkerSourceSnapshotCloning
{
  enum Mutation: Sendable {
    case source(URL)
    case destination(String)
  }

  let mutation: Mutation

  func clone(source: URL, destination: URL) throws {
    try FileManager.default.copyItem(at: source, to: destination)
    switch mutation {
    case .source(let sourceURL):
      try Data("changed-source".utf8).write(to: sourceURL)
    case .destination(let relativePath):
      try Data("changed-destination".utf8).write(
        to: destination.appendingPathComponent(
          relativePath,
          isDirectory: false
        )
      )
    }
  }
}

private struct CancellingExecutableBundleCloner:
  TrainingRunWorkerSourceSnapshotCloning
{
  func clone(source: URL, destination: URL) throws {
    throw CancellationError()
  }
}

private final class RejectingSecondBundlePreflight:
  TrainingRunWorkerExecutableBundlePreflighting, Sendable
{
  struct Invocation: Sendable, Equatable {
    let rootURL: URL
    let executableRelativePath: String
  }

  private let invocations = Mutex<[Invocation]>([])

  func verifyBundle(
    at rootURL: URL,
    executableRelativePath: String
  ) throws {
    let invocationCount = invocations.withLock { invocations in
      invocations.append(
        Invocation(
          rootURL: rootURL,
          executableRelativePath: executableRelativePath
        )
      )
      return invocations.count
    }
    if invocationCount == 2 {
      throw BundlePreflightFixtureError.stagedBundleRejected
    }
  }

  func recordedInvocations() -> [Invocation] {
    invocations.withLock { $0 }
  }
}

private enum BundlePreflightFixtureError: Error, Sendable, Equatable {
  case stagedBundleRejected
}
