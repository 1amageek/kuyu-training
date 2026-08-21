import Foundation

public struct TrainingRunWorkerExecutableSource: Sendable, Equatable {
  public enum ValidationError: Error, Sendable, Equatable {
    case invalidBundleRoot(String)
    case invalidExecutableRelativePath(String)
  }

  public let executableURL: URL
  public let bundleRootURL: URL?
  public let executableRelativePath: String?

  public init(executableURL: URL) {
    self.executableURL = executableURL
    self.bundleRootURL = nil
    self.executableRelativePath = nil
  }

  public init(
    bundleRootURL: URL,
    executableRelativePath: String
  ) throws {
    guard bundleRootURL.isFileURL,
      bundleRootURL.path.hasPrefix("/"),
      bundleRootURL.standardizedFileURL.path != "/"
    else {
      throw ValidationError.invalidBundleRoot(bundleRootURL.absoluteString)
    }
    guard Self.isSafeRelativePath(executableRelativePath) else {
      throw ValidationError.invalidExecutableRelativePath(
        executableRelativePath
      )
    }

    let root = bundleRootURL.standardizedFileURL
    self.executableURL = root.appendingPathComponent(
      executableRelativePath,
      isDirectory: false
    )
    self.bundleRootURL = root
    self.executableRelativePath = executableRelativePath
  }

  public var isBundle: Bool {
    bundleRootURL != nil
  }

  private static func isSafeRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty,
      !path.hasPrefix("/"),
      path.utf8.allSatisfy({ $0 != 0 })
    else {
      return false
    }
    let components = path.split(
      separator: "/",
      omittingEmptySubsequences: false
    )
    return components.allSatisfy { component in
      !component.isEmpty && component != "." && component != ".."
    }
  }
}
