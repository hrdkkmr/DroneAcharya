# Executed verification · Phase 6 local handoff

**2026-10-17 · Linux · Node20.20.2 / npm10.8.2.** Executed results, not planned coverage. Browser acceptance used the known rebuilt **production preview** on5173 and actual separate module Worker. Zero retries, no removed critical regression cases or axe exclusions. This is local application acceptance, not authenticated official PS, ML efficacy, security/accessibility or production certification.

## Final complete application gate

```sh
npm test
npm run test:launcher
npm run build
npm audit --audit-level=low
npm run test:e2e -- --workers=2
```

Executed **2026-10-17 14:41:44–14:55:20 UTC**, exit0, **816s** combined. [Full unabridged command log](test-evidence/phase6-full-gate.txt) (ANSI formatting stripped only).

| Check | Actual result |
|---|---|
| App unit/integration/component/protocol | **369/369 passed**,22 files,29.03s |
| Zero-dependency native host tests | **9/9 passed**,1 suite,204.332698ms process duration |
| Strict production build | Passed, TypeScript +Vite7.3.7,1642 modules,3.95s bundling; no final chunk warning |
| Installed dependency audit | **0 vulnerabilities reported**; lockfile/dependency versions unchanged; package scripts added only |
| Production Chromium | **111/111 passed**,37 journeys×3 sizes,2 workers,zero retries,12.9min |
| Server identity | Existing `npm run preview -- --port 5173`,0.0.0.0; actual production HTML/asset names verified |
| Current captures | **84 actual Phase6 PNGs**,28 states×3;141 older PNGs preserved |

Fresh Phase6 entry baseline at clean `f0d2802`:315/315/20 files/26.23s, strict1639-module build/4.02s, audit0 and18/18 desktop Foundation+History journeys,112.716s combined. That targeted baseline was not adaptation acceptance. First new targeted policy/root run51/51; planner UI added8 for59/59; new desktop5/5 journeys passed after correcting two test assumptions. The first complete366/9/108 pass is preserved in [initial gate log](test-evidence/phase6-initial-gate.txt). Final review then found the peer-tab freshness edge: an older acknowledged snapshot could still offer a plan after a same-epoch save notice. Added explicit needsReload withholding and three unit/root/component cases plus a real peer-save journey. Targeted74/74 +desktop peer case passed, then the full369/9/111 gate above reran everything.

### Exact production assets tested

| Asset | Actual bytes / Vite gzip | SHA-256 |
|---|---|---|
| `index-BiSwf0C9.js` | 499981 /148.81kB gzip | `251fea8d595ea4304a1b41978415f704e6c944c7410facbb881b34d1c7059542` |
| `index-48Timya1.css` | 108564 /22.68kB gzip | `27dcf7f4a8e1216ed17081ff8b69ab328982e28c951809bf904a4a3ecb8e4cba` |
| `simulation.worker-DUgXOd5k.js` | 84318 | `26cf3a140eccf9e66182576873a87a7ce86b8973244afb3d0ac5a3db972ee162` |

`dist/index.html`605 bytes; favicon290. Build size/time is not a runtime-performance benchmark. Worker bytes and engine/scoring/replay/Worker source are unchanged. The bridge now retains a healthy loaded Worker for an explicitly reviewed next/manual terminal briefing; confirmed discard/reset still recreates it. No test interception/debug globals enter the app bundle. No dependency addition; package-lock unchanged. HistoryStore adds only an ephemeral needsReload flag for known same-epoch peer changes, not a DB/portable schema change.

## All22 application test files

All315 prior checks retained; **+54** =36 policy +9 planner +8 root +1 store freshness =369. Tests create actual engine/evaluator records, never initial app performance history. Schema3/generator-2/sensor-2/rubric-1/replay-1 and DBv1/portable-format1 unchanged.

| File | Passed | Executed coverage |
|---|---:|---|
| `src/domain/config.test.ts` | 22 | presets, bounds, seeds, objectives, weights, helpful errors |
| `src/domain/contracts.test.ts` | 2 | public/hidden/event type boundaries, not a security proof |
| `src/engine/engine.test.ts` | 27 | generator/sensor/clock/actions/log/isolation/terminal immutability |
| `src/engine/variation.test.ts` | 32 | patterns/conditions/reproduction, 24-seed × 3-pattern bounds, requests/provenance, genuine arrival inversions |
| `src/scoring/evaluate.test.ts` | 26 | every credit/penalty, zero/mixed/abort, corrections, malformed log and real references |
| `src/scoring/audit.test.ts` | 41 | timing/threshold/weight/precision edges, per-track raw contributions and anchors, strict failures |
| `src/replay/replay.test.ts` | 30 | every-prefix/cursor/order, source coordinates/inversions, mutation isolation, malformed records |
| `src/hooks/useRecordedReplay.test.tsx` | 8 | playback1×/2×/4×, pause/seek/step/end/restart/switch/timer cleanup |
| `src/workers/runtime.test.ts` | 6 | serialized commands/isolation/clock/pause/speed/termination |
| `src/App.test.tsx` | 16 | seven routes, async hydration, config/briefing, anonymous profiles, guide/unavailable Worker |
| `src/components/ConfirmDialog.test.tsx` | 3 | cancel-first focus, containment, Escape/confirmation |
| `src/components/ScenarioEvidence.test.tsx` | 8 | public settings, config correction, capture-age/marker/monitor/provenance |
| `src/components/observationLayout.test.ts` | 4 | bounded deterministic nonoverlapping text, actual marker positions unchanged |
| `src/components/SessionReport.test.tsx` | 10 | fixed result/anchors, keyboard/scrub, actual paused/empty/abort/filter/switch/error |
| `src/persistence/validation.test.ts` | 28 | actual roundtrip, versions/shape/date/identity/orphan/duplicate/score/audit/truth/seed/rubric/log/anchor/count/size/canonical rejection |
| `src/persistence/repository.test.ts` | 13 | initialization, transaction/reload, preferences, immutable merge, rollback, controlled quota, independent writers, reset epoch, quarantine/raw/missing-meta/unavailable |
| `src/persistence/HistoryStore.test.ts` | 13 | startup/acknowledgement, detached exactly-once record, retry/queued writes, displayed-invalid vs durable-valid draft, import/late result, corrupt-copy retention/reset/stale writer |
| `src/analytics/history.test.ts` | 9 | saved/completed/comparable eligibility, genuine no-delivery completion, empty/null/n/missing, per-profile and attempt-weighted unit means/difficulty/order/comparison |
| `src/analytics/exports.test.ts` | 10 | JSON roundtrip/empty, CSV formula prefixes/quoting/outcome/saved status, escaped self-contained actual HTML and partial labels |
| `src/hooks/workspacePersistence.test.tsx` | 16 | actual Runtime/Engine/Evaluator through test transport + fake IDB: hydrate/reload, stale/current Start guards, resets, interrupted run, denied recovery, abort/import; +8 fresh derived-plan/frozen-briefing/no-auto-start/healthy-Worker-reuse/pending/profile/reset tests |
| `src/adaptive/policy.test.ts` | 36 | actual-engine eligible/empty/all5 targets/strong/weak/sparse/noisy/penalty/context/objectives/weights/dedup/window/range/seed/bounds/nonmutation/80–75 threshold cases |
| `src/components/NextPractice.test.tsx` | 9 | actual means/source controls, nulls/no fake bars, explicit apply/manual choice, live/storage locks, root errors and heuristic/table labels |

In-process persistence/root tests use fresh **fake-indexeddb** and a test transport around the real Runtime/Engine/Evaluator. Browser cases use native Chromium IndexedDB and actual module Worker. Controlled fixture dates/styles/seeds are test inputs, not real human-performance assertions. A true no-delivery completion is found using the actual sensor; no-actions alone is not mistaken for no delivered evidence.

Retained scoring tests include every penalty, D1 latencies0/5/6/17/29/30/31; R1 at0/15/16/30/59/60/61; confidence70/71/quality59/60; full-precision aggregate/clamp, missing Finish anchors and no later-evidence justification. Historical numeric fixtures remain numerical regressions, not initialized history.

### Native host suite

`scripts/serve.test.mjs`:9 actual HTTP/fs checks for HTML/allowed preview host, Worker JavaScript MIME/body, HEAD length/no body, missing asset404, read-only methods, invalid encoding/backslash traversal, outside-root symlink/source rejection, no-store/nosniff/no iframe block, and clear missing-bundle failure. Tests use temporary fixture files/ephemeral local ports and close them. No npm/runtime dependencies are needed by `serve.mjs`.

## Production browser:37 journeys at each of3 sizes

| Spec | Distinct journeys | Across3 viewports |
|---|---:|---:|
| `tests/e2e/foundation.spec.ts` | 9 | 27 |
| `tests/e2e/exercise.spec.ts` | 5 | 15 |
| `tests/e2e/variation.spec.ts` | 4 | 12 |
| `tests/e2e/replay.spec.ts` | 4 | 12 |
| `tests/e2e/history.spec.ts` | 9 | 27 |
| `tests/e2e/adaptive.spec.ts` | 6 | 18 |
| **Total** | **37** | **111** |

Desktop1440×1000; laptop1024×768; mobile-sized390×844. Actual Chromium, not separate physical mobile hardware. Existing31 journeys are retained verbatim in purpose/assertions; capture destinations advance to phase6 names. Full log lists every executed case.

### New actual-history personalized journeys

1. Empty null estimates/foundation n0→explicit briefing without Worker Start→manual seed override; no invented report.
2. Real offline completion/save/AAR→source metric/reason/link equality→heuristic table→reviewed next config→second actual completion/save→score/replay equality→reload. Exact second scenario config matches the policy derived from the first actual record.
3. Three real qualifying distinct-seed same-context reports→first two hold/third Level1→2→actual source IDs→other-profile nulls→real JSON backup/reset/validated import→same plan/config. No injected scored records.
4. Live/paused planner/estimate/private AAR locks→actual abort exclusion.
5. Genuine completed but controlled-quota-unsaved report cannot drive adaptation→retry acknowledgement→actual sourced sparse plan.
6. A real peer-tab completion marks an older snapshot for reload and withholds its planner; actual native reload includes that exact source record before a new plan. Store/root tests also prove a newer weak record blocks a stale strong-history increase, even after local preference writes.

New named-state axe scans and overflow checks cover empty/table/reasons/strong/active/failure surfaces at all3 sizes. Root tests independently cover stale apply in the Start event, after profile switch and during pending/unavailable history.

### Retained whole-application journeys

All4 curated presets complete offline after readiness. Actual final score/six components/counts/every ordered event ID equal the Worker record; request provenance/genuine arrival inversions/newest-capture markers, clock/pause/reset/abort/variation and Worker failure/private locks remain tested. Exact replay/penalty/missing-action anchors and same-time event stepping remain read-only. Native-IDB report/profile/draft/aborted reload; corrupt-score quarantine/valid sibling/raw preservation; atomic JSON import/dedup/empty/conflict/version/orphan rejection; two-tab reset epochs; actual comparison/group means/CSV/HTML/print regressions pass.

Controlled browser actual95/0 scores produce47.5 mean/−95 difference; these are measured test trajectories, not fabricated learner data. New strong-policy journeys require the actual Worker results to satisfy every threshold, not a UI-created score.

Native print dialog is stubbed to inspect portal/invocation/cleanup; separately, exported HTML produces a real nonempty Chromium `%PDF` buffer. No claim of every OS printer/dialog, PDF visual accuracy or extracted-text proof. Quota/denial faults are controlled browser API injections, not physical disk exhaustion.

## Screenshots and visual review

**84 Phase6 PNGs** =28 states×3 under `docs/screenshots/phase6-*.png`.66 Phase5 and75 earlier PNGs retained unchanged. Current 22 retained state families plus6 new adaptive states (empty/targeted/estimates/strong/lock/unsaved). Captures come from executed production sessions; no generated decorative mockup is used as test evidence.

Opened desktop sourced/empty/estimate panels and laptop/mobile adaptive/progress surfaces. Long mobile details and horizontal table alternatives remain scrollable; a viewport is not a claim that all content is above-fold. Current axe/keyboard/focus/overflow tests pass without rule exclusions, not broad accessibility/browser certification.

## Extracted runnable archive / rehearsal

Extracted executable-payload rehearsal **passed 2026-10-17 14:25:23.782–14:25:55.469 UTC**, Chromium156.0.8078.4. The provisional ZIP inventory was reread, then363 manifest-listed files extracted/hash-compared with no node_modules/.git. Invoked its POSIX helper from outside the app directory; the actual extracted Node-only server listened on8787 and returned Worker JavaScript MIME/HTTP200. No runtime npm install was performed.

The actual extracted browser app completed **two offline Worker exercises**, each with17 actual events and actual score0 (no trainee decisions), with explicit next briefing/no auto-start, preserved source conditions/weights/new seed, exact native-IDB record agreement, matching score/replay counts and latest-report reload. Only same-origin local asset requests occurred; no page errors/bad responses. [Included execution receipt](test-evidence/package-payload-smoke.json) records IDs/timestamps/browser/asset hashes; this is measured QA, not shipped initial history.

This14:25 rehearsal predates the final freshness guard; its asset hashes are historical, not the current111-case asset hashes above. Candidate checkout was explicitly dirty/provisional and is **not the delivered ZIP**. The final archive is generated only from the clean committed source plus production assets byte-identical to the final111-case gate above; its file list/source commit/SHA-256 inventory are in RELEASE_MANIFEST.json. Independent final-archive extraction/launch results and ZIP hash are recorded in accompanying `package-validation.json`, outside the self-inventoried ZIP to avoid circular hashing. Windows helper is supplied, not Windows-executed/certified.

## Known limits / honest gate scope

27 Verified /2 Partially implemented /2 Missing requirement targets; [matrix](REQUIREMENTS_TRACEABILITY.md) and [QA verdict](QA_REPORT_PHASE_6.md). Official brief403/no attachment and optional VR missing. Broader Firefox/Safari/AT/zoom/low-end/large-history/long-soak/real-event/Windows execution remain unverified. No PWA cold-start cache, signed identity, cloud backup, active-run recovery, calibrated learner model or operational/production/competition claim. Fixed teaching thresholds and matching contexts do not prove improved learning.

Historical evidence remains archived: [Phase5 results](TEST_RESULTS_PHASE_5.md), [Phase4 results](TEST_RESULTS_PHASE_4.md), older PROGRESS/checkpoints/captures. Full prior Phase5 source checkpoint `f0d2802` is preserved; final source commit is identified by release manifest/Git rather than a self-referential guessed hash in this file.
