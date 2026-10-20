# DroneAcharya — Installation, Launch and Testing

All commands run in PowerShell from `E:\Hardik\Programming\DroneAcharya`. Every result below was produced on this machine:

- **CPU:** Intel Core Ultra 5 125H
- **Graphics:** Intel Arc integrated GPU
- **Memory:** 15.6 GB RAM
- **OS:** Windows 11
- **Engine:** Godot 4.7.2

## 1. Install and launch

| Need | How |
|---|---|
| Run the simulator | Only `Godot_v4.7.2-stable_win64.exe` (already in the workspace). The trained model ships in `simulator/models/`, so no Python or network is needed |
| Retrain or evaluate the ML model | Python 3.13 and `python -m pip install -r ml/requirements.txt` (numpy 2.3.5, scikit-learn 1.8.0, jsonschema 4.26.0) |

```powershell
.\Godot_v4.7.2-stable_win64.exe --path simulator          # run the game (or open simulator\project.godot in the editor and press F5)
```

**Session files** are saved to `%APPDATA%\DroneAcharya\sessions\`. **Exports** go to `%APPDATA%\DroneAcharya\exports\`. Tests write only to `%APPDATA%\DroneAcharya\test_runs\`.

## 2. Controls

| Mode | Keys |
|---|---|
| Flight training | W/S forward/back · A/D sideways · Q/E turn · Space/C climb/descend · V camera · R restart · Esc pause |
| Threat observation | Right-drag or W/A/S/D look · mouse wheel zoom · V eye/sensor view · Tab or click a marker to select · **F** acknowledge · **K** classify (with the panel's category and confidence) · **Enter** submit response · Esc pause · R restart |

No physical key is bound to two actions; `test_input_map.gd` checks this.

## 3. Automated tests

```powershell
$G = ".\Godot_v4.7.2-stable_win64_console.exe"
& $G --headless --path simulator --script res://tests/run_tests.gd                                   # full suite (~80 s)
& $G --headless --path simulator --script res://tests/run_tests.gd -- --exclude=flight_training,menus  # fast subset (81 tests, ~17 s)
& $G --headless --path simulator --script res://tests/run_tests.gd -- --only=rubric                  # one file
& $G --headless --path simulator --quit-after 600                                                      # headless scene-load check
python -m unittest discover -s ml/tests -v                                                             # ML pipeline (11 tests)
python -m unittest discover -s schemas -v                                                              # session JSON Schema (4 tests)
```

The runner fails a test on any failed assertion **and** on any engine or script error logged while it runs. It prints each file's duration and exits with code 1 on any failure. All tests are deterministic and offline. Waits are counted in physics frames or simulation ticks, never as wall-clock sleeps.

### Coverage by requirement

| Requirement | Test file(s) |
|---|---|
| Original flight mode and smoke tests (unchanged assertions) | `test_smoke.gd`, `test_flight_training.gd` (incl. the 23.9 s autopilot and chase-camera collision), `test_flight_model.gd`, `test_mission_state.gd`, `test_input_map.gd` |
| Main-menu navigation, scenario selection, briefing, settings | `test_menus_and_observation.gd` |
| Scenario configuration validation, procedural generation | `test_scenario_config.gd` |
| Seed reproducibility; single-drone and swarm creation; day/night; urban/rural | `test_threat_world.gd`, `test_menus_and_observation.gd` |
| Sensor range, field of view, line of sight, noise, missed detections, delay, degradation | `test_sensor_and_tracker.gd` |
| Track association, lifecycle, stale tracks, swarm grouping | `test_sensor_and_tracker.gd` |
| Ground-truth isolation from model inputs and the UI | `test_decision_models.gd`, `test_sensor_and_tracker.gd`, `test_menus_and_observation.gd`, `ml/tests` |
| Model loading, prediction schema, fallback, parity, latency | `test_ml_classifier.gd`, `ml/tests` |
| Training-data leakage checks; evaluation output generation | `ml/tests/test_pipeline.py` (seed-disjoint splits, shipped metrics recomputed from the full test split) |
| Decision policy and uncertainty handling | `test_decision_models.gd` |
| Scoring formulas, penalties, bounds and edge cases | `test_rubric.gd` |
| Replay reproducibility | `test_sessions_and_replay.gd`, `test_menus_and_observation.gd` |
| JSON export/import and schema validation; history persistence | `test_sessions_and_replay.gd`, `schemas/test_session_schema.py` |
| Adaptive-difficulty bounds and rules | `test_adaptive.gd` |
| Invalid scenarios, missing or invalid model artefacts, invalid session files | `test_scenario_config.gd`, `test_ml_classifier.gd`, `test_sessions_and_replay.gd` |

### Results (final run, Phase 6)

| Suite | Result |
|---|---|
| Godot | **108 passed, 0 failed**, exit code 0, 83 s |
| Fast Godot subset | 81 passed in 17 s |
| Python ML | **11 passed** |
| Python schema | **4 passed** |
| Flight autopilot regression | completes in **23.9 s**, identical to Stage 1 on every run |

Two `WARNING` lines in the output are expected: they come from a test that deliberately builds incomplete scene parts.

**Deviation from 23.9 s, investigated.** During Phase 6 I tried running tests with `Engine.time_scale = 8`. The autopilot then took 26.4 s, and a yaw assertion failed. Godot scales the physics `delta` with `time_scale`, so that change was a real behavioural change, not timing variation. It was reverted, and the original 23.9 s returned. Only the observation tests were sped up, by stepping the simulation directly rather than waiting in real time.

## 4. Performance (measured, not assumed)

`.\Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path simulator --script res://tools/measure_performance.gd -- --out=C:/Temp/perf.json`

Measured with vsync off at 1600×900:

| Measure | Typical scenario | 30-actor stress scenario |
|---|---|---|
| Startup to first menu frame | 1.08 s (engine initialisation 0.91 s) | — |
| Simulation tick (20 Hz) | mean 0.10 ms, p95 0.20 ms | mean 1.13 ms, p95 3.2 ms |
| Once-per-second decision tick (features, both classifiers, policy) | mean 2.4 ms | mean 19.3 ms, max 29.9 ms (52 tracks) |
| Share of real time used by the simulation | 0.4 % | 4.1 % |
| ML inference per track | 0.14 ms | 0.15 ms |
| Frame rate, eye / sensor view (mean; 1 % low) | 647 / 572 FPS; 362 / 338 | 631 / 555 FPS; 319 / 288 |
| Session file | 262 KB (180 s) | 0.72 MB at 60 s; 4.5 MB at 300 s (limit 20 MiB) |

**Limitation:** in the stress case, the decision tick can take up to about 30 ms, longer than one 60 Hz frame. That may cause a brief hitch once per second (Future work in `DRONEACHARYA_ARCHITECTURE.md` §6).

Earlier phase measurements:

- **Stage 1 flight course:** 593 FPS mean / 524 minimum.
- **Dataset generation** (1,050 scenarios, 4 processes): about 6 minutes.
- **Training** (3 candidates): about 20 s.
- **Evaluation:** about 10 s.

## 5. Visual and manual checks performed

Screenshots were captured in a real window with `tests/tools/capture_screens.gd` and `tests/tools/capture_flythrough.gd`, and inspected after each phase:

- menu, scenario selection, briefing and settings;
- swarm in urban daylight (eye and TV sensor view);
- mixed contacts at night under 70 % radar degradation (thermal view, coasting tracks);
- single contact in fog;
- after-action review, and 3D replay with truth labels.

Issues found this way and fixed:

- the decision panel overflowing at 1600×900;
- mirrored ring and camera transforms (Stage 1);
- washed-out TV view and low marker contrast;
- oversized truth labels;
- overlapping swarm labels.

**Not yet performed:** a human playing a full observation exercise end to end with mouse and keyboard. The scripted equivalents pass.

## 6. Reproduce the ML model

See `DRONEACHARYA_DATASET_AND_EVALUATION.md` §6. Generation is deterministic; the model file stores the dataset SHA-256 hashes.

## 7. Packaging (outstanding: needs your action)

`simulator/export_presets.cfg` defines a **Windows Desktop** preset:

- output `exports/DroneAcharya.exe`;
- embedded PCK;
- includes `scenarios/*.json` and `models/*.json`;
- excludes tests and tools.

Exporting needs the official **Godot 4.7.2 export templates** (about 1 GB), which are not installed. The run on this machine stopped with: `No export template found at …/AppData/Roaming/Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe`.

To finish packaging:

1. Open the editor.
2. Go to **Editor → Manage Export Templates → Download and Install**.
3. Run:

   ```powershell
   .\Godot_v4.7.2-stable_win64_console.exe --headless --path simulator --export-release "Windows Desktop" ../exports/DroneAcharya.exe
   ```
