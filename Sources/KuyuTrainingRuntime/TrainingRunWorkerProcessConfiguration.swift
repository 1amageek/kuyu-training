import Foundation

public struct TrainingRunWorkerProcessConfiguration: Sendable, Equatable {
  public enum ConfigurationError: Error, Sendable, Equatable {
    case cacheDirectoryUnavailable
    case invalidCachePathComponent(String)
  }

  public let executableSource: TrainingRunWorkerExecutableSource
  public let launchRootDirectory: URL
  public let resourceBundles: [TrainingRunWorkerResourceBundle]

  public var executableURL: URL {
    executableSource.executableURL
  }

  public init(
    executableURL: URL,
    launchRootDirectory: URL,
    resourceBundles: [TrainingRunWorkerResourceBundle] = []
  ) {
    self.executableSource = TrainingRunWorkerExecutableSource(
      executableURL: executableURL
    )
    self.launchRootDirectory = launchRootDirectory
    self.resourceBundles = resourceBundles
  }

  public init(
    executableSource: TrainingRunWorkerExecutableSource,
    launchRootDirectory: URL,
    resourceBundles: [TrainingRunWorkerResourceBundle] = []
  ) {
    self.executableSource = executableSource
    self.launchRootDirectory = launchRootDirectory
    self.resourceBundles = resourceBundles
  }

  public static func userCache(
    executableURL: URL,
    resourceBundles: [TrainingRunWorkerResourceBundle] = [],
    pathComponents: [String] = ["Kuyu", "TrainingWorkerLaunches"],
    fileManager: FileManager = .default
  ) throws -> Self {
    return Self(
      executableURL: executableURL,
      launchRootDirectory: try userCacheLaunchRoot(
        pathComponents: pathComponents,
        fileManager: fileManager
      ),
      resourceBundles: resourceBundles
    )
  }

  public static func userCache(
    executableSource: TrainingRunWorkerExecutableSource,
    resourceBundles: [TrainingRunWorkerResourceBundle] = [],
    pathComponents: [String] = ["Kuyu", "TrainingWorkerLaunches"],
    fileManager: FileManager = .default
  ) throws -> Self {
    Self(
      executableSource: executableSource,
      launchRootDirectory: try userCacheLaunchRoot(
        pathComponents: pathComponents,
        fileManager: fileManager
      ),
      resourceBundles: resourceBundles
    )
  }

  private static func userCacheLaunchRoot(
    pathComponents: [String],
    fileManager: FileManager
  ) throws -> URL {
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
    return launchRootDirectory
  }
}
