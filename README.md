# kuyu-training

Training data collection and pipeline infrastructure for the Kuyu simulation environment.

## Overview

kuyu-training handles the data side of the training pipeline: collecting rollouts from simulations, labeling them, exporting datasets, and orchestrating the training curriculum.

### Data Collection

- **`TrainingDatasetWriter`** — Writes per-step records (observations, actions, rewards) to structured dataset files.
- **`TrainingDatasetExporter`** — Exports complete datasets from scenario runs.
- **`ParallelDataCollector`** — Concurrent data collection across multiple scenarios.
- **`OnlineDataBuffer`** — Rolling buffer for online training data.

### Training Pipeline

- **`AutomatedTrainingPipeline`** — Orchestrates the full training sequence: BC warm-start, swap adaptation, reflex HF stress, optional RL fine-tuning.
- **`CurriculumController`** — Manages progressive difficulty scheduling.
- **`AutoLabeler`** — Automatic labeling of rollouts with rewards and success criteria.

### Dataset Types

- **`TrainingDatasetTypes`** — Shared types for dataset records, metadata, and formats.

## Package Structure

| Module | Dependencies | Description |
|--------|-------------|-------------|
| **KuyuTraining** | KuyuCore, KuyuPhysics, KuyuScenarios | Training data and pipeline |

## Requirements

- Swift 6.2+
- macOS 26+

## Dependency Graph

```
KuyuCore
  |
  +-- KuyuPhysics
  |     |
  |     +-- KuyuScenarios
  |           |
  |           +-- KuyuTraining (this package)
  |                 |
  |                 +-- kuyu (uses training in UI/CLI)
  |
  +-- manas (controller being trained)
```

## License

See repository for license information.
