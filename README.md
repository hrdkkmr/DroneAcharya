# DroneAcharya

AI-enabled drone and counter-drone **threat-recognition training simulator** (prototype) for a desktop PC, built with Godot 4.7.2.

**Synthetic training only:**

- fictional environments, synthetic actors and sensors;
- procedural (non-kinetic) responses;
- no operational capability or real-world accuracy claim.

## Quick start (Windows, PowerShell, from this folder)

```powershell
.\Godot_v4.7.2-stable_win64.exe --path simulator                                                 # play
.\Godot_v4.7.2-stable_win64_console.exe --headless --path simulator --script res://tests/run_tests.gd   # 108 tests
python -m unittest discover -s ml/tests ; python -m unittest discover -s schemas                  # 11 + 4 tests
```

## Modes

- Flight training (pilot a drone through a four-ring course).
- Threat observation and classification: radar-like and camera sensor tracks, decision support from a rule-based baseline **and** a trained ML classifier, scoring.
- Scenario selection (presets and seeded procedural generation).
- Training history with after-action review, deterministic 3D replay, export/import and a rule-based next-exercise recommendation.
- Settings and model information.

## Documentation (`docs/`)

| Topic | File |
|---|---|
| Architecture | `DRONEACHARYA_ARCHITECTURE.md` |
| Simulation, sensors and tracking | `DRONEACHARYA_SIMULATION_MODELS.md` |
| Decision models, rubric and adaptation | `DRONEACHARYA_DECISION_MODELS.md` |
| ML dataset and evaluation | `DRONEACHARYA_DATASET_AND_EVALUATION.md` |
| Session format and VIGIL mapping | `DRONEACHARYA_SESSION_SCHEMA.md` |
| Install, test, performance, packaging | `DRONEACHARYA_TESTING.md` |
| Plan and status | `DRONEACHARYA_STAGE2_PLAN.md` |
| Baseline and restore | `DRONEACHARYA_BASELINE.md` |

`VIGIL/` is the original browser trainer, kept byte-for-byte unchanged (tag `baseline-vigil-2026-10-20`).
