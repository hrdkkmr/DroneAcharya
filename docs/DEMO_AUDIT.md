# DroneAcharya — Demo-readiness audit

Audit date: 2026-10-20. Machine: the development PC (Windows 11, Intel Core Ultra 5 125H, Intel Arc iGPU, Godot 4.7.2 stable official `ed1daf0bf`, Python 3.13.7).

This file records what was found **before** any code was changed (sections 1–8), then what was changed and re-verified (section 9). Every "confirmed" bug below was reproduced or traced to specific code; anything not reproduced is listed as a suspicion or a risk.

---

## 1. Baseline

| Item | Value |
|---|---|
| Branch | `main`, tracking `origin/main` (https://github.com/hrdkkmr/DroneAcharya.git) |
| HEAD | `0959a17f26439656584569ebcde5e86269061a79` "Phases 6-7: integration, performance check and documentation" |
| Git status at start | clean (no staged, unstaged or untracked files) |
| Tracked files | 585 (VIGIL 373 incl. `VIGIL/dist`, simulator 189, docs 18, ml 7, schemas 3, root 2) |
| Ignored, present locally | `Godot_v4.7.2-stable_win64.exe` (180 MB), `Godot_v4.7.2-stable_win64_console.exe`, `simulator/.godot/`, `ml/data/` (generated dataset, 52 MB), `__pycache__/`, empty `exports/` |
| VIGIL baseline | tag `baseline-vigil-2026-10-20` → commit `24b37d1`. Tree hash of `VIGIL/` is `c9bb2c8158d0b3aa70677ef2a49825dddb6a5e40` at both the tag and HEAD; `git diff --stat baseline-vigil-2026-10-20 HEAD -- VIGIL` is empty |
| Automated checks | No GitHub Actions or other CI (`.github/` does not exist). Tests are run by hand |
| Export | `simulator/export_presets.cfg` has a "Windows Desktop" preset (embedded PCK, `../exports/DroneAcharya.exe`), but **no export templates are installed** (`%APPDATA%\Godot\export_templates\` is empty), so no exported build can be produced on this machine without downloading templates |

## 2. Test results at the baseline (this run, not copied from `TESTING.md`)

All commands run from `E:\Hardik\Programming\DroneAcharya`.

| Suite | Command | Result | Exit |
|---|---|---|---|
| Godot (21 files) | `.\Godot_v4.7.2-stable_win64_console.exe --headless --path simulator --script res://tests/run_tests.gd` | **167 passed, 0 failed** (≈264 s of test time) | 0 |
| ML pipeline | `python -m unittest discover -s ml/tests -v` | **11 passed** (2 dataset tests ran because `ml/data/` exists locally; on a fresh clone they are skipped) | 0 |
| Session schema | `python -m unittest discover -s schemas -v` | **4 passed** | 0 |

The Godot output contains exactly the two expected `WARNING` lines (a test builds an incomplete flight scene on purpose). No `ERROR` or `SCRIPT ERROR` lines.

Covered by the Godot suite: main scene and every menu scene load (`test_smoke`, `test_menus_and_observation`), ML model loading, validation, fallback and Python parity (`test_ml_classifier`), input map, flight, radar, threat workflow, reports, audio, sessions and replay.

## 3. Launch dependencies (actual)

| Dependency | Status |
|---|---|
| Godot 4.7.2 **standard** (not .NET) Windows editor binary | **Required, not in the repository** (git-ignored). The README commands `.\Godot_v4.7.2-stable_win64.exe …` only work where the binary has been copied into the repo root |
| Vulkan-capable GPU (Forward+ renderer) | Required by `config/features = "Forward Plus"`; worked on Intel Arc |
| `simulator/.godot/` import cache | **Not required.** The project has no importable assets (no textures, audio, meshes or fonts files; sound is generated in code), no `class_name` and no `@tool` scripts. Confirmed: a fresh clone without `.godot/` launches and runs tests with no errors |
| ML model | `simulator/models/track_classifier_v1.json` (+ `.metrics.json`) — tracked, loaded with `FileAccess` (no import step), included by the export preset's `include_filter` |
| Scenarios | `simulator/scenarios/*.json` — tracked, also in the export `include_filter` |
| Python, numpy, scikit-learn, jsonschema | Only for the ML and schema tests and retraining. **Not needed to run the simulator** |
| Network | None. No HTTP/socket code in `simulator/`. The only OS call is "Open folder" on the History screen (`OS.shell_open` of a local folder) |
| User data | `%APPDATA%\DroneAcharya\` (`config/use_custom_user_dir`): `settings.cfg`, `sessions\`, `flight_sessions\`, `exports\`, `logs\`. Tests use `test_runs\` inside it |

## 4. Architecture and entry points

- `simulator/project.godot` → main scene `res://scenes/main.tscn` (`scripts/menu/main_menu.gd`). No autoloads; screens share state through static vars in `scripts/app/app_state.gd` and `scripts/app/settings_store.gd`. Scene changes go through `AppState.goto()`, which always unpauses the tree.
- **Flight training:** menu → `flight_briefing.tscn` (mission + drone profile) → `flight/flight_training.tscn` (`flight_training.gd`: builds the city/village world, drone, `mission.gd` + pure `mission_state.gd`, HUD, radar from `flight_sensor.gd`, hazards from `flight_traffic.gd`) → result overlay → flight record (`flight_record.gd`, `user://flight_sessions`) → History.
- **Threat detection:** menu → tutorial (first visit) → `briefing.tscn` → `observation/observation.tscn` (`observation_main.gd` renders and routes input; the pure `sim/threat_session.gd` holds the world, sensors, tracker, decision support and trainee actions) → `training/session_record.gd` + `rubric.gd` → `session_io.gd` (`user://sessions`) → History (`menu/history.gd` + `training/report_builder.gd`).
- **Decision support:** `ai/features.gd` (features-1, tracker output only) → `ai/rule_engine.gd` (Model 1, rules) and `ai/ml_classifier.gd` (Model 2, random forest JSON, GDScript inference) → `ai/decision_policy.gd` (Model 3, rule-based response policy). ML is used when loaded and `AppState.use_ml` is on; otherwise the rules, labelled as the fallback.
- **Tests:** `simulator/tests/run_tests.gd` (SceneTree runner, fails on any logged engine/script error); `ml/tests/test_pipeline.py`; `schemas/test_session_schema.py`. Tools: `tests/tools/capture_ui.gd` (screenshots in a real window), `tools/measure_performance.gd`.

## 5. Confirmed bugs (before changes)

| # | Priority | Bug | Evidence |
|---|---|---|---|
| B1 | **P1** (documented launch breaks) | The README quick-start commands fail on any machine that does not already have the Godot binaries copied into the repo root; the README never says to install Godot. | Fresh `git clone` of HEAD into a scratch folder, then the README command: `'.\Godot_v4.7.2-stable_win64_console.exe' is not recognized…`. The binaries are git-ignored (`.gitignore`: `Godot_*.exe`). |
| B2 | **P2** (history unusable after one bad file) | A flight record with the right keys but wrong value types passes `FlightRecord.validate()` (it only checks that keys exist), then the History screen stops with a script error and shows **no entries at all**, valid ones included. | Probe: record with `"mission": "not a dictionary"` → `validate()` returns `ok: true`; History logs `SCRIPT ERROR: Invalid access to property or key 'title' on a base object of type 'String'` at `history.gd:129`; list has 0 items, report blank. The app itself always writes complete records, so this needs a hand-edited, truncated-but-valid-JSON or future-format file. |
| B3 | **P2** (settings not honoured at launch) | Saved volume and mute are not applied when the app starts: the main menu calls `SettingsStore.apply()` before anything has loaded `settings.cfg`, so the menu plays at the default 80 % volume, unmuted, until another screen reads a setting. | Probe: saved `muted=true`, `master_volume=0.3` → after the main menu's `_ready`, Master bus mute = false, volume 0.80; the first `get_value()` then applies mute. Code: `settings_store.gd` `apply()` uses `values` without `_ensure_loaded()`. |
| B5 | **P1** (wrong decision recorded) | When the selected contact joins a swarm group while the decision card is mid-decision, the card silently resets: a pending alarm confirmation falls back to the response list with "Continue observing" highlighted, so the trainee's next right-click/Enter records a **different final response** from the one shown for confirmation (and the score follows it). Happens in the swarm scenario, where contacts are confirmed singly and grouped seconds later. | Probe on `02_swarm_urban_day` (seed 26248): T003 selected at 14.8 s, classified, "Notify the supervisor" pending confirmation; T003 joins group at 31.3 s; after the next HUD refresh the card is `respond` / `continue_observing`. Cause: `observation_hud.gd` `_refresh_tracks()` re-selects the re-created Contacts row with `item.select(0)`, which emits `item_selected` → `track_selected` → `observation_main.select_track()` → `bind_card()`, which resets step and highlight. The new regression test fails on the original code with `got ["T003", "respond", "continue_observing"]` and the session recording `continue_observing`. |
| B4 | **P3** (test hygiene; touches real user data) | The test suite writes an export file into the **real** `%APPDATA%\DroneAcharya\exports\` on every run (contrary to `TESTING.md`: "tests write only to user://test_runs/"). | `test_menus_and_observation.gd::test_exercise_to_review_to_3d_replay_and_back` calls `history.export_selected()`, which uses the constant `SessionIO.EXPORT_DIR = "user://exports"`. The baseline run added `droneacharya-session-da-26247-1792470276.json` (09:54); 23 earlier files with the same seed are from previous test runs. Nothing is overwritten or deleted. |

## 6. Suspected bugs and risks (not reproduced, or reproduced but harmless)

| # | Item | Status |
|---|---|---|
| S1 | Restarting from the pause menu might leave the motor/ambience loops paused (restart unpauses the tree without calling `set_paused_mix(false)`). | **Disproved by probe**: Godot clears `stream_paused` on PAUSABLE players when the tree unpauses; after Restart the rotor and wind loops play. No change. |
| S2 | Decision card loses a pending step when the selected contact's Contacts-list row is re-created. | **Confirmed by probe → B5.** |
| S3 | A threat session file with a malformed nested event (e.g. an action without `kind`) makes the rubric recompute log a `SCRIPT ERROR` during validation. | Reproduced; the file is still quarantined as "invalid" and the rest of History works. Error noise only. Not fixed. |
| S4 | Swarm decisions: classifying a member as "swarm" (and responding) overwrites the category/response of every group member, including members that already had a final response. | Code reading only; needs a scenario where a contact gets a final response before its group forms. Not fixed (scoring logic; not demo-critical). |
| S5 | `R` restarts the flight mission or the threat exercise immediately, without confirmation, and `R` still works while the threat tutorial is open over the pause menu (the tutorial then stays open over a running exercise; Esc closes it). | Design risk for a live demo; documented in the runbook. Not changed. |
| S6 | The "Use the trained ML classifier" checkbox is not persisted (static `AppState.use_ml`, back to on at every launch), while the README says settings are "all saved locally". | Cosmetic; the default (on) is what the demo needs. Not changed. |
| S7 | Test runs write Godot logs into the same `%APPDATA%\DroneAcharya\logs\` as the app; Godot keeps 5 log files, so a test run can rotate out the log of an interactive failure. | Documented in the runbook (copy the log before running tests). |
| S8 | `settings.gd` measures ML latency with `res://tests/fixtures/ml_parity_v1.json`, which the export preset excludes (`tests/*`). | Handled: `file_exists` check → latency line omitted in an exported build. No change. |
| S9 | Right-clicking directly on a decision-card option row does not confirm (the row is `MOUSE_FILTER_STOP` and consumes the click); right-clicking the 3D view does. | Code reading; UX only. Runbook says to right-click on the scene. |

## 7. Manual checks still needed

Things the headless suite cannot prove (also in `LIVE_DEMO_RUNBOOK.md`, section E):

1. Sound balance and loudness on the demo machine's speakers.
2. Flying each profile by hand in city and village (feel, camera among buildings).
3. Right-click vs right-drag on the real mouse/touchpad that will be used in the demo.
4. Readability at 1366×768 and with Windows display scaling above 100 %.
5. Projector/second-screen behaviour (window placement, resolution change).

## 8. Fix priority and proposed minimal changes

| Fix | For | Change |
|---|---|---|
| 1 | B1 | Docs only: README "Requirements" step (install Godot 4.7.2 standard win64, put both binaries in the repo root or call them by full path), plus the runbook's launch section. No engine binary committed. |
| 2 | B2 | `flight_record.gd` `validate()`: also check the types of the fields the History list and report read (`created_at`, `session_id`, `mission`, `profile`, `result` numbers, event shape). Regression test in `test_reports.gd`. |
| 3 | B3 | `settings_store.gd` `apply()`: load the settings file first if it has not been loaded. Regression test in `test_ui_and_navigation.gd`. |
| 5 | B5 | `observation_hud.gd`: when the Contacts list selects a row from code (re-created row, or mirroring a selection), do not emit the selection back to the scene; keep the card's step and highlight and just re-render it. Regression test in `test_decision_workflow_and_tutorial.gd`. |
| 4 | B4 | Make the export folder redirectable like the sessions folder (`AppState.exports_dir`, default `user://exports`); `history.gd` uses it; `run_tests.gd` redirects it to `user://test_runs/exports`. |

No other application changes are planned for the demo.

## 9. Changes made and verification

### 9.1 Changes (uncommitted, for review)

| Bug | Files | Change |
|---|---|---|
| B5 | `simulator/scripts/observation/observation_hud.gd` | `_syncing_selection` flag around the two programmatic `item.select(0)` calls; `_on_tree_selected` ignores selections made from code; after re-selecting a re-created row the card is re-rendered (step and highlight kept, scope text current). Real clicks on rows behave as before. |
| B3 | `simulator/scripts/app/settings_store.gd` | `apply()` calls `_ensure_loaded()` first (no recursion: `load_settings()` sets `_loaded_from` before it applies). |
| B2 | `simulator/scripts/flight/flight_record.gd` | `validate()` also checks: `session_id`/`created_at` are text; `mission` has `title` and `environment`; `profile` has `title`; result numbers (`elapsed_s`, `checkpoints_passed`, `checkpoint_count`, `integrity_end`) and `checkpoint_times`; every event has numeric `t`, text `type`, dictionary `data` with the keys the report reads for that type. All 5 real flight records in `%APPDATA%\DroneAcharya\flight_sessions` still validate (checked read-only). |
| B4 | `simulator/scripts/app/app_state.gd`, `simulator/scripts/menu/history.gd`, `simulator/tests/run_tests.gd` | New `AppState.exports_dir` (default `user://exports`, unchanged for users); History exports there; the test runner points it at `user://test_runs/exports`. |
| B1 | `README.md` | "Requirements" section (Godot 4.7.2 standard win64, where to put it, Vulkan; no import/templates/Python/network needed to play); test count 167 → 170; links to this file and the runbook. |
| tests | `simulator/tests/test_decision_workflow_and_tutorial.gd`, `test_ui_and_navigation.gd`, `test_reports.gd`, `test_menus_and_observation.gd` | 3 new regression tests (B5, B3, B2) and one added assertion (B4: the test export lands under `user://test_runs/`). No test removed, skipped or weakened. |
| docs | `docs/DEMO_AUDIT.md`, `docs/LIVE_DEMO_RUNBOOK.md` (new), `docs/demo_evidence/*.png` (new, 16 files, 5.5 MB) | This audit; the runbook; screenshots. |

### 9.2 Verification after the changes (this run)

| Check | Result |
|---|---|
| New B5 test against the **original** `observation_hud.gd` (from HEAD) | **FAIL** as expected: `expected ["T003", "confirm", "notify_supervisor"], got ["T003", "respond", "continue_observing"]` |
| Same test with the fix | PASS (decision-workflow file 11/11) |
| Godot suite, all files | **170 passed, 0 failed**, exit 0 (≈263 s); the same two expected `WARNING` lines, no errors |
| Real `%APPDATA%\DroneAcharya\exports` file count | 24 before the run, 24 after (the test export is now in `test_runs\exports`) |
| ML (`python -m unittest discover -s ml/tests`) | 11 passed, exit 0 |
| Schema (`python -m unittest discover -s schemas`) | 4 passed, exit 0 |
| Fresh clone of HEAD, README command as written | Fails: binary not present (B1, now documented) |
| Fresh clone of HEAD, engine by full path, no `.godot/` cache: `--only=smoke`, `ml_classifier`, `input_map`, `ui_and_navigation` | 2 + 5 + 2 + 7 passed, exit 0, no errors |
| Fresh clone, windowed launch of the main scene, then relaunch (`--quit-after`) | Both exit 0; log has only the engine and Vulkan banner lines |
| Screenshots (real window, `capture_ui.gd` through a scratch wrapper that also redirects flight records and exports) | 16 images, exit 0, no errors; real flight history unchanged (5 records) |
| VIGIL | see 9.3 |

**Not verified:** a genuinely clean Windows machine (only a fresh clone on the development PC, which has the Vulkan driver and a Godot user folder); an exported `.exe` (no export templates installed); sound on real speakers; the manual checks in the runbook, section E2.

### 9.3 VIGIL

`git diff --stat baseline-vigil-2026-10-20 -- VIGIL` (working tree against the baseline tag) is empty, `git status --porcelain -- VIGIL` is empty, and the tree hash at HEAD is still `c9bb2c8158d0b3aa70677ef2a49825dddb6a5e40`.

### 9.4 Not fixed (and why)

| Item | Reason |
|---|---|
| S3 (malformed nested threat event logs a script error) | The file is still refused and History keeps working; fixing it means a broader rewrite of validation in `session_io.gd`. |
| S4 (swarm decision overwrites earlier final responses) | Not reproduced; touches scoring rules. Needs its own test scenario first. |
| S5 (`R` restarts without confirmation; tutorial left open after `R`) | Design choice, not a defect; covered by the runbook. |
| S6 (ML toggle not saved) | Default is correct for the demo; documented. |
| S7 (test logs rotate app logs) | Runbook instruction instead of a code change. |
| No exported build | Needs export templates (a download). Not done without your approval; the documented method runs the project with the Godot binary. |
