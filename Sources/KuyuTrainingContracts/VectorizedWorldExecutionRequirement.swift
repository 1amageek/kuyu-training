public enum VectorizedWorldExecutionRequirement: String, Sendable, Codable, Equatable, CaseIterable {
    /// Require the accelerator shared-world path. Evaluation fails fast if any
    /// scenario is not tensor-world capable.
    case acceleratorSharedWorld

    /// Prefer the accelerator shared-world path, but fall back to isolated CPU
    /// worlds when a scenario is not tensor-world capable.
    case preferAcceleratorSharedWorld

    /// Require the isolated CPU world path even for tensor-world capable
    /// scenarios. Measured 6-10x faster than the shared accelerator world at
    /// small population batch sizes (see EVALUATION_PERFORMANCE_DECISION.md).
    case isolatedCpuWorlds
}
