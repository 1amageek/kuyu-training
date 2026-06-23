# Kuyu Training Target Ownership

This file defines the pre-split ownership map for the current single-target
`KuyuTraining` package. The package still exposes one facade target, but new
source files must fit one of these future target responsibilities before the
physical split is performed.

## Future Targets

| Future target | Owns | Import posture before split |
|---|---|---|
| `KuyuTrainingContracts` | Plans, project manifests, task/profile contracts, model bundle references, run requests, run summaries, IDs, tensor shapes, and stable facade protocol types. | Must stay independent of `KuyuPhysics`, `KuyuScenarios`, MLX, and Manas internals. |
| `KuyuEvolution` | Candidate evaluation, population seed requests, reproduction requests, selection, mutation, evolution artifacts, resume state, lineage, and quality diversity. | Must stay independent of `KuyuPhysics`, `KuyuScenarios`, MLX, and Manas internals. |
| `KuyuReinforcement` | Reinforcement backend protocols, rollout health contracts, world-model tuples, online buffers, vectorized batch specs, and vectorized collectors. | Core protocols and data structures must stay independent of `KuyuPhysics`, `KuyuScenarios`, MLX, and Manas internals. Runtime harnesses may depend on scenario/world protocols until the split. |
| `KuyuTrainingRuntime` | Orchestration, probe execution, managed run handles, standard executors, archive driver lifecycle, cancellation/resume, control commands, progress, and event streams. | May depend on scenario execution and durable run contract types. Must not depend on MLX or Manas internals. |
| `KuyuTrainingValidation` | Artifact validation, project validation, dataset validation, convergence gates, checkpoint gates, relabeling validators, action codecs, and profile-specific acceptance helpers. | May depend on domain contracts required to validate artifacts. Must not depend on MLX or Manas internals. |

## Gate

`/Users/1amageek/Desktop/Robot/unconscious/scripts/validate-kuyu-boundaries.sh`
enforces this map while the package is still a single target:

| Gate | Failure condition |
|---|---|
| File ownership | A new `Sources/KuyuTraining/**/*.swift` file is not classified into a future target responsibility. |
| Contract imports | A future contract file imports physics, scenarios, MLX, or Manas internals. |
| Evolution imports | A future evolution file imports physics, scenarios, MLX, or Manas internals. |
| Reinforcement core imports | A future reinforcement protocol/data file imports physics, scenarios, MLX, or Manas internals. |

The physical target split should happen only after these gates pass and the
facade API compatibility tests are in place.
