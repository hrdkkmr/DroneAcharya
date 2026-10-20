# DroneAcharya — Improvement Plan (realism, tactical UI, training UX, audio)

Status: **living document**. It is updated at the end of every phase (§6 Progress log). It covers the brief "Simulator Realism, Tactical UI, Training UX & Audio Overhaul" (2026-10-20).

## 1. Starting point (inspected 2026-10-20, commit `afd8a66`)

**Repository**
- `main` was clean, with `origin/main` at `afd8a66`.
- Tags: `baseline-vigil-2026-10-20`.
- `git diff baseline-vigil-2026-10-20 HEAD -- VIGIL` is empty.

**Baseline tests:** `run_tests.gd`: **108 passed, 0 failed**. The flight autopilot regression completes in **23.9 s**. The two expected `WARNING` lines come from the incomplete-scene test.

### Current architecture

| Area | Files | Notes |
|---|---|---|
| Screens | `scenes/main.tscn` + `scripts/menu/*.gd`, layouts built in code with `scripts/ui/ui_kit.gd` | Menu has 6 equal buttons; screens pass data through static `scripts/app/app_state.gd` (no autoload, so headless tests work) |
| Flight training | `scenes/flight/flight_training.tscn`, `scripts/flight/flight_training.gd`, `scripts/drone/drone_controller.gd`, `scripts/mission/{mission,mission_state}.gd`, `scripts/camera/camera_rig.gd`, `scenes/course/*`, `scenes/ui/hud.tscn` + `scripts/ui/hud.gd` | One drone tuning (exported vars), one hand-built course (4 rings, pillars, walls, crates). Clock starts at takeoff. Pause is a text overlay only |
| Threat observation | `scenes/observation/observation.tscn`, `scripts/observation/*.gd` | Pure `ThreatSession` (world → sensors → tracker → decision support) at 20 Hz; HUD shows tracker output only |
| Training records | `scripts/training/{session_record,session_io,rubric,replay,aar,adaptive}.gd` | `droneacharya-session` v1, recompute-and-compare validation, deterministic replay |
| Audio | — | **None** |
| Settings | `scripts/menu/settings.gd` | Model information and ML on/off only; nothing persisted |

### Working features (must be preserved)

- Flight feel (assisted position-hold) and its tests.
- Checkpoints and landing.
- Crash and out-of-bounds failure.
- Chase-camera collision.
- Scenario configuration and generator.
- Sensors and tracker.
- Rule, ML and policy decision support.
- Rubric, session files, history, export/import and replay.
- Adaptive recommendation.

### Problems found

1. **Main menu:** six equal buttons with no hierarchy. Scenario Selection and Threat Observation look like separate modes.
2. **Flight HUD:** a permanent 6-line controls panel. Pause is only "Esc: resume / R: restart" text, with no buttons, no Back to Menu, no controls or settings.
3. **One drone tuning and one course:**
   - no environment choice;
   - no time limits;
   - no time warning;
   - no flight report (results vanish after restart);
   - no radar;
   - no threats or other traffic.
4. **Key conflicts:**
   - `mark` = F **and** left mouse button. In observation, LMB also selects markers, so `observation_main.gd` filters out the mouse.
   - Observation uses the wheel for zoom and right-drag for look. Both collide with the requested mouse-first workflow.
5. **Observation decisions:** three separate steps (Acknowledge F → choose category + confidence slider → K; choose response → Enter) in a dense left column. The screen shows two text panels, a 7-column track table, details, a long help line and decision support at once.
6. **Briefing:** a wall of text, with no tutorial.
7. **After-action review:** a single dense block mixing scores, rule codes (P1–P4) and full timelines. It is hard for a trainee to act on.
8. **Settings and audio:** no sound at all, no volume or sensitivity settings, no persistence.
9. **Scaling:** the window has no stretch mode, so UI built for 1600×900 overflows at 1366×768.

## 2. Design decisions (sensible defaults; documented, not blocking)

| Topic | Decision |
|---|---|
| UI scaling | `display/window/stretch/mode = canvas_items`, `aspect = expand`, base 1600×900. 3D still renders at the window's native resolution |
| Shared style | `ui_kit.gd` gets a theme: dark neutral surfaces, one amber accent, status colours always paired with a text or shape cue, minimum 14 px text |
| Settings | Static `SettingsStore`, persisted with `ConfigFile` at `user://settings.cfg`. Tests redirect to `user://test_runs/`. Holds master/effects/ambience volume, mouse sensitivity, effects quality, tutorial completion, preferred drone/environment |
| Audio | **Procedurally generated** short cues (sine/square/noise envelopes rendered to `AudioStreamWAV` once at start-up), so there are no third-party assets or licences. Buses `Master`, `SFX`, `Ambience` are created at runtime. Each cue has a cooldown. Rotor loop pitch follows speed. Players are children of the scene, so a scene change stops them. Narration: none. Captions/text only; documented as a later enhancement |
| Drone profiles | `scripts/flight/drone_profiles.gd`: data dictionary applied to the one existing controller. **Recon = the current tuning, unchanged** (default). Scout and Heavy differ in speed, acceleration, braking, climb, yaw, damping (braking), camera distance and battery endurance |
| Flight missions | `scripts/flight/flight_missions.gd`: data (environment, spawn, checkpoints, landing, time limit, area, threats). The original course is kept as mission `basic_course`, so existing tests and the 23.9 s autopilot are unaffected |
| Environments | Procedural low-poly builders (`scripts/world/`): **City** (road grid with irregular blocks, varied buildings with a window-facade shader, roads, markings, crossings, streetlights, cars, park, walls/gates, rooftop tanks, signs) and **Village** (pitched-roof houses, huts, dirt roads, fields, trees/bushes, walls/fences, utility poles with lines, water tank, sheds, camp landing site). MultiMesh for repeated props; collision only on buildings, walls, poles and tanks |
| Timer policy | The clock starts when the drone leaves the pad (unchanged), freezes while paused, and stops at completion or failure. An optional time limit warns at 30 s remaining (HUD colour, banner and a sound cue), then fails with "time limit reached" |
| Flight threats | A separate "hostile area" mission variant. Fictional ground emplacements launch slow, straight-flying simulated projectiles aimed at the drone's position at launch (no lead or prediction). A hostile drone patrols and follows the trainee slowly when near. Hits reduce airframe integrity (3 hits = fail). Seeded and stepped by a pure class at a fixed 60 Hz, so tests are deterministic. Projectile warnings are visual (edge arrow + banner) **and** audible |
| Flight radar | Pure `FlightSensor`: range-limited, probability of detection falls with range, seeded position noise, update interval, contact persistence (stale, then dropped). Classification from observable cues only: IFF reply → friendly; high speed → projectile; closing on own drone over several updates → hostile; otherwise unknown. The radar widget reads sensor contacts only. The destination and briefed threat areas are mission information, not sensor data |
| Observation mouse workflow | **Left click** a marker, radar contact or list row to select. **Mouse wheel** cycles the highlighted option of the selected contact's decision card (classification, then response). **Right click** (without dragging) confirms the highlighted option. Alarm responses (notify supervisor, area alert) need one more explicit **Confirm** click. **Right-drag** still looks around. **Shift+wheel** or `=`/`-` zooms. Keyboard fallback: Tab next contact, ↑/↓ option, Enter confirm, Backspace back/cancel, 1/2/3 confidence. Confirming a classification acknowledges an unacknowledged contact automatically (one step instead of two); F still acknowledges on its own. LMB is removed from `mark` |
| Tutorial | `scripts/menu/tutorial_panel.gd`: short steps with drawn diagrams and two practice interactions (click a demo contact; wheel + right-click a demo decision). Offered automatically the first time; can be skipped (with confirmation) or replayed from the menu or the pause screen |
| Reports | `scripts/training/report_builder.gd`: a structured, plain-language report built only from the record (result, ≤3 strengths, ≤3 improvements, decision timeline, ≤3 next steps, score categories, Details). Flight results are saved as a new versioned `droneacharya-flight-session` v1 record. Threat records stay `droneacharya-session` v1, so old files still read |

## 3. Files expected to change

- **New files:**
  - `scripts/app/settings_store.gd`
  - `scripts/audio/sound_bank.gd`, `scripts/audio/audio_cues.gd`
  - `scripts/ui/pause_menu.gd`, `scripts/ui/radar_display.gd`, `scripts/ui/settings_panel.gd`
  - `scripts/flight/{drone_profiles,flight_missions,flight_sensor,flight_threats,flight_record}.gd`
  - `scripts/world/{props,city_builder,village_builder}.gd`
  - `scenes/menu/flight_briefing.tscn` + script
  - `scripts/menu/tutorial_panel.gd`, `scenes/menu/tutorial.tscn`
  - `scripts/training/report_builder.gd`
  - `shaders/building_facade.gdshader`
  - tests per phase
- **Changed files:**
  - `project.godot` (stretch, input map)
  - `main_menu.gd`, `settings.gd`, `briefing.gd`, `history.gd`
  - `flight_training.gd`/`.tscn`, `hud.gd`/`.tscn`, `mission.gd`, `mission_state.gd`, `drone_controller.gd`
  - `observation_main.gd`, `observation_hud.gd`, `track_overlay.gd`, `observer_rig.gd`
  - `threat_session.gd` (auto-acknowledge option, decision scope)
  - `app_state.gd`, `ui_kit.gd`
  - `run_tests.gd` (settings redirect)
  - README and docs
- **Not changed:** anything in `VIGIL/`; the simulation, sensor, tracker, decision-model and rubric logic (except the additive session helpers above); the ML artefact.

## 4. Phases and tests

| # | Phase | Tests to add or update |
|---|---|---|
| 1 | Menu, shared style, stretch, pause screen (flight + observation), back navigation, settings with persistence, controls only on demand, key-conflict fix | Menu layout and entries; pause buttons resume/restart/back; Esc toggles; back to menu frees the mission; settings save/load round-trip; no controls panel in the HUD; LMB not bound to `mark`; no duplicate keys |
| 2a | Drone profiles, mission data, timer/limits/warnings, flight briefing, flight record | Profiles load and differ; Recon = original numbers; reset restores profile; timer start/pause/resume/stop; limit failure; warning; record saved |
| 2b | City and village environments | Both build, have collision on buildings, mission checkpoints are reachable (no ring intersects geometry), node counts within budget |
| 2c | Flight sensor, radar, traffic and threats | Radar range/Pd/noise/persistence, seeded reproducibility, widget reads contacts only, hazards deterministic, hit → integrity → fail, warning visual + audio |
| 3 | Tutorial, observation HUD redesign, observation radar, mouse workflow, swarm group presentation | Tutorial start/skip/replay; wheel affects only the selected contact; right-click confirm; alarm needs confirmation; duplicate submit blocked; keyboard fallback; radar from tracks only; group decision scored once |
| 4 | Plain-language reports (threat + flight) | Statements match the record; no banned phrases; no unsupported claims; reports reload from disk; old v1 records still render |
| 5 | Sound bank and cues, volumes, tutorial cues | Buses exist; volume/mute applied; cooldown prevents repeats; no players left after a scene change; visual equivalent for every alarm cue |
| 6/7 | Integration, docs, final verification | Full suite, autopilot regression, VIGIL diff, performance spot check |

## 5. Manual checks (cannot be automated headless)

- How the audio actually sounds, and its loudness balance.
- Readability at real laptop resolutions.
- Feel of the Scout and Heavy profiles in the hands of a human pilot.
- Visual coherence of the environments.

These are listed in `docs/TESTING.md` once performed or still outstanding.

## 6. Progress log

- **2026-10-20 — Phase 0:** inspection done; baseline 108/108; plan written.
- **2026-10-20 — Phase 1 complete:**
  - **Built:**
    - Shared theme in `ui_kit.gd`.
    - New landing page.
    - `canvas_items` stretch.
    - Shared `PauseMenu` (Resume, Restart, Controls, Settings, Back to menu) in flight and observation.
    - Controls list moved from the flight HUD to the pause menu (`controls_reference.gd`).
    - `SettingsStore` (persisted volumes, mute, mouse sensitivity, effects quality) with runtime `SFX`/`Ambience` buses.
    - `SettingsPanel` on the Settings screen and in the pause menu.
    - LMB removed from `mark`, so no action has a mouse binding.
  - **Tests:**
    - New `test_ui_and_navigation.gd` (7 tests).
    - Suite **115/115**, autopilot 23.9 s.
  - **Remaining:**
    - Observation HUD layout (Phase 3).
    - Flight HUD layout (Phase 2).
    - Tutorial entry is disabled until its scene exists (Phase 3).
- **2026-10-20 — Phase 2a complete:**
  - **Drone profiles:** `drone_profiles.gd` (Scout / Recon / Heavy utility; Recon = Stage 1 numbers) applied to the one controller and the chase camera.
  - **Mission catalogue:** `flight_missions.gd` (`basic_course` = original course, 3:00 limit).
  - **MissionState limits:** time limit with a 30 s warning, battery endurance (climb drains ×1.5, 20 % warning), integrity/hits, minor-collision count and an event log.
  - **Flight HUD:** rebuilt as a mission card + clock with limit, alert banners (word + bar + "!"), and a telemetry strip with battery and integrity.
  - **Flight briefing screen:** mission and profile choice remembered in settings; the clock starts at takeoff.
  - **Flight records:** versioned `droneacharya-flight-session` v1, saved on finish; the result screen offers "Open report".
  - **Test changes:**
    - One existing test was updated: `test_main_menu_lists_all_modes_and_opens_flight_training` now passes through the flight briefing before flying (the menu flow changed by design; the assertion that a flight scene with a drone loads is kept).
    - New `test_drone_profiles_and_missions.gd` (14 tests).
  - **Result:** suite **129/129**, autopilot 23.9 s.
- **2026-10-20 — Phase 2b complete:**
  - **Builders:** procedural `city_builder.gd` and `village_builder.gd` on shared `props.gd`:
    - MultiMesh batches with per-instance colour;
    - a world-space window facade shader;
    - named obstacle bodies, with collision only on buildings, poles, wires, walls, trees, tanks, the crane and similar.
  - **Route corridor:** `route_corridor.gd` keeps every mission route clear.
  - **Mission assembly:** `flight_world.gd` adds the launch pad, rings and landing zone.
  - **Four new missions:** City delivery, Village supply run, and a hostile-area variant of each. The threats are added in Phase 2c.
  - **Test support:** the test autopilot gained an optional landing cruise altitude (default unchanged, 4 m).
  - **Tests:** new `test_environments.gd` (5 tests):
    - build;
    - determinism;
    - collision budget;
    - a shape-cast along every route segment;
    - autopilot completes city in 68.3 s and village in 63.2 s.
  - **Result:** suite **134/134**.
- **2026-10-20 — Phase 2c complete:**
  - **`flight_traffic.gd` (pure, seeded truth):**
    - friendly patrol drones (ID reply);
    - unknown transits;
    - in hostile missions, fictional emplacement sites that launch straight-line projectiles at the drone's position at launch (22 m/s, 120 m range, 6–9 s cooldown, line of sight required);
    - a hostile drone that follows at 4.5 m/s when within 90 m and gives up after 25 s;
    - hits deal 35 % integrity.
  - **`flight_sensor.gd`:**
    - range-limited;
    - Pd 0.97→0.6;
    - seeded noise;
    - stale after 1.6 s, dropped after 4 s;
    - cue-based classification;
    - the incoming warning computed from sensor contacts.
  - **`radar_display.gd`:** heading-up scope, shape + letter per kind, legend, rim-pinned destination, briefed threat areas.
  - **HUD:** radar, INCOMING banner + edge arrow, hit flash.
  - **Flight record:** threat summary added.
  - **Balance probe (autopilot, no evasion, not committed as a test):** all 6 hostile mission/profile combinations complete; Heavy takes 2 hits in the village. The hostile drone speed was lowered from 5.0 to 4.5 m/s after Heavy failed at 5.0.
  - **Tests:** new `test_flight_radar_and_threats.gd` (9 tests). Suite **143/143**.
- **2026-10-20 — Phase 3 complete:**
  - **Tutorial:** 9 steps with drawn diagrams and two practice interactions.
    - Offered on the first Threat Detection visit; skip asks for confirmation; replayable from the menu, the briefing and the pause screen.
    - Completion is remembered.
    - No voice narration (text only); this is documented.
  - **Observation HUD rebuilt:**
    - status card (time left, objective, SENSOR DEGRADED / NEW alerts, collapsible sensor status);
    - decision card bound to the selected contact;
    - contacts list with swarm groups nested under one row;
    - collapsible contact details;
    - decision-support toggle (still logged);
    - radar of tracker tracks and groups with a view wedge and the protected area.
  - **Mouse workflow:**
    - wheel = option, right-click = confirm, right-drag = look;
    - Shift+wheel or `=`/`-` = zoom (the plain wheel zooms only when nothing is selected);
    - alarm responses need one more explicit Confirm;
    - a 350 ms double-confirm guard;
    - confirming a classification acknowledges the contact in the same step (`ThreatSession.classify(..., auto_acknowledge)`).
  - **Keyboard fallback:** ↑/↓, Enter, Backspace, 1/2/3. New input actions are covered by `test_input_map.gd`.
  - **Group scope:** `ThreatSession.decision_scope()` tells the card whether a decision covers one contact or the whole group.
  - **Test change:** `test_threat_observation_uses_default_scenario_when_none_selected` now marks the tutorial as already seen, because a first visit now opens the tutorial.
  - **Tests:** new `test_decision_workflow_and_tutorial.gd` (10 tests). Suite **153/153**.
- **2026-10-20 — Phase 4 complete:**
  - **`report_builder.gd`** builds a plain-language report from threat (`droneacharya-session` v1) and flight (`droneacharya-flight-session` v1) records. Sections:
    1. result;
    2. ≤3 strengths;
    3. ≤3 improvements;
    4. a decision timeline with assessment and reason;
    5. 1–3 next steps;
    6. plain score categories.
  - **Data only:** every statement is computed from the record and left out when unsupported. The threat summary separates correct, incorrect, unknown, unresolved, missed, unnecessary alerts and delayed decisions.
  - **Details:** the full rubric output (`aar.gd`) is kept under "Details".
  - **Versions:** an unknown version gives a notice, not a guess.
  - **History screen:** lists flight and threat records together; the flight result screen's "Open report" selects the new record.
  - **End-of-exercise overlay:** shows the score, the contact summary and the first strength and improvement.
  - **Test changes:**
    - `test_exercise_to_review_to_3d_replay_and_back` now finds "Decision timeline" under Details, and the plain report must contain "What went well".
    - New `test_reports.gd` (7 tests), including banned-phrase and reload-from-disk checks.
  - **Result:** suite **160/160**.
- **2026-10-20 — Phase 5 complete:**
  - **`sound_bank.gd`:** 18 procedurally generated cues plus rotor and wind loops, rendered once to 16-bit WAV. There are no audio files, so no third-party licences.
  - **`audio_cues.gd`:** one per screen, freed with it.
    - per-cue cooldowns and a pool of 6 players;
    - loops are PAUSABLE and pause with the game;
    - `CRITICAL_CUES` documents the visual sign shown with every alarm sound.
  - **Flight:** a rotor loop whose pitch follows speed and climb, plus cues for mission start, takeoff, checkpoint, out-of-order ring, bump, hit, time and battery warnings, INCOMING, success and failure.
  - **Observation:** a wind ambience, plus cues for new or reacquired contacts, lost contacts, sensor degradation, decision accepted or rejected, alarm confirmation and the exercise end.
  - **Shared UI and tutorial:** shared buttons click. The tutorial has step and practice cues with a "Sound cues" toggle.
  - **Narration:** none. The tutorial is text plus cues; voice narration is listed as a later enhancement.
  - **Tests:** new `test_audio.gd` (7 tests). Suite **167/167**.
