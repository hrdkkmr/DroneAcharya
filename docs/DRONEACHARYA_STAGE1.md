# DroneAcharya — Stage 1: First Playable Drone Simulator

Date: 2026-10-20 · Engine: Godot 4.7.2 (Forward+) · Project: `simulator/`

This is a foundational training prototype. It is **not** a photorealistic simulator and **not** a validated flight model. Every screen shows "DroneAcharya — synthetic training only".

> **Change of direction from the Phase 1 plan.** `DRONEACHARYA_IMPLEMENTATION_PLAN.md` described Stage 1 as procedural mountain terrain for a ground observer. The Stage 1 brief instead asked for a **pilotable drone on a checkpoint course**, and that is what was built. The observer/sensor/classification plan and the session-file and dashboard plans have not been started. They should be re-confirmed before later stages.

---

## 1. Features implemented

| Area | What exists |
|---|---|
| Environment | Procedural sky, sun with shadows, light distance fog, 400 m × 400 m ground with a 5 m / 25 m grid (shader), ground collision |
| Course | Orange launch pad ("LAUNCH") at the origin; green landing zone (radius 4 m, "LAND", beacon pole) 125 m north; 4 numbered checkpoint rings, each turned to face its approach direction; 6 obstacles (2 pillars, a wall with a 10 m gap, 2 crates) |
| Drone | Built from primitive meshes: body, arms, 4 spinning rotors, skids, red nose / green tail markers. The body tilts toward the direction of travel (visual only) |
| Flight | Assisted ("position-hold") model: hovers when keys are released; accelerates toward a target velocity; configurable limits (Inspector → Drone). Fixed 60 Hz physics |
| Collision | Cannot pass through the ground or obstacles. Hitting an obstacle at ≥ 3.5 m/s is a crash. Below 0.3 m with no climb input the drone settles onto the ground |
| Cameras | Smoothed chase camera behind the drone (follows heading, not tilt, and stays above the ground); onboard camera. `V` toggles |
| HUD | Altitude, ground speed, vertical speed, heading (degrees + compass point), mission time, camera mode, objective, flight status, event messages, controls panel, pause/result box. All values are read from the simulated drone and mission every frame |
| Mission | Take off → checkpoints 1–4 **in order** → land in the zone and hold still for 1 s → "Mission complete" with time. Failure on obstacle crash or leaving the training area (x ±80 m, z −170…+40 m). `R` restarts at any time, including after success or failure |
| Pause | `Esc` freezes the drone, mission clock and camera; `Esc` resumes; `R` restarts |

### Flight parameters (defaults, editable on the Drone node)

| Parameter | Value |
|---|---|
| Max ground speed | 8 m/s |
| Climb / descent | 4 / 3 m/s |
| Turn rate | 90°/s |
| Acceleration / braking | 6 / 8 m/s² |
| Altitude ceiling | 40 m |
| Crash speed | 3.5 m/s |

## 2. Controls

| Key | Action |
|---|---|
| W / S | Forward / back |
| A / D | Left / right (sideways) |
| Q / E | Turn left / right *(added so heading can change; not in the brief's list)* |
| Space / C | Climb / descend |
| V | Switch chase ↔ onboard camera |
| R | Restart mission (drone back on the launch pad) |
| Esc | Pause / resume |

The mouse is not used. Esc therefore pauses; there is no mouse capture to release.

**Input map notes.**

- All 10 Stage 0 actions are kept unchanged, and the existing test still checks them. The new actions are `ascend`, `descend`, `yaw_left`, `yaw_right` and `reset_mission`.
- Some keys now carry two actions: Space (`jump` + `ascend`), C (`classify` + `descend`), R (`report` + `reset_mission`).
- `jump`, `classify`, `report` and `mark` are not used by any Stage 1 code, so the overlap has no effect today. A later stage that uses them must re-assign keys.

## 3. Architecture

```
Main (Node3D, main.gd, process_mode = Always)   wires parts; Esc/R; feeds HUD each frame
├─ Course (training_course.tscn)                environment, ground, pads, rings, obstacles
│  ├─ WorldEnvironment, Sun, Ground (group "ground")
│  ├─ LaunchPad, LandingZone (landing_zone.gd: radius, contains())
│  ├─ Checkpoints/Checkpoint1..4 (checkpoint.tscn → checkpoint.gd, Area3D)
│  └─ Obstacles/* (StaticBody3D, group "obstacle")
├─ Drone (drone.tscn → drone_controller.gd, CharacterBody3D, group "drone")
│  ├─ Visual (meshes, rotors)    └─ OnboardCamera
├─ CameraRig (camera_rig.gd) └─ FollowCamera
├─ Mission (mission.gd)  → owns MissionState (mission_state.gd, pure rules)
├─ HUD (hud.tscn → hud.gd, CanvasLayer; display only)
└─ Title (Label, the Stage 0 notice)
```

| Script | Responsibility | Size |
|---|---|---|
| `scripts/drone/drone_controller.gd` | Reads input; `compute_velocity()` (pure, unit-tested); `step()`; crash detection; telemetry getters; `reset_to()` | 141 lines |
| `scripts/mission/mission_state.gd` | Pure rules: READY → FLYING → COMPLETED / FAILED, checkpoint order, landing hold, messages, objective/status text. No scene access | 115 lines |
| `scripts/mission/mission.gd` | Connects MissionState to drone, rings, landing zone and the area boundary. Stays inactive (with a warning) if any part is missing | 96 lines |
| `scripts/camera/camera_rig.gd` | Chase smoothing, ground clamp, view toggle, `snap()` after reset | 86 lines |
| `scripts/ui/hud.gd` | Static formatters (`format_heading`, …) and display setters only | 80 lines |
| `scripts/course/checkpoint.gd`, `landing_zone.gd` | Ring colour/number and entry signal; zone membership test | 41 / 10 lines |
| `scripts/main.gd` | Wiring, pause, restart, HUD updates | 83 lines |

Design choices:

- **Determinism.** Gameplay runs in `_physics_process` at a fixed 60 Hz with no randomness. The same inputs give the same results: the automated autopilot lands at exactly 23.9 s on every run.
- **Physics interpolation** is enabled, so motion is smooth on monitors faster than 60 Hz.
- **No `class_name` globals.** Scripts reference each other with `preload()`, so tests run on a fresh checkout without the editor's cache.
- **No third-party assets, addons or downloads.**

## 4. Launch in Godot

1. Run `E:\Hardik\Programming\DroneAcharya\Godot_v4.7.2-stable_win64.exe`.
2. In the Project Manager, open **DroneAcharya Simulator**. If it isn't listed, use **Import** and choose `simulator\project.godot`.
3. Press **F5** (Run Project).

You can also launch the game directly from PowerShell in the workspace root:

```powershell
.\Godot_v4.7.2-stable_win64.exe --path simulator
```

## 5. Run the tests

From `E:\Hardik\Programming\DroneAcharya` in PowerShell:

```powershell
# All automated tests, headless (no window). Exit code 0 = all passed.
.\Godot_v4.7.2-stable_win64_console.exe --headless --path simulator --script res://tests/run_tests.gd

# Headless scene-load check: runs the real game for 600 frames, then quits.
.\Godot_v4.7.2-stable_win64_console.exe --headless --path simulator --quit-after 600

# Visual check (opens a window): the test autopilot flies the mission with real key
# presses, saves screenshots to the folder given, and prints FPS (vsync off).
.\Godot_v4.7.2-stable_win64_console.exe --path simulator --script res://tests/tools/capture_flythrough.gd -- --out=C:/Temp/da_captures
```

| Test file | Covers |
|---|---|
| `test_smoke.gd` (Stage 0, unchanged) | Main scene loads and shows the title; the 10 original input actions exist |
| `test_input_map.gd` | Every Stage 1 control is bound to its documented key |
| `test_flight_model.gd` | Acceleration rate; speed caps (including diagonals and over-range input); braking to hover; yaw/heading maths; climb/descent caps and ceiling; hover vs ground settling; determinism; invalid time steps ignored; HUD formatting and units |
| `test_mission_state.gd` | Takeoff threshold; checkpoint order; out-of-range indices; early landing; held touchdown; landing outside zone; failure stops everything; reset; negative counts and NaN/negative time steps |
| `test_main_scene.gd` (real scene, real physics) | Components initialise on the pad; rings face their approach; onboard camera points forward and down; controls move the drone and the HUD equals the actual state; ground cannot be passed; chase camera position and `V` toggle; checkpoint order, landing and completion overlay; `R` reset; crash into PillarA fails, then reset recovers; leaving the area fails; pause freezes; incomplete scene parts stay inactive without errors; **autopilot completes the mission using only real input actions** |

The runner (`tests/run_tests.gd`) fails a test on any failed assertion **and** on any engine or script error logged while it runs. This was proven with a deliberately failing temporary test folder, which was then deleted. The two `WARNING:` lines in the output are expected: they come from the test that builds a mission and camera without a course.

## 6. Actual results (2026-10-20, this machine)

| Check | Result |
|---|---|
| Full suite, headless | **32 passed, 0 failed, exit code 0.** Autopilot mission time 23.9 s. Two later runs gave the same output |
| Same suite on a copy of `simulator/` **without** the `.godot` cache (simulates a fresh clone) | 32 passed, 0 failed, exit code 0 |
| Runner self-check (temporary failing tests incl. an error after awaiting frames) | 1 passed, 2 failed, exit code 1 (as intended); temp folder removed |
| Headless scene load, 600 frames | Exit code 0, no errors |
| Windowed launch, 600 frames | `Vulkan 1.4.348 - Forward+ - Intel(R) Arc(TM) Graphics`, exit code 0, no errors |
| Windowed autopilot fly-through (vsync off, 1600×900) | Mission completed in 23.9 s; **average 586 FPS, minimum 502 FPS** after a 2 s warm-up |
| Screenshots reviewed | Chase view at takeoff, checkpoint 2, onboard view, completion screen |
| `VIGIL/` vs `baseline-vigil-2026-10-20` | No differences |

Problems found during this stage and fixed:

1. **Drone hovered 2 cm above the pad forever** (no gravity in hover mode), so it was never "landed". Fixed by ground settling below 0.3 m and spawning at ground level. Both are covered by tests.
2. **Rings were mirrored and the onboard camera pointed 8° up**, because I wrote `.tscn` matrices in the wrong layout. Confirmed in Godot, fixed, and covered by a regression test.
3. **A test value of −1.25 was ambiguous** for one-decimal rounding (Godot rounds halves away from zero). The test now uses −1.24 plus an extra `+2.0` case.
4. **HUD layout:** the message overlapped the objective panel and the result box covered the drone. Both were moved.

## 7. Known limitations

- **Flight model:**
  - Simplified kinematics: no thrust, mass, drag, wind, battery or motor failure.
  - The tilt is cosmetic and does not affect movement.
  - There is no manual (acro) mode.
- **Collisions:** the drone is a box. Glancing contacts below 3.5 m/s slide along obstacles without penalty, and the ground never causes a crash, because descent is capped at 3 m/s.
- **Chase camera:** it does not avoid obstacles and can pass through a pillar or wall when the drone flies close by.
- **Onboard view:** the drone's own front arms are visible in the lower corners.
- **Checkpoints:** a ring counts when the drone's box touches its inner disc. Clipping the edge of the opening at an angle can still count.
- **One fixed course.** There is no course editor, randomisation or difficulty setting yet.
- **No session saving, scoring rubric or dashboard link.** These are later stages; the mission time is the only result.
- **Gamepad not supported.** The keyboard only, as specified.
- **Visual quality was checked only on this laptop.** The FPS figure is from one 24 s fly-through; it is not a benchmark.
- **The "Stage 0" editor check** (you opening the project in the editor GUI) was still outstanding at the time of writing.

## 8. Files

New:

- `scenes/course/checkpoint.tscn`, `scenes/course/training_course.tscn`
- `scenes/drone/drone.tscn`, `scenes/ui/hud.tscn`
- `scripts/camera/camera_rig.gd`
- `scripts/course/checkpoint.gd`, `scripts/course/landing_zone.gd`
- `scripts/drone/drone_controller.gd`
- `scripts/mission/mission.gd`, `scripts/mission/mission_state.gd`
- `scripts/ui/hud.gd`, `shaders/ground_grid.gdshader`
- `tests/test_flight_model.gd`, `tests/test_input_map.gd`, `tests/test_main_scene.gd`, `tests/test_mission_state.gd`
- `tests/tools/autopilot.gd`, `tests/tools/capture_flythrough.gd`
- the matching `*.uid` files generated by Godot

Modified:

- `project.godot`: 5 input actions added; physics interpolation on. Nothing removed.
- `scenes/main.tscn` and `scripts/main.gd`: the title screen became the simulator; the `Title` label is kept.
- `tests/run_tests.gd`: awaits tests and calls `cleanup()`.
- `tests/test_case.gd`: scene and frame helpers, plus `assert_near`.
