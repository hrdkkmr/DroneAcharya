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
