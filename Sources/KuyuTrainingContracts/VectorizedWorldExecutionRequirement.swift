public enum VectorizedWorldExecutionRequirement: String, Sendable, Codable, Equatable, CaseIterable {
    /// Require the accelerator shared-world path. Evaluation fails fast if any
    /// scenario is not tensor-world capable.
    case acceleratorSharedWorld

    /// Prefer the accelerator shared-world path, but fall back to isolated CPU
    /// worlds when a scenario is not tensor-world capable.
    case preferAcceleratorSharedWorld
}
