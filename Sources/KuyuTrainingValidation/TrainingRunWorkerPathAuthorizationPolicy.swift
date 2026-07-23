import Foundation
import KuyuTrainingContracts

public struct TrainingRunWorkerPathAuthorizationPolicy: Sendable {
  public enum AuthorizationError: Error, Sendable, Equatable {
    case missingAllowedRoots(category: String)
    case invalidAllowedRoot(category: String, path: String)
    case unauthorizedPath(category: String, path: String)
  }

  private let artifactRoots: [URL]
  private let sourceRoots: [URL]
  private let projectRoots: [URL]

  public init(
    allowedArtifactRoots: [URL],
    allowedSourceRoots: [URL],
    allowedProjectRoots: [URL] = []
  ) throws {
    self.artifactRoots = try Self.validatedRoots(
      allowedArtifactRoots,
      category: "artifact"
    )
    self.sourceRoots = try Self.validatedRoots(
      allowedSourceRoots,
      category: "source"
    )
    self.projectRoots = try Self.validatedRoots(
      allowedProjectRoots,
      category: "project",
      allowsEmpty: true
    )
  }

  public func validate(_ artifact: TrainingRunWorkerLaunchArtifact) throws {
    try requireAuthorized(
      artifact.operation.artifactRoot,
      roots: artifactRoots,
      category: "artifact"
    )
    switch artifact.operation {
    case .start(let request):
      if let projectRoot = request.projectRoot {
        try requireAuthorized(projectRoot, roots: projectRoots, category: "project")
      }
      if let sourceBundle = request.sourceBundle {
        try requireAuthorized(sourceBundle.url, roots: sourceRoots, category: "source")
      }
      try validateReinforcementRoot(request.configuration)
      try validateStopSentinel(
        request.configuration,
        artifactRoot: request.artifactRoot
      )
    case .resume(let request):
      if let projectRoot = request.projectRoot {
        try requireAuthorized(projectRoot, roots: projectRoots, category: "project")
      }
      switch request.source {
      case .artifactRoot(let sourceRoot):
        try requireAuthorized(sourceRoot, roots: sourceRoots, category: "source")
      case .checkpoint(let checkpoint):
        try requireAuthorized(checkpoint.url, roots: sourceRoots, category: "source")
      case .continuation(let continuation):
        try requireAuthorized(
          continuation.artifactRoot,
          roots: sourceRoots,
          category: "source"
        )
        try requireAuthorized(
          continuation.checkpoint.url,
          roots: sourceRoots,
          category: "source"
        )
      }
      try validateReinforcementRoot(request.configuration)
      try validateStopSentinel(
        request.configuration,
        artifactRoot: request.destinationArtifactRoot
      )
    }
  }

  private func validateReinforcementRoot(_ configuration: TrainingRunConfiguration) throws {
    if let reinforcementRoot = configuration.artifacts.reinforcementTrainingArtifactDirectory {
      try requireAuthorized(reinforcementRoot, roots: sourceRoots, category: "source")
    }
  }

  private func validateStopSentinel(
    _ configuration: TrainingRunConfiguration,
    artifactRoot: URL
  ) throws {
    guard let stopSentinelPath = configuration.artifacts.stopSentinelPath else {
      return
    }
    let stopSentinelURL = URL(fileURLWithPath: stopSentinelPath, isDirectory: false)
    let resolvedArtifactRoot = Self.resolvedPath(artifactRoot)
    let resolvedSentinel = Self.resolvedPath(stopSentinelURL)
    guard Self.contains(path: resolvedSentinel, root: resolvedArtifactRoot) else {
      throw AuthorizationError.unauthorizedPath(
        category: "stop-sentinel",
        path: resolvedSentinel
      )
    }
  }

  private func requireAuthorized(
    _ url: URL,
    roots: [URL],
    category: String
  ) throws {
    let path = Self.resolvedPath(url)
    guard roots.contains(where: { root in Self.contains(path: path, root: root.path) }) else {
      throw AuthorizationError.unauthorizedPath(category: category, path: path)
    }
  }

  private static func validatedRoots(
    _ roots: [URL],
    category: String,
    allowsEmpty: Bool = false
  ) throws -> [URL] {
    guard allowsEmpty || !roots.isEmpty else {
      throw AuthorizationError.missingAllowedRoots(category: category)
    }
    return try roots.map { root in
      guard root.isFileURL, root.path.hasPrefix("/") else {
        throw AuthorizationError.invalidAllowedRoot(
          category: category,
          path: root.absoluteString
        )
      }
      return root.standardizedFileURL.resolvingSymlinksInPath()
    }
  }

  private static func resolvedPath(_ url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
  }

  private static func contains(path: String, root: String) -> Bool {
    path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
  }
}
