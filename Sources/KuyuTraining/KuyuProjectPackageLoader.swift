import Foundation

public struct KuyuProjectPackageLoader: Sendable {
    private let decoder: JSONDecoder

    public init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load(from rootURL: URL) throws -> KuyuProjectPackage {
        try KuyuProjectPackageWriter.validatePackageExtension(rootURL)
        let manifestURL = rootURL.appendingPathComponent("project.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw KuyuProjectPackageError.missingProjectManifest(path: manifestURL.path)
        }

        let manifest = try read(KuyuProjectManifest.self, from: manifestURL)
        let template = try read(
            LearningProjectTemplate.self,
            from: rootURL
                .appendingPathComponent("templates", isDirectory: true)
                .appendingPathComponent("selected-template.json")
        )
        let experiment = try read(
            KuyuProjectExperiment.self,
            from: rootURL
                .appendingPathComponent("experiments", isDirectory: true)
                .appendingPathComponent("default", isDirectory: true)
                .appendingPathComponent("experiment.json")
        )
        let robotManifest = try read(
            LearningProjectRobotManifestReference.self,
            from: rootURL
                .appendingPathComponent("robot-manifests", isDirectory: true)
                .appendingPathComponent("default", isDirectory: true)
                .appendingPathComponent("robot-manifest-ref.json")
        )
        let environment = try read(
            KuyuProjectEnvironmentReference.self,
            from: rootURL
                .appendingPathComponent("environments", isDirectory: true)
                .appendingPathComponent("default", isDirectory: true)
                .appendingPathComponent("environment.json")
        )
        let sourceBundle = try read(
            KuyuProjectBundleReference.self,
            from: rootURL
                .appendingPathComponent("model-bundles", isDirectory: true)
                .appendingPathComponent("source.bundle-ref.json")
        )

        let package = KuyuProjectPackage(
            rootURL: rootURL,
            manifest: manifest,
            selectedTemplate: template,
            defaultExperiment: experiment,
            robotManifestReference: robotManifest,
            environmentReference: environment,
            sourceBundleReference: sourceBundle
        )
        try KuyuProjectPackageValidator().validate(package)
        return package
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }
}
