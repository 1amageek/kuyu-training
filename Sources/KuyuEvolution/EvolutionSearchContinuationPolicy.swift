import KuyuTrainingContracts

/// Selects exploration parents for a generation in which no candidate passed
/// the strict search gate, so that a bounded number of rejected generations
/// can keep searching instead of terminating at the first all-fail
/// generation.
///
/// Candidates are ranked lexicographically: fewer safety violations first,
/// then higher task pass rate, then higher scalar fitness. Full-scenario
/// evidence is preferred over screening-fidelity evidence when both exist.
///
/// Exploration parenthood is NOT a capability claim: it never grants elite,
/// quality-diversity, or promotion eligibility. Those remain owned by the
/// strict gate.
public struct EvolutionSearchContinuationPolicy: Sendable {
    public init() {}

    public func explorationParentIDs(
        fitness: [FitnessSummary],
        limit: Int
    ) -> [String] {
        let finite = fitness.filter { summary in
            summary.scalarFitness.isFinite
                && summary.taskPassRate.isFinite
                && summary.safetyViolationRate.isFinite
        }
        let fullScenario = finite.filter { $0.evaluationFidelity.isFullScenario }
        let pool = fullScenario.isEmpty ? finite : fullScenario
        let ranked = pool.sorted { lhs, rhs in
            if lhs.safetyViolationRate != rhs.safetyViolationRate {
                return lhs.safetyViolationRate < rhs.safetyViolationRate
            }
            if lhs.taskPassRate != rhs.taskPassRate {
                return lhs.taskPassRate > rhs.taskPassRate
            }
            if lhs.scalarFitness != rhs.scalarFitness {
                return lhs.scalarFitness > rhs.scalarFitness
            }
            return lhs.candidateID < rhs.candidateID
        }
        return Array(ranked.prefix(max(1, limit)).map(\.candidateID))
    }
}
