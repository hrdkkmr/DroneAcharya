# Executed verification · Phase 5

**2026-10-17 · Linux · Node 20.20.2 / npm 10.8.2.** Executed results, not projected coverage. All browser cases used the known rebuilt **production preview** on 5173 and the actual separate module Worker. No retries, removed regression cases or axe-rule exclusions. Phase 5 acceptance is not full-product, official-PS, security or accessibility certification.

## Final complete gate

```sh
set -e
npm run test
npm run build
npm audit
npm run test:e2e -- --workers=2
```

Executed **2026-10-17 12:46:12–12:56:02 UTC**, exit 0, **590.410s** combined:

| Check | Actual result |
|---|---|
| Unit / integration / component / protocol | **315/315 passed**, 20 files, 28.86s |
| Strict production build | Passed, TypeScript + Vite 7.3.7, 1639 modules, 3.88s bundling |
| Dependency audit | **0 vulnerabilities reported** for the installed graph; no Phase 5 package/lock changes |
| Production Chromium | **93/93 passed**, 31 journeys × 3 viewports, 2 workers,zero retries, 9.1min |
| Preview | Existing `npm run preview -- --port 5173`, 0.0.0.0; production page + Worker HTTP 200 checked after gate |
| Last-run record | `test-results/.last-run.json`: passed, empty failedTests |

Entry baseline after re-auditing clean Phase 4 `75e68a9`:235/235 tests (19.12s), strict build (1625 modules, 3.44s bundling), audit 0 and21/21 desktop production-browser cases. Intermediate failures were investigated and fixed before the final full gate; they are not presented as final passes.

### Production assets tested by that gate

| Asset | Vite build size | SHA-256 |
|---|---|---|
| `index-Cz_a4yn2.js` | 486.63 kB / gzip144.53 kB | `5abd94617bb124eb6c0292565f39d3a5a3e864a3844ba8ae4e26ba72e2b2a87e` |
| `index-CewaP2PB.css` | 105.10 kB / gzip21.99 kB | `a29cf85ab26c4edcd81b2a6fa85924e2ec2fa4a9fe7ca3caef3b46fb5cbdc61e` |
| `simulation.worker-DUgXOd5k.js` | 84.32 kB | `26cf3a140eccf9e66182576873a87a7ce86b8973244afb3d0ac5a3db972ee162` |

Build sizes are not runtime-performance benchmarks. Worker is unchanged from Phase 4. Source comparison preserves engine/scoring/replay/Worker/package/lock and earlier screenshots. Test-only Worker/storage interception is not bundled. Generated dist/reports/download artifacts are ignored/regenerable; final checkpoint ID is in Git/delivery, not a guessed self-reference here.

## Unit / integration / component / protocol evidence

All235 prior checks remain; 80 new checks across six files bring the total to315. Schema3/generator-2/sensor-2/rubric-1/replay-1 remain; IndexedDB v1 and portable format 1 have their own versions.

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
| `src/persistence/HistoryStore.test.ts` | 12 | startup/acknowledgement, detached exactly-once record, retry/queued writes, displayed-invalid vs durable-valid draft, import/late result, corrupt-copy retention/reset/stale writer |
| `src/analytics/history.test.ts` | 9 | saved/completed/comparable eligibility, genuine no-delivery completion, empty/null/n/missing, per-profile and attempt-weighted unit means/difficulty/order/comparison |
| `src/analytics/exports.test.ts` | 10 | JSON roundtrip/empty, CSV formula prefixes/quoting/outcome/saved status, escaped self-contained actual HTML and partial labels |
| `src/hooks/workspacePersistence.test.tsx` | 8 | actual Runtime/Engine/Evaluator through test transport + fake IDB: hydrate/reload, stale/current root guards at Start, resets, interrupted run, denied storage/retry, abort and imports |

In-process repository/store/root tests use fresh captured **fake-indexeddb**, not an actual browser disk. Browser history tests below use **native Chromium IndexedDB and the real module Worker**. Unit fixtures are made by the actual engine; they are not initial app history.

Retained scoring checks cover every default penalty, D1 latencies0/5/6/17/29/30/31; R1 at0/15/16/30/59/60/61; confidence70/71 and clear-quality59/60; real missing-action/Finish anchors; later evidence never justifies an earlier decision; full-precision aggregation/clamp; no-evidence/aborted exclusion. Existing engine fixture outcomes100/95/57.8/0/84.3 remain numerical regression fixtures, not performance history. Full historical details: [Phase 4 results](TEST_RESULTS_PHASE_4.md).

## Production browser:31 journeys at each of three sizes

| Spec | Distinct journeys | Across3 viewports |
|---|---:|---:|
| `tests/e2e/foundation.spec.ts` | 9 | 27 |
| `tests/e2e/exercise.spec.ts` | 5 | 15 |
| `tests/e2e/variation.spec.ts` | 4 | 12 |
| `tests/e2e/replay.spec.ts` | 4 | 12 |
| `tests/e2e/history.spec.ts` | 9 | 27 |
| **Total** | **31** | **93** |

Retained foundation/exercise cases: seven routes and no page errors/overflow; validated briefing without auto-start; helpful correction; zero-history identities; guide/drawer/keyboard/focus; loaded shell offline; actual evidence/actions/results; pause/reset/abort/active config/profile/answer locks; unavailable Worker and injected transport fault with retained snapshot. Transport fault is not OS-crash recovery.

Variation now proves **all four unmodified curated presets**, including newly covered Rural crossing, complete after browser network is disabled at readiness. Actual Worker score/components/counts and **every event ID in order** agree with the UI. Requests/cooldown/provenance, genuine conditions/clutter/rain, actual monitor/newest-capture age and same-seed reset/new-seed changes execute. No fixed fake score is substituted.

Four replay journeys retain actual weak-evidence P1/P2 links, P3/missing-report terminal opportunity, pre-arrival aborted Start/Pause/Finish including0s, active prior/current locks and source switching. Exact same-second cursor/marker/support/score agreement, read-only1×/2×/4×/seek/steps/timers and **zero replay Worker commands/source mutation** remain tested.

### Nine native-IndexedDB / actual-Worker History journeys

1. **Offline completed report → acknowledged save → reload → same AAR/replay**; native stored record equals actual Worker; no new exercise command on reload; individual baseline/unit row and empty siblings are actual.
2. **Instructor identity/group/draft/aborted reload → reset cancel/focus/Escape → confirmed reset → real JSON preview/import/dedup/reload**; Practice Delta filter and aborted denominator agree.
3. **Malformed/unsupported/schema/score/orphan/conflict import rejection** without partial writes; otherwise-new incoming profile is absent after conflict; empty merge leaves actual history intact.
4. **Controlled mid-write quota fault** in native IDB object-store put: rollback, retained exportable actual AAR, unsaved analytics exclusion, retry exactly once and durable reload.
5. **Controlled startup storage denial**: clearly labelled in-memory exercise/report, portable backup, retry after restoring availability saves actual record.
6. **Deliberately corrupt stored score**: non-destructive quarantine, valid sibling review, raw diagnostic retains changed original; normal backup excludes quarantined invalid row.
7. **Active boundaries / console reset / refresh**: private controls disabled; forced native enabled attribute still produces no download; forced profile submit hits root guard; current/prior answers/exports absent. Console reset retains prior history; active reload creates no fake interrupted record.
8. **Real two-tab reset epoch**: stale active tab cannot save/resurrect on Finish or Retry; local real report remains backup-able and the other tab remains empty.
9. **Two actual completions → actual mean/delta → real CSV/HTML/print**: formula-prefixed profile/group escaped, session IDs and rows match; actual HTML score/ordered events self-contained; print portal invokes stubbed `window.print` and cleans up; rendered HTML yields nonempty Chromium PDF with `%PDF` header.

The ninth case verifies print integration and real headless PDF generation, **not a manual OS dialog/printer, PDF visual inspection or extracted-text correctness**. Storage quota/denial faults are controlled API failures, not physical disk-fill tests. Harness interception lives only in Playwright; no production debug API/fake engine is added.

## Accessibility / visual / captured evidence

- **1440×1000 desktop**, **1024×768 laptop**, **390×844 mobile-sized Chromium**, mobile touch enabled.
- Axe WCAG2A/AA +2.1AA scans pass in tested named states, **no rule exclusions**. New history summary/table/comparison/import/reset/quota/quarantine states join retained screens/dialogs/briefing/live/degraded/disconnected/result/replay/audit scans.
- Keyboard navigation/shortcuts, cancel-first dialogs/focus containment/Escape/return focus, range/transport/links and named keyboard-scrollable data tables execute. Main/document overflow checks pass. This is not accessibility certification or an assistive-technology study.
- **66 Phase 5 PNGs**:22 states × 3 sizes under `docs/screenshots/phase5-*.png`: home/lab/console/result; Urban/Night/Rural exercise/results; replay/evidence/audit/missing-report/empty-replay; progress/unit/comparison/import/reset/storage-failure/quarantine. They are real viewport captures from actual test states, not initialized performance history.
- Inspected actual desktop history/reporting views and mobile progress/import/failure/reset plus laptop progress/unit/comparison/quarantine and mobile actual AAR; retained earlier gates include desktop/laptop/mobile exercise/replay inspection. Mobile import capture shows tools/file input with preview below fold, not a complete visible preview; DOM/interaction/axe verifies it. Small chart text has accessible tabular alternatives.
- **75 earlier PNGs unchanged:** Phase 1=6,Phase 2=6,Phase 3=24,Phase 4=39. Earlier gates/checkpoints are historical, not counted as additional current test runs.

## Investigated intermediate failures / root fixes

- Async hydration initially raced one retained config test; use explicit loaded-state waits and fresh captured IDB per test rather than removing assertions. Root integration added8 real Runtime/Engine/Evaluator cases.
- Foundation browser checks caught an invalid empty progressbar ARIA role and stale competency/storage copy. Empty bars no longer pretend to expose assessed values; actual labels and scans fixed, no axe exclusions.
- Initial new browser cases selected the wrong accessible Unknown label and assumed an editable confidence field instead of the actual slider/default40. Corrected test interactions without changing model/evaluator results.
- Removed disabled attribute did not bypass React disabled-prop event suppression. Test records no download and separately forces form submit to prove the root guard; current/stale API integration tests cover private methods.
- Store review fixed loss of a prior valid in-memory report when its stored copy becomes corrupt; it now remains unsaved/exportable while the conflict prevents overwrite. Retrying does not replace displayed invalid edits with the durable valid draft.
- Added actual Rural crossing completion coverage, group-filter/aborted denominator checks, bounded-event/ID validation and attempt-weighted unit-mean regression. Same-ID comparison is ineligible; exerciseType/conditions/objectives/weights disclosure is preserved. `priorKnowledge` does not exist in ScenarioConfig.
- Busy import/reset/reload now reports the real operation/saving state; quarantine is amber, records use actual date/ID labels, and Unit title/region accurately reflect the selected local group. Full315/93 gate ran after these changes.

## Post-documentation verification / final source review

Executed **2026-10-17 13:15:15–13:15:57 UTC**, exit 0, 42.962s combined: **315/315 tests** again (20 files, 27.08s), strict TypeScript/Vite build again (1639 modules, 4.25s bundling), audit again **0 vulnerabilities**. All three production main/CSS/Worker SHA-256 values match the complete 93-case browser gate **byte-for-byte**. No functional application changes followed that gate; the later trailing-whitespace-only cleanup below also produced identical assets. This was not claimed as an additional browser run. Production page and Worker again HTTP 200; last full browser result still passed/no failures.

Final review: actual root tsconfig.json is strict and includes src + tests/Playwright configuration. Preview process remains production Vite on 0.0.0.0:5173.19 Markdown files checked: 50 relative links resolve to 16 existing destinations; 31 requirement rows are identical in QA/traceability.75 historical PNGs match HEAD byte-for-byte; the Phase4 result archive exactly preserves its previous text.66 new actual screenshots present. No test-only interception in production assets, no source TODO/FIXME markers, no package/lock/engine/scoring/replay/Worker or historical-image diff. Formatting checked; final staged review/checkpoint recorded in Git/delivery.

### Staged formatting correction / last recheck

Staged validation found one trailing space in the newly added HistoryTools JSX; removed it without a functional change. **2026-10-17 13:21:12–13:21:54 UTC**, exit 0, 41.785s: **315/315 tests again**, 20 files, 27.21s; strict build 1639 modules/4.03s; audit 0. All three main/CSS/Worker hashes remain **byte-identical to the full 93-case production-browser gate**. No additional browser run or broader coverage is inferred. The staged whitespace check was then rerun after this fix.

## Limits / acceptance boundary

[QA report](QA_REPORT_PHASE_5.md) and [traceability](REQUIREMENTS_TRACEABILITY.md) classify every repository requirement as verified/partially implemented/missing. Official PS portal returned 403 and no authoritative attachment was available; **official conformance is unverified**.

No Firefox/Safari, screen-reader studies, comprehensive zoom, prolonged low-end/large-dataset benchmarks, physical disk/OS crash/eviction guarantees, cloud/authentication, legacy schema migration or active-attempt recovery tested/implemented. Offline means after loaded readiness, not a service-worker cold start. Unsigned validation is consistency, not authenticity or real-world assessment. Competency estimation/adaptive policy remains **Phase 6**, broader hardening/rehearsal **Phases7–8**; no ML/operational/readiness/competition-placement claim. Stop after Phase 5.

Historical Phase 4 details are [preserved separately](TEST_RESULTS_PHASE_4.md). PROGRESS retains executed Phase 0–4 history; current Phase 5 evidence supersedes their old memory-only notices without rewriting those past results.
