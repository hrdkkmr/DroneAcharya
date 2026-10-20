# DroneAcharya — Testing (after the 2026-10-20 overhaul)

All commands run in PowerShell from `E:\Hardik\Programming\DroneAcharya`.

**Measurement machine:**

| | |
|---|---|
| CPU | Intel Core Ultra 5 125H |
| Graphics | Intel Arc integrated GPU |
| Memory | 15.6 GB RAM |
| OS | Windows 11 |
| Engine | Godot 4.7.2 |

`DRONEACHARYA_TESTING.md` remains the reference for the ML pipeline, the dataset and packaging.

## 1. Commands

```powershell
$G = ".\Godot_v4.7.2-stable_win64_console.exe"
& $G --headless --path simulator --script res://tests/run_tests.gd                       # all Godot tests (about 4.5 min)
& $G --headless --path simulator --script res://tests/run_tests.gd -- --only=reports     # one file
python -m unittest discover -s ml/tests                                                    # ML pipeline (11)
python -m unittest discover -s schemas                                                     # session JSON Schema (4)
& $G --audio-driver Dummy --path simulator --script res://tests/tools/capture_ui.gd -- --out=C:/Temp/shots [--size=1366x768] [--shots=menu,city]
& $G --audio-driver Dummy --path simulator --script res://tools/measure_performance.gd -- --out=C:/Temp/perf.json
```

**How a test fails:**

- on any failed assertion, or any engine or script error logged while it runs;
- the runner then exits with code 1.

**Sandboxing:** tests write only to `user://test_runs/` (sessions, flight records, settings). Settings are reset at the start of each run.

## 2. Results (final run)

| Suite | Result |
|---|---|
| Godot, 21 test files | **167 passed, 0 failed** (exit 0) |
| Python ML | **11 passed** |
| Python schema | **4 passed** |

**Autopilot regressions (real controls):**

| Course | Time |
|---|---|
| Basic course | **23.9 s** (unchanged since Stage 1) |
| City delivery | 68.3 s (4:00 limit) |
| Village supply | 63.2 s (4:00 limit) |

**VIGIL:** `git diff baseline-vigil-2026-10-20 HEAD -- VIGIL` is empty.

**Expected warnings:** two `WARNING` lines in the output come from a test that builds incomplete scene parts on purpose.

### Tests added in this overhaul

| File | Tests | Covers |
|---|---|---|
| `test_ui_and_navigation.gd` | 7 | Landing page, pause menus (flight and observation), back to menu releases the mission, no focus kept by in-game buttons, settings persistence and clamping, settings screen, no mouse bindings on actions |
| `test_drone_profiles_and_missions.gd` | 14 | Profiles complete and different (velocity model and in-scene), Recon = original tuning, reset restores profile and state, time limit warning/failure, no-limit case, battery drain and climb factor, hits and integrity, bump vs crash, flight record saved and validated, flight briefing, HUD limit and TIME LOW banner |
| `test_environments.gd` | 5 | City and village build with their own props, determinism, collision only on hazards and within budget, shape-cast along every route segment, autopilot completes both |
| `test_flight_radar_and_threats.gd` | 9 | Sensor range and id hiding, Pd vs range, seeded noise, stale then dropped then reacquired, cue-based classification, traffic determinism, hovering hit vs moving, hostile drone follows and gives up, radar heading-up and range limit, radar shows exactly the sensor contacts, hits fail the mission, INCOMING shown |
| `test_decision_workflow_and_tutorial.gd` | 10 | First visit opens the tutorial, skip with confirmation, steps and practice interactions, replay from pause, wheel affects only the selected contact and never acts, right-click confirms but right-drag does not, alarm confirmation, double submission blocked without penalty, keyboard fallback, observation radar = tracker output, swarm decision applies to the group and is scored once |
| `test_reports.gd` | 7 | Correct decisions with their counts, errors/missed/false alarms named with real times, no praise without data, reports reload identically from disk, flight report (time, rings, collisions, landing, failure cause), unknown versions not guessed, history lists flight and threat reports |
| `test_audio.gd` | 7 | Every cue generated and short, loops loop, cooldown, player pool, volume and mute (game runs muted), flight event cues and motor paused with the game, no sound left after a scene change, alarm cue only with its visual sign, observation contact/decision/confirmation cues |

### Existing tests changed (and why)

The other existing files are unchanged.

| Test | Change | Reason |
|---|---|---|
| `test_menus_and_observation.gd::test_main_menu_lists_all_modes_and_opens_flight_training` | Now passes through the flight briefing, then checks that the flight scene and drone load (as before) | The menu opens a briefing before flying (the clock must not run during it) |
| `test_menus_and_observation.gd::test_threat_observation_uses_default_scenario_when_none_selected` | Marks the tutorial as seen first | A first visit now opens the tutorial (covered by a new test) |
| `test_menus_and_observation.gd::test_exercise_to_review_to_3d_replay_and_back` | Looks for "Decision timeline" under Details and for "What went well" in the report | The plain report comes first; the rubric output moved under Details |
| `test_input_map.gd` | 8 new actions in the expected list | Keyboard fallback for the decision card |

No test was deleted, skipped or weakened.

## 3. Automated vs manual

**Automated (headless):** everything above. Logic, state, input routing (synthetic input events), what the HUD and radar show, which sounds are triggered, and file round trips.

**Checked visually** (screenshots with `capture_ui.gd` in a real window; issues found and fixed):

- **Screens checked:**
  - menu;
  - settings;
  - flight briefing (at 1600×900 and 1366×768);
  - flight HUD;
  - pause menu with controls;
  - city and village, chase and overview views;
  - hostile mission with radar and INCOMING;
  - observation screen;
  - alarm confirmation;
  - tutorial;
  - briefing;
  - threat report.
- **Issues fixed:**
  - washed-out lighting;
  - alert banner running off-screen;
  - truncated group names;
  - duplicate Confirm button;
  - unlabelled practice radar;
  - report wording ("uav" lower case, "0 s of clear view").

**Still needs a person:**

1. Hearing the sounds: balance, loudness, whether any cue is annoying.
2. Flying every profile in both environments by hand (feel of Scout and Heavy; whether the chase camera is comfortable among buildings).
3. A full threat exercise played with the mouse workflow, especially right-click vs right-drag on a real mouse and touchpad.
4. Readability on a real 1366×768 laptop screen, and with high-DPI scaling.

## 4. Performance (measured with `measure_performance.gd`, vsync off, 1600×900)

| Measure | Result |
|---|---|
| Startup to first menu frame | 1.19 s |
| Flight, basic course | 498 FPS mean (1 % low 317) · 72 draw calls · scene load 262 ms |
| Flight, city delivery | 426 FPS (260) · 178 draw calls · load 144 ms |
| Flight, city hostile | 401 FPS (247) · 232 draw calls · load 81 ms |
| Flight, village supply | 494 FPS (308) · 151 draw calls · load 98 ms |
| Flight, village hostile | 447 FPS (275) · 211 draw calls · load 96 ms |
| Observation, typical, eye / sensor view | 581 / 527 FPS |
| Observation, 30-actor stress, eye / sensor view | 515 / 420 FPS |
| Static memory in flight missions | about 82 MB |

**Concern (unchanged from before):** the threat decision tick in the 30-actor stress scenario averages 21.7 ms, with a 46.5 ms maximum. That can cause a brief hitch about once per second, only in that extreme case.

**Environment cost:** the city and village builders run once at load (under 0.3 s). Collision shapes stay under the tested budget of 2,500.
