# DroneAcharya — Missions, drones, environments and scenarios

Everything here is fictional and synthetic: places, traffic, hazards and sensors. Hazards are simplified game mechanics. They do not model any real weapon, guidance or countermeasure.

## 1. Flight training

### 1.1 Drone profiles (`simulator/scripts/flight/drone_profiles.gd`)

All profiles drive the same assisted flight controller (`drone_controller.gd`); only these numbers change.

| | Scout | **Recon** (default) | Heavy utility |
|---|---|---|---|
| Top horizontal speed | 12 m/s | 8 m/s | 5.5 m/s |
| Acceleration / braking | 10 / 12 m/s² | 6 / 8 m/s² | 3 / 3.5 m/s² |
| Climb / descent | 5 / 4 m/s | 4 / 3 m/s | 2.5 / 2 m/s |
| Vertical acceleration | 9 m/s² | 6 m/s² | 3 m/s² |
| Turn rate | 130 °/s | 90 °/s | 55 °/s |
| Crash speed (into an obstacle) | 3.0 m/s | 3.5 m/s | 4.5 m/s |
| Chase camera distance / height / smoothing | 5.5 m / 2.4 m / 7 | 7 m / 3 m / 5 | 9.5 m / 4 m / 3.5 |
| Battery endurance (level flight) | 5:00 | 10:00 | 15:00 |
| Model scale | 0.8× | 1.0× | 1.35× |

- **Recon:** keeps the original Stage 1 tuning exactly. Tests check every value.
- **Battery:** drains only while airborne, 1.5× faster while climbing.
- **Collision box:** the same for every profile, so all of them fit every course.

### 1.2 Missions (`simulator/scripts/flight/flight_missions.gd`)

| Mission | Environment | Time limit | Rings | Other traffic | Hazards |
|---|---|---|---|---|---|
| Basic course | Hand-built training course (Stage 1) | 3:00 | 4 | — | Pillars, walls, crates |
| City delivery | City | 4:00 | 5 | Friendly patrols, unknown transits | Buildings, streetlights, sign gantry, rooftop tanks, tower crane |
| Village supply run | Village | 4:00 | 5 | Friendly patrols, unknown transits | Power lines (~9 m), water tower, trees, camp watchtower |
| City transit — hostile area | City | 5:00 | 5 | As above | + 3 emplacement sites, 1 hostile drone |
| Village transit — hostile area | Village | 5:00 | 5 | As above | + 3 emplacement sites, 1 hostile drone |

**Objective (all missions):** fly through the rings in number order, then land in the green zone and hold still for 1 s.

**Failure** happens on any of:

- hitting an obstacle at or above the profile's crash speed;
- leaving the training area;
- reaching the time limit;
- an empty battery;
- integrity reaching 0 % (hostile missions).

**Clock policy:**

- **Start:** at takeoff (above 0.5 m). The briefing screen never counts.
- **Pause:** frozen while paused.
- **Stop:** when the mission ends.
- **Warning:** at 30 s left, as a TIME LOW banner, an amber clock and a sound.
- **Battery:** warns at 20 %.

**Result:** the end of every mission saves a flight record. "Open report" shows the plain-language report (`docs/SESSION_AND_REPORTS.md`).

### 1.3 Environments (`simulator/scripts/world/`)

All geometry is procedural, low-poly, built from Godot primitives at load time:

- one MultiMesh per prop type (one draw call each);
- a world-space window shader for building facades.

The build is deterministic for the mission seed.

**City** (`city_builder.gd`):

- **Street grid:** uneven block sizes; a 20 m main avenue with a planted median and a 20 m main street; 14 m side streets with dashed lane markings, zebra crossings and corner signs.
- **Buildings:** blocks are split into lots of different sizes. Buildings vary in height (taller towards the centre), colour, parapet, rooftop water tanks, AC units, stair houses and occasional billboards.
- **Street furniture:** streetlights on both sides; parked cars along the kerbs.
- **Special blocks:**
  - depot yard: containers, sheds, fence, launch pad;
  - park: paths, pond, trees, benches;
  - walled compound with a boom gate;
  - construction site: fence, half-built frame, tower crane;
  - plaza: fountain, planters, landing pad.
- **Overhead hazard:** a sign gantry over one avenue.

**Village** (`village_builder.gd`), deliberately not a recoloured city:

- **Roads:** a winding dirt main road and footpaths.
- **Houses:**
  - pitched-roof houses;
  - flat-roof concrete houses with roof tanks and stair houses;
  - round thatched huts;
  - many plots inside low boundary walls.
- **Fields:** crop fields with rows and earth bunds; an orchard; a pond with a muddy bank.
- **Vegetation:** shade trees, tall narrow trees and bushes.
- **Power line:** utility poles along the main road with three sagging wires.
- **Landmarks:** a water-tank tower; a farmyard with a shed, haystacks and a cattle shelter.
- **Camp (landing site):** fence, gate with sandbags, tents, watchtower, flagpole, trucks and helipad.

**Collision** is limited to things a drone can realistically hit, in named obstacle bodies that appear in crash messages:

- buildings, walls, fences;
- poles, wires;
- trees, tanks;
- the crane, tents and similar.

Road markings, fields, bushes and ground decals have no collision.

**Every mission route stays flyable:** `route_corridor.gd` refuses any prop that would block a route segment. A test shape-casts a drone-sized box along every segment, and the test autopilot completes both missions.

### 1.4 Radar and simulated hazards

**Synthetic radar** (`flight_sensor.gd`). It is the only source of radar contacts. The radar display never reads ground-truth positions.

| Setting | Value |
|---|---|
| Range | 160 m (projectiles 140 m) |
| Update interval | 0.5 s |
| Probability of detection | 97 % close, falling linearly to 60 % at the range limit (contacts drop out at long range) |
| Position noise | seeded Gaussian, σ = 1 m + 1.2 % of range |
| Persistence | a contact not detected for 1.6 s is drawn hollow with "?" at its last measured position, and removed after 4 s |
| Contact ids | the sensor's own (C01, C02, …) |

The sensor associates each detection with the right contact (ideal association; a training simplification).

**Classification** uses observable cues only:

| Cue | Result |
|---|---|
| Cooperative ID reply (95 % reply rate) | Friendly ○ F |
| Measured speed above 16 m/s | Projectile ▲ P |
| Closing on you within 110 m for about 3 updates | Hostile ◆ H (behaviour-based: a harmless drone heading straight at you can be marked hostile too) |
| Anything else | Unknown □ U |

**Radar display** (`radar_display.gd`):

- heading-up;
- rings at half and full range;
- destination ⊕ LZ, pinned to the rim when out of range;
- next ring ● with its number;
- briefed threat areas as dashed circles (mission information, not sensor detections);
- a Legend button.

**Traffic and hazards** (`flight_traffic.gd`, seeded, stepped at the physics rate):

- **Friendly patrol drones:** 2, circling at 28–40 m, with an ID reply.
- **Unknown drones:** cross the area every 25–40 s at 30–50 m.
- **Emplacement sites (hostile missions only):**
  - launch a projectile when you are within 120 m and in line of sight, then wait 6–9 s;
  - the projectile flies straight at 22 m/s toward where your drone was at launch (no lead or guidance);
  - it stops at buildings and expires after 180 m.
- **Hostile drone (hostile missions only):**
  - patrols;
  - follows you at 4.5 m/s (slower than every profile) when you come within 90 m;
  - gives up after 25 s or when outrun, then breaks off for 10 s after contact.
- **Damage:** every hit removes 35 % integrity; the third hit fails the mission.
- **Warning:** INCOMING appears when a sensor-detected projectile's straight path will pass within 12 m in the next 4 s. It shows a banner with the side and time, an edge arrow and a sound.

**Balance check** (test autopilot that flies the route but never dodges): all six hostile mission/profile combinations completed. Heavy utility took 2 hits in the village.

## 2. Threat detection

### 2.1 Scenarios

- **Presets** in `simulator/scenarios/`: single rural day, swarm urban day, mixed rural night with degraded sensor, single urban fog.
- **Procedural:** seeded scenarios from the scenario selection screen.

The scenario format, generator, actors and sensor models are unchanged; see `DRONEACHARYA_SIMULATION_MODELS.md`.

### 2.2 Observation radar

The observation radar (bottom right) shows tracker output only:

| Symbol | Meaning |
|---|---|
| □ T | Confirmed track |
| Hollow with "?" | Coasting (no recent update; the position is extrapolated) |
| ⬡ S | Swarm group, at its centroid |
| Dashed green circle | Protected area |
| Faint lines | Your current field of view |

- **Orientation:** heading-up, so the top is where you are looking.
- **Range:** the scenario's radar range (1,500 m by default).
- **Sensor limits apply:** range, field of view, noise, dropouts, delays and degradation all come from the existing sensor model and tracker.
- **No answers given away:** tentative tracks and ground truth are never shown, and no label gives the answer away before you decide.
