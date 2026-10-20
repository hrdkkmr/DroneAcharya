# DroneAcharya — Session records and reports

## 1. Where things are stored (offline, on this computer)

| What | Path (Windows: `%APPDATA%\DroneAcharya\…`) | Format |
|---|---|---|
| Threat-detection sessions | `user://sessions/*.json` | `droneacharya-session` v1 (unchanged; see `DRONEACHARYA_SESSION_SCHEMA.md` and `schemas/`) |
| Flight-training missions | `user://flight_sessions/*.json` | `droneacharya-flight-session` v1 (new, §2) |
| Exports | `user://exports/` | Threat sessions as a `droneacharya-history` bundle; flight records as single JSON files |
| Settings | `user://settings.cfg` | Godot ConfigFile, section `settings` |

**Isolation:** tests use `user://test_runs/…` only, and never touch these files.

**Error handling:**

- Invalid files are listed on the history screen with the reason, and are never changed or deleted.
- An unreadable settings file falls back to defaults.

## 2. Flight record (`droneacharya-flight-session`, version 1)

Built by `simulator/scripts/flight/flight_record.gd` from the pure `MissionState` when a mission completes or fails.

```json
{
  "format": "droneacharya-flight-session", "format_version": 1,
  "session_id": "flight-city_delivery-…", "created_at": "2026-10-20T11:00:00Z",
  "mission": {"id": "city_delivery", "title": "City delivery", "environment": "city", "hostile": false},
  "profile": {"id": "scout", "title": "Scout"},
  "result": {
    "status": "completed | failed", "failure_reason": "", "elapsed_s": 68.3, "time_limit_s": 240,
    "checkpoints_passed": 5, "checkpoint_count": 5, "checkpoint_times": [9.1, 14.0, 27.3, 41.2, 52.0],
    "wrong_checkpoints": 0, "bumps": 0, "hits": 0, "integrity_end": 100, "battery_end": 0.83,
    "endurance_s": 300, "landed_in_zone": true,
    "threats": {"projectiles_launched": 9, "incoming_warnings": 9, "projectile_hits": 0, "hostile_drone_hits": 1},
    "radar_contacts_seen": 6
  },
  "events": [{"t": 0.0, "type": "takeoff", "data": {}}, {"t": 9.1, "type": "checkpoint", "data": {"number": 1, "of": 5}}]
}
```

**Optional fields:** `threats` and `radar_contacts_seen` appear only for missions with traffic or hazards.

**Event types:**

| Group | Types |
|---|---|
| Progress | `takeoff`, `checkpoint`, `wrong_checkpoint`, `early_landing`, `completed`, `failed` |
| Contact | `bump`, `hit` |
| Warnings | `time_warning`, `battery_warning`, `incoming_warning` |

Event times are mission-clock seconds.

**Versioning policy:**

- **Version list:** `validate()` accepts every version in `SUPPORTED_VERSIONS`.
- **Readers:** the report builder dispatches on `format` and `format_version`. A new version adds a reader instead of changing the old one, so old files keep their reports.
- **Unknown versions:** an unknown version gets a short notice, never a guessed report.

## 3. Reports (`simulator/scripts/training/report_builder.gd`)

The same five sections for both modes, built only from the saved record:

1. **Mission result:**
   - mission, environment, mode or drone profile;
   - result (and the failure cause);
   - duration;
   - final score (threat detection only; flight missions have no single score).
2. **What went well:** at most three, each tied to a number in the record.
3. **What needs improvement:** at most three concrete errors, most serious first.
4. **Important decisions:** a timeline of up to 14 rows (time · contact or event · decision · assessment · short reason).
5. **Next practice:** one to three suggestions, each following from an error that occurred.

Below the five sections, **How the result is made up** lists plain score categories. **Details** (on request) shows the full rubric output (`aar.gd`) or the flight event log.

### Threat-detection statements

They come from the `da-rubric-1` evaluation stored in the record.

**Contact outcomes are kept apart:**

| Outcome | Meaning |
|---|---|
| Correct | Category equals the truth category |
| Incorrect | A specific category that is wrong |
| Unknown | Classified as unknown |
| Unresolved | Selected but never classified |
| Missed | Never selected |
| Unnecessary alert | Alarm for a non-threat or for sensor clutter (rubric P2) |
| Delayed | Response more than 15 s after the contact was confirmed |

**Naming:** contacts are named by the tracker ids the trainee saw (T03, or T02/T06 when one object was tracked twice, or "the swarm (T03 and 4 more)"). Ground truth is revealed only in the report, after the exercise.

**Score categories:**

- noticing contacts quickly;
- identifying them;
- matching confidence to evidence;
- choosing the right response;
- responding in time;
- coping with sensor degradation;
- deductions (missed threats, unnecessary alarms, over-confident calls, repeated actions).

### Flight statements

From the flight record:

- landing time;
- rings passed (and out of order);
- minor collisions (named obstacles);
- crash or failure cause and time;
- simulated hits and remaining integrity;
- battery warnings;
- time to spare against the limit.

### Rules the builder follows (tested in `test_reports.gd`)

- **Data only:** a statement appears only when the record supports it. There is no praise without a number behind it.
- **Banned filler:** the phrases in `ReportBuilder.BANNED` (e.g. "as an AI", "leveraged", "comprehensive understanding", "performed well", "Overall,") never appear.
- **Limits:** the section limits are enforced.
- **Persistence:** a report built from a file reloaded from disk is identical to the one built when the session ended.
- **Scope of claims:** reports make no medical, intelligence or operational claims. All data is synthetic training data.
