# DroneAcharya — Architecture (after the 2026-10-20 overhaul)

This document covers the whole simulator as it stands. The threat-observation core (scenarios, synthetic sensors, tracker, decision models, rubric, replay) is described in more depth in:

- `DRONEACHARYA_ARCHITECTURE.md`
- `DRONEACHARYA_SIMULATION_MODELS.md`
- `DRONEACHARYA_DECISION_MODELS.md`

Those parts did not change, except where §5 says so.

DroneAcharya is a **synthetic training prototype**, not an operational system:

- Places, contacts, sensors and hazards are fictional.
- Responses are procedural steps.
- Hazards are simplified game mechanics.

## 1. Separation of data

| Layer | Flight training | Threat detection | Rule |
|---|---|---|---|
| Ground truth | `FlightTraffic` entities, `MissionState` | `ThreatWorld` actors, truth channel (`truth_links`, availability) | Only simulation and assessment read it |
| Sensor observations | `FlightSensor` contacts (C01…) | `SensorModel` observations → `Tracker` tracks (T001…) | The trainee UI and radars read only this layer |
| Trainee decisions | Flight controls → drone | Decision card → `ThreatSession.classify/respond` (validated, logged) | Logged as events |
| Assessment | `FlightRecord` + `ReportBuilder` | `Rubric.evaluate` + `ReportBuilder` | Runs after the exercise, from the saved record |

Tests enforce the separation:

- Radar items come only from sensor contacts or tracker tracks.
- Sensor contacts carry no truth ids.
- The HUD never shows truth labels.
- Decisions do not depend on truth.

## 2. Components and files (`simulator/`)

| Component | Files | Kind |
|---|---|---|
| App state and navigation | `scripts/app/app_state.gd` (static, no autoload) | Glue |
| Settings | `scripts/app/settings_store.gd` (ConfigFile, audio buses), `scripts/ui/settings_panel.gd` | Service + UI |
| Shared UI style | `scripts/ui/ui_kit.gd` (theme, cards, buttons), `scripts/ui/pause_menu.gd`, `scripts/ui/controls_reference.gd` | UI |
| Radar display | `scripts/ui/radar_display.gd` (shared by flight and observation) | UI (draws given data only) |
| Drone profiles | `scripts/flight/drone_profiles.gd` | Data |
| Flight controller | `scripts/drone/drone_controller.gd` (unchanged feel; `apply_profile`, `bumped` signal) | Physics |
| Mission timer and objectives | `scripts/mission/mission_state.gd` (pure), `scripts/mission/mission.gd` (scene glue) | Pure logic + glue |
| Mission catalogue | `scripts/flight/flight_missions.gd` | Data |
| Environments | `scripts/world/{props,city_builder,village_builder,route_corridor,flight_world}.gd`, `shaders/building_facade.gdshader` | Procedural content |
| Traffic and hazards | `scripts/flight/flight_traffic.gd` (pure, seeded), `scripts/flight/traffic_visuals.gd` | Pure simulation + visuals |
| Flight sensor | `scripts/flight/flight_sensor.gd` (pure, seeded) | Synthetic sensor |
| Flight scene | `scripts/flight/flight_training.gd`, `scripts/ui/hud.gd` | Scene glue + HUD |
| Flight records | `scripts/flight/flight_record.gd` | Persistence |
| Threat session | `scripts/sim/*` (`threat_session.gd` gained `classify(..., auto_acknowledge)` and `decision_scope()`) | Pure simulation |
| Observation scene | `scripts/observation/{observation_main,observation_hud,track_overlay,observer_rig}.gd` | Scene glue + HUD |
| Tutorial | `scripts/menu/tutorial_panel.gd` (reusable), `scripts/menu/tutorial.gd`, `scenes/menu/tutorial.tscn` | UI |
| Reports | `scripts/training/report_builder.gd` (+ unchanged `rubric.gd`, `aar.gd`, `session_io.gd`, `replay.gd`) | Pure logic |
| Audio | `scripts/audio/sound_bank.gd` (procedural WAV), `scripts/audio/audio_cues.gd` (per-screen player) | Service |
| Screens | `scripts/menu/{main_menu,flight_briefing,briefing,scenario_select,history,settings}.gd` | UI |

## 3. Flight-training data flow

```
flight_briefing ─► AppState.flight_mission / flight_profile
flight_training._ready:
  FlightWorld.build(mission)  (city / village; "course" keeps the hand-built scene)
  drone.apply_profile(profile); camera follow values; mission.configure_limits(time limit, endurance)
every physics frame (paused → nothing runs):
  drone_controller.step(pilot input) ─► move_and_slide ─► crashed / bumped
  mission.gd ─► MissionState.update(altitude, ground, zone, speed, dt, climb) ─► events, messages
  FlightTraffic.step(dt, drone position) ─► hits ─► mission.register_hit
  FlightSensor.step(dt, drone position, active traffic) ─► contacts, incoming warnings
every frame:
  HUD ◄─ telemetry, MissionState (clock, limit, battery, integrity), radar ◄─ FlightSensor contacts only
  AudioCues ◄─ new MissionState events (+ rotor loop from speed/climb)
mission ends ─► FlightRecord.build/save ─► result screen ─► History ─► ReportBuilder
```

## 4. Threat-detection UI flow

```
Threat Detection Training ─► (first time) tutorial ─► briefing ─► observation
observation_main: ThreatSession stepped at 20 Hz (unchanged)
  input: left click / radar / list ─► select_track ─► hud.bind_card
         wheel / ↑↓ ─► hud.cycle_option        (selected contact only)
         right click / Enter ─► hud.confirm ─► classify(auto_acknowledge) / respond
         alarm response ─► confirmation step ─► respond
  HUD: status card · decision card · contacts (groups nested) · details · decision support · radar (tracker output)
  end ─► SessionRecord + Rubric ─► SessionIO.save ─► summary ─► History ─► ReportBuilder
```

## 5. What changed in existing code, and why

| Change | Why |
|---|---|
| Flight HUD rebuilt in code (`hud.gd`); the permanent controls panel was removed | Controls on demand only; room for the clock, alerts and radar. Value labels keep their names and formats (tests) |
| `mission_state.gd` gained limits, an event log and counters | Timer, battery, integrity and reports. Existing behaviour and messages are unchanged |
| `mission.gd` can re-run `setup()` | Procedural environments replace the course after the scene loads |
| `drone_controller.gd` gained `apply_profile` and a `bumped` signal | Profiles without a second controller; minor collisions for reports |
| `observation_hud.gd` rebuilt | Decision card, less information at once, radar. Text helpers and the names tests use are kept |
| `observer_rig.gd`: plain wheel zooms only when nothing is selected | The wheel now chooses decision options |
| Input map: LMB removed from `mark`; 8 actions added | Removes the key/mouse conflict; keyboard fallback for the decision card |
| `project.godot`: `canvas_items` stretch | UI scales with the window (tested at 1366×768) |

## 6. Design decisions and limitations

**Simplifications:**

| Area | Decision |
|---|---|
| Autoloads | None. Static state (`AppState`, `SettingsStore`, `AudioCues.active`) keeps headless tests and the `--script` runner working |
| Sound | Generated at run time (no files), so no licensing questions. Sound quality is simple tones and noise |
| Narration | None (offline, no TTS dependency). Text is the caption for everything |
| Flight sensor | Ideal association. Classification is behaviour- and cue-based, so a harmless drone flying straight at you can be marked hostile |
| Hazards | Deliberately simple: straight-line projectiles aimed at the drone's position at launch; a slow follower drone |

**Performance:** see `TESTING.md` §4.

**Known gaps:**

- Flight missions have no replay.
- Flight records have no import.
- Threat-session imports and exports are unchanged.
