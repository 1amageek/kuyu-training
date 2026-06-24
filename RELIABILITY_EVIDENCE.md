# Kuyu Training Reliability Evidence

This file records package-local evidence for `RELIABILITY_MILESTONES.md`.
Entries must identify the verification command, the files or gates that prove
the claim, and what remains outside package-local reliability.

## Evidence Entries

| ID | Milestone | Status | Verification | Evidence | Scope |
|---|---|---|---|---|---|
| 2026-06-24-kt6-individual-reliability-baseline | KT6 individual reliability baseline | Passed for the current package-local self-verification baseline | `git -C /Users/1amageek/Desktop/Robot/unconscious/kuyu-training diff --check`; `/Users/1amageek/Desktop/Robot/unconscious/scripts/validate-kuyu-boundaries.sh`; `/Users/1amageek/Desktop/Robot/unconscious/scripts/validate-unconscious-boundaries.sh`; `TEST_TIMEOUT_SECONDS=120 /Users/1amageek/Desktop/Robot/unconscious/scripts/test.sh kuyu-training` (315 tests) | `README.md`, `RELIABILITY_MILESTONES.md`, `TARGET_OWNERSHIP.md`, `RELIABILITY_EVIDENCE.md`, `../INDIVIDUAL_RELIABILITY_MILESTONES.md`, `../scripts/validate-kuyu-boundaries.sh` | Proves `kuyu-training` has a package-local reliability ladder, target ownership map, evidence file, root individual reliability linkage, static import/source boundary gates, and package-level `xcodebuild` test coverage through `scripts/test.sh`. This proves the package can be audited as a generic training-contract dependency. It does not prove MLX backend quality, reference-quadrotor long-horizon G1 success, RoArm M1 hardware parity, or UI/CLI adapter completeness. |
