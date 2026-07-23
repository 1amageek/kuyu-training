import Foundation
import Testing

@testable import KuyuTrainingRuntime

@Suite("Training worker resource bundle")
struct TrainingRunWorkerResourceBundleTests {
  @Test(.timeLimit(.minutes(1)))
  func stagerMaterializesAnImmutableBundleBesideACommandLineWorker() throws {
    let directory = try temporaryDirectory()
    let sourceExecutable = directory.appendingPathComponent("source-worker", isDirectory: false)
    try FileManager.default.copyItem(
      at: URL(fileURLWithPath: "/usr/bin/true", isDirectory: false),
      to: sourceExecutable
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: sourceExecutable.path
    )
    let resourceBundle = directory.appendingPathComponent(
      "mlx-swift_Cmlx.bundle",
      isDirectory: true
    )
    let resourceDirectory = resourceBundle
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Resources", isDirectory: true)
    try FileManager.default.createDirectory(
      at: resourceDirectory,
      withIntermediateDirectories: true
    )
    let sourceMetalLibrary = resourceDirectory.appendingPathComponent(
      "default.metallib",
      isDirectory: false
    )
    try Data("metal-library".utf8).write(to: sourceMetalLibrary)
    let launchDirectory = directory.appendingPathComponent("launch", isDirectory: true)
    try FileManager.default.createDirectory(
      at: launchDirectory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    let executableIdentity = try TrainingRunWorkerExecutableIdentity.validated(
      sourceExecutable
    ).identity

    let stagedExecutable = try TrainingRunWorkerExecutableStager().stage(
      sourceExecutableURL: sourceExecutable,
      expectedIdentity: executableIdentity,
      resourceBundles: [TrainingRunWorkerResourceBundle(sourceURL: resourceBundle)],
      in: launchDirectory
    )

    let stagedBundle = stagedExecutable.deletingLastPathComponent()
      .appendingPathComponent(resourceBundle.lastPathComponent, isDirectory: true)
    let stagedMetalLibrary = stagedBundle
      .appendingPathComponent("Contents", isDirectory: true)
      .appendingPathComponent("Resources", isDirectory: true)
      .appendingPathComponent("default.metallib", isDirectory: false)
    #expect(try String(contentsOf: stagedMetalLibrary, encoding: .utf8) == "metal-library")
    try FileManager.default.removeItem(at: resourceBundle)
    #expect(try String(contentsOf: stagedMetalLibrary, encoding: .utf8) == "metal-library")
  }

  @Test(.timeLimit(.minutes(1)))
  func stagerRejectsDuplicateBundleDestinations() throws {
    let directory = try temporaryDirectory()
    let sourceExecutable = directory.appendingPathComponent("source-worker", isDirectory: false)
    try FileManager.default.copyItem(
      at: URL(fileURLWithPath: "/usr/bin/true", isDirectory: false),
      to: sourceExecutable
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: sourceExecutable.path
    )
    let firstRoot = directory.appendingPathComponent("first", isDirectory: true)
    let secondRoot = directory.appendingPathComponent("second", isDirectory: true)
    let firstBundle = try resourceBundle(in: firstRoot)
    let secondBundle = try resourceBundle(in: secondRoot)
    let launchDirectory = directory.appendingPathComponent("launch", isDirectory: true)
    try FileManager.default.createDirectory(at: launchDirectory, withIntermediateDirectories: true)
    let executableIdentity = try TrainingRunWorkerExecutableIdentity.validated(
      sourceExecutable
    ).identity

    #expect(
      throws: TrainingRunWorkerExecutableStager.StageError.duplicateResourceBundle(
        "mlx-swift_Cmlx.bundle"
      )
    ) {
      _ = try TrainingRunWorkerExecutableStager().stage(
        sourceExecutableURL: sourceExecutable,
        expectedIdentity: executableIdentity,
        resourceBundles: [
          TrainingRunWorkerResourceBundle(sourceURL: firstBundle),
          TrainingRunWorkerResourceBundle(sourceURL: secondBundle),
        ],
        in: launchDirectory
      )
    }
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "worker-resource-bundle-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func resourceBundle(in root: URL) throws -> URL {
    let bundle = root.appendingPathComponent("mlx-swift_Cmlx.bundle", isDirectory: true)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
    try Data("resource".utf8).write(
      to: bundle.appendingPathComponent("default.metallib", isDirectory: false)
    )
    return bundle
  }
}
