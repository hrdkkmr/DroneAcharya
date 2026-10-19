# DroneAcharya — Session Record Schema (`droneacharya-session` v1)

| Item | Location |
|---|---|
| Structural schema | `schemas/droneacharya-session-1.schema.json` (JSON Schema 2020-12) |
| Example record | `schemas/examples/session_example.json` (produced by `simulator/tools/export_sample_session.gd`) |
| Writer | `scripts/training/session_record.gd` |
| Validator, files, history, export/import | `scripts/training/session_io.gd` |
| Deterministic replay | `scripts/training/replay.gd` |

The structural schema is checked independently by `python -m unittest discover -s schemas`. The GDScript validator enforces the same structure **plus** the semantic rules in §3. Both are run on the committed example.

**VIGIL cannot import these records.** No importer exists; §5 only documents how the fields relate.

---

## 1. Top-level fields

| Field | Type | Meaning |
|---|---|---|
| `format`, `format_version` | `"droneacharya-session"`, `1` | Identity and version |
| `session_id` | string `^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$` | Generated as `da-<seed>-<unix time>`; no personal data |
| `created_at` | ISO-8601 UTC string | When the record was built |
| `scenario` | `droneacharya-scenario` v1 object | The **validated config**, including the seed. Together with `generator` this fully determines the world |
| `generator` | string (`generator-1`) | Scenario generator version |
| `tick_rate` | `20` | Simulation ticks per second |
| `status` | `completed` \| `aborted` | Outcome |
| `end_tick`, `end_t` | integer, seconds | Last simulated tick and time |
| `models` | object | `features`, `rules`, `policy` versions; `ml` = `{loaded, version, model_type, path, error, classes, trees, features}` or `{loaded: false}` |
| `spam_count` | integer | Invalid or repeated trainee actions (rubric P4) |
| `events` | array | **Trainee-visible** event log (§2) |
| `observations` | `{columns, rows}` | Every delivered synthetic observation, in compact row form (§2) |
| `tracks` | array | Every track ever created: `{id, status, created_t, confirmed_t, retired_t, hits, obs_ids}` |
| `truth` | object | **Ground truth, for assessment and replay only** (§4) |
| `evaluation` | object | `da-rubric-1` result: `score`, `weighted_score`, `penalty_points`, `components`, `entities`, `findings`, `comparable`, `eligible_entities` |

## 2. Events and observations (trainee-visible)

Each event is `{seq, tick, t, type, data}`, where `seq` runs from 1 to n.

| `type` | `data` |
|---|---|
| `started` | `{scenario_id, seed, ml_active}` |
| `paused`, `resumed` | `{}` |
| `finished` | `{outcome: completed \| aborted}` |
| `sensor_degraded`, `sensor_restored` | `{severity}` |
| `track_created`, `track_confirmed`, `track_coasting`, `track_reacquired`, `track_lost`, `track_dropped` | `{track_id}` |
| `model_output` | `{track_id, rules: {model, category, confidence, evidence, rule}, ml?: {…}, policy: {response, reason_code, based_on}}`, logged whenever an output changes |
| `action` | `{kind: acknowledge \| classify \| respond, track_id, valid, members?, category?, confidence?, response?, model_recommendation?, spam?, message?}`. Rejected actions are logged with their arguments, so replay reproduces them |
| `decision_support_visible` | `{visible}` |

`observations.columns` = `id, sensor, t, t_delivered, bearing_deg, elevation_deg, range_m, quality, degraded, id_reply, id_quality, apparent_size_m, flap_detected`. These are the measured synthetic values only (see `DRONEACHARYA_SIMULATION_MODELS.md` §6).

## 3. Validation rules (GDScript validator)

1. **Format and version** match exactly. Unknown versions are rejected, never migrated.
2. **Required fields** are present. `session_id` matches its pattern. `scenario` passes full `droneacharya-scenario` validation.
3. **Events:**
   - `seq` is contiguous from 1;
   - `tick` never decreases;
   - every type is known;
   - the first event is `started`;
   - the last is `finished` with `outcome == status`;
   - `end_tick` equals the last tick;
   - a completed session ends exactly at `duration_s × 20`, and no session ends after it.
4. **Observations** use exactly the documented columns. Every track's `obs_ids` exist.
5. **Truth:** the actors are complete, and every truth link points to an actor or `clutter`.
6. **Evaluation:** recompute and compare. `da-rubric-1` is re-run on the record, and the stored evaluation must be identical (canonical JSON). A mismatch rejects the record, which is **never repaired**. This follows VIGIL's validation policy.
7. **Size:** files are limited to 20 MiB.

## 4. Ground truth (`truth`)

| Field | Meaning |
|---|---|
| `actors[]` | `{id, profile, behavior, truth_category, significant, group_id, spawn_tick}` |
| `links` | observation id → actor id or `"clutter"` |
| `events[]` | `{tick, type: spawned \| exited, actor_id}` |
| `availability[]` | Once per second: `{t, active, id, zone}`, the actors that are active, **genuinely available at identification quality**, and inside the protected zone |
| `protected_zone_radius_m` | Zone radius |

During an exercise, neither the trainee UI nor any decision model reads this section; tests in `test_decision_models.gd` and `test_menus_and_observation.gd` verify this. The after-action review and the replay's optional "Truth labels" show it **after** the exercise.

## 5. Mapping to VIGIL `vigil-session-export` (reference only)

VIGIL's `SessionRecord` (schemaVersion 3) is described in `docs/DRONEACHARYA_AUDIT.md` §3. **VIGIL cannot import DroneAcharya sessions.** Its validator regenerates the scenario with its own 2D generator and re-scores against its 4-second observation schedule, so any DroneAcharya record would be rejected. The mapping below is documentation for a possible future importer.

| Concept | VIGIL field | DroneAcharya field | Notes |
|---|---|---|---|
| Record identity | `id`, `schemaVersion: 3` | `session_id`, `format_version: 1` | Different formats and versions |
| Trainee | `profileId` (anonymous profile) | — | Not stored; no personal data is kept |
| Times | `startedAt`, `endedAt` (ISO) | `created_at` (ISO), `end_t` (simulated s) | DroneAcharya does not record wall-clock start |
| Status | `completed` \| `aborted` | `completed` \| `aborted` | Same meaning, including "aborted = not comparable" |
| Scenario config | `scenario.config` (environment urban/rural, lighting day/dusk/night, weather, reliability, noise, delay, trackCount, trafficPattern, difficulty 1–5, seed, objectives, weights) | `scenario` (environment, time_of_day, visibility, sensor block, groups, difficulty 1–5, seed, weights) | Shared vocabulary: environment, difficulty, seed, weights. VIGIL `grouped` corresponds roughly to a `swarm_uav` group. `dusk`, `rain`, `trafficPattern` and objectives have no equivalent |
| Hidden truth | `scenario.tracks[]` with `category` routine/review/background, `significant` | `truth.actors[]` with `profile` and the same `truth_category` / `significant` vocabulary | DroneAcharya profiles are finer-grained (five), and positions are 3D metres, not a 0–100 grid |
| Observations | `observation` events on a fixed 4-s schedule plus requests; `confidence`, `motion` and `signature` cues | `observations` rows from two sensors with variable rates, delays and identification-quality cues | **Differently interpreted:** no `request_observation` action; no "clear observation" count |
| Trainee actions | `select`, `track`, `request_observation`, `classify(category, confidence)`, `report(decision log/observe/escalate, summary)` | `acknowledge`, `classify(category, confidence)`, `respond(response)` | `track` ≈ `acknowledge`; `report` ≈ `respond`. Five procedural responses instead of three decisions; no free-text summary |
| Evidence | Count of "clear" observations (≥ 60 % confidence, resolved cues) | Seconds genuinely available at identification quality (truth geometry) | **Differently interpreted** |
| Scoring | `rubric-1`: detection, classification, uncertainty, reporting, decision, objectives; P1–P3 | `da-rubric-1`: detection, classification, evidence, response, response_time, degraded; P1–P4 | Same formulas where meaningful (window credit, unknown credit, decision table). VIGIL "objectives" has no equivalent; "degraded" and P4 are new |
| Findings | `{ruleId, anchorEventId, points, appliedPenalty, reason, eventIds}` | `{rule, entity, points, penalty, reason, event_seqs}` | Same concept; events are referenced by sequence number |
| Replay | Prefix projection of recorded events; never re-runs the engine | Deterministic re-simulation from config + recorded actions, verified identical | **Different approach.** Wall-clock pause lengths are not recorded in either |
| Adaptation input | `recommendNext(records)` reads comparable completed scores | Phase 6 rule-based adaptation reads `evaluation.components` | See `DRONEACHARYA_DECISION_MODELS.md` |
| Bundle | `vigil-session-export` v1 with profiles | `droneacharya-history` v1 `{format, format_version, exported_at, sessions[]}` | Import is an immutable merge in both: a same-id conflict is rejected |

**Not supported in DroneAcharya:** profiles and units, objectives, IndexedDB storage, CSV and HTML export.

**Not supported in VIGIL:** 3D geometry, multiple sensors, track lifecycle, ML model outputs, swarm groups, degradation scoring.

## 6. Storage, history, export and import

| Action | Behaviour |
|---|---|
| Save | At the end of an exercise, to `user://sessions/<session_id>.json`, which is `%APPDATA%\DroneAcharya\sessions\` on Windows. The file is validated first and written via a `.tmp` file plus rename. A different record with an existing id is **not** written |
| History | Every `*.json` in the folder is validated. Invalid files are listed with their reason and **left untouched** |
| Export | `user://exports/droneacharya-session-<id>.json` (selected session) or `droneacharya-history-<date>.json` (all sessions) |
| Import | A `droneacharya-history` bundle chosen in a file dialog. **Every** session is validated first; any invalid or conflicting session aborts the whole import (nothing partial). Identical duplicates are skipped |
| Replay | "Verify replay" re-simulates and reports whether events and evaluation are identical. "Replay in 3D" plays the re-simulation with a timeline, speed and optional truth labels. A missing or different ML model version is reported as a warning |
| Size | A 120 s single-contact session is about 194 KB; a 60 s example is 147 KB pretty-printed |
