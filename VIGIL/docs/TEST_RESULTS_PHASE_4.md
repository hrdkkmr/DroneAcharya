> **Historical checkpoint `75e68a9`.** These are the executed Phase 4 results, preserved verbatim below. The current application is described in [Phase 5 results](TEST_RESULTS.md); the historical stop/memory-only statements below are not its current status.

# Executed verification · Phase 4

Date: **2026-10-17**. Linux, Node **20.20.2**, npm **10.8.2**. These are executed results, not projected coverage. Browser checks reused the known **production preview** on port 5173 after rebuilding. Zero retries, removed regression checks or accessibility-rule exclusions were used.

## Final combined gate

```sh
set -e
npm run test
npm run build
npm audit
npm run test:e2e -- --workers=2
```

| Executed check | Actual result |
|---|---|
| Unit/component/protocol | **235/235 passed**, **14 files**, **19.76s** |
| Strict production build | **Passed**, TypeScript + Vite 7.3.7, **1625 modules**, bundling **3.70s** |
| Dependency audit | **0 vulnerabilities reported** for the installed graph; no Phase 4 dependency changes |
| Production-browser checks | **63/63 passed**, **21 journeys × 3 Chromium viewports**, **about 6.0 minutes**, two workers, zero retries |
| Combined tool call | **Exit 0**, **391.659s** |
| Production preview | Existing `npm run preview -- --port 5173`, bound to `0.0.0.0`; rebuilt app + separate module Worker |

Phases **0–4**, not the complete product, are verified. Phase 5 persistence/export/history and Phase 6 adaptation were not implemented. Historical clean checkpoints: Phase 1 `4a36bee` (39 unit/component, 27 browsers); Phase 2 `44b269f` (102/42); Phase 3 `70c947d` (146/51). Their captures and history remain preserved. A fresh Phase 4-entry baseline also passed **146/146 (15.89s)** and the strict build (bundling **3.97s**) before changes.

### Browser-tested production assets

| Asset | Build size | SHA-256 |
|---|---|---|
| `index-Ct1VbXdM.js` | 423.98 kB / gzip 125.29 kB | `e057401276676bd7d5e45ad12350a81e584601e652cad0dacb98eef4e8d120e6` |
| `simulation.worker-DUgXOd5k.js` | 84.32 kB | `26cf3a140eccf9e66182576873a87a7ce86b8973244afb3d0ac5a3db972ee162` |
| `index-CiReGeKq.css` | 95.91 kB / gzip 20.12 kB | `d381966e642fba27a8f66d836f424c55beeee6763c8f468f852f490cfab4e4f6` |

Sizes are build output, not runtime-performance benchmarks. Generated `dist/`, HTML reports and traces are ignored/regenerable. The final Git checkpoint identity is recorded in the delivery response/Git log rather than a self-referential hash here.

## Unit / component / protocol breakdown

All **146 prior checks remain**; **89 new checks** cover audit/replay/controller/report. Explicit version assertions now require schema **3**; generator-2/sensor-2 and numerical rubric-1 are retained.

| File | Passed | Executed coverage |
|---|---:|---|
| `src/domain/config.test.ts` | 22 | curated settings, bounds, seeds, objectives, weights/helpful errors |
| `src/domain/contracts.test.ts` | 2 | public/hidden and event type boundaries, not security proof |
| `src/engine/engine.test.ts` | 27 | generation, sensor/request/clock/actions/log/isolation/terminal immutability |
| `src/engine/variation.test.ts` | 32 | patterns/conditions/reproduction, 24-seed × 3-pattern bounds, requests/provenance, genuine arrival inversions |
| `src/scoring/evaluate.test.ts` | 26 | retained credits, every penalty, zero/mixed/abort, corrections, malformed log and actual references |
| `src/scoring/audit.test.ts` | 41 | timing/threshold edges, action-specific traces, precise penalties/contributions, strict inputs |
| `src/replay/replay.test.ts` | 30 | exact recorded-prefix fold, cursor order/time, mutation/isolation, actual-source coordinates, inversions and malformed records |
| `src/hooks/useRecordedReplay.test.tsx` | 8 | 1×/2×/4×, pause/seek/step/end/restart, timers, shorter/empty record switch and no mutations |
| `src/workers/runtime.test.ts` | 6 | strict commands, serialized isolation, clock/pause/speed/termination |
| `src/App.test.tsx` | 16 | routes, configuration, profiles, guide and unavailable Worker |
| `src/components/ConfirmDialog.test.tsx` | 3 | cancel-first focus, containment/Escape/confirmation |
| `src/components/ScenarioEvidence.test.tsx` | 8 | public settings, impossible config correction, capture age/actual markers, diagnostics/provenance |
| `src/components/observationLayout.test.ts` | 4 | bounded nonoverlapping deterministic identity text, actual marker positions preserved |
| `src/components/SessionReport.test.tsx` | 10 | fixed result, exact P1/P2 links, keyboard/scrub, recorded pause, declared rubric/audits, empty/abort/filter/switch/error |

### Rubric and audit acceptance

- D1 at latencies **0/5/6/17/29/30/31 seconds**; R1 at **0/15/16/30/59/60/61** including valid completeness after timeliness reaches zero.
- P1 confidence **70 vs 71**, clear signal **59 vs 60**, unresolved high-signal cues, stored minimum-clear/timing/penalty thresholds and configured weights.
- P2 unjustified escalation, conservative-observe half credit and supported branch; P3 once per eligible significant track, absent report/termination anchor, no penalty for unobserved truth.
- Later deliveries can support a later report but never retrospectively justify an earlier assessment. Corrections before the immutable final report replace the scored assessment, not replay history.
- Per-track raw credit, eligible-track weighted share and actual event anchors/references; no component-loss double subtraction. Missing actions cite real opportunities/Finish, never invented IDs.
- Fractional **0.04 + 0.04** penalties remain unrounded until aggregation: displayed penalty **0.1**, final **69.7** in the controlled fixture. Extreme configured penalties clip final to zero; no NaN/default substitution.
- Strict rejection of missing/string/nonfinite/negative/oversized/unknown rubric fields, invalid clear counts/thresholds/windows, mismatched weights, duplicate track/capture despite changed IDs, impossible >19s delay and incorrectly labelled coalesced provenance.
- Retained fixtures remain **100 / 95 / 57.8 / 0 / 84.3** for supported / early unknown / unsupported escalation / no actions / strong-evidence unknown. These are actual test-engine fixtures, **not historical performance or injected UI scores**.

### Recorded replay acceptance

- Every event and every second in a real fixture are compared against the actual prefix; exact jumps distinguish same-second assessment/report and pause/resume. Time scrubbing applies all events through that second.
- Start is before Start; actual terminal time bounds aborts, including zero-duration records. Previous from a gap returns first to the last applied event. Seek/chunk/step reach the same terminal frame.
- Captured/arrived/source/latest-by-capture and recorded link/status/selection are preserved; gaps are not extrapolated. Genuine capture-order inversions from seeded actual logs do not rewind the marker.
- Deliberately changed valid recorded coordinates are replayed as recorded, proving the model is not regenerating the seed. Timeline/frame omit hidden tracks, rubric, evaluator and future disruption schedule; detached copies prevent record/frame mutation crossing boundaries.
- Wrong schema/session/outcome/duration/order, missing Finish, unknown/future evidence references, unknown anchors and inconsistent/nonfinite cursors are rejected, not sorted or repaired into plausible history. This is **not a full portable-import authenticity validator**.
- Hook tests verify pacing, pause freeze, exact steps/jumps, auto-stop/restart, source/evaluation immutability, timer teardown on unmount and safe reset when switching to a shorter/zero-duration result.

## Twenty-one browser journeys at each viewport

**9 foundation** + **5 live exercise/lifecycle/failure** + **3 variation** + **4 new replay/AAR** = **21 × 3 = 63**.

Retained journeys cover all routes, validated briefing without auto-start, useful input correction, anonymous empty-history profiles, guide/drawer/keyboard/focus, offline shell, unavailable Worker and injected transport error (not OS-crash recovery), active configuration/profile/answer locks, confirmed reset, partial abort and same-seed/next-seed actual captures.

Unmodified **Perimeter watch (90s)**, **Urban ambiguity (120s)** and **Nightfall protocol (150s)** complete with browser network disabled after code readiness. Moving evidence, distinct conditions/clutter/rain, real requests/cooldown/provenance, degraded feed and pause/resume execute. UI score/six metrics/counts/formula and **every rendered event ID in order** match the actual Worker record. No fixed performance target is substituted.

### Four new Phase 4 real-Worker journeys

1. **Offline weak-evidence/penalty replay.** A validated custom 60s, seed-1, rural/night/rain/noise-25% exercise receives actual evidence. A deliberately overconfident specific assessment + escalation produces real **P1=4/P2=8**, not injected findings. Each link matches its evaluator anchor and public prefix; earlier assessment has no later report. Same-second source events support keyboard next/previous order checks. Slider Home/ArrowRight, 4× play/pause/freeze/end, captured marker coordinates, actual status/counts and fixed score agree. Expanded delivered evidence, declared rubric and per-track references pass axe. **No replay Worker commands** are sent, and the original record remains identical.
2. **Missing significant report.** Actual no-action 60s seed-1 run produces **P3=5/final0**. Its link goes to the real Finish; no tracking/assessment/report is invented. Action-only log correctly shows no recorded trainee actions.
3. **Empty partial.** Delay8 and early exit before arrival produce actual **Start → Pause → Finish** (the confirmation dialog pauses). Exact stepping exposes each state, no live pause overlay blocks inspection, no marker appears, final0/no penalties/noncomparable remain honest. Actual duration can be **0**, not invented planned time.
4. **Active lock / record switch.** Prior player is unmounted before a new attempt. Current/prior score, evaluator tables/audits and replay are absent while active. Actual early termination releases a separate result; selecting either record resets cursor/speed/player and no stale timer advances the new record.

All Worker observation/command interception is injected by **test-only Playwright harness**, not a production debug API or replacement engine. Waiting for the real new-session response is explicit; asynchronous Start is not assumed synchronous. Active public messages omit hidden tracks/positions/answers/rubric/future geometry/schedule.

## Accessibility / responsive / captured evidence

- **Desktop 1440×1000**, **laptop 1024×768**, **mobile-sized Chromium 390×844**, touch enabled for mobile.
- Axe WCAG 2 A/AA + 2.1 AA scans: **no violations in tested states**, no excluded rules. Includes retained routes/dialogs/briefings/live/degraded/disconnected/results plus linked replay, expanded delivered observations/rubric/audit, missing actions, empty abort and prior-answer lock.
- Keyboard transport/event stepping/scrub, navigation, focus, filters and named keyboard-scrollable tables execute. Main/document overflow checks pass. Automated checks are **not accessibility certification or screen-reader studies**.
- **39 actual Phase 4 viewport captures** under `docs/screenshots/`: `phase4-{home,lab,console,result}-*.png`; `phase4-{urban-dusk,night-watch}-*.png` and `-result-*.png`; `phase4-{replay,replay-evidence,audit,missing-report,empty-replay}-*.png`. All three viewports are present. Prior Phase 1–3 images were not overwritten.
- Inspected final actual desktop replay, laptop audit, mobile replay/inspector/empty partial. Controls wrap without document overflow; identity markers/evidence remain separate from evaluator answers. Viewport capture deliberately respects the fixed-height workspace scroller; it is not an over-tall element capture with clipped/unpainted areas.

## Investigated failures and fixes

- A retained test's schema-2 literal was updated to the explicit schema-3 contract; generator/sensor assertions and all geometry checks remain.
- Replay health test initially guessed disruption at second12; it now checks before/at the **actual recorded sensor-change event**, with no model change.
- Browser axe caught highlighted-row timestamp/order contrast **4.15:1**. Darkened those foregrounds rather than excluding the rule; final scans pass.
- Early-exit test initially omitted the actual confirmation pause; preserved and asserted **Start/Pause/Finish**, including exact paused-prefix inspection.
- One result-switch test read the old Worker response immediately after asynchronous Start. It now waits for the actual new session ID, not a fabricated synchronous response.
- Visual inspection found an overbroad SVG selector enlarging the timeline's caption icon and audit content flush to its border; scoped the chart selector and added report padding. Capture helper now records the real viewport, avoiding ancestor-clipped tall element shots. The complete **235/63** gate ran after these changes.

No failed regression was deleted, score manufactured or required visibility/privacy assertion weakened. Earlier Phase 1–3 investigation details remain in Git and `docs/PROGRESS.md`.

## Verification limits / stopping point

No Firefox/Safari, assistive-technology study, exhaustive zoom checks, prolonged low-end performance benchmark or every OS/Worker failure path was tested. Offline verification begins **after code loading**, not a service-worker cold start. No real-sensor/operational/readiness validity is claimed.

Results/profiles remain **memory-only**. IndexedDB/reload, validated portable imports/exports, historical competencies/unit trends and conservative rules-based adaptation were **not implemented or claimed tested**. No legacy-schema migration. **Stop after Phase 4; Phases 5–8 remain unchecked.**
