# DroneAcharya — Live demo runbook

For demonstrating the prototype to evaluators on the development PC (Windows 11). Everything below uses features that exist in the current build; nothing here needs a network connection.

Paths in this file: **repo** = `E:\Hardik\Programming\DroneAcharya`, **data** = `%APPDATA%\DroneAcharya` (settings, reports, logs).

---

## A. Pre-demo checklist (about 10 minutes, the day before and again 30 minutes before)

### A1. Launch command

Open PowerShell in the repo folder and run:

```powershell
cd E:\Hardik\Programming\DroneAcharya
.\Godot_v4.7.2-stable_win64.exe --path simulator --resolution 1600x900
```

- The two Godot 4.7.2 binaries must be in the repo folder (see README "Requirements"). They are git-ignored, so a fresh clone does not have them.
- **On a 1366×768 laptop or projector**, use `--resolution 1366x768`, or `--fullscreen` for full screen at the display's resolution. The UI scales (`canvas_items` stretch) and was checked at 1366×768.
- For a console window that shows errors live, launch `.\Godot_v4.7.2-stable_win64_console.exe` with the same arguments instead.
- **Close the Godot editor / project manager before the demo.** It is the same executable, so a forced quit (section C5) could hit the wrong window.

### A2. Display

- Windows display scaling 100 % or 125 % (Settings → System → Display). Above 125 %, check that the decision card and the contacts list do not overlap (smoke test step 13).
- If you use a projector, set it to **Duplicate** before launching. Moving the window between screens while a 3D scene runs is untested.
- Disable notifications (Focus assist / Do not disturb) so pop-ups do not steal keyboard focus.

### A3. Audio

1. Main menu → **Settings**: Master 80 %, Effects 80 %, Ambience 60 % (defaults), **Mute off**.
2. Click any menu button: you should hear a short click. In a flight mission you hear the rotor hum rise when you climb.
3. If the room has no speakers, mute in Settings. Every alarm sound also has a visual sign (INCOMING banner, TIME LOW banner, red flash, confirmation text), so the demo works muted.

### A4. Model availability

Main menu → **Settings**, right column "Decision support models":

- Expected: "Model 2 — **trained ML classifier** track-classifier-v1: random forest with 40 trees, loaded from res://models/track_classifier_v1.json. Runs locally and offline", plus the held-out evaluation lines (test accuracy 0.889).
- The checkbox "Use the trained ML classifier…" must be **ticked**. It is not saved between launches and is on by default.
- If it says **NOT LOADED (reason)**, the model file is missing or damaged. Restore it with `git checkout -- simulator/models`. Decision support then shows "ML classifier unavailable … using the rule-based baseline", which is the documented fallback. Say so if it happens live.

### A5. Network independence

- Turn Wi-Fi off (or unplug the cable) and launch. The app has no network code. The only operating-system call is History → "Open folder" (local Explorer).
- Verified on 2026-10-20: launch, relaunch and the full test suite run with no network access in the code paths.

### A6. Training history and demo data (never delete existing reports)

- The History screen lists every saved report, newest first. After an exercise, the new report is selected automatically, so **a clean history is not needed**.
- If you want a clean demo state anyway, use this reversible procedure (nothing is deleted). Do it with the app closed:
  1. Rename `%APPDATA%\DroneAcharya` to `%APPDATA%\DroneAcharya.pre-demo`.
     PowerShell: `Rename-Item "$env:APPDATA\DroneAcharya" DroneAcharya.pre-demo`
  2. Launch. The app creates a fresh `DroneAcharya` folder with default settings. **The tutorial will open again on the first Threat Detection visit** (useful for the demo).
  3. After the demo, close the app and swap back. To keep the demo folder, run `Rename-Item "$env:APPDATA\DroneAcharya" DroneAcharya.demo-<date>`, then `Rename-Item "$env:APPDATA\DroneAcharya.pre-demo" DroneAcharya`.
- `%APPDATA%\DroneAcharya\exports\` holds about 24 files named `droneacharya-session-da-26247-*.json`. They were written by test runs before 2026-10-20 (now fixed). They are harmless and not shown anywhere in the app; delete them yourself if you want.
- **Do not run the test suite in the 30 minutes before the demo.** It takes about 5 minutes, and its log files rotate out the app's logs (Godot keeps five).

### A7. Rehearsal state

- Tutorial already done? With your current settings (`tutorial_done=true`), Threat Detection goes straight to the briefing. To show the tutorial, use the main-menu link **Threat detection tutorial**. It does not depend on that setting.
- Flight briefing remembers the last mission and drone (currently `village_hostile`). Pick **City delivery** + **Recon** during the rehearsal so the briefing opens on it.

### A8. If a scene fails or the app must restart

See section C. Short version: **Esc → Back to menu / Exit to menu**. If that does not respond, close the window (Alt+F4) and relaunch with the A1 command (about 2 s to the menu).

---

## B. Demonstration sequence (about 6–7 minutes)

| # | Time | Show | Say (facts only) |
|---|---|---|---|
| 1 | 0:00–0:40 | **Main menu** | DroneAcharya is a desktop training prototype with two separate modes: flight training and threat-detection (counter-drone) training. Everything is synthetic: fictional places, contacts, sensors and procedural responses. It runs offline in Godot 4.7.2. |
| 2 | 0:40–1:20 | **Flight Training** → briefing: select **City delivery** and **Recon**; point at the other profiles | Three drone profiles with different speed, climb and endurance (Scout 12 m/s / 5 min, Recon 8 m/s / 10 min, Heavy utility 5.5 m/s / 15 min). The briefing gives the objective, the 4:00 time limit (the clock starts at takeoff), the battery and the hazards. Village and hostile-area variants exist. |
| 3 | 1:20–2:40 | **Start mission**. Hold **Space** to take off, **W** forward, **Q/E** turn, **V** onboard camera. Fly through ring 1 | Mission clock and time limit (top left), telemetry with battery and integrity (bottom), radar (bottom right): heading-up, range-limited, with noise and dropouts. It shows the next ring and the landing zone, plus friendly (○ F) and unknown (□ U) traffic, each with its own shape and letter. Rings must be flown in order, then a held landing. Then **Esc** → show the pause menu (Controls, Settings) → **Back to menu**. |
| 4 | 2:40–3:10 | **Threat Detection Training** → briefing (scenario "Ridge outpost: single contact (day)", 2 min) | The briefing explains the task and the assessment weights. Mention the interactive tutorial (main-menu link) shown on a first visit. **Start exercise.** |
| 5 | 3:10–5:00 | **Observation**: the first track appears after about 8 s ("● NEW" in the status card, with a radar symbol). Up to five tracks can show at once even in this "single contact" scenario, because the simulated sensor also produces false tracks from clutter. That is part of the training, so say so. **Left-click** it (marker, radar or row). **Mouse wheel** to "Unknown" or another category, **right-click** to confirm. Then wheel to **Request identification**, right-click. Open **Contact details** and **Decision support** on the right | The radar shows tracker output, not ground truth. The decision card works on the selected contact only. Wheel to choose, right-click on the scene to confirm; alarms (notify supervisor, area alert) need one more confirmation. Decision support shows the rule-based baseline and the ML classifier side by side, each labelled, with the recommended procedural response and its reason. Then let the clock run out (2:00 in total). |
| 6 | 5:00–5:50 | **Exercise ended** → **Open the after-action report** | The report is built only from the saved session: result, what went well, what to improve, the timeline of your actual decisions with times, next practice. **Show details** gives the full rubric (da-rubric-1). **Verify replay** re-simulates the seed with the recorded actions and reproduces the score. Point at a flight report in the same list. |
| 7 | 5:50–6:30 | **Back to menu** → **Settings** (right column) | Model 1: hand-written rules. Model 2: a random forest (40 trees) trained in scikit-learn on synthetic simulator data and run in GDScript; inputs are 27 tracker features (features-1), never ground truth. Model 3: a rule-based response policy. Held-out test accuracy 0.889 vs 0.565 for the rules, and 0.757 vs 0.302 on degraded-sensor scenarios (unseen scenario seeds). |
| 8 | 6:30–7:00 | Main menu | **Implemented:** both modes, three drone profiles, city/village/course worlds, synthetic radar and hazards, threat sensors and tracker, mouse decision workflow, rule + ML decision support, scoring, reports, deterministic replay, export/import, offline. **Prototype limits:** see below. |

**Limitations to state honestly**

- All data is synthetic. ML accuracy describes the simulator's own fictional behaviour profiles, **not** real-world recognition.
- ML scores are not calibrated probabilities (calibration error about 0.13). The policy uses fixed thresholds.
- The flight model is an assisted "position-hold" approximation, not aerodynamics. Hazards are simplified and non-graphic.
- Responses are procedural training steps only. There is no operational capability.
- One machine, Windows only, run from the Godot editor binary (no exported installer yet: export templates are not installed).

**Keep the path short.** Do not open the scenario editor, import or export during the demo, and do not use **R** (it restarts immediately, with no confirmation).

**Backup if the threat contact is slow or unclear:** press **Tab** to select the next contact, then use **↑/↓**, **Enter** and **Backspace** (the keyboard fallback). Choose **Unknown** at low confidence if unsure. The report then shows partial credit, which is a good talking point.

---

## C. Recovery plan

| Situation | Do this |
|---|---|
| C1. Restart the current flight mission | **Esc → Restart mission**, or **R**. The drone goes back to the pad and the clock, battery and integrity reset. |
| C2. Restart the threat exercise | **Esc → Restart exercise**, or **R**. The same seed starts again from 0:00. The interrupted run is **not** saved. |
| C3. Return to the main menu | Flight: **Esc → Back to menu**. Threat: **Esc → Exit to menu** (the running exercise is aborted and not saved). Briefings and History have **Back to menu** / **Main menu** buttons. |
| C4. Keys or mouse stop responding | 1. Click once inside the game window (focus may have moved to another window). 2. If the view keeps turning or the drone keeps moving, press and release the key involved (W/A/S/D/Q/E/Space/C); a key released while another window had focus can stay "held". 3. If a right-drag left the view spinning, press and release the right mouse button over the scene. The app never captures or hides the mouse pointer. 4. If a menu is open, use **Esc** to close it. |
| C5. The scene freezes | Wait 5 s (the 30-contact stress scenario can hitch briefly; the demo scenarios do not). Then **Alt+F4** on the game window and relaunch with A1. If the window does not close, open Task Manager and end the **Godot_v4.7.2-stable_win64.exe** process whose window title is "DroneAcharya Simulator" (not the editor), then relaunch. Saved reports and settings are kept. |
| C6. Switch to the other training mode | Back to menu (C3), then pick **Flight Training** or **Threat Detection Training**. No restart is needed; each scene is freed when you leave it. |
| C7. Model shows NOT LOADED | Continue: decision support uses the rule-based baseline and says so. Afterwards run `git status simulator/models` and `git checkout -- simulator/models`. |
| C8. Logs after a failure | `%APPDATA%\DroneAcharya\logs\godot.log` is the current or most recent run; older runs are `godot<date>T<time>.log` (five kept). **Copy the log before relaunching more than four times or running tests.** Look for `SCRIPT ERROR` or `ERROR:` lines. For live output, launch with the `_console.exe` binary. |

---

## D. Evidence (screenshots)

Captured on 2026-10-20 in a real 1600×900 application window with the project's own tool, `simulator/tests/tools/capture_ui.gd`. It drives the real scenes by script: it presses the real input actions and steps the real session, then saves the window image. No image is a mock-up. Files are in `docs/demo_evidence/` (untracked; see section 9 of `DEMO_AUDIT.md`).

| Screen | File |
|---|---|
| Main menu | `menu.png` |
| Flight briefing | `flight_briefing.png` |
| City flight HUD and radar (chase view) | `city_chase.png` |
| Village environment | `village_chase.png`, `village_overview.png` |
| Hostile area: radar and INCOMING warning | `hostile_incoming.png` |
| Threat observation with radar (swarm scenario) | `observation.png` |
| Decision card with alarm confirmation | `observation_alarm.png` |
| Final report (threat exercise) | `report_threat.png` |
| 1366×768 checks | `*_1366x768.png` |

To recapture (about 1 minute):

```powershell
.\Godot_v4.7.2-stable_win64_console.exe --audio-driver Dummy --path simulator --script res://tests/tools/capture_ui.gd -- --out=E:/Hardik/Programming/DroneAcharya/docs/demo_evidence --shots=menu,flight_briefing,city,village,hostile,observation,observation_alarm,report_threat
```

---

## E. Manual smoke test (10–15 minutes, the day before the demo)

### E1. Already automated (no need to repeat by hand)

`.\Godot_v4.7.2-stable_win64_console.exe --headless --path simulator --script res://tests/run_tests.gd` checks all of these (170 tests, about 5 minutes):

- main menu and every screen load; menus open each mode;
- pause, resume, restart and back-to-menu, with scenes released;
- profile switching and reset; time-limit, battery, integrity and crash failures; flight records saved and reported;
- city/village/course build, determinism and autopilot completion of each;
- radar contacts appear, go stale, drop and reacquire; radar shows sensor output only;
- tutorial, wheel/right-click/right-drag routing, alarm confirmation, double-submission guard, keyboard fallback;
- swarm group decisions; card keeps a pending decision when a contact joins a group;
- reports built from saved data and identical after reload; malformed records refused;
- audio cues, mute (game still runs), no sound after a scene change; saved mute applied at startup;
- ML model load, validation, fallback and parity with Python.

### E2. You must check by hand

Tick each one. Times are approximate.

| # | Check | Pass when |
|---|---|---|
| 1 | Launch with A1; close with the menu's **Exit**; launch again (1 min) | Menu appears within about 3 s both times; no error window |
| 2 | **Flight Training** → briefing → **Back to menu**; **Threat Detection Training** → briefing → **Main menu** (1 min) | Both modes open and return |
| 3 | Flight, **Basic course**, **Scout**: take off (Space), fly a few seconds, **Esc** (paused, clock stopped), **Resume**, **Esc → Restart mission**, **Esc → Back to menu** (2 min) | Clock stops while paused; restart puts the drone back on the pad with the clock at 0 |
| 4 | Fly **Recon** and **Heavy utility** briefly (Basic course) (1 min) | Recon slower than Scout; Heavy slowest, with a bigger body; motor sound rises in flight |
| 5 | **City delivery** (any profile): take off; watch the radar (1 min) | Buildings and streets render; radar shows ○/□ traffic symbols that appear and disappear as they move in and out of range |
| 6 | **Village supply run**: take off, fly to ring 1 (1 min) | Village, fields and power lines render; ring 1 passes with a message and sound |
| 7 | Finish or fail a flight: easiest is to fly straight out of the training area, or hit a wall hard on the Basic course (1 min) | "Mission failed" screen with the cause; **Open report** shows the same cause, time and ring count |
| 8 | Threat exercise, scenario 01: select the contact with a **left-click**; **mouse wheel** changes the highlighted category; **right-click on the scene** confirms; then a response by wheel + right-click (2 min) | Card advances Classify → Respond → ✓ final; Contacts list "Your call" updates |
| 9 | In the same exercise: right-**drag** on the scene | View turns and nothing is confirmed |
| 10 | Keyboard fallback: **Esc → Restart exercise**; then **Tab**, **↓**, **3**, **Enter**, **Backspace** (1 min) | Tab selects; ↓ moves the highlight; 3 sets High; Enter classifies; Backspace goes back a step |
| 11 | Let the exercise run to 0:00 → **Open the after-action report** (2 min) | Report time, contact name and your decisions (category, confidence, response) match what you did |
| 12 | **Settings → Mute**; open a flight mission; then unmute (1 min) | Silent while muted; everything else works; sound returns |
| 13 | Relaunch with `--resolution 1366x768` and open the flight HUD, the observation screen and History (1 min) | No text cut off or overlapping; decision card and contacts list both readable |
| 14 | Repeat the step 8 exercise once more without relaunching (2 min) | Starts at 0:00 with no contact preselected and an empty card; the new report appears at the top of History |
| 15 | After the checks, open `%APPDATA%\DroneAcharya\logs\godot.log` | No `SCRIPT ERROR` or `ERROR:` lines |

If anything fails, note the step and copy `godot.log` before relaunching (C8).
