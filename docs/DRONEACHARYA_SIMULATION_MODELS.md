# DroneAcharya — Simulation Models

Component classes used throughout the DroneAcharya docs:

- **Deterministic simulation:** the ground-truth world, scenario generation and flight models.
- **Synthetic sensor simulation:** radar-like and camera observations (§6).
- **Rule-based decisions / trained ML inference / training assessment:** see `DRONEACHARYA_DECISION_MODELS.md`.

Everything here is a **fictional training model**. Values are chosen to make behaviours learnable and distinguishable, not to match real aircraft, animals or sensors.

---

## 1. Coordinate system and time

| Item | Convention |
|---|---|
| Axes | +X east, +Y up, −Z north (Godot default). Ground plane at y = 0 |
| Compass heading | 0° = north, 90° = east, clockwise |
| Yaw | Godot rotation about +Y; 0 faces north; positive turns left |
| Observer | Fixed post at (0, 25, 0), the top of a 25 m tower. The protected zone is a circle on the ground centred at the origin |
| Threat simulation tick | **20 Hz fixed** (`TICK_RATE`), time = `tick / 20` (never accumulated, so no drift) |
| Flight-training drone | Godot physics at 60 Hz (unchanged from Stage 1) |

## 2. Scenario configuration (`droneacharya-scenario` v1) — deterministic simulation

Implemented in `simulator/scripts/sim/scenario_config.gd`; presets are in `simulator/scenarios/*.json`.

| Field | Type / range | Default |
|---|---|---|
| `format`, `version` | `"droneacharya-scenario"`, `1` | required |
| `id` | text, 1–64 characters | required |
| `title`, `description` | text | `id`, `""` |
| `seed` | integer 0 … 4294967295 | required |
| `environment` | `urban` \| `rural` | required |
| `time_of_day` | `day` \| `night` | required |
| `visibility` | `clear` \| `haze` \| `fog` | required |
| `duration_s` | integer 60–600 | required |
| `difficulty` | integer 1–5 | 1 |
| `protected_zone_radius_m` | 40–400 | 120 |
| `wind.speed_mps`, `wind.direction_deg` | 0–15; 0–360 (direction the wind blows *toward*) | 3, 90 |
| `groups[]` | 1–12 groups, at most **30 actors** in total | required |
| `groups[].profile` | `bird`, `balloon`, `authorised_uav`, `unidentified_uav`, `swarm_uav` | required |
| `groups[].behavior` | must be allowed for the profile (§4) | the profile's first behaviour |
| `groups[].count` | 1–6 (swarm: 3–12) | 1 (swarm: 3) |
| `groups[].spawn_s`, `start_range_m`, `altitude_m`, `speed_mps` | `[min, max]` pairs | the profile's defaults |
| `sensor.radar` / `sensor.eo` | see §6 | §6 defaults |
| `sensor.delay_s`, `sensor.clutter_per_min`, `sensor.degradation[]` | `[min, max]` 0–5 s; 0–30; windows `{start_s, end_s, severity 0–1}` | `[0.2, 1.0]`, 1.0, none |
| `weights` | six assessment components, summing to 100 | 20/20/15/20/15/10 |

`validate()` returns `{ok, errors, config}`. Every error names the field and the allowed range. Invalid preset files are listed as *invalid*, with their errors, on the selection screen and cannot be started.

### Seeded procedural generation

`ScenarioConfig.generate(seed, options)` builds a valid config from a seed. The options can fix the environment, time of day, visibility, difficulty, `swarm` and `single`.

Difficulty affects:

- duration (120 + 30 × (level − 1) s);
- actor count and whether a swarm appears (level ≥ 3);
- radar and camera detection probability (−10 % per level);
- radar range noise;
- delivery delay;
- clutter rate;
- a degradation window (level ≥ 2).

Each combination comes from configuration; there are no hand-made scenes.

## 3. Scenario generation — deterministic simulation

`scenario_generator.gd` turns a config into a definition containing actors, routes, layout, zone and wind. Every random draw comes from an independent stream: `FNV-1a(seed | label)` seeds a Godot `RandomNumberGenerator`, with labels such as `group-0` and `layout` (`sim_random.gd`). Adding a new stream therefore never changes existing ones. The same config always gives the same definition; this is verified in `test_threat_world.gd`.

- **Start position:** a random compass bearing at `start_range_m`. Balloons start upwind, so the wind carries them across the area.
- **Transit routes:** a straight line past the zone. Unidentified UAVs pass at 0.2–1.6 × the zone radius; authorised UAVs keep a 250–420 m corridor.
- **Loiter / hover points:** 0.8–2.5 × the zone radius from the centre, near the start bearing; orbit radius 40–90 m.
- **Swarms:** the first member leads, and the others take staggered V-formation slots 8–12 m apart.
- **Layout:**
  - *urban* — buildings on a 60 m grid (16–40 m footprint, 8–38 m tall, ~35 % of cells empty) out to 720 m;
  - *rural* — 180 trees (6–14 m) and 8 farmhouses out to 900 m.
  - Nothing is placed within the protected-zone radius + 40 m.
- **Truth labels:** profile, `truth_category` (VIGIL vocabulary: routine / review / background) and `significant` are stored in the definition. They are used for evaluation and replay only.

## 4. Actor profiles and behaviours — deterministic simulation

| Profile | Truth category | Significant | Behaviours | Size (m) | Radar reflectivity | ID reply | Max speed (m/s) | Turn rate (°/s) | Wind factor |
|---|---|---|---|---|---|---|---|---|---|
| bird | background | no | erratic | 0.6 | 0.25 | no | 15 | 140 | 0.25 |
| balloon | background | no | drift | 1.8 | 0.6 | no | 1 (air) | 30 | 1.0 |
| authorised_uav | routine | no | transit | 0.9 | 0.45 | **yes** (fictional cooperative reply) | 16 | 25 | 0.2 |
| unidentified_uav | review | **yes** | transit, loiter, hover | 0.7 | 0.35 | no | 14 | 50 | 0.25 |
| swarm_uav | review | **yes** | transit, loiter (members: formation) | 0.5 | 0.3 | no | 14 | 70 | 0.25 |

Behaviours (`threat_world.gd`) output a *desired air velocity*:

| Behaviour | Rule |
|---|---|
| transit | Fly to each waypoint in turn (reached within 20 m), then continue straight until leaving the 2.2 km area |
| loiter | Fly to the centre; within radius + 25 m, orbit (tangent × speed + radial correction) |
| hover | Fly to the point; within 15 m, hold with a proportional pull back to it |
| drift | No air motion; slow climb (0.1–0.4 m/s); moves with the wind |
| erratic | Every 1–3 s choose a new heading (±100°), speed (0.6–1.2 × cruise) and height (±15 m); turn back when more than 250 m from the anchor. Uses the actor's own seeded stream |
| formation | Leader velocity + 0.8 × (slot − position); the slot rotates with the leader's yaw |

An actor that moves more than **2.2 km** horizontally from the post *exits* and is no longer simulated.

## 5. Flight model for target actors — deterministic simulation

`flight_model.gd` uses a point-mass model. Each tick:

1. Clamp the desired horizontal speed to `max_speed` and the vertical speed to `max_climb_rate`.
2. Rotate the current heading toward the desired heading by at most `max_turn_rate × dt`.
3. Change velocity by at most `max_acceleration × dt` (momentum).
4. Multiply by `(1 − damping × dt)` to apply velocity damping.
5. Ground velocity = air velocity + wind × `wind_factor`. The wind includes a deterministic gust of ±15 % (`sin(0.7 t)`).
6. Integrate position; clamp altitude to [`min_altitude`, `max_altitude`] (5–400 m) and zero any vertical speed into the limit.
7. Record acceleration and yaw (from air velocity).

Target actors **do not collide** with buildings or trees. The generator keeps their altitude bands mostly above props, and occlusion is handled by the sensor (§6). Boundary handling is the 2.2 km exit plus the altitude clamp.

**This is a game approximation, not a validated aerodynamic model.**

### Shared vehicle-state interface

`vehicle_state.gd` holds position, velocity, acceleration, yaw, time, `horizontal_speed()`, `heading_degrees()` and `to_dict()`. Target actors use it directly. The player's training drone keeps its own Stage 1 assisted-flight controller (`drone_controller.gd`, 60 Hz Godot physics, collisions with course obstacles). Its telemetry uses the same units and axis conventions.

## 6. Sensor model

*Added in Phase 2. See the Phase 2 section once it is implemented.*

## 7. Rendering (observation scene)

The scene renders the simulation; it never changes it. `observation_main.gd` steps the session at 20 Hz from Godot's 60 Hz physics loop and interpolates actor positions between ticks for smooth motion.

`environment_builder.gd` builds:

- a day (sun) or night (moonlight, dark sky, no shadows) lighting setup;
- exponential fog with density clear 0.0006 / haze 0.003 / fog 0.012;
- an urban (grey) or rural (green) ground grid;
- obstacles as one MultiMesh per kind;
- the protected zone and the tower.

Actors are primitive meshes (UAV with rotors; authorised UAVs carry a green light; flapping birds; balloons) drawn at **2× nominal size**, a readability choice that is documented in `actor_visuals.gd`.
