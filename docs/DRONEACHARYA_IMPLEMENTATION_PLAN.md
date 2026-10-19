# DroneAcharya — Implementation Plan

Status: proposal. **No stage starts without your approval.** Every stage follows the same rules:

- Stages are small and self-contained, and end with a working state plus a commit.
- I implement; you run the "You do" steps (I explain every command first).
- A stage is done only when its **acceptance check** passes. If a check fails, I report the failure and its cause rather than hiding it.
- I never claim the game runs unless it was launched or an automated test passed.
- VIGIL is not modified before Stage 10, and not without separate approval.

Paths below are relative to `E:\Hardik\Programming\DroneAcharya\`.
`GODOT` = `.\Godot_v4.7.2-stable_win64_console.exe` (for terminal / tests)
`GODOT_EDITOR` = `.\Godot_v4.7.2-stable_win64.exe` (for the editor)

---

## Milestone 1 — first playable vertical slice

### Stage 0 — Safety net and empty project ★ first task

**Goal:** version control protects VIGIL; an empty Godot project opens; the headless test runner works.

Steps:

1. `git init` at the workspace root, then add a `.gitignore` covering:
   - `Godot_*.exe`;
   - `simulator/.godot/`;
   - `**/node_modules/`;
   - `exports/`;
   - `*.tmp`.
2. Make a **baseline commit of VIGIL exactly as it is now** (a restore point).
3. Create `simulator/project.godot` with:
   - name "DroneAcharya Simulator";
   - Forward+ renderer;
   - physics at 60 ticks/s;
   - `use_custom_user_dir=true` with the name `DroneAcharya`;
   - the window size;
   - input actions `move_forward/back/left/right`, `jump`, `toggle_view`, `mark`, `classify`, `report`, `pause`.
4. Create `simulator/scenes/main.tscn` + `scripts/main.gd`: a black screen with the label "DroneAcharya — synthetic training only".
5. Create `simulator/tests/run_tests.gd`: a headless runner that finds `tests/test_*.gd`, calls every `test_*` method, prints PASS/FAIL and exits with code 1 on any failure.
6. Create `simulator/tests/test_smoke.gd` with one trivial test, plus a test that `project.godot` declares the input actions.

You do:

- Open `GODOT_EDITOR` → Import → choose `simulator/project.godot`.
- Press F5 and confirm the label appears.

Acceptance:

- `GODOT --headless --path simulator --script res://tests/run_tests.gd` prints `2 passed, 0 failed` and exits 0.
- The editor opens the project without errors.
- `git log` shows the baseline commit.

### Stage 1 — Mountain terrain, sky and lighting

- Write `terrain_generator.gd`, which builds the terrain from `FastNoiseLite` (seeded) with ridged/fBm noise.
  - Size 2 km × 2 km, 257×257 vertices.
  - A valley floor near the observer spawn.
  - Vertex colours by height and slope (grass, rock, snow).
  - Normals, an `ArrayMesh` and a `HeightMapShape3D` built from the **same** height array.
- `mountain_world.tscn` adds the WorldEnvironment (ProceduralSky, depth fog, filmic tonemap) and a DirectionalLight3D with shadows.
- Add a debug FPS label (toggle `F3`).
- Tests:
  - same seed → identical height checksum;
  - a different seed gives a different checksum;
  - the height at a sample point matches between mesh data and collision data;
  - heights stay within bounds.
- **You do:** run the game and report the FPS shown at 1600×900 and 1920×1080.
- **Acceptance:** tests pass; you see mountains, sky and shadows; FPS ≥ 60 at 1600×900 on your laptop. If FPS is lower, we reduce resolution or shadows **before** continuing.

### Stage 2 — First-person observer controller

- `observer.tscn` is a `CharacterBody3D` with a capsule, a Head node and an ObserverCamera.
- `observer_controller.gd` provides:
  - WASD movement, gravity, slope handling and an optional jump;
  - mouse look with pitch clamped to ±85°;
  - mouse capture on click and release on `Esc`.
- Sensitivity and speed are exported variables.
- Tests: input-to-velocity mapping as a pure function, and the pitch clamp.
- **Acceptance:** you can walk on the terrain without falling through, look around smoothly, and release the mouse with `Esc`.

### Stage 3 — Synthetic aerial object on a scripted path

- `aerial_object.tscn` is an abstract procedural mesh: a small body, four rotor discs and a dim light, with `scale` and `contrast` parameters.
- `aerial_object.gd` interpolates waypoints `{tS, pos}` as Catmull-Rom or linear, driven by **scenario ticks** rather than frame time.
- `scenario_loader.gd` loads and validates `scenarios/ridge_watch_01.scenario.json`.
- Tests:
  - position at tick *t* is deterministic;
  - loader rejects a missing field, a bad version and non-increasing waypoint times.
- **Acceptance:** the object visibly flies its route; tests pass.

### Stage 4 — Observer / sensor view toggle

- Add a SensorCamera with zoom on the mouse wheel (FOV 25° → 6°).
- `sensor_view.gdshader` on a full-screen ColorRect provides monochrome, contrast, grain and a reticle.
- `V` toggles the view; the HUD shows the mode and zoom.
- **Acceptance:** the toggle works both ways; FPS in sensor mode stays within 10 % of observer mode.

### Stage 5 — Scenario flow and event log

- `scenario_runner.gd` implements the state machine `briefing → running ⇄ paused → completed|aborted` and the tick clock (counting only while running).
- It executes the scripted timeline (`scenario_event`, e.g. fog thickening at 90 s).
- `event_log.gd` provides append-only ordered events with IDs and validation, and rejects events after finish.
- A briefing screen has a Start button; the pause menu offers Resume and End exercise.
- `observability_probe.gd` logs `truth_observable` and `id_view` intervals at 10 Hz.
- Tests:
  - illegal transitions are rejected;
  - the clock does not advance while paused;
  - completion happens exactly at `durationTicks`;
  - event order and IDs are contiguous;
  - the probe changes state correctly with a mocked LOS/angle input.
- **Acceptance:** tests pass. A full play-through reaches "completed", and an early exit gives "aborted".

### Stage 6 — Trainee actions: mark, classify, report

- `F` marks, checking validity against the active camera tolerance.
- `classify_panel.tscn` offers category (`Routine` / `Requires review` / `Background` / `Unknown`) and a confidence slider (0–100).
- The report panel offers a decision (`Routine log` / `Continue observation` / `Training escalation`) and a summary of 12–500 characters.
- Preconditions follow the chain mark → classify → report, with one report per object.
- Tests cover the precondition chain, the summary length bounds and the mark validity geometry (as a pure function).
- **Acceptance:** all actions appear in the event log with correct ticks; invalid actions show a clear message and are not logged as valid.

### Stage 7 — Evaluator and results screen

- Write `shared/RUBRIC.md` (normative `da-rubric-1`, from Architecture §7).
- `evaluator.gd` is a pure `evaluate(scenario, events) -> Dictionary` function that produces components, findings with event anchors, penalties, score and `comparable`.
- `results_screen.tscn` shows:
  - the score;
  - per-component credit and weight;
  - each finding with its reason;
  - the event timeline;
  - the "Synthetic training only" notice.
- Create the first golden fixtures in `shared/fixtures/`, each with a hand-computed expected result:
  1. perfect run;
  2. late detection;
  3. `unknown` with weak evidence;
  4. over-confident wrong classification (P1);
  5. unjustified escalation (P2);
  6. no report on a significant object (P3);
  7. never observable (E0);
  8. aborted run.
- Tests: the evaluator matches every fixture exactly (to 0.1) and is deterministic.
- **Acceptance:** fixtures pass; a played session shows a results screen you can check against the rubric by hand.

### Stage 8 — Saved local session record

- Write `shared/SESSION_FORMAT.md` (normative v1).
- `session_writer.gd` writes `user://sessions/<sessionId>.session.json` atomically (write `.tmp`, then rename) and records 2 Hz samples.
- `session_validator.gd` validates a loaded file. It re-evaluates the session and requires the result to equal the stored evaluation.
- The results screen shows the saved path and offers "Open folder".
- Tests:
  - write → read → validate round-trip;
  - a tampered score is rejected;
  - truncated JSON is rejected;
  - the file stays under 2 MiB for a 300 s session.
- **Acceptance:** after a play-through, the file exists in `%APPDATA%\DroneAcharya\sessions\` and validates.

### Stage 9 — Reproducible test procedure and Windows build

- `simulator/tests/test_playthrough.gd` runs a headless scripted bot through `ridge_watch_01` using simulated ticks and injected actions. It produces a session and asserts the expected score.
- Write `docs/DRONEACHARYA_MANUAL_QA.md`, a click-by-click checklist (see the Test Plan).
- **You do:** install the Godot **4.7.2 export templates** (Editor → Manage Export Templates → Download; about 1 GB). Then I add `export_presets.cfg` for Windows Desktop.
- **Acceptance:**
  - the automated suite passes;
  - the exported `exports/DroneAcharya.exe` launches outside the editor;
  - the manual QA checklist is completed with results recorded.

**→ Milestone 1 complete.**

---

## Milestone 2 — dashboard integration (needs separate approval to modify VIGIL)

**Stage 10** adds `VIGIL/src/droneacharya/` with:

- a Zod schema;
- the TypeScript `da-rubric-1` evaluator;
- conformance tests over `shared/fixtures`.

Nothing existing changes, and the existing 369 tests must still pass.

**Stage 11** adds the `#sim` route, which provides:

- import (file picker; rejects mismatched scores);
- a session list;
- an after-action report reusing VIGIL's UI primitives and the event-log component;
- CSV export via `csvCell`;
- a separate IndexedDB database, `droneacharya-sessions`.

The existing e2e suite then needs Playwright Chromium (`npx playwright install chromium`).

**Stage 12** adds a 2D top-down replay from `samples`, using VIGIL's cursor/prefix approach, and descriptive history for simulator sessions.

**Stage 13 (optional)** adds an adapter so that VIGIL's `rules-1` `recommendNext` can suggest the next simulator scenario (difficulty and fog/visibility).

## Milestone 3+ — content (each is its own small plan)

- Day/dusk/night lighting presets and reduced-visibility weather (fog, haze, rain particles at a fixed budget).
- Multiple objects and background objects (bird-like or balloon-like placeholders).
- New terrains: desert (dunes noise), rural (fields and low hills, with a simple instanced tree budget) and urban (procedural block extrusion). Each is added only after an FPS check.
- A scenario selection menu and a trainee profile picker. Profile IDs must match the dashboard's ID rules (`^[A-Za-z0-9][A-Za-z0-9._:-]{0,99}$`).

## Software you will need, and when

| Software | When | Status |
|---|---|---|
| Godot 4.7.2 standard | Now | Present [VERIFIED] |
| Git | Stage 0 | Present (2.52.0) [VERIFIED] |
| VS Code extension "godot-tools" (GDScript syntax and LSP) | Optional, Stage 0 | Not checked |
| Godot 4.7.2 export templates | Stage 9 | Not installed [ASSUMPTION] |
| Node.js ≥ 20.19 / 22.12 | Stage 10 | v24.14.1 present; VIGIL tests pass on it [VERIFIED] |
| Playwright Chromium | Stage 11 (VIGIL e2e) | Not installed [VERIFIED] |
| Windows Developer Mode (optional) | Only to make VIGIL's launcher symlink test pass unmodified | Off [VERIFIED] |
