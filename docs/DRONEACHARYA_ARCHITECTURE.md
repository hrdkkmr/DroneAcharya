# DroneAcharya — Architecture

Status: proposal for approval (Phase 1). Nothing described here has been implemented yet.
Labels: **[VERIFIED]** (checked in the audit), **[ASSUMPTION]**, **[RECOMMENDATION]**, **[DECISION-NEEDED]**.

---

## 1. Scope and non-goals

DroneAcharya is a **synthetic training prototype**. It is not an operational defence system.

Out of scope, permanently:

- weapon control or interception logic;
- real-world engagement guidance;
- real terrain, coordinates, targets or sensor parameters;
- any "how to defeat" content.

Trainee decisions are **training dispositions**: `log`, `observe`, or `escalate` (meaning "escalate to the instructor"). This is the same vocabulary as VIGIL.

Out of scope for now, but possible later if justified:

- database server, cloud, accounts or authentication;
- networking or multiplayer;
- ML or "AI" adaptation (VIGIL's rule-based `rules-1` is enough);
- VR;
- external asset packs (milestone 1 uses procedural placeholders only).

---

## 2. System overview

```
┌────────────────────────────────────┐        writes JSON        ┌──────────────────────────────────┐
│  DroneAcharya Simulator (Godot 4)  │ ───────────────────────▶ │  %APPDATA%\DroneAcharya\sessions │
│  GDScript, Windows desktop         │  droneacharya-session v1 │  *.session.json                  │
│                                    │                           └──────────────┬───────────────────┘
│  scenario JSON ─▶ ScenarioRunner   │                                          │ user imports file
│  World (terrain/sky/object)        │                                          ▼
│  Observer + Sensor cameras         │                           ┌──────────────────────────────────┐
│  EventLog ─▶ Evaluator (GDScript)  │                           │  VIGIL dashboard (React/TS)      │
│  Results screen                    │                           │  NEW module src/droneacharya/    │
└────────────────────────────────────┘                           │  validate ─▶ re-evaluate (TS) ─▶ │
               ▲                                                 │  compare ─▶ AAR / history / CSV  │
               │  shared/fixtures/*.json (golden sessions)       │  existing VIGIL trainer unchanged│
               └─────────── both test suites must pass ─────────▶└──────────────────────────────────┘
```

- The simulator works fully offline, without the dashboard. It shows its own results screen.
- The dashboard is an optional instructor tool for import, review, history and analytics.
- The only coupling between the two is a **documented, versioned JSON file**. There is no live link and no network.

---

## 3. Key decisions and why

### D1. A new session format, not VIGIL's `SessionRecord` [VERIFIED reason]

`VIGIL/src/persistence/validation.ts:192` (`validateStoredRecord`) accepts a record only if two conditions hold. First, the scenario equals `generateScenario(config)` from VIGIL's 2D generator. Second, the stored evaluation equals a re-run of `evaluateSession`, which itself enforces VIGIL's 4-second observation schedule.

A Godot session cannot meet either condition. Forcing it to would mean faking a 2D grid world inside the 3D game.

→ Define **`droneacharya-session` formatVersion 1** (§6). VIGIL's `vigil-session-export` format and IndexedDB database stay untouched.

### D2. One scoring *specification*, two small conformance-tested implementations

The game needs a results screen without the dashboard, and the dashboard must not blindly trust a number written in a file. Godot cannot execute VIGIL's TypeScript. The options were:

| Option | Problem |
|---|---|
| A. Dashboard-only scoring | No offline in-game results; trainee waits for an instructor |
| B. Game-only scoring, dashboard trusts the file | Hand-edited files show fake scores; no audit |
| C. Embed a JS runtime in Godot | Heavy, unusual dependency; hard for one student |
| **D. Spec + GDScript evaluator + TS evaluator + shared golden fixtures** | Two implementations, but kept identical by tests |

**Recommendation: D.**

- The specification (§7, `da-rubric-1`) is the single source of truth.
- The evaluator is small, about 150 lines in each language, and is a pure function: `(scenario, events) → evaluation`.
- `shared/fixtures/` holds hand-checked sessions with their expected evaluations. The Godot test runner and VIGIL's Vitest suite both assert against the same files.
- On import, the dashboard re-evaluates. If its result differs from the stored one, it **rejects or flags** the file. This follows VIGIL's existing "recompute and compare, never repair" policy.
- No second, conflicting rubric is introduced. `da-rubric-1` is a documented adaptation of VIGIL's `rubric-1` that keeps its components, weights, formulas, decision tree and penalties wherever their meaning carries over to 3D.

### D3. The evaluator is pure over the logged events

Geometry (line of sight, view cones and ranges) is computed live in the game. Its *outcomes* are written to the log as interval events (`truth_observable`, `id_view`). The evaluator only does arithmetic over ticks, so anyone with the file can re-compute it exactly.

Consequence, inherited from VIGIL's own limitation: the dashboard can verify **consistency, not authenticity**. A crafted file with consistent intervals would be accepted.

### D4. Integer tick time

The scenario clock counts physics ticks at 60 Hz while the session is running. It does not count while paused. Every event stores an integer `tick`, so all evaluator comparisons are integer and exact in both languages. Seconds are derived as `tick / tickRate` and appear in display text only.

### D5. Deterministic randomization via the scenario seed

Godot's `RandomNumberGenerator` (PCG32) is deterministic for a given seed. Terrain noise (`FastNoiseLite.seed`) and any path jitter derive from `scenario.seed` and are recorded in the session. Porting VIGIL's Mulberry32 is unnecessary, because the dashboard never regenerates the 3D world.

### D6. No new dependencies in milestone 1

- Testing uses a ~60-line headless GDScript runner instead of the GUT addon.
- Assets are procedural meshes and materials only.
- The dashboard needs nothing beyond its existing `zod` and `react`.

### D7. Version control before any change [RECOMMENDATION]

The workspace has no Git repository [VERIFIED]. Initialize one at the workspace root and make a baseline commit of VIGIL *as-is* before anything else. The Godot executables (180 MB) must be listed in `.gitignore`.

---

## 4. Recommended folder structure

```
E:\Hardik\Programming\DroneAcharya\
├─ .gitignore                         # Godot exes, simulator/.godot/, node_modules, exports
├─ Godot_v4.7.2-stable_win64.exe      # stays where it is (ignored by git)
├─ Godot_v4.7.2-stable_win64_console.exe
├─ docs\                              # the four DroneAcharya documents (this phase)
├─ shared\
│  ├─ SESSION_FORMAT.md               # normative spec of droneacharya-session v1 (Stage 8)
│  ├─ RUBRIC.md                       # normative spec of da-rubric-1 (Stage 7)
│  └─ fixtures\                       # golden *.session.json + *.expected.json
├─ simulator\                         # the Godot project (res://)
│  ├─ project.godot
│  ├─ scenes\
│  │  ├─ main.tscn                    # boots into menu / scenario
│  │  ├─ world\mountain_world.tscn    # terrain + sky + light + environment
│  │  ├─ player\observer.tscn         # CharacterBody3D + cameras
│  │  ├─ actors\aerial_object.tscn
│  │  └─ ui\{hud,briefing,classify_panel,results}.tscn
│  ├─ scripts\
│  │  ├─ core\    scenario_loader.gd, scenario_runner.gd, event_log.gd,
│  │  │           evaluator.gd, session_writer.gd, session_validator.gd
│  │  ├─ world\   terrain_generator.gd, aerial_object.gd, observability_probe.gd
│  │  ├─ player\  observer_controller.gd, sensor_view.gd
│  │  └─ ui\      hud.gd, classify_panel.gd, results_screen.gd
│  ├─ shaders\sensor_view.gdshader
│  ├─ scenarios\ridge_watch_01.scenario.json
│  └─ tests\
│     ├─ run_tests.gd                 # headless runner (extends SceneTree)
│     └─ test_*.gd
└─ VIGIL\                             # existing app. Unchanged until the dashboard phase
   └─ src\droneacharya\               # (later, with approval) import/validate/evaluate/views
```

Rationale:

- `simulator\` and `VIGIL\` are siblings, so neither tool sees the other's files.
- `shared\` is the only contract between them.
- In the dashboard phase, `shared\fixtures` is read by both test suites. VIGIL's test can load it through a relative path.

---

## 5. Simulator architecture (Godot)

### 5.1 Scene tree (milestone 1)

```
Main (Node)                             main.gd: owns state machine, loads scenario
├─ World (Node3D)                       mountain_world.tscn
│  ├─ WorldEnvironment                  ProceduralSkyMaterial, depth fog, tonemap
│  ├─ Sun (DirectionalLight3D)          shadows, max distance ~300 m, 2 splits
│  ├─ Terrain (StaticBody3D)
│  │  ├─ MeshInstance3D                 ArrayMesh generated by terrain_generator.gd
│  │  └─ CollisionShape3D               HeightMapShape3D from the same heights
│  └─ AerialObject (Node3D)             follows scenario waypoints; simple procedural mesh
├─ Observer (CharacterBody3D)           observer_controller.gd (WASD, mouse look, gravity)
│  └─ Head (Node3D)
│     ├─ ObserverCamera (Camera3D)      FOV 75°
│     └─ SensorCamera (Camera3D)        FOV 25°→6° zoom; activated in sensor mode
├─ ObservabilityProbe (Node)            10 Hz checks: LOS raycast, range, view cones
├─ ScenarioRunner (Node)                tick clock, scripted timeline, emits events
├─ EventLog (Node)                      append-only, ordered, validated
└─ UI (CanvasLayer)
   ├─ SensorOverlay (ColorRect + shader) monochrome/noise/reticle, visible in sensor mode
   ├─ HUD                               mode, clock, prompts (no truth)
   ├─ BriefingPanel / ClassifyPanel / ResultsScreen
```

### 5.2 Session state machine (mirrors VIGIL's)

`briefing → running ⇄ paused → completed | aborted`

- A session reaches `completed` only when the clock reaches `durationTicks`. Ending early gives `aborted`, which is not comparable. This matches VIGIL's rule.
- No events are allowed after `finished`.
- The clock does not advance while paused.

### 5.3 Trainee actions (milestone 1)

| Input | Action | Preconditions | Logged as |
|---|---|---|---|
| `V` | Toggle observer / sensor view | running | `view_mode {mode}` |
| Mouse wheel (sensor) | Zoom | sensor mode | (not logged; sampled) |
| `F` / left click | Mark sighting at screen centre | running | `mark {valid, angleDeg, distanceM}` |
| `C` | Open classify panel: category + confidence | ≥ 1 valid mark | `classify {category, confidence}` |
| `R` | Open report panel: decision + summary (12–500 chars) | classified; one report per object | `report {decision, summary}` |
| `Esc` | Pause menu (resume / end exercise) | running/paused | `paused` / `resumed` / `finished{aborted}` |

The precondition chain *mark → classify → report* mirrors VIGIL's *track → classify → report*.

A mark is **valid** when the object is observable and lies within `markToleranceDeg` of the active camera's centre ray. The default tolerance is 4° in observer mode and 1.5° in sensor mode.

### 5.4 Observability probe (ground truth, hidden from the trainee)

At 10 Hz the probe computes:

- **observable** = within `detectRangeM` of the observer **and** an unobstructed terrain raycast from the camera to the object **and** within the current fog visibility distance.
- **inIdView** = observable **and** within `idConeDeg` of the active camera centre **and** within identification range. Defaults: observer cone 10° and ≤ 250 m; sensor cone 5° and ≤ `250 m × zoom`.

Each change of state is logged as an interval event: `truth_observable {value}` and `id_view {value}`. The HUD never shows `truth_observable`.

### 5.5 Sensor view

The sensor view is the same world, rendered through a second `Camera3D` with a narrow FOV, plus a full-screen `ColorRect` shader providing monochrome, contrast, grain, a slight vignette and a reticle. It needs no `SubViewport`, so the extra GPU cost is close to zero.

It is a stylised training aid. It does not model any real sensor.

### 5.6 Performance budget (target: this machine, Intel Arc iGPU)

| Item | Budget |
|---|---|
| Frame rate | ≥ 60 FPS at 1600×900, ≥ 45 FPS at 1920×1080 [targets, to be measured] |
| Renderer | Forward+ (Godot default, Vulkan). Fallback: Compatibility if driver issues [ASSUMPTION: Arc Vulkan works] |
| Terrain | 2 km × 2 km, 257×257 vertices (~131k triangles), single mesh, vertex colours by height/slope, no textures |
| Lighting | 1 DirectionalLight3D, PSSM 2 splits, shadow distance 300 m |
| Environment | ProceduralSky, depth fog. **Off:** SDFGI, VoxelGI, SSR, SSAO, SSIL, volumetric fog, glow-heavy effects |
| Anti-aliasing | FXAA or MSAA 2× (choose by measurement) |
| Scripts | Probe at 10 Hz, not every frame; samples at 2 Hz |

---

## 6. Session format `droneacharya-session` v1 (outline)

This outline becomes the normative `shared/SESSION_FORMAT.md` in Stage 8.

```json
{
  "format": "droneacharya-session",
  "formatVersion": 1,
  "app": { "name": "DroneAcharya Simulator", "version": "0.1.0", "engine": "4.7.2.stable" },
  "sessionId": "da-20261020T101500Z-3f9a",
  "profileId": "trainee-01",
  "startedAt": "2026-10-20T10:15:00Z",
  "endedAt":   "2026-10-20T10:18:05Z",
  "status": "completed",
  "tickRate": 60,
  "durationTicks": 10800,
  "elapsedTicks": 10800,
  "scenario": { "...": "full scenario definition incl. hidden truth (post-exercise file)" },
  "rubric":   { "version": "da-rubric-1", "weights": { "detection": 20, "...": 0 }, "...": 0 },
  "events": [
    { "order": 1, "id": "da-...:e00001", "tick": 0,   "type": "started",          "data": { "scenarioId": "ridge-watch-01@1" } },
    { "order": 2, "id": "da-...:e00002", "tick": 612, "type": "truth_observable", "data": { "objectId": "A1", "value": true } },
    { "order": 3, "id": "da-...:e00003", "tick": 790, "type": "mark",             "data": { "objectId": "A1", "valid": true, "angleDeg": 1.8, "distanceM": 640, "mode": "observer" } }
  ],
  "samples": [ { "tick": 0, "object": { "A1": [120.0, 340.0, -800.0] }, "observer": [0, 12.5, 0], "yawDeg": 0, "pitchDeg": 0, "view": "observer", "zoom": 1 } ],
  "evaluation": { "rubricVersion": "da-rubric-1", "score": 81.4, "...": "see §7" }
}
```

Event types:

- `started`, `paused`, `resumed`, `finished {outcome}`
- `view_mode {mode}`
- `scenario_event {kind, ...}`: scripted changes, e.g. a fog change
- `truth_observable {objectId, value}` *(hidden during play)*
- `id_view {objectId, value}`
- `mark {objectId|null, valid, angleDeg, distanceM, mode}`
- `classify {objectId, category, confidence}`
- `report {objectId, decision, summary}`

Rules (validated by both sides):

- `order` = 1..n contiguous; ids unique; `tick` non-decreasing.
- The first event is `started` at tick 0 and the last is `finished`.
- No tick advance between `paused` and `resumed`.
- `completed` implies a final tick of `durationTicks`.
- Intervals alternate true/false per object.
- `samples` are optional and are used for the replay map only, never for scoring.

Limits, matching VIGIL's: ≤ 2 MiB per file and ≤ 5,000 events.

Storage location: `user://sessions/`. With `application/config/use_custom_user_dir=true` and the name `DroneAcharya`, this is **`%APPDATA%\DroneAcharya\sessions\`** [ASSUMPTION: confirm at Stage 8].

The scenario input file `droneacharya-scenario` v1 (`simulator/scenarios/*.scenario.json`) contains:

- `id`, `version`, `title`, `environment` (`"mountain"`), `lighting`, `fogVisibilityM`;
- `seed`, `terrain {sizeM, heightM, noiseFrequency}`, `durationS`, `observerSpawn`;
- `objects[] {id, truthCategory, significant, scale, contrast, waypoints[{tS, pos}]}`;
- `timeline[] {tS, kind, value}`;
- `weights`, `objectives`.

---

## 7. Rubric `da-rubric-1` (adaptation of VIGIL `rubric-1`)

Definitions per object:

- **T_obs** = tick of the first `truth_observable=true`. If it never occurs, the object is not eligible (VIGIL's equivalent is "no delivered observation").
- **T_mark** = tick of the first valid `mark`.
- **dwell(t)** = total `id_view=true` ticks before tick *t*.
- **strong** = dwell(classification tick) ≥ `minIdDwellTicks`. The default is 3 s = 180 ticks; it replaces VIGIL's "≥ 2 clear observations".

`windowCredit(l, g, d) = clamp((d − l)/(d − g), 0, 1)` uses the same function as VIGIL.

| Component (weight) | Rule | Credit per eligible object |
|---|---|---|
| Detection (20) | D1 | `windowCredit((T_mark − T_obs)/rate, 5 s, 30 s)`; 0 if no valid mark |
| Classification (20) | C1 | correct = 1, wrong = 0; `unknown` = 0.75 (weak) / 0.5 (strong); none = 0 |
| Uncertainty (15) | U1 | `unknown`: 1 weak / 0.75 strong; specific + weak = 0.25; specific + strong: 1 if correct, 0 if wrong |
| Reporting (20) | R1 | `0.4 + 0.6 × windowCredit((T_report − T_obs)/rate, 15 s, 60 s)`; 0 if no report |
| Decision (15) | Q1 | expected: unclassified, `unknown` or weak at report → `observe`; else `review` → `escalate`; else `log`. Match = 1, `observe` = 0.5, else 0 |
| Objectives (10) | O1 | fraction of selected skills whose average credit is ≥ 0.70 |

Penalties:

| Rule | Points | Condition |
|---|---|---|
| P1 | −4 | specific classification with confidence > 70 % without strong evidence |
| P2 | −8 | `escalate` when the expected decision is not `escalate` |
| P3 | −5 | a significant object was eligible but never reported |
| P4 | −1 each, max −5 | invalid marks beyond the first 3 *(new: guards against spamming the mark key)* |

- Score = `clamp(Σ component credit × weight − penalties, 0, 100)`. Precision is kept internally and rounded to 0.1 for display.
- `comparable` = completed **and** at least one eligible object. If no object is eligible, the result is E0 and is not comparable.
- Every finding lists `anchorEventId` and `eventIds`, as in VIGIL.

---

## 8. Dashboard integration (later phase, needs approval to modify VIGIL)

Add, never replace:

- `VIGIL/src/droneacharya/schema.ts`: Zod schema for `droneacharya-session` v1.
- `VIGIL/src/droneacharya/evaluate.ts`: TypeScript `da-rubric-1` evaluator (pure).
- `VIGIL/src/droneacharya/*.test.ts`: conformance tests over `../../shared/fixtures`.
- A separate IndexedDB database, `droneacharya-sessions`, so VIGIL's `vigil-training-history` v1 schema is not migrated.
- A new route, `#sim` ("Simulator sessions"): import files, list them, view the after-action report (findings, event log, a 2D top-down replay from `samples` using VIGIL's cursor/prefix approach) and export CSV with `csvCell`.
- Later: an adapter so that `summarizeHistory` and `recommendNext` (`rules-1`) can work over simulator sessions.

---

## 9. Safety and content rules

- **Fictional world:** procedurally generated terrain measured in local metres, with no geographic coordinates and no real place names. The first scenario is "border-*inspired*" in mood only.
- **Aerial object:** an abstract placeholder mesh, with no real model, performance data or signature. Truth categories are VIGIL's training labels (`routine`, `review`, `background`).
- **Actions:** observe, mark, classify and report only. No aiming, firing, jamming or interception mechanics, and no guidance on defeating objects.
- Every screen and exported file states **"Synthetic training only"**, as VIGIL does.

## 10. Risks

| Risk | Mitigation |
|---|---|
| GDScript and TS evaluators drift apart | Shared golden fixtures run in both suites; the dashboard rejects mismatches |
| iGPU performance | Strict budget (§5.6); measure FPS in Stage 1 before adding features |
| Scope creep ("open world") | Fixed milestone list; one stage at a time with acceptance checks |
| Loss of VIGIL work | Git baseline commit before any change; VIGIL is not edited until the dashboard phase |
| A user mis-reads the score as real-world competence | Disclaimers on the results screen and in the file; same wording policy as VIGIL |
