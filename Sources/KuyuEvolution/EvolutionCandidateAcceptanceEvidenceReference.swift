public struct EvolutionCandidateAcceptanceEvidenceReference: Sendable, Codable, Equatable {
    public let artifactType: String
    public let relativePath: String
    public let sha256Digest: String
    public let byteCount: Int64

    public init(
        artifactType: String,
        relativePath: String,
        sha256Digest: String,
        byteCount: Int64
    ) {
        self.artifactType = artifactType
        self.relativePath = relativePath
        self.sha256Digest = sha256Digest
        self.byteCount = byteCount
    }
}
