import Foundation
import Testing

@testable import KuyuTrainingRuntime

@Suite("Training run worker executable bundle identity")
struct TrainingRunWorkerExecutableBundleIdentityTests {
  @Test(.timeLimit(.minutes(1)))
  func sourceRejectsUnsafeExecutableRelativePaths() throws {
    let root = URL(fileURLWithPath: "/tmp/runtime", isDirectory: true)
    for path in ["", "/bin/worker", "../bin/worker", "bin//worker", "bin/./worker"] {
      #expect(
        throws: TrainingRunWorkerExecutableSource.ValidationError
          .invalidExecutableRelativePath(path)
      ) {
        _ = try TrainingRunWorkerExecutableSource(
          bundleRootURL: root,
          executableRelativePath: path
        )
      }
    }
    let filesystemRoot = URL(fileURLWithPath: "/", isDirectory: true)
    #expect(
      throws: TrainingRunWorkerExecutableSource.ValidationError
        .invalidBundleRoot(filesystemRoot.absoluteString)
    ) {
      _ = try TrainingRunWorkerExecutableSource(
        bundleRootURL: filesystemRoot,
        executableRelativePath: "bin/worker"
      )
    }
  }

  @Test(.timeLimit(.minutes(1)))
  func bundleIdentityIncludesEmptyDirectoryEntries() throws {
    let root = try executableBundleRoot("worker-empty-directory-identity")
    let before = try TrainingRunWorkerExecutableBundleIdentity.validated(root)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("empty", isDirectory: true),
      withIntermediateDirectories: false
    )

    #expect(
      try TrainingRunWorkerExecutableBundleIdentity.validated(root) != before
    )
  }

  @Test(.timeLimit(.minutes(1)))
  func bundleIdentityRejectsSymbolicLinks() throws {
    let root = try executableBundleRoot("worker-symbolic-link-identity")
    let link = root.appendingPathComponent("lib/runtime-link", isDirectory: false)
    try FileManager.default.createSymbolicLink(
      at: link,
      withDestinationURL: root.appendingPathComponent(
        "lib/libRuntime.dylib",
        isDirectory: false
      )
    )

    #expect(
      throws: TrainingRunWorkerExecutableBundleIdentity.IdentityError
        .symbolicLink(link.path)
    ) {
      _ = try TrainingRunWorkerExecutableBundleIdentity.validated(root)
    }
  }

  private func executableBundleRoot(_ label: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "\(label)-\(UUID().uuidString)/runtime",
      isDirectory: true
    )
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
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: executable.path
    )
    try Data("runtime-library".utf8).write(to: library)
    return root
  }
}
