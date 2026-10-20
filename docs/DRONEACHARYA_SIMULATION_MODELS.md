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

### Player training drone (flight mode)

This is unchanged from Stage 1 (`DRONEACHARYA_STAGE1.md`), except for one addition in Phase 6: the chase camera casts a ray from the drone to its desired position and stops 0.4 m in front of any obstacle, so it no longer passes through pillars or walls (`camera_rig.gd`; tested in `test_flight_training.gd`).

### Shared vehicle-state interface

`vehicle_state.gd` holds position, velocity, acceleration, yaw, time, `horizontal_speed()`, `heading_degrees()` and `to_dict()`. Target actors use it directly. The player's training drone keeps its own Stage 1 assisted-flight controller (`drone_controller.gd`, 60 Hz Godot physics, collisions with course obstacles). Its telemetry uses the same units and axis conventions.

## 6. Synthetic sensor model — synthetic sensor simulation

`sensor_model.gd`. These are **fictional training sensors**: their outputs are synthetic and are **not real sensor measurements or performance figures**.

**Separation from truth.** The sensor reads only `ThreatWorld.physical_snapshot()`: position, velocity, size, radar reflectivity, cooperative-ID capability and whether the object flaps its wings. It never sees profile names or truth labels. Each observation is a dictionary of measured values. The actor that produced it is written to a separate `truth_links` map (observation id → actor id, or `"clutter"`), which only evaluation, dataset labelling and replay may read. `test_sensor_and_tracker.gd` checks that no observation or track carries a truth key.

| Parameter | Radar-like sensor (default) | Camera / EO (default) |
|---|---|---|
| Range | `range_m` 1500 | `range_m` 700 × visibility (clear 1, haze 0.6, fog 0.25) × night 0.5 |
| Field of view | all-round azimuth; elevation ≤ `max_elevation_deg` 60 | azimuth sector `fov_deg` 360 (panoramic array) centred on `center_deg`; configurable down to 5° |
| Scan rate | `rate_hz` 1.0 | `rate_hz` 5.0 |
| Detection probability | `detection_prob` 0.9 × reflectivity factor (0.55–1.0) × (1 − 0.5 (r/R)²) × (1 − 0.6 s) × 0.7 through trees × 0.95 urban | `detection_prob` 0.95 × (1 − 0.6 (r/R)²) × (1 − 0.3 s) |
| Line of sight | blocked by buildings; trees reduce detection | blocked by buildings and trees |
| Measurement noise | range σ `range_noise_m` 8 m, bearing σ 0.5°, elevation σ 0.8°, all × (1 + 2 s) | bearing/elevation σ 0.15° × (1 + s); range is a coarse estimate (σ = 25 % of range) |
| Extra cues | fictional cooperative ID reply: 90 % × (1 − 0.5 s) for cooperative objects, 1 % spurious otherwise | within `id_range_m` 350 (also limited by the current camera range): apparent size (±15 %) and wing-beat cue (85 % for flapping objects, 4 % false) |
| Quality indicator | detection probability + N(0, 0.05) | 1 − r/R + N(0, 0.05) |
| Clutter | Poisson false detections, `clutter_per_min` × (1 + 2 s), random positions 200 m–range | none |

*s* = severity (0–1) of an active degradation window; *r* = target range; *R* = sensor range.

- **Delay:** every observation is delivered `delay_s` [min, max] × (1 + s) seconds after it is measured, rounded to the tick. It carries both its measurement time `t` and its delivery time `t_delivered`.
- **Random streams:** separate seeded streams for radar, camera, clutter and delay keep the output reproducible.

**Observation fields:**

- `id`, `sensor`, `t`, `t_delivered`;
- `bearing_deg`, `elevation_deg`, `range_m`, `range_sigma_m`;
- `position` (estimated from the measurements);
- `quality`, `degraded`, `id_reply`, `id_quality`, `apparent_size_m` (−1 when not available), `flap_detected`.

**Night "thermal" and day "TV" sensor views** are rendering styles only (§8). Detection is decided by the model above, not by pixels.

## 7. Tracking and association — deterministic, rule-based processing of observations

`tracker.gd` uses only delivered observations plus public sensor specifications.

| Step | Rule |
|---|---|
| Association | Per (sensor, time) batch, greedy global nearest neighbour inside a gate. **Radar:** distance to the predicted position; gate = 15 m + 3·√(σ_range² + (range·σ_bearing)²) + 6 m/s × time since the last update. **Camera:** cross-range metres (angle × range); gate = 10 m + 3·range·σ_bearing + 6 m/s × elapsed time |
| Track start | An unassociated radar observation starts a *tentative* track. The camera starts tracks only if the radar is disabled |
| Filter | Alpha-beta. The first updates use growing-memory gains α = 2(2n−1)/(n(n+1)), β = 6/(n(n+1)) (least-squares line fit), settling to radar α 0.4 / β 0.1 and camera α 0.5 / β 0.02 |
| Fusion | The camera corrects direction only, keeping the predicted range (its range is coarse). While a track has a camera update less than 1 s old, radar corrects **range only**, along the line of sight. Camera updates closer than 50 m are not applied to motion |
| Late observations | Observations older than the track's last update add to its attributes (counts, cues) but not to its motion |
| Lifecycle | tentative → **confirmed** (3 hits within 6 s; otherwise *dropped*) → **coasting** (no update for 2.5 s; the position shown is extrapolated and labelled as such) → **lost** (no update for 8 s; retired and kept for review). A coasting track that is updated again is *reacquired* with the same ID |
| History | Up to 240 filtered states per track, plus counts: radar and camera hits, ID replies, identification-quality hits, size estimates, wing beats, quality and degraded hits |
| Swarm summary | Confirmed tracks are linked when closer than 80 m with horizontal velocity within 6 m/s (single-link). Components of 3+ tracks form a swarm group (`S01`, …) whose ID persists through membership overlap. Individual tracks are kept; the group is a summary for assessment |

Known limitations:

- Greedy association can swap closely spaced targets.
- Swarms flying closer together than the radar can resolve (about 2σ cross-range) appear as fewer tracks.
- The filter is not a Kalman filter: it has no covariance and no manoeuvre model.

Each limitation is visible in testing and is documented rather than hidden.

## 8. Rendering (observation scene)

The scene renders the simulation; it never changes it. `observation_main.gd` steps the session at 20 Hz from Godot's 60 Hz physics loop and interpolates actor positions between ticks for smooth motion.

`environment_builder.gd` builds:

- a day (sun) or night (moonlight, dark sky, no shadows) lighting setup;
- exponential fog with density clear 0.0006 / haze 0.003 / fog 0.012;
- an urban (grey) or rural (green) ground grid;
- obstacles as one MultiMesh per kind;
- the protected zone and the tower.

Actors are primitive meshes (UAV with rotors; authorised UAVs carry a green light; flapping birds; balloons) drawn at **2× nominal size**, a readability choice that is documented in `actor_visuals.gd`.

### Sensor view and track display (trainee-facing)

- **`V`** toggles between the eye view (70°–20° field of view) and the simulated sensor camera (30°–2°).
  - By day the sensor view is a monochrome "TV" style.
  - At night it is a "thermal" style, in which actor meshes are drawn as bright, unshaded heat signatures (balloons dimmer).
  - Both are visual aids only.
- **Track markers** (`track_overlay.gd`) are drawn at the **tracker's estimated position**, never at the ground-truth position:
  - grey square: tentative;
  - green brackets: confirmed;
  - amber dashed brackets: coasting, with "no update N s";
  - yellow: selected.
  - Swarm members show brackets only, plus one group label at the group centroid.
- **The HUD** (`observation_hud.gd`) shows:
  - radar status, including "DEGRADED" during degradation windows;
  - the current camera range;
  - track counts, recent delivery delay and the view;
  - a sortable track table and selected-track details.

  It reads only tracker and sensor-status data. A test checks that the HUD text contains no actor IDs or profile names.
