# DroneAcharya — Phase 1 Repository Audit

Audit date: 2026-10-20
Audited tree: `E:\Hardik\Programming\DroneAcharya\VIGIL` (no files in it were modified)

Labels used throughout:

- **[VERIFIED]** — checked by reading the source or running a command during this audit.
- **[DOC-CLAIM]** — stated in VIGIL's own docs, not independently re-checked.
- **[ASSUMPTION]** — reasonable belief, not proven.
- **[RECOMMENDATION]** — proposed action.

---

## 1. Workspace and environment

| Item | Finding | Status |
|---|---|---|
| Workspace root | `E:\Hardik\Programming\DroneAcharya` contains `VIGIL\`, `Godot_v4.7.2-stable_win64.exe` (180.9 MB) and `Godot_v4.7.2-stable_win64_console.exe` | [VERIFIED] |
| Godot editor executable | `E:\Hardik\Programming\DroneAcharya\Godot_v4.7.2-stable_win64.exe` | [VERIFIED] |
| Godot console executable (for scripts/tests) | `E:\Hardik\Programming\DroneAcharya\Godot_v4.7.2-stable_win64_console.exe` → reports `4.7.2.stable.official.ed1daf0bf` | [VERIFIED] |
| Godot headless scripting | A throwaway project in the session scratchpad ran `--headless --script` and exited 0. JSON round-trip and 64-bit integer masking work | [VERIFIED] |
| Godot export templates | Not checked. They are needed only to build a standalone `.exe` (Stage 9) | [ASSUMPTION: not installed] |
| Node.js / npm | v24.14.1 / 11.11.0 | [VERIFIED] |
| Python | 3.13.7 (used only by VIGIL's `scripts/package_release.py`) | [VERIFIED] |
| Git | 2.52.0 installed | [VERIFIED] |
| Version control | **Neither the workspace nor `VIGIL\` is a Git repository.** VIGIL's docs refer to commits (e.g. `4a36bee`), so the original history exists elsewhere, not in this copy | [VERIFIED] |
| VS Code | 1.142.0 | [VERIFIED] |
| Hardware | Intel Core Ultra 5 125H, **Intel Arc integrated graphics** (driver 32.0.101.8801), 15.6 GB RAM | [VERIFIED] |
| `VIGIL\node_modules` | Absent. VIGIL ships a prebuilt `dist\` | [VERIFIED] |

**Hardware note:** this machine has an integrated GPU, not a discrete gaming GPU. The performance budget in the architecture document targets this machine as the minimum, which also keeps the game comfortable on a mid-range gaming laptop.

---

## 2. What VIGIL is

**[VERIFIED]** VIGIL is a React 19 + TypeScript 5.7 + Vite 7 single-page web app. It is a **2D, schematic** synthetic observation trainer:

- Tracks move on a **normalized 0–100 grid** (`engine/sensor.ts:83-91`), not in geographic or 3D space.
- The simulation advances in **whole simulated seconds** (`SimulationEngine.advance`, `engine/clock.ts`).
- The engine runs in a **Web Worker** (`workers/simulation.worker.ts`, `workers/runtime.ts`). The UI only receives a public view without hidden truth (`domain/publicScenario.ts`).
- The trainee works through a fixed action chain for each track: `select` → `track` → (`request_observation`) → `classify(category, confidence)` → `report(decision, summary)` (`domain/actions.ts`).
- History is stored in browser **IndexedDB** (`persistence/repository.ts`). Portable JSON backups use the format `vigil-session-export`, formatVersion 1.

Size: about 5,300 lines across 98 source/test/script files. Lines are dense, with many one-line functions.

### 2.1 Package configuration [VERIFIED]

- Runtime deps: `react`, `react-dom`, `recharts`, `lucide-react`, `zod`.
- Dev deps: `vite`, `vitest`, `@playwright/test`, `@axe-core/playwright`, `@testing-library/*`, `jsdom`, `fake-indexeddb`, `typescript ~5.7.3`.
- Scripts: `dev`, `build` (`tsc -b && vite build`), `test` (vitest), `test:e2e` (playwright), `test:launcher` (node:test), `serve:bundle`, `test:package`.
- `START-VIGIL.cmd` runs `node scripts\serve.mjs`, a zero-dependency static server on port 8787.

---

## 3. Module-by-module findings

### 3.1 Scenario generation and randomization — `engine/scenario.ts`, `engine/random.ts`, `domain/config.ts`

**[VERIFIED]**

- `mulberry32(seed)` is a deterministic PRNG. `hash32` is FNV-1a and is used to derive independent random streams. `canonicalJson` sorts keys so that output is deterministic.
- `generateScenario(config)` creates 1–8 hidden tracks. Each track has a truth `category` (`routine`, `review` or `background`), a spawn time, an origin, a velocity and a phase. `significant = (category === 'review')`.
- Three traffic patterns: `independent`, `crossing` (meet in one seeded region) and `grouped`.
- One seeded "sensor degradation" window (starting at 12–16 s and lasting 18 s).
- The config is validated with Zod: duration 60–300 s, trackCount 1–8, reliability ≥ 0.35, noise ≤ 0.3, delay 0–8 s, seed uint32, objectives, and weights that sum to 100.
- Four presets: `perimeter`, `urban-dusk`, `night-watch` and `rural-crossing`.
- `environment` is limited to `'urban' | 'rural'`; there is no desert or mountain environment. `lighting` is `day | dusk | night` and `weather` is `clear | haze | rain`.

**Reuse assessment:** the configuration *concepts* (environment, lighting, weather, difficulty, seed, objectives, weights) carry over well to the 3D scenario format. The generator itself does not, because it produces 2D grid trajectories.

### 3.2 Sensor / observation model — `engine/sensor.ts`, `domain/conditions.ts`

**[VERIFIED]** Observations are scheduled every 4 s (`TRAINING_RULES.observationIntervalSeconds`), and trainee requests add an extra capture 2 s later. Lighting, weather, urban clutter zones and degradation all affect dropout, noise, confidence, delivery delay and whether the motion or signature cues are "resolved". All formulas are explicitly fictional.

**Reuse assessment:** not reusable as code. In 3D, "observation" means the trainee actually looking at the object through a camera. The *idea* of a clear vs unresolved observation, using a confidence threshold of 60, can be carried over as "identification-quality dwell" (see the architecture document).

### 3.3 Event log and validation — `engine/log.ts`, `domain/events.ts`, `engine/evidence.ts`

**[VERIFIED]**

- Events have `{id, sessionId, order, time, type, data}`. The types are `started`, `observation`, `sensor_change`, `action`, `paused`, `resumed` and `finished`.
- `validateSessionLog` is **very strict**. It requires:
  - contiguous order and non-decreasing time;
  - no clock advance while paused, and no events after finish;
  - completion exactly at `durationSeconds`;
  - every observation's provenance to match VIGIL's **own 4-second schedule or an earlier request**, with `deliveredAt === event.time`.
- `projectEvidence` folds events into the per-track state that both the UI and the evaluator use.

**Reuse assessment:** the event-log *design* (ordered, ID-anchored, append-only, validated before scoring) is excellent and should be copied. The validator cannot accept a Godot log, because its observation rules are specific to VIGIL's sensor.

### 3.4 Assessment / scoring — `scoring/evaluate.ts`, `scoring/rubric.ts`

**[VERIFIED]** There is a single pure function, `evaluateSession(scenario, events)`, using rubric `rubric-1`:

| Component (default weight) | Rule | Per-track credit |
|---|---|---|
| Detection (20) | D1 | `windowCredit(latency, grace 5 s, window 30 s)`, where latency = first `track` action − first delivered observation |
| Classification (20) | C1 | 1 if correct; 0 if wrong; `unknown` = 0.75 with weak evidence, 0.5 with strong evidence |
| Uncertainty (15) | U1 | `unknown`: 1 if weak, 0.75 if strong. Specific + weak evidence = 0.25. Specific + strong: 1 if correct, 0 if wrong |
| Reporting (20) | R1 | `0.4 + 0.6 × windowCredit(reportLatency, 15 s, 60 s)` if a report exists, else 0 |
| Decision (15) | Q1 | 1 if it matches the expected branch of the decision tree, 0.5 for `observe`, else 0 |
| Objectives (10) | O1 | fraction of selected skills whose average is ≥ 70 % |
| Penalties | P1 −4 | specific classification at > 70 % confidence with < 2 clear observations |
| | P2 −8 | escalation not supported by the tree |
| | P3 −5 | significant track observed but never reported |

- `windowCredit(l, g, d) = clamp((d − l)/(d − g), 0, 1)`.
- Expected decision tree: no classification, `unknown`, or fewer than 2 clear observations → `observe`; else `review` → `escalate`; else `log`.
- Final score = `clamp(Σ weighted − penalties, 0, 100)`. Every finding cites event IDs, and a result is `comparable` only if the session completed and at least one track was observed.

**Reuse assessment: high conceptual reuse, low direct code reuse.**
- The rubric's structure, formulas, decision tree and "every point is explained with an event anchor" principle map directly onto a 3D exercise. The architecture document defines `da-rubric-1` as a deliberate adaptation of `rubric-1`.
- `evaluateSession` cannot be called on Godot data, because it first runs `validateSessionLog`, which enforces VIGIL's sensor provenance (§3.3).

### 3.5 Session history and persistence — `persistence/*`

**[VERIFIED]**

- IndexedDB database `vigil-training-history` v1, with stores `profiles`, `sessions` and `meta`.
- On load and import, `validateStoredRecord` (`persistence/validation.ts:192`) requires all of the following:
  - The record must already be canonical JSON.
  - `scenario` must **deep-equal `generateScenario(scenario.config)`**, regenerated by VIGIL's generator-2.
  - `evaluation` must **deep-equal `evaluateSession(...)`**, recomputed.
  - The replay must build.
- Invalid entries are quarantined and never overwritten. Imports are immutable merges in which a same-ID conflict is an error. Limits: 20 MiB per file, 500 profiles, 500 sessions, 2 MiB per record, 5,000 events.

**Consequence for DroneAcharya [VERIFIED by reading]:** a session produced by Godot **cannot** be imported as a VIGIL `SessionRecord`. This would only work if Godot reproduced generator-2/sensor-2 floating-point arithmetic bit for bit and simulated a 2D grid world, which defeats the purpose. **A new, separate session format is required** (`droneacharya-session` v1).

**Reusable:** the validation *policy* (strict schema, no silent repair, recompute-and-compare, quarantine instead of delete, immutable merge, size limits) and the code patterns (`mergeImmutable`, `sameData`, `canonicalJson`, `errorMessage`).

### 3.6 Replay — `replay/replay.ts`, `hooks/useRecordedReplay.ts`, `components/RecordedReplay.tsx`

**[VERIFIED]** Replay is a pure projection over an event-list prefix (`seekReplayTime`, `seekReplayEvent`, `stepReplayEvent`, `replayFrame`) and never re-runs the engine. A replay frame reconstructs the public view up to the cursor position.

**Reuse assessment:** the cursor/prefix algorithm is directly reusable for a 2D "timeline replay" of a 3D session in the dashboard, provided the session stores sampled positions (see the architecture document). Its types are bound to `SimulationEvent`/`ActiveSessionView`, so it needs a thin adapter or a parallel module.

### 3.7 Adaptation / difficulty — `adaptive/policy.ts`

**[VERIFIED]** `recommendNext(records, savedIds, profileId)` is a transparent rule-based policy (`rules-1`) and contains no ML:

- It looks at at most 5 distinct-seed completions in the latest matching context and targets the weakest skill.
- Difficulty moves ±1 only after 3 consistent, distinct, matching attempts: increase when every attempt scores ≥ 80 with every skill ≥ 75 and no penalties; decrease when every attempt scores < 55 and the weakest skill < 60.
- Otherwise difficulty holds, with explicit reasons (sparse, mixed context, repeated, inconsistent).

**Reuse assessment:** the rules port cleanly to DroneAcharya sessions once enough sessions exist. **Not needed for the first milestone.** The function reads `SessionRecord` fields directly, so it needs a small adapter interface (`score`, `componentScores`, `seed`, `context`, `status`, `comparable`, `endedAt`).

### 3.8 Analytics and export — `analytics/history.ts`, `analytics/exports.ts`

**[VERIFIED]** `summarizeHistory` produces descriptive means, ranges and trends over saved, completed, comparable records, and never imputes missing latency as zero. `compareRecords` flags differing conditions. `summaryCsv` produces formula-injection-safe CSV (`csvCell`), and `reportHtml` produces an escaped, printable after-action report.

**Reuse assessment:** `csvCell`, `escapeHtml` and the summary approach can be reused as-is. The functions themselves read `SessionRecord` and need adapters.

### 3.9 Dashboard UI — `pages/*`, `components/*`, `hooks/useWorkspace.tsx`

**[VERIFIED]** There are seven hash routes: `home`, `lab` (Scenario Lab), `console` (live trainer), `aar` (after-action review), `progress`, `unit` and `instructor`. Charts are hand-written SVG plus Recharts (`HistoricalAnalytics`). There are no placeholder pages: `FoundationPages.tsx` contains working Progress, Unit and Instructor views despite its name.

**Reuse assessment for the instructor dashboard:**
- Shell, UI primitives (`Button`, `Badge`, `PageTitle`, `EmptyState`), `ConfirmDialog`, `EventLog`, `HistoricalAnalytics` charts and `HistoryTools` (import/export UI): **reusable** with light adaptation.
- `ObservationMap`, `TrackWorkspace`, `DeliveryMonitor`, `SimulationConsole`: **VIGIL-specific**, because they belong to the 2D trainer. Keep them unchanged for VIGIL's own exercises.

### 3.10 API / data contracts

**[VERIFIED]** There is no network API, backend, database server or authentication. The only external contract is the JSON file `vigil-session-export` formatVersion 1 (schemaVersion 3). CSV and HTML are output-only formats.

---

## 4. Test execution results (this audit)

All commands were run on a **copy** of VIGIL in the session scratchpad, so VIGIL itself was not modified (no `node_modules` was created inside it).

| Check | Command | Result | Status |
|---|---|---|---|
| Install | `npm ci` | 200 packages, OK | [VERIFIED] |
| Unit/integration/component tests | `npx vitest run` | **369 passed / 369, 22 files**, 14 s. Matches README claim | [VERIFIED] |
| Strict type check + production build | `npm run build` | Passed. **Output hashes are identical to the shipped `dist/`** (`index-BiSwf0C9.js`, `simulation.worker-DUgXOd5k.js`), so the build is reproducible | [VERIFIED] |
| Dependency audit | `npm audit --audit-level=moderate` | 0 vulnerabilities | [VERIFIED] |
| Launcher tests | `npm run test:launcher` | **FAILED: 0 / 9 on this machine.** See §4.1 | [VERIFIED] |
| Launcher tests, symlink step removed (scratch copy only) | `node --test scripts/serve.nosymlink.test.mjs` | 9 / 9 passed. The symlink-escape assertion is vacuous in this run | [VERIFIED] |
| Bundle server smoke | `node scripts/serve.mjs --port 8799` + `curl` | `/` → 200 HTML; Worker → 200 `text/javascript` | [VERIFIED] |
| Browser end-to-end | `npm run test:e2e` | **Not run.** Playwright's Chromium is not installed (`%LOCALAPPDATA%\ms-playwright` absent). README claims 111/111 | [DOC-CLAIM, unverified] |
| Interactive UI behaviour | — | Not exercised in a browser during this audit | Unverified |

### 4.1 Launcher test failure — root cause

- `scripts/serve.test.mjs` line 9 (`before` hook) calls `fs.symlink(...)`.
- On Windows, creating a symlink requires **Developer Mode** or administrator rights. Developer Mode is not enabled here (the `AppModelUnlock\AllowDevelopmentWithoutDevLicense` registry value is absent).
- Node throws `EPERM: operation not permitted, symlink`. The hook fails, so all 9 tests are reported as failed.
- This is a **test-environment portability defect**, not a server defect. With only that line removed, the other assertions pass.
- VIGIL's reported 9/9 was presumably obtained on Linux; its fixtures reference an `e2b.app` host, which suggests a Linux sandbox [ASSUMPTION].
- The "never serve a symlink outside the root" protection is **unverified on Windows**.
- **[RECOMMENDATION]** Later, with approval, make the symlink fixture conditional (`it.skip` when `symlink` throws `EPERM`) or enable Developer Mode. This was not changed, as instructed.

---

## 5. Documentation claims vs implementation

| VIGIL claim | Finding |
|---|---|
| "369 tests" | **Confirmed** |
| "9 launcher checks pass" | **Not reproducible on this Windows machine** (§4.1) |
| "111 production Chromium cases" | Not checked (no browser installed) |
| Strict build, audit 0 | **Confirmed** |
| "One deterministic rubric-1 evaluator" | **Confirmed**: a single `evaluateSession`, which the engine, persistence validation and tests all reuse |
| "Hidden truth never enters the active view" | **Confirmed by code**: `publicScenario` is an explicit whitelist and `ActiveSessionView` has no truth fields. The docs themselves note that a client-only app cannot stop a determined user reading the source or seed |
| "rules-1 heuristic, not ML" | **Confirmed** |
| `docs/PROGRESS.md` header says "Stop before Phase 6"; `LIMITATIONS.md` and README say Phase 6 is accepted | **Internal inconsistency in VIGIL's docs.** The code contains Phase 6 (adaptive policy and its tests), so the PROGRESS header is stale |
| "Official problem-statement conformance unverified" | VIGIL's own disclaimer; acknowledged |

---

## 6. Summary: reuse matrix

| Area | Reuse level | How |
|---|---|---|
| Rubric design (D/C/U/R/Q/O + P1–P3, event-anchored findings) | **High (concept)** | `da-rubric-1` adapts it; formulas kept identical where meaning carries |
| `windowCredit`, decision tree, unknown-credit table | **High (formula)** | Re-implemented in GDScript; conformance-tested against shared fixtures |
| Event-log principles (ordered, ID'd, validated, no events after finish) | **High (concept)** | Same envelope in `droneacharya-session` |
| `evaluateSession` / `validateSessionLog` code | **None directly** | Bound to VIGIL's sensor provenance |
| `SessionRecord` / `vigil-session-export` | **None directly** | New format; VIGIL format stays untouched |
| Persistence validation policy, `mergeImmutable`, `canonicalJson` | **High** | Copy patterns into a new dashboard module |
| Replay prefix/cursor algorithm | **Medium** | Adapter over new event type |
| Adaptive `rules-1` | **Medium, later** | Adapter interface; after milestone 1 |
| Analytics, CSV, HTML report helpers | **Medium–High** | Adapter; `csvCell` and `escapeHtml` as-is |
| UI primitives, shell, charts, import UI | **High** | New "Simulator sessions" route in VIGIL (later phase) |
| 2D map, track workspace, Worker engine | **Keep for VIGIL only** | Not used by the simulator |

## 7. What is missing (relative to the DroneAcharya vision)

Everything 3D. Specifically:

- no Godot project;
- no terrain, sky, lighting, observer controller or sensor camera;
- no 3D aerial object or scripted 3D scenario events;
- no in-game UI, results screen or local file writer;
- no session format shared between the game and the dashboard;
- no import path for game sessions in VIGIL;
- no desert or mountain environment types;
- no version control in this workspace;
- no Windows-compatible launcher test;
- no installed browser for the e2e suite.
