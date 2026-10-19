# DroneAcharya — Test Plan

Labels: **[VERIFIED]** = already executed during the Phase 1 audit; everything else is planned.

## 1. Principles

- A feature is "working" only after an automated test passes **or** a recorded manual check passes. "It compiles" does not count.
- Failing tests are investigated and reported. They are never deleted or skipped silently.
- Tests use no third-party test addons. Godot uses a custom headless runner and VIGIL keeps its existing Vitest and Playwright.
- The evaluator is tested against **shared golden fixtures** that both implementations must satisfy.

## 2. Environment verification (run before Stage 0)

What each command does is explained beside it. Run them in PowerShell from `E:\Hardik\Programming\DroneAcharya`.

| # | Command | Purpose | Expected |
|---|---|---|---|
| E1 | `.\Godot_v4.7.2-stable_win64_console.exe --version` | Prints the Godot version, then exits | `4.7.2.stable.official.ed1daf0bf` [VERIFIED] |
| E2 | `git --version` | Confirms Git is installed | `git version 2.52.0.windows.1` [VERIFIED] |
| E3 | `node --version` | Confirms Node for VIGIL | `v24.14.1` [VERIFIED] |
| E4 | `.\Godot_v4.7.2-stable_win64.exe` | Opens the Project Manager window. Close it again | Window opens. The renderer appears in the editor's top-right corner later (Forward+) |
| E5 | `code --list-extensions \| Select-String godot` | Shows whether the godot-tools VS Code extension is installed | Optional |

## 3. VIGIL regression baseline [VERIFIED 2026-10-20, on a scratch copy]

| Suite | Command (inside a VIGIL working copy) | Baseline result |
|---|---|---|
| Unit / integration | `npm ci` then `npx vitest run` | **369/369 passed**, 22 files |
| Build | `npm run build` | Passed; output hashes identical to shipped `dist/` |
| Audit | `npm audit --audit-level=moderate` | 0 vulnerabilities |
| Launcher | `npm run test:launcher` | **0/9 on Windows.** `EPERM` on `fs.symlink` in the `before` hook (Developer Mode off). 9/9 with the symlink line removed in a scratch copy |
| Browser e2e | `npx playwright install chromium`, then `npm run test:e2e` | **Not run** (no browser installed). README claims 111/111 |

Rule: from Stage 10 onward, every VIGIL change must keep 369/369 (plus new tests) and a clean build.

Note: `npm ci` creates `VIGIL\node_modules`. It is git-ignored and does not change source, but it was avoided during the audit because the audit made no changes.

## 4. Godot automated tests

Runner command (from the workspace root):

```
.\Godot_v4.7.2-stable_win64_console.exe --headless --path simulator --script res://tests/run_tests.gd
```

- `--headless` runs without a window or GPU.
- `--path` selects the project.
- `--script` runs the runner, which exits with code 0 if all tests pass and 1 otherwise.

Headless mode uses a dummy renderer, so these tests cover **logic**, not visuals.

| Area | Stage | Tests |
|---|---|---|
| Smoke | 0 | Runner works; required input actions exist |
| Terrain | 1 | Same seed → same height checksum; different seed differs; mesh height == collision height at sample points; heights within bounds |
| Controller | 2 | Input → velocity mapping; pitch clamp ±85° |
| Scenario loader | 3 | Valid file loads; rejects wrong `format`/`formatVersion`, missing fields, non-increasing waypoints, unknown category |
| Object path | 3 | Position at tick t is deterministic; endpoints exact |
| State machine | 5 | Legal/illegal transitions; no tick advance while paused; completion exactly at `durationTicks`; no events after finish |
| Event log | 5 | Contiguous `order`; unique IDs; non-decreasing ticks; intervals alternate true/false |
| Probe | 5 | Observable/in-view toggles for mocked range/LOS/angle inputs; 10 Hz sampling |
| Actions | 6 | Mark validity geometry; chain mark → classify → report; one report per object; summary 12–500 chars |
| Evaluator | 7 | Every golden fixture matches `expected.json` to 0.1; determinism; each penalty P1–P4 isolated; E0; aborted ⇒ not comparable |
| Session file | 8 | Write → read → validate round-trip; tampered score rejected; truncated JSON rejected; size < 2 MiB for 300 s |
| Play-through | 9 | Scripted bot completes `ridge_watch_01` headless; resulting file validates; score equals expected |

### Golden fixtures (`shared/fixtures/`)

| Fixture | Purpose | Key expectations |
|---|---|---|
| `01_perfect` | Mark within grace, correct strong classification, timely correct report | Score 100, no findings |
| `02_late_detection` | Mark at 20 s after T_obs | D1 credit = (30−20)/25 = 0.4 |
| `03_unknown_weak` | `unknown` with dwell < 3 s | C1 = 0.75, U1 = 1, Q1 expected `observe` |
| `04_overconfident_wrong` | Wrong category at 90 % with weak evidence | C1 = 0, U1 = 0.25, P1 −4 |
| `05_unjustified_escalation` | `escalate` on a routine object | Q1 = 0, P2 −8 |
| `06_missed_significant` | `review` object observed, never reported | R1 = 0, P3 −5 |
| `07_never_observable` | Object never in LOS | E0, `comparable=false` |
| `08_aborted` | Ended at 40 s | status `aborted`, `comparable=false` |
| `09_mark_spam` | 8 invalid marks | P4 −5 (capped) |

Expected values are computed by hand from `shared/RUBRIC.md` and documented in each `expected.json` with the arithmetic shown. From Stage 10, VIGIL's Vitest loads the same files.

## 5. Manual QA checklist (milestone 1, executed at Stage 9)

Record pass/fail, FPS and notes in `docs/DRONEACHARYA_MANUAL_QA.md`.

1. Launch the exported `.exe`. The title and the "Synthetic training only" notice are visible.
2. The briefing shows the scenario name, duration and controls. Start works.
3. Walk 30 s over mixed slopes: no falling through terrain and no jitter.
4. Mouse look is smooth, pitch is clamped, and `Esc` releases the mouse and opens pause.
5. Press `V`: the sensor view appears with its overlay. Zoom with the wheel. Press `V` again to return.
6. Find the object and mark it with `F`. The HUD confirms the mark, and a mark on empty sky is reported as a miss.
7. Classify with `C`, then report with `R`, using a summary of at least 12 characters. A shorter summary is refused with a message.
8. The fog thickens at the scripted time, so the scenario event is visible.
9. Let the scenario complete. The results screen shows the score, components and findings, and the numbers agree with the rubric by hand.
10. Open the session folder. The file exists and opens as readable JSON.
11. Replay and end early through the pause menu. Results show "aborted / not comparable".
12. FPS: record minimum and typical values at 1600×900 and 1920×1080 in both views. Targets: ≥ 60 and ≥ 45 FPS respectively.

## 6. Performance tests

- From Stage 1, an FPS overlay is available (`F3`).
- The scripted benchmark (Stage 9, optional) flies the camera along a fixed path for 30 s and logs average, 1 % low and draw calls through `Performance.get_monitor`.
- Budget: ≥ 60 FPS at 1600×900 on the Intel Arc iGPU. A regression above 10 % between stages must be explained before continuing.

## 7. Cross-implementation conformance (Stage 10+)

- `VIGIL/src/droneacharya/evaluate.test.ts` iterates over `shared/fixtures/*.session.json` and asserts equality with `*.expected.json`.
- A session exported by the game in Stage 9 is imported into the dashboard: the score shown must be equal, and a copy edited by hand to change the score must be rejected.

## 8. Not tested / known limits

- Authenticity of session files: consistency checks only, as in VIGIL.
- Visual correctness is checked manually only; there are no screenshot-diff tests in milestone 1.
- Hardware other than this laptop.
- VIGIL's browser e2e suite until Playwright Chromium is installed.
