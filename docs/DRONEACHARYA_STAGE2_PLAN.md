# DroneAcharya — Stage 2 Plan: Threat Recognition and Decision Training

Date: 2026-10-20 · Status: **proposal for review. Nothing in this document has been implemented.**

Labels:

- **[VERIFIED]** — checked in source or by running it during this audit.
- **[PROPOSED]** — a design to be approved.
- **[DECISION]** — needs your answer.

## 0. Scope and safety boundary

Stage 2 adds a **threat-observation training mode** alongside the existing flight mode.

The trainee:

- watches a fictional border-inspired area from an observation post;
- finds synthetic aerial objects (single drones, swarms, birds, balloons, authorised aircraft) by eye or through a simulated sensor camera;
- classifies each one;
- chooses a **predefined, procedural training response**;
- then reviews a scored after-action report and replay.

Boundaries, which apply to every stage:

- **Responses are communication and procedure choices only.** Examples: log, keep observing, request an identity check, alert the supervisor, raise an area alert. There is no weapon, jamming, interception or "defeat" mechanic, and no guidance on how to counter a real drone.
- **The world is fictional.** Places are "inspired by" Indian border landscapes (high mountain ridge, desert, riverine plain), with no real coordinates, units, posts or place names.
- **Objects, cues and sensor readings are synthetic.** They are not models of real systems and are not calibrated to any real sensor.
- **No AI claims.** Detections, cues and "assistance" are scripted and deterministic, and are labelled as such in the UI. Nothing is presented as a trained model (see §6, Q1).

---

## 1. Current verified architecture

### 1.1 Repository state [VERIFIED 2026-10-20]

| Item | State |
|---|---|
| Commits | `24b37d1` baseline (tag `baseline-vigil-2026-10-20`, unchanged) → `db933d2` Stage 0. **Stage 1 is not committed.** It exists only as working-tree changes: 5 modified files, 33 untracked files and `docs/DRONEACHARYA_STAGE1.md` |
| `simulator/project.godot` | Re-saved by the Godot editor after Stage 1 (02:37). It removed `physics_ticks_per_second=60` and `rendering_method="forward_plus"`. I confirmed in Godot that both are the engine defaults (60, `forward_plus`), so behaviour is unchanged. This is normal editor clean-up |
| Tests | `run_tests.gd`: **32 passed, 0 failed, exit code 0** (re-run during this audit). The autopilot mission time is 23.9 s, as before |
| `VIGIL/` | Identical to the baseline tag (see §7) |

### 1.2 Simulator structure [VERIFIED]

```
Main (main.tscn / main.gd, process_mode Always): Esc pause, R reset, feeds HUD
├─ Course (training_course.tscn): sky, sun, ground, launch pad, landing zone, 4 rings, 6 obstacles
├─ Drone (drone.tscn / drone_controller.gd, CharacterBody3D)
├─ CameraRig (camera_rig.gd): FOLLOW / ONBOARD
├─ Mission (mission.gd) → MissionState (mission_state.gd, pure rules)
├─ HUD (hud.tscn / hud.gd, display-only)
└─ Title (Label "DroneAcharya — synthetic training only")
```

### 1.3 Interfaces that already support more than one training mode [VERIFIED]

| Interface | Why it is reusable |
|---|---|
| `MissionState` | Pure rules object with no scene access; `update()` and `pass_checkpoint()` return messages. It is a template for a `ScenarioState` with the same shape |
| `mission.gd` | Resolves its scene parts through exported `NodePath`s and stays inactive if any is missing. A tested pattern for an observation-mode controller |
| `drone_controller.gd` | `step(move, yaw, delta)` and `compute_velocity()` are independent of input, so the same class could fly **scripted threat drones** from waypoints without a second flight model |
| `camera_rig.gd` | Already switches between two cameras with `make_current()`. A sensor camera can be added the same way |
| `hud.gd` | Static formatters (`format_heading`, `format_time`, …) and display-only setters |
| `checkpoint.gd` / `landing_zone.gd` | `Area3D` and geometric zone tests. A "protected zone" uses the same pattern |
| Test harness | Async runner; a test fails on any engine error; `add_scene()`/`wait_physics_frames()`; a real-input autopilot that can serve as a template for a scripted "observer bot" |
| Determinism | Fixed 60 Hz physics with no randomness. The same inputs give the same result (verified by repeated 23.9 s runs) |

### 1.4 Current limitations relevant to Stage 2 [VERIFIED]

- **`main.tscn` is the flight mode.** `test_smoke.gd:11` requires the main scene to be `res://scenes/main.tscn` with a `Title` label. Adding a mode menu must keep that exact test passing (see §3.4).
- **Overlapping keys.**
  - C = `descend` + `classify`; R = `reset_mission` + `report`; Space = `ascend` + `jump`.
  - `mark` (F, left-click), `classify`, `report` and `jump` are defined but read by no code.
  - In an observation scene that reads both `report` and a restart action, R would trigger both, so **`report` must be re-bound** before Stage 2.3.
- **Chase camera** has no collision avoidance and can pass through a pillar or wall.
- **Simplified flight physics:** kinematic, with no wind, mass or battery. Adequate for scripted threat paths; not a flight-dynamics model.
- **Flat world:** one 400 m grid plane and one fixed course. There is no terrain, line-of-sight occlusion or environment variety.
- **No persistence:** no session file, score, replay or history. The mission time is shown and discarded.
- **Hard-wired HUD:** `main.gd` assumes the flight HUD. Observation mode needs its own HUD scene; it should not branch inside the flight HUD.

---

## 2. VIGIL functionality found in the source

Read directly from `VIGIL/src` (unchanged since the baseline). Phase 1 results still apply: 369/369 unit tests pass on a scratch copy.

| Capability | Where | What it actually does |
|---|---|---|
| Scenario config + presets | `domain/config.ts` | Zod-validated config: environment urban/rural, lighting day/dusk/night, weather clear/haze/rain, reliability, noise, delay, 1–8 tracks, traffic pattern independent / crossing / **grouped (≥ 3, swarm-like)**, 60–300 s, difficulty 1–5, uint32 seed, objectives, weights summing to 100. Four presets |
| Scenario generator | `engine/scenario.ts`, `engine/random.ts` | Seeded Mulberry32/FNV-1a; hidden tracks on a **normalised 0–100 2D grid**, truth category routine / review / background, `significant = review`; one seeded sensor-degradation window |
| Synthetic sensor | `engine/sensor.ts`, `domain/conditions.ts` | Scheduled observations every 4 s plus trainee requests; dropout, noise, confidence, delay and "resolved" motion/signature cues; urban clutter zones |
| Live engine | `engine/SimulationEngine.ts`, `workers/*` | Whole-second ticks in a Web Worker; public view without hidden truth |
| Trainee actions | `domain/actions.ts` | select → track → request_observation → classify(category, confidence) → report(log / observe / escalate, summary ≥ 12 chars); one report per track |
| Event log + validation | `engine/log.ts`, `domain/events.ts` | Ordered, ID-anchored events; strict validation including observation provenance against VIGIL's own 4 s schedule |
| Scoring | `scoring/evaluate.ts`, `scoring/rubric.ts` | `rubric-1`: detection / classification / uncertainty / reporting / decision / objectives (20/20/15/20/15/10), penalties P1 −4, P2 −8, P3 −5 (missed significant track), event-anchored findings, `comparable` flag |
| Replay | `replay/replay.ts` | Pure prefix projection over recorded events with time/event seeking; never re-runs the engine |
| Adaptation | `adaptive/policy.ts` | `rules-1` (not ML): weakest skill over ≤ 5 distinct-seed completions; difficulty ±1 only after 3 consistent attempts |
| History + analytics | `persistence/*`, `analytics/*` | Browser IndexedDB; import/export `vigil-session-export` v1, which **re-generates the scenario and re-scores before accepting**; descriptive summaries; formula-safe CSV; printable HTML report |

**What VIGIL does *not* have:** 3D, terrain, line of sight, visual recognition, object types (drone / bird / balloon / authorised aircraft), swarm-as-a-group classification, protected zones, response options beyond log/observe/escalate, desktop file storage, or any API or service.

### 2.1 What can be reused without modifying VIGIL [VERIFIED]

| Reuse | How | Limit |
|---|---|---|
| **Rubric design** (components, weights, `windowCredit` formula, unknown-credit table, evidence-based decision tree, penalties, event-anchored findings, `comparable` rule) | Port to GDScript as `da-rubric-1`, with a line-by-line traceability table and shared fixtures | `windowCredit` is **not exported** (`scoring/evaluate.ts:13`), and `evaluateSession` only accepts VIGIL logs that pass its 4 s sensor-provenance check, so the TS function cannot score a 3D session even from outside VIGIL |
| **Scenario vocabulary** (lighting, weather, difficulty 1–5, seed, objectives, weights; *grouped* ≈ swarm; truth categories) | Same field names and ranges in the Godot scenario format, so sessions are comparable and a later dashboard can map them | VIGIL's `environment` enum is urban/rural only |
| **Action chain** (select → track → classify + confidence → report) | Same order and preconditions in observation mode | — |
| **Replay principle** (replay recorded data, never re-simulate to reconstruct) | Same rule in the Godot AAR | Code is typed on VIGIL events |
| **`rules-1` progression** | Port later (about 60 lines) | Reads VIGIL `SessionRecord` fields directly |
| **Validation policy** (strict schema, no silent repair, recompute-and-compare on import) | Apply to session files | — |
| Executable TS code | Only trivial helpers are usable from outside (`clamp`, `round1`, `canonicalJson`, `csvCell`, `escapeHtml`) | Not worth a dependency |

**Conclusion:** VIGIL's *design* is highly reusable. Its *executable* scoring and replay code cannot score or replay a 3D session without changing VIGIL, which this stage forbids.

---

## 3. Proposed integration architecture

### 3.1 Options compared

| Option | What it means | Reuses VIGIL code? | Cost and risk for one student | Verdict |
|---|---|---|---|---|
| **A. In-process reuse** | Run VIGIL's TypeScript inside Godot | Would be full reuse | Godot cannot run TypeScript or JavaScript without a third-party JS-engine GDExtension: a new native dependency, a build chain and Windows packaging issues | **Rejected** |
| **B. Local service / sidecar** | Bundle VIGIL's engine and evaluator into a Node process that Godot starts (`OS.execute_with_pipe`, JSON lines); Godot renders VIGIL tracks in 3D | Full reuse of engine, evaluator and records; sessions importable into VIGIL unchanged | The 3D game would become a renderer of VIGIL's **2D, 1-second, 4-second-observation sensor feed**: objects could appear only at delivered, delayed observation positions, which defeats visual recognition. It also needs Node at play time, a separate bundling setup (VIGIL has no `node_modules`) and IPC error handling | **Rejected for gameplay.** It contradicts the 3D recognition goal |
| **C. File-based exchange** | Godot owns simulation and scoring and writes a versioned JSON session file; VIGIL is untouched | Reuses design; ~40 lines of formulas re-implemented in GDScript and traced to `rubric-1` | Simplest; works offline; testable headless; no new runtime | **Recommended** |

### 3.2 Recommended architecture (option C)

```
simulator/scenarios/*.scenario.json ─▶ ScenarioLoader (validate) ─▶ ScenarioRunner (60 Hz ticks, seeded)
                                                                     │  spawns ThreatObjects (scripted paths)
                                   ObservabilityProbe (LOS, range, fog, view cone; 10 Hz) ◀┘
Observer input ─▶ ObservationController ─▶ EventLog (ordered, ID'd) ─▶ Evaluator (da-rubric-1, pure)
                                                         │                         │
                                         Recorder (10 Hz transforms)        AAR screen + replay
                                                         └──▶ user://sessions/<id>.session.json
                                                              (= %APPDATA%\DroneAcharya\sessions)
```

- **One scoring implementation** for the 3D mode, in GDScript. It is not a second copy of VIGIL's engine, because VIGIL's evaluator cannot run on these sessions. Each `da-rubric-1` rule cites the `rubric-1` rule it adapts (D1, C1, U1, R1, Q1, O1, P1–P3) and states any difference.
- **The session file format** (`droneacharya-session` v1) is documented in `docs/`. It is the future integration point for VIGIL or any dashboard.
- **VIGIL dashboard integration is deferred.** Showing simulator sessions in VIGIL requires *adding* a module to VIGIL, which needs your explicit permission later (§6, Q4). Until then, after-action review and history live **in the game**, which also fits the "game-like, not dashboard-first" goal.

### 3.3 Proposed observation-mode scene structure [PROPOSED]

```
ObservationTraining (observation_training.tscn / observation_main.gd)
├─ Environment (environment_<preset>.tscn): terrain/props/lighting per preset
├─ ProtectedZone (zone.gd: radius, contains()) and ObservationPost (tower + spawn point)
├─ Threats (ScenarioRunner spawns ThreatObject instances; swarm = group of objects)
├─ Observer (observer_controller.gd): fixed post, mouse pan/tilt
│  ├─ EyeCamera (FOV 70)   └─ SensorCamera (zoom 25°→4°) + SensorOverlay (shader)
├─ ObservabilityProbe, ScenarioRunner, EventLog, Recorder
├─ ObservationHUD (contacts list, selected-track panel, classify/response panels, clock)
└─ Title (same safety notice)
```

### 3.4 Keeping the flight mode working and the tests unweakened [PROPOSED, DECISION]

Recommended:

- **`main.tscn` becomes a small mode menu** with the existing `Title` label, plus buttons for **Flight training** and **Threat observation**. `test_smoke.gd` still passes unchanged.
- The current flight scene moves as-is to `scenes/flight/flight_training.tscn` (`git mv`; contents unchanged).
- In the flight tests and capture tool, only the scene path changes. **No assertion changes.**

Alternative, with no file moves: keep `main.tscn` as flight mode and add a key (e.g. `F1`) that loads the observation scene. Simpler, but a hidden mode switch is poor UX.

---

## 4. Training workflow (observation mode) [PROPOSED]

| Step | What the trainee does / sees | Implementation notes |
|---|---|---|
| **1. Scenario selection** | Menu → Threat observation → list of scenarios (title, environment, time of day, visibility, difficulty, objectives). Optional seed field for instructors | Scenario JSON files in `simulator/scenarios/`; validated before listing; invalid files shown as "unavailable" with the reason |
| **2. Initialisation and spawning** | Briefing card (area, protected zone, rules, controls) → Start. Objects appear on their scripted timelines | Fixed-tick `ScenarioRunner`; spawn times and path jitter from `RandomNumberGenerator(seed)`, so the same seed gives identical runs |
| **3. Observation** | Mouse looks around from the post. `V` toggles eye ↔ simulated sensor (zoom on wheel, monochrome/grain/reticle, synthetic range/bearing/elevation readout with seeded noise) | Probe logs hidden `truth_observable` and `id_view` intervals. Sensor readouts are labelled "simulated" |
| **4. Detection and identification** | Aim and press **F** (or left-click) on an object → it becomes track T01, T02, … A mark on empty sky is logged as a miss. Tab cycles tracks | Mark is valid if the object is within an angular tolerance of the crosshair and observable |
| **5. Classification** | For the selected track, choose: *Bird / biological*, *Drifting object (balloon)*, *Authorised UAV*, *Unidentified UAV*, *Coordinated swarm*, *Unknown / insufficient evidence*, plus a confidence slider | Mirrors VIGIL's classify-with-confidence and `unknown`-is-legitimate rule |
| **6. Response** | Choose a predefined training response: *Log and continue*, *Continue observation*, *Request identity check*, *Alert supervisor*, *Raise area alert* | Procedural options only. Each object type has an "expected response" given the evidence (VIGIL-style decision tree) |
| **7. Scoring** | At scenario end: score /100 with components (detection timeliness, classification, uncertainty handling, response timeliness, response appropriateness, objectives), penalties (over-confidence, unjustified alert, **missed threat**, mark spam) and every finding linked to a moment | `da-rubric-1`, pure function over the event log; missed detections = significant objects observable but never marked |
| **8. After-action review and replay** | Results screen → **Replay**: the 3D scene replays recorded positions with a scrub bar; findings jump to their timestamp; hidden truth labels are shown *only* in review | Recorder stores object and camera transforms at 10 Hz; replay reads the recording and never re-simulates |
| **9. History and progression** | Menu → History: past sessions (date, scenario, score, components). "Next recommended scenario" with stated reasons | Reads `user://sessions/*.session.json`; progression rules ported from VIGIL `rules-1` (§5, Stage 2.5) |

### 4.1 Synthetic object catalogue (first set) [PROPOSED]

| Object | Visual / motion cue | Truth category (VIGIL) | Significant | Expected response with strong evidence |
|---|---|---|---|---|
| Bird (flock of 1–5) | Flapping silhouette, erratic glide | background | no | Log and continue |
| Drifting balloon | Round, slow, drifts with the scenario wind direction | background | no | Log and continue |
| Authorised UAV | Quadrotor, steady transit along the published corridor, steady green fictional ID light (visible in sensor view) | routine | no | Log and continue |
| Unidentified UAV | Quadrotor, no ID light, loiters near or approaches the protected zone | review | **yes** | Alert supervisor |
| Coordinated swarm (3–8) | Several quadrotors in formation (VIGIL *grouped* pattern) | review | **yes** | Raise area alert |

With weak evidence (too little identification-quality viewing), *Continue observation* or *Request identity check* is the expected response, mirroring VIGIL's "observe when evidence is insufficient" branch.

---

## 5. Incremental implementation plan

All stages use **Godot built-in features only**: GDScript, `JSON`, `FileAccess`, `RandomNumberGenerator`, `Area3D`/raycasts, `Camera3D`, shaders, `Control` UI. **No external dependencies** are planned.

Two rules apply to every stage:

- The 32 Stage 1 tests keep passing, and existing assertions are not weakened.
- `VIGIL/` is untouched.

### Stage 2.0b — housekeeping (prerequisite, small)

- Commit Stage 1 (needs your approval).
- Add the mode menu (§3.4) and move the flight scene. The tests are updated by path only.
- Re-bind the unused `report` action away from R (proposed **Enter**) so that observation mode can use R for restart. `test_smoke` only checks that `report` exists and has a binding, so it stays unchanged.
- **Acceptance:**
  - all 32 tests pass;
  - the menu opens both modes; the observation entry shows "coming soon";
  - flight mode behaves exactly as in Stage 1, verified by the autopilot test and a capture.

### Stage 2.1 — configurable scenario system

**Files:**

- `scripts/scenario/scenario_loader.gd`
- `scripts/scenario/scenario_state.gd` (pure)
- `scripts/scenario/scenario_runner.gd`
- `scripts/threats/threat_object.gd` and `scenes/threats/{uav,bird,balloon}.tscn`
- `scenes/observation/observation_training.tscn`
- `scenes/environments/{ridge,desert,riverine}.tscn` (primitive props + lighting/fog presets)
- `simulator/scenarios/*.scenario.json` (2–3 samples)
- `docs/SCENARIO_FORMAT.md`

**Visible behaviour:**

- Choose a scenario → briefing → objects spawn and move along scripted paths in a fictional environment, seen from a fixed post.
- The scenario ends at its duration.
- No classification yet.

**Tests:**

- loader accepts valid files and rejects a wrong format/version, missing fields, unknown object types, non-increasing waypoint times and out-of-range values;
- the same seed gives identical object positions at tick *t*, and a different seed differs;
- spawn and despawn happen at the scripted ticks;
- scenario state transitions (briefing → running → paused → ended);
- the scene loads headless without errors.

**Acceptance:**

- 2+ scenarios selectable and playable to the end;
- deterministic replays of a seed;
- flight tests unchanged and passing.

**Risks:**

- Scope creep in environment art. Mitigation: primitives, colours and fog only; terrain heightmaps come later.
- Format churn. Mitigation: versioned format from the start.

### Stage 2.2 — observer / sensor mode

**Files:**

- `scripts/observation/observer_controller.gd`
- `scripts/observation/sensor_view.gd` and `shaders/sensor_view.gdshader`
- `scripts/observation/observability_probe.gd` (pure geometry functions + node)
- `scenes/ui/observation_hud.tscn`
- new input actions: `obs_zoom_in/out` on the wheel, `cycle_track` on Tab

**Visible behaviour:**

- Mouse look from the post;
- `V` toggles eye ↔ sensor view with zoom and overlay;
- synthetic readout (range/bearing/elevation) for the object under the reticle when it is in identification view;
- objects can be hidden by terrain or props and fade in fog.

**Tests:**

- pure functions for angle-to-crosshair, range, fog visibility and LOS decision;
- probe interval events alternate and match scripted geometry;
- the view toggle switches cameras;
- the sensor overlay is visible only in sensor mode;
- a real-input "observer bot" can aim at a known object.

**Acceptance:**

- the trainee can find every object in a sample scenario by eye or sensor;
- **FPS ≥ 60 at 1600×900 on this laptop with an 8-object swarm**, measured with the capture tool.

**Risks:**

- LOS raycasts per object per tick. Mitigation: 10 Hz probe.
- Mouse-capture handling with Esc/pause.

### Stage 2.3 — classification and response workflow

**Files:**

- `scripts/observation/track_manager.gd` (marks → tracks; swarm grouping)
- `scripts/observation/event_log.gd`
- `scenes/ui/{classify_panel,response_panel}.tscn`
- `scripts/observation/action_rules.gd` (pure preconditions)

**Visible behaviour:**

- F/click marks an object as a track; misses are reported;
- the track list shows each track's state;
- a classification panel with confidence, then a response panel;
- one final response per track; clear messages for invalid actions.

**Tests:**

- precondition chain: mark → classify → respond (with the response final once given);
- mark validity geometry;
- swarm members map to one group track (§6, Q3);
- every action appears in the event log with correct tick and order;
- no events are accepted after the scenario ends.

**Acceptance:**

- a full scenario can be played with classifications and responses recorded;
- the event log is internally consistent;
- no new key conflicts in either mode.

**Risks:**

- UI complexity. Mitigation: keyboard shortcuts plus mouse.
- Ambiguity about swarm handling.

### Stage 2.4 — scoring, replay and after-action review

**Files:**

- `scripts/assessment/evaluator.gd` (`da-rubric-1`, pure)
- `docs/DA_RUBRIC.md` (with the traceability table to VIGIL `rubric-1`)
- `scripts/session/{recorder,session_writer,session_validator}.gd`
- `docs/SESSION_FORMAT.md`
- `scenes/ui/{results,replay_controls}.tscn`
- `tests/fixtures/*.json`

**Visible behaviour:**

- results screen with score, component breakdown and findings (each with a "jump to" moment);
- replay of the 3D scene with play/pause/scrub at 1×/2×/4×;
- hidden truth labels shown in review only;
- the session saved to `%APPDATA%\DroneAcharya\sessions`.

**Tests:**

- hand-computed golden fixtures: perfect run, late detection, `unknown` with weak evidence, over-confident wrong classification, unjustified area alert, missed threat, no observable objects, aborted run, mark spam;
- the evaluator is deterministic;
- write → read → validate round-trip; a tampered score is rejected; truncated JSON is rejected;
- replay frame at time *t* equals the recorded transforms;
- file size < 2 MiB for 300 s.

**Acceptance:**

- the score is explainable by hand from the rubric;
- replay matches the session;
- the file validates;
- flight mode is unaffected.

**Risks:**

- Rubric adaptation choices (§6, Q2).
- Recorder size. Mitigation: 10 Hz with rounding.

### Stage 2.5 (optional) — history and progression

- An in-game history list and a "next recommended scenario" using a port of VIGIL `rules-1`, with the reasons shown.
- Tests port the `rules-1` scenarios: sparse, mixed context, repeated, inconsistent, increase, decrease, ceiling, floor.

---

## 6. Risks and unresolved questions

| # | Question / risk | Recommendation |
|---|---|---|
| **Q1** | "AI-enabled" is in the target title. What must "AI" mean for your evaluators? | Stage 2 contains **no ML** and must not claim any. Honest options later: (a) VIGIL-style rule-based adaptive difficulty, labelled "rule-based"; (b) a genuinely trained classifier would need real data, training and evaluation evidence, a much larger project |
| **Q2** | `da-rubric-1` adapts `rubric-1`. Are these adaptations acceptable? (a) Evidence = seconds of identification-quality viewing instead of "≥ 2 clear observations"; (b) responses extend log/observe/escalate to five options; (c) a new mark-spam penalty | Yes. Each difference will be documented in a traceability table |
| **Q3** | Swarms: classify each member, or the group as one track? | One group track: the first valid mark on any member creates it; classification and response apply to the group; detection credit comes from the first mark |
| **Q4** | Will you later allow **adding** a module to VIGIL (no edits to existing files) so it can import `droneacharya-session` files? | Decide before Stage 2.4 is finished. Until then, review and history stay in the game |
| **Q5** | Mode menu with the flight scene moved (§3.4), or a hidden key switch with no moves? | The mode menu |
| **Q6** | Environments: are primitive props, colour palettes and fog per preset acceptable for 2.1, with heightmap terrain later? | Yes. This keeps 2.1 small and performant |
| **Q7** | Is there an official problem statement with required features (VIGIL's docs say its conformance was never verified)? | If one exists, share it before 2.1 so the scenario catalogue matches it |
| **R1** | **Stage 1 is uncommitted**, so work is at risk | Commit before any Stage 2 change (needs approval) |
| **R2** | Content risk: drifting into operational detail | Hold to the §0 boundary; review the response wording in 2.3 |
| **R3** | Two rubric families (VIGIL's `rubric-1`, the game's `da-rubric-1`) could diverge in meaning | Traceability table, shared terminology and golden fixtures. If a VIGIL import module is later approved, it re-scores with a TS port tested on the same fixtures |
| **R4** | Performance with swarms and LOS raycasts on the Intel Arc iGPU | 10 Hz probe; FPS check as an acceptance criterion in 2.2 (Stage 1 measured 502–586 FPS, so headroom is large) |
| **R5** | Earlier Phase 1 docs (`DRONEACHARYA_ARCHITECTURE.md`, `_IMPLEMENTATION_PLAN.md`) describe an observer-first plan that Stage 1 changed | Treat this document as superseding their stage list; their session-format and rubric ideas carry forward |

## 7. Acceptance criteria and testing strategy (all Stage 2 sub-stages)

- **Automated:** the headless GDScript suite (existing runner) covers pure logic (loader, state, geometry, rules, evaluator) plus integration on real scenes with real physics frames. Each stage adds tests; none removes or weakens existing ones.
- **Scripted players:** the Stage 1 autopilot stays green. An **observer bot** (2.2+) aims and acts **only through real input actions** to prove that each scenario is completable.
- **Determinism:** each scenario test runs a seed twice and compares the event logs exactly.
- **Golden fixtures** (2.4): hand-computed expected evaluations, with the arithmetic written in each fixture.
- **Visual:** the capture tool takes windowed screenshots per stage, which I inspect, plus an FPS figure with vsync off.
- **Fresh checkout:** the suite also runs on a copy without `.godot/`.
- **Preservation:** at the end of every stage, `git diff baseline-vigil-2026-10-20 -- VIGIL` must be empty and `git status -- VIGIL` clean.
- **Reporting:** actual command output is quoted, and failures are reported with their cause.

## 8. Recommended next smallest step

**Stage 2.0b, part 1 only.**

1. Commit the current Stage 1 work (with your approval).
2. Add the mode menu as `main.tscn` (keeping `Title`), move the flight scene to `scenes/flight/flight_training.tscn`, update only the scene paths in the flight tests and the capture tool, and re-bind `report` from R to Enter.

It is done when:

- all 32 tests pass unchanged except for scene paths;
- the autopilot still completes in 23.9 s;
- the menu launches flight mode;
- VIGIL is unchanged.

This unblocks every later stage without touching gameplay.

---

## 9. Implementation status and deviations (updated at Phase 6)

The plan above was implemented under the later brief "Complete Simulation, AI Decision Models, and Training System" (SIH PS 26247 context). That brief's Phases 0–6 replaced the stage list in §5:

| Brief phase | Commit | Delivered |
|---|---|---|
| 0 Preserve and baseline | (no commit needed) | Stage 1 already committed as `91fdd32`; baseline 32 tests, 23.9 s autopilot |
| 1 Scenario foundation | `72cead7` | Menu, flight scene moved, scenario format and procedural generator, threat world, observation scene |
| 2 Sensors and tracking | `7daf38e` | Radar-like and camera sensors, tracker, swarm groups, sensor view, track UI |
| 3 Rule-based decisions | `a1e91fe` | features-1, Model 1, Model 3, trainee workflow, `da-rubric-1` |
| 4 Real ML model | `d81de8e` | Dataset generator, trained random forest, held-out evaluation, GDScript inference, fallback, settings |
| 5 Replay and review | `47711a3` | Session schema and validator, history, export/import, deterministic replay, AAR |
| 6 Adaptive and polish | (Phase 6 commit) | `adapt-da-1`, chase-camera collision, key conflicts resolved, marker contrast, faster tests, performance, export preset, docs |

### Answers to §6 questions

- **Q1 (AI):** a genuinely trained ML classifier now exists (Model 2), alongside clearly labelled rule-based Models 1 and 3 and rule-based adaptation. Metrics come from held-out synthetic data and are not real-world evidence.
- **Q2 (rubric adaptations):** implemented as proposed. Evidence is the time an object is genuinely available at identification quality (truth geometry), not screen time. There are five responses. Spam penalty P4 and a degraded-conditions component were added.
- **Q3 (swarms):** individual tracks are kept; the swarm is assessed as one group entity (configurable through `group_swarms`).
- **Q4 (VIGIL):** VIGIL is unchanged and no VIGIL module was added. A field mapping is documented (`DRONEACHARYA_SESSION_SCHEMA.md` §5); there is no importer.
- **Q5 (mode menu):** implemented. `main.tscn` is the menu with the original `Title`; the flight course moved to `scenes/flight/flight_training.tscn`.
- **Q6 (environments):** urban (building grid) and rural (trees and farmhouses) on flat ground, with day/night and clear/haze/fog. There is no heightmap terrain, so mountain and desert looks are future work.
- **Q7 (problem statement):** the brief names SIH PS 26247 (Ministry of Defence / DSSC). Conformance to the official text has not been independently verified.

### Other deviations from §§3–5

- **Two sensors:** the observer and sensor mode use synthetic radar-like and camera sensors feeding a tracker, rather than marking objects by aiming. The trainee acknowledges tracks; markers show tracker estimates.
- **Replay:** deterministic re-simulation, verified identical (no 10 Hz transform recording).
- **Key bindings:** `report` moved from R to Enter, `classify` from C to K, `jump` from Space to J. No key now drives two actions.
- **Rule baseline:** revised once (`rules-da-1` → `rules-da-2`) from training-split statistics. This is documented with both results.
