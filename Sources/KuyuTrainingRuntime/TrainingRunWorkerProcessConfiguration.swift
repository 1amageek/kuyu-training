import Foundation

public struct TrainingRunWorkerProcessConfiguration: Sendable, Equatable {
  public enum ConfigurationError: Error, Sendable, Equatable {
    case cacheDirectoryUnavailable
    case invalidCachePathComponent(String)
  }

  public let executableURL: URL
  public let launchRootDirectory: URL
  public let resourceBundles: [TrainingRunWorkerResourceBundle]

  public init(
    executableURL: URL,
    launchRootDirectory: URL,
    resourceBundles: [TrainingRunWorkerResourceBundle] = []
  ) {
    self.executableURL = executableURL
    self.launchRootDirectory = launchRootDirectory
    self.resourceBundles = resourceBundles
  }

  public static func userCache(
    executableURL: URL,
    resourceBundles: [TrainingRunWorkerResourceBundle] = [],
    pathComponents: [String] = ["Kuyu", "TrainingWorkerLaunches"],
    fileManager: FileManager = .default
  ) throws -> Self {
    guard let cacheDirectory = fileManager.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first else {
      throw ConfigurationError.cacheDirectoryUnavailable
    }
    var launchRootDirectory = cacheDirectory
    for component in pathComponents {
      guard !component.isEmpty,
        component != ".",
        component != "..",
        !component.contains("/")
      else {
        throw ConfigurationError.invalidCachePathComponent(component)
      }
      launchRootDirectory.appendPathComponent(component, isDirectory: true)
    }
    return Self(
      executableURL: executableURL,
      launchRootDirectory: launchRootDirectory,
      resourceBundles: resourceBundles
    )
  }
}
