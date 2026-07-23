extension EvolutionRunOrchestrator {
    func generationRecord(
        config: EvolutionRunConfig,
        generationIndex: Int,
        population: EvolutionPopulation,
        generationFitness: [FitnessSummary],
        allFitness: [FitnessSummary],
        gateReport: EvolutionGateReport,
        mutationRate: Double,
        mutationNoiseScale: Double
    ) -> PopulationGenerationRecord {
        PopulationGenerationRecord(
            runID: config.runID,
            generationIndex: generationIndex,
            candidateCount: population.candidates.count,
            evaluatedCandidateCount: generationFitness.count,
            eliteCandidateIDs: gateReport.eliteCandidateIDs,
            bestCandidateID: gateReport.bestCandidateID,
            bestFitness: gateReport.bestFitness,
            incumbentCandidateID: gateReport.incumbentCandidateID,
            incumbentFitness: gateReport.incumbentFitness,
            bestVsIncumbentDelta: gateReport.bestVsIncumbentDelta,
            minimumImprovementOverIncumbent: gateReport.minimumImprovementOverIncumbent,
            incumbentImproved: incumbentImproved(gateReport: gateReport),
            qualityDiversityCellCount: EvolutionQualityDiversityArchiveBuilder()
                .build(runID: config.runID, fitness: allFitness)
                .cells
                .count,
            mutationRate: mutationRate,
            mutationNoiseScale: mutationNoiseScale,
            accepted: gateReport.accepted,
            rejectionReasons: gateReport.rejectionReasons
        )
    }
}
