import Foundation
import KuyuTrainingContracts

struct TrainingRunWorkerAuthorizedRoots: Sendable {
  let artifactRoots: [URL]
  let sourceRoots: [URL]
  let projectRoots: [URL]

  init(artifact: TrainingRunWorkerLaunchArtifact) {
    artifactRoots = [Self.parent(of: artifact.operation.artifactRoot)]

    var sources: [URL] = []
    var projects: [URL] = []
    switch artifact.operation {
    case .start(let request):
      if let sourceBundle = request.sourceBundle {
        sources.append(Self.parent(of: sourceBundle.url))
      }
      if let projectRoot = request.projectRoot {
        projects.append(Self.parent(of: projectRoot))
      }
      if let reinforcementRoot = request.configuration.artifacts
        .reinforcementTrainingArtifactDirectory
      {
        sources.append(Self.parent(of: reinforcementRoot))
      }
    case .resume(let request):
      switch request.source {
      case .artifactRoot(let artifactRoot):
        sources.append(Self.parent(of: artifactRoot))
      case .checkpoint(let checkpoint):
        sources.append(Self.parent(of: checkpoint.url))
      case .continuation(let continuation):
        sources.append(Self.parent(of: continuation.artifactRoot))
        sources.append(Self.parent(of: continuation.checkpoint.url))
      }
      if let projectRoot = request.projectRoot {
        projects.append(Self.parent(of: projectRoot))
      }
      if let reinforcementRoot = request.configuration.artifacts
        .reinforcementTrainingArtifactDirectory
      {
        sources.append(Self.parent(of: reinforcementRoot))
      }
    }
    sourceRoots = Self.unique(sources)
    projectRoots = Self.unique(projects)
  }

  var workerArguments: [String] {
    var arguments: [String] = []
    for root in artifactRoots {
      arguments.append(contentsOf: ["--allowed-artifact-root", root.path])
    }
    for root in sourceRoots {
      arguments.append(contentsOf: ["--allowed-source-root", root.path])
    }
    for root in projectRoots {
      arguments.append(contentsOf: ["--allowed-project-root", root.path])
    }
    return arguments
  }

  private static func parent(of url: URL) -> URL {
    url.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()
  }

  private static func unique(_ roots: [URL]) -> [URL] {
    var paths = Set<String>()
    return roots.filter { paths.insert($0.path).inserted }
  }
}
