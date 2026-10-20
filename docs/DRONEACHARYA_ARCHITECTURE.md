# DroneAcharya — Architecture (as implemented)

> **Note (2026-10-20 overhaul):** `ARCHITECTURE.md` describes the current simulator, including flight missions, environments, radar, the new observation interface, reports and sound. This file remains the detailed reference for the threat-observation core.

Status: describes the code at the Phase 6 commit. The Phase 1 *proposal* that this file used to contain is preserved in Git history (commit `24b37d1`); where the implementation differs, this document is authoritative.

DroneAcharya is a **synthetic training prototype**: an AI-enabled drone and counter-drone threat-recognition trainer built as a Godot 4.7.2 desktop simulator. It is **not** an operational system.

- **Fictional content:** environments and actors are fictional, and sensors are synthetic.
- **Procedural responses only:** responses are communication and procedure steps. There is no weapon control, targeting, interception, electronic attack or "defeat" guidance anywhere in the code.

## 1. Components by kind

| Kind | Components | Docs |
|---|---|---|
| Deterministic simulation | scenario config and generator, threat world, flight model, vehicle state, player training drone (flight mode) | `DRONEACHARYA_SIMULATION_MODELS.md` |
| Synthetic sensor simulation | radar-like and camera (EO) sensor model, degradation, clutter, delays | same, §6 |
| Deterministic processing of observations | tracker (association, lifecycle, swarm groups), `features-1` | same, §7; `DRONEACHARYA_DECISION_MODELS.md` §1 |
| **Rule-based decisions** | Model 1 rule engine `rules-da-2`; Model 3 response policy `policy-da-1`; adaptive difficulty `adapt-da-1` | `DRONEACHARYA_DECISION_MODELS.md` |
| **Trained ML inference** | Model 2 `track-classifier-v1` (scikit-learn random forest, evaluated in GDScript) | `DRONEACHARYA_DATASET_AND_EVALUATION.md` |
| Training assessment | `da-rubric-1`, after-action review | `DRONEACHARYA_DECISION_MODELS.md` §5 |
| Records | session format, validation, history, export/import, deterministic replay | `DRONEACHARYA_SESSION_SCHEMA.md` |
| Future work | listed in §6 | — |

## 2. Data flow (threat-observation mode)

```
scenario JSON / procedural seed
  └─ ScenarioConfig.validate / generate ─► ScenarioGenerator.build ─► definition (truth labels stay here)
                                                                     │
ThreatSession.step() at 20 Hz:                                       ▼
  ThreatWorld.step()  ── physical_snapshot() (no labels) ──► SensorModel.update()
        │                                                         │ observations (measured values only)
        │ truth: spawned/exited, availability (1 Hz)               │ truth_links (separate map)
        ▼                                                         ▼
  truth channel ◄──────────────────────────────────────────  Tracker.process() ─► tracks, swarm groups
                                                                  │
                                    once per second: DecisionSupport.update()
                                    features-1 ─► Model 1 rules ─┐
                                               └► Model 2 ML ────┴► Model 3 policy ─► model_output events
                                                                  │
  trainee (UI) ─► acknowledge / classify / respond ─► action events (validated, logged)
                                                                  │
  end ─► SessionRecord.build ─► Rubric.evaluate (uses truth) ─► SessionIO.save ─► history / review / replay
```

**Isolation rule:** nothing on the trainee/model side of the diagram may read the truth channel during an exercise.

- **Tests that check it:** `test_decisions_never_read_ground_truth_labels` (rewrites every truth label and finds identical model outputs), `test_observations_carry_no_ground_truth`, and `test_track_ui_shows_only_tracker_output`.
- **When truth may be shown:** the review screen and the replay's "Truth labels" show truth only after the exercise.

## 3. Modes and screens

| Screen | Scene / script | Notes |
|---|---|---|
| Main menu | `scenes/main.tscn` / `scripts/menu/main_menu.gd` | Keeps the Stage 0 `Title` label (smoke test). Entries: Flight Training, Threat Observation, Scenario Selection, Training History & AAR, Settings & Model Information, Quit |
| Flight training | `scenes/flight/flight_training.tscn` | The Stage 1 course, unchanged apart from chase-camera collision. Autopilot regression: 23.9 s |
| Scenario selection | `scenes/menu/scenario_select.tscn` | 4 presets + seeded procedural generator (difficulty, environment, time, visibility, swarm, single) |
| Briefing | `scenes/menu/briefing.tscn` | Scenario, available observations, task, assessment weights, controls |
| Threat observation | `scenes/observation/observation.tscn` | Eye and sensor view (TV by day / thermal style at night), track markers at tracker estimates, track table, details, assessment panel, decision support labelled by method, pause / restart / exit; replay mode |
| History & AAR | `scenes/menu/history.tscn` | Sessions, review, verify replay, 3D replay, export / import, next recommended exercise |
| Settings & model info | `scenes/menu/settings.tscn` | Components, versions, status, held-out metrics, live latency, ML on/off |

Menu layouts are built in code with `scripts/ui/ui_kit.gd`, so styling stays consistent; the `.tscn` files are minimal roots. Selected scenario, review session and settings pass between screens through static variables in `scripts/app/app_state.gd` (no autoload, so headless tests work).

## 4. Folder structure

```
DroneAcharya/
├─ simulator/                 Godot project (res://)
│  ├─ scenes/                 main menu, flight/, menu/, observation/, course/, drone/, ui/
│  ├─ scripts/
│  │  ├─ sim/                 scenario_config, scenario_generator, threat_world, flight_model,
│  │  │                       vehicle_state, actor_profiles, sensor_model, tracker, threat_session, sim_random
│  │  ├─ ai/                  features, rule_engine, ml_classifier, decision_policy, decision_support, vocabulary
│  │  ├─ training/            rubric, session_record, session_io, replay, aar, adaptive
│  │  ├─ observation/         scene, HUD, overlay, observer rig, environment builder, actor visuals
│  │  ├─ flight/, drone/, camera/, mission/, course/, ui/, menu/, app/
│  ├─ scenarios/              droneacharya-scenario v1 presets
│  ├─ models/                 track_classifier_v1.json (+ .metrics.json)  ← deployed ML artefact
│  ├─ shaders/                ground grid, sensor view
│  ├─ tools/                  generate_dataset, export_sample_session, measure_performance
│  ├─ tests/                  GDScript suites, fixtures/, tools/ (autopilot, screenshot capture)
│  └─ export_presets.cfg      Windows Desktop export (needs export templates)
├─ ml/                        Python training/evaluation: common, train, evaluate, tests/, reports/, requirements.txt
│  └─ data/                   generated datasets (git-ignored)
├─ schemas/                   droneacharya-session-1.schema.json, examples/, test_session_schema.py
├─ docs/                      this documentation set
└─ VIGIL/                     original application — byte-for-byte unchanged (baseline tag)
```

## 5. Key design decisions

| Decision | Why |
|---|---|
| **Pure simulation core** (RefCounted classes, no nodes) stepped at a fixed 20 Hz from integer ticks | Determinism: one code path serves the game, tests, the dataset generator and replay |
| **Separate seeded random streams** (FNV-1a(seed \| label)) | Adding a stream never changes existing ones, so scenarios stay reproducible |
| **Truth links stored outside observations** | Ground truth cannot leak into inference by accident; evaluation and labelling can still use it |
| **ML trained in Python, inferred in GDScript** from a versioned JSON artefact | No Python, service or network at run time; parity with scikit-learn is tested (< 10⁻⁶) |
| **Classification and response are separate models** | Each can be tested and explained alone; the policy works with either classifier |
| **Score by recompute-and-compare** (the VIGIL validation policy) | A stored score is never trusted or repaired; tampering is detected |
| **Replay by deterministic re-simulation**, verified identical | Replay shows the real 3D scene, not just a log; any divergence is reported |
| **VIGIL not modified** | Its scorer requires its 2D observation schedule; DroneAcharya implements its own adapted rubric and documents a field mapping (`DRONEACHARYA_SESSION_SCHEMA.md` §5) |

## 6. Future work (not implemented)

- A VIGIL importer or dashboard module (VIGIL must remain unchanged; no importer exists).
- Spreading the once-per-second decision-support work across ticks: about 19–30 ms in the 30-actor stress case can cause a small hitch once per second (`DRONEACHARYA_TESTING.md` §4).
- Terrain relief and line-of-sight on heightmaps; more environments (the brief mentions mountain, desert and riverine looks; currently rural and urban).
- A Kalman filter or multi-hypothesis tracker if evaluation shows a need; calibrated ML scores (e.g. isotonic calibration on validation data).
- Windows packaging, once the export templates are installed (§7 of `DRONEACHARYA_TESTING.md`).
- Gamepad support; localisation.
