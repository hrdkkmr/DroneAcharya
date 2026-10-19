# VIGIL · Independent QA report
## Phase 5: durable local history, portable reporting and actual progress

**Audit date: 2026-10-17 · Verdict: Phase 5 accepted in the tested scope.** All critical implemented trainee/instructor/storage/export flows passed the final combined regression gate. A post-documentation 315-test/build/audit recheck also passed with identical production asset hashes. **The complete target product and official-PS conformance are not accepted as complete. Stop before Phase 6.**

### Executed final gate

| Check | Result |
|---|---|
| Unit / integration / component / protocol | **315/315 passed**, 20 files, 28.86s |
| Production build | **Passed**, strict TypeScript + Vite 7.3.7, 1639 modules, 3.88s bundling |
| Dependency audit | **0 vulnerabilities reported**, no dependency changes |
| Real production Chromium | **93/93 passed**, 31 journeys × 3 viewports, 2 workers,zero retries, 9.1min |
| Combined command | Exit0, 590.410s; 2026-10-17 **12:46:12–12:56:02 UTC** |
| Captured evidence | **66 actual Phase 5 PNGs**; 75 Phase 1–4 images unchanged |

The suite ran against the known rebuilt production preview and real separate module Worker, not a mocked browser engine or a development HMR acceptance claim. All four curated presets now complete with network disabled **after local code/Worker readiness**. Actual score/components/counts/ordered events agree with actual Worker records. `test-results/.last-run.json` records passed/no failed tests. See [full executed results and assets](TEST_RESULTS.md).

## Audit basis and official-source blocker

Entry audit reviewed clean Phase 4 `75e68a9`, Git history, source/contracts/routes/components/Worker/evaluator/replay, dependency/lock/scripts/configuration, tests, deployment and all current docs. Baseline executed:235 tests, strict build, audit 0 and21 desktop production-browser cases before Phase 5 work. Typed storage/validation/analytics boundaries and PHASE_5_PLAN were written before integration; no scaffold/user work was replaced, no dependency or external service added.

No authoritative official brief was attached. Fresh requests to `https://sih.gov.in/sih2026PS` and `https://sih.gov.in/sih2025PS` returned **403 Forbidden**. Searches found third-party projects, not a retrievable official source; they were not used as acceptance requirements. The matrix below therefore covers the **repository specification + agreed user scope**, not authenticated official conformance. An official PDF/text is still needed for that external sign-off. This is a QA-role audit, not third-party laboratory/security certification.

## Requirement-by-requirement result

Every target has an explicit status and actual evidence. A verified status is limited to the stated implementation/test scope; optional/future targets and missing external evidence are distinguished from Phase 5 blockers. No completion percentage is inferred.

| ID | Requirement | Status | Executed evidence | Scope / remaining work |
|---|---|---|---|---|
| R00 | Authoritative official PS / external conformance | Missing | No official attachment. Fresh SIH 2026/2025 PS fetches returned 403. No third-party implementation adopted as a requirement. | Evidence missing, not a claimed app defect. Official conformance cannot be signed off. |
| R01 | Browser-first, no specialized hardware | Verified | Strict React/Vite production build; all 93 Chromium cases at desktop/laptop/mobile sizes. | Current local prototype only; no browser-universal or VR claim. |
| R02 | Curated + procedural synthetic scenarios | Verified | config 22; engine 27; variation32; all four curated presets complete offline at all 3 sizes. | Independent/crossing/grouped teaching geometry, not tactical swarm control. |
| R03 | Day/dusk/night, urban/rural and conditions | Verified | Isolated condition/model tests; real Perimeter/Urban/Night/Rural browser completions and screenshots. | Schematic synthetic weather/clutter, not physical sensor validity. |
| R04 | Meaningful noise/dropout/delay and requests | Verified | engine/variation/runtime tests; real cooldown/request/provenance/arrival traces; delay bound and duplicate/coalescing rejection. | Requests can fail; no invented hidden missed-return telemetry. |
| R05 | Delivered evidence, age and diagnostic honesty | Verified | Actual Worker observation/count/delay agreement; genuine arrival inversions; recorded-prefix marker agreement. | Newest capture, not latest arrival; no hidden-position extrapolation. |
| R06 | Stateful tracking → assessment/uncertainty → report | Verified | Engine/action/protocol/component checks; real keyboard and UI mark/category/unknown/confidence/report actions. | Immutable final reports; no richer decision-tree authoring promised. |
| R07 | Clock, speed, pause, reset and partial termination | Verified | Fixed-clock/runtime tests; real pause/resume/4×/reset/next-seed/abort; active refresh creates no fake result. | No active-run recovery from refresh or Worker loss. |
| R08 | One authority and active truth/private-operation boundary | Verified | Serialized public messages omit answers/truth/weights; prior/current AAR/replay absent while active; root integration guards + forced form submit. | Source/devtools are inspectable; not adversary-proof examination security. |
| R09 | Bounded deterministic explainable evaluation | Verified | evaluate26 + audit 41; every penalty/window/threshold/precision/zero/abort edge; actual UI score/components/event agreement. | One rubric-1 evaluator; teaching scores, not calibrated readiness. |
| R10 | Exact ordered actual-log recorded replay | Verified | replay 30 + controller 8 + report 10; four real replay journeys × 3; no replay Worker commands or source mutation. | Exact (time,eventCount); no invented wall-clock pause/speed history. |
| R11 | Evidence-linked AAR and declared rubric | Verified | Real P1/P2/P3/absence anchors, assessment/report-time prefixes and immutable score; imported/reloaded actual AAR retains log/replay. | Expected outcomes are explicitly post-exercise, never active advice. |
| R12 | Anonymous profiles and valid draft/selection hydration | Verified | repository 13 + store 12 + root 8; real add/group/select/reload, last-valid config and selected result restoration. | Three initial identities have zero sessions; no accounts or cloud identities. |
| R13 | Durable completed/aborted reports and reload | Verified | Transaction-complete acknowledgement; actual native IndexedDB equals Worker record; timed completion and abort survive browser reload. | Browser/origin-local, not eviction-proof; unfinished attempts are not persisted. |
| R14 | Explicit storage failure and retained-report recovery | Verified | Repository/store rollback and pending tests; controlled native-browser quota/denial failures, backup, retry, exactly-one durable result. | Failures are injected API faults, not exhaustive physical-disk/OS testing. |
| R15 | Strict versioned validation and non-destructive quarantine | Verified | validation 28; seeded definition + same-evaluator + replay checks; real corrupt-score quarantine, valid sibling, untouched raw diagnostic. | Unsigned consistency ≠ authenticity. Missing/schema-invalid metadata blocks automatic load; no migration. |
| R16 | Portable previewed atomic import / dedup / conflicts | Verified | Real JSON download/reset/import/reload; malformed/version/tamper/orphan/conflict rejected without partial writes; duplicate/empty merges safe. | 20 MiB/500 profiles/500 reports per file; same-ID differences rejected, not overwritten. |
| R17 | Actual JSON/CSV/HTML/native print exports | Verified | exports 10; real formula-prefixed names/groups and CSV downloads; HTML score/ordered events; print portal/cleanup + generated Chromium %PDF. | OS print dialog/printer and PDF visual/text extraction not certified; no server PDF. |
| R18 | Confirmed reset and stale-tab resurrection protection | Verified | Cancel-first focus/Escape/retained history; confirmed atomic reset; repository concurrent writers; real two-tab epoch rejection and retained backup. | Console discard ≠ history reset. Cross-tab notice is not cloud synchronization. |
| R19 | Individual descriptive progress and comparison | Verified | history 9; actual two completions drive mean/delta; n/missing/exclusions, trend/data table, components/difficulty samples; empty/unsaved/abort states. | Saved + completed + comparable only. Means/raw differences are not inferred competencies. |
| R20 | Local unit/group aggregation with denominators | Verified | Attempt-weighted unit-mean test; actual saved unit row, zero-history siblings and Practice Delta group filter/aborted denominator in browser. | Anonymous local groups only, not authenticated multi-device unit management. |
| R21 | Configurable difficulty / deterministic variation | Verified | L1–5 / uint32 seed/config tests; many-seed bounds; actual same-seed reset and changed next-seed evidence. | Manual difficulty only; no policy automatically adjusts it. |
| R22 | Local/offline core without paid services | Verified | All4 curated presets + penalty replay complete with browser network disabled after code/Worker readiness. Exports are self-contained. | Initial installation/loading needs its source; no PWA/cold-offline caching. |
| R23 | Functional instructor configuration/reporting controls | Verified | Objectives/weights validation; durable anonymous profile/group; compare/export/import/reset/cancel/active locks in actual browser. | No trusted role/authentication, arbitrary tree editor or real-personnel database. |
| R24 | Broad accessible/responsive/browser usability | Partially implemented | Current93 Chromium checks, axe without rule exclusions, keyboard/focus/overflow and actual 3-size captures pass. | Phase 7: broader browsers, assistive technology, zoom and prolonged low-end use remain unverified. |
| R25 | History-derived competency / weakness estimator | Missing | Historical component means and AAR feedback execute, but no learner estimator or controlled competency-history tests exist. | Phase 6 reserved contracts are not an implemented learner model; no ML claim. |
| R26 | Personalized conservative next-exercise policy | Missing | Manual Lab/presets/next seed only; no connected sparse/strong/weak-history policy, evidence explanation or anti-repeat selection tests. | Phase 6, not authorized in this implementation. No single-result difficulty increase. |
| R27 | Complete configure → replay → adapt → repeat target | Partially implemented | Configure/brief/evidence/actions/evaluation/replay + persisted actual progress pass all critical Phase 5 browser flows. | Personalized adapt step remains missing. Full product/official PS not complete. |
| R28 | Executed regression/build/audit gates and honest evidence | Verified | 315/315 tests; strict build; audit 0; 93/93 production-browser cases, zero retries; 66 new actual captures; historical evidence preserved. | These results do not establish external PS compliance, operational validity or production readiness. |
| R29 | Optional immersive/VR extension | Missing | No VR runtime, hardware integration or VR tests implemented. Browser core has no such dependency. | Explicitly optional future extension in repository specification, not a Phase 5 blocker. |
| R30 | Full hardening / demonstration rehearsal gates | Partially implemented | Current regression, failure states and responsive inspection pass; run/deployment/backup instructions exist. | Phases7–8 still open: broader hardening and actual demonstration rehearsal not accepted by this gate. |

[Traceability and PRODUCT_SPEC acceptance-criterion mapping](REQUIREMENTS_TRACEABILITY.md).

## Critical journeys actually executed

### Trainee

- Configure/brief without auto-start → real changing delivered evidence → tracking/unknown/confidence/report → deterministic AAR/replay. All4 curated presets complete offline at all 3 sizes; existing unavailable/disconnected Worker, pause/reset/abort/privacy/variation/replay cases remain green.
- Actual completed report transaction-acknowledged in native IndexedDB is structurally identical to the Worker record; reload retains the same session ID, score, actual event log and terminal replay. Reload issues no new exercise commands.
- Real individual baseline and local unit row equal actual saved performance; zero-history siblings stay empty. Aborted/no-evidence/unsaved records are not eligible means. Genuine no-delivery completion is additionally engine-generated and unit-tested, not a score fixture inserted into app history.
- Console discard leaves saved history intact. Active refresh warns and creates no fabricated interrupted result or new automatic run. Profiles/config/answer/replay/private reports stay locked while active, including paused/disconnected state.

### Instructor

- Add an anonymous profile/group, configure an exercise, save an actual partial, refresh: profile/draft/selected result persist. Group filtering and aborted/eligible denominators agree with actual data.
- Cancel-first history reset supports keyboard containment/Escape/return focus and retains data on cancel. Confirmed reset is atomic, changes epoch and restores zero-history anonymous definitions. It is not console discard.
- Download real JSON, preview/confirm import, refresh and review the unchanged report. Equal duplicates do not double-count; empty merge never clears history. Invalid JSON/version/schema/score/profile/ID conflict rejects with no partial incoming rows.
- Two actual completions in a controlled browser journey produce95.0 and0.0; displayed47.5 mean/−95.0 difference are checked against the actual records. These are test outcomes, not initialized history, learner-model performance or prescribed targets.
- Real profile CSV includes both actual session IDs; `=...` names/groups are neutralized. Self-contained HTML retains the actual score and all ordered events. Print entrypoint/portal/cleanup is exercised with a stubbed native dialog; exported HTML is separately rendered and produces a real nonempty Chromium PDF. OS printer/dialog behavior and PDF visual/extracted-text validation remain unverified.

### Empty / failure / concurrency

- Empty startup has three anonymous definitions and **zero sessions**, null means/dashes, n = 0 and no inserted comparison or chart baseline.
- Controlled session-store quota fault aborts the native transaction; actual AAR remains exportable, unsaved analytics are excluded and retry commits once, surviving reload. Controlled startup SecurityError permits clearly labelled in-memory training, then recovers the actual terminal record.
- A deliberately corrupted stored score remains untouched/quarantined; valid sibling report remains reviewable. Raw diagnostic preserves the corrupt original and is deliberately not a format 1 import. Missing metadata recovery/refusal and immutable conflicts are additionally tested at repository level.
- Real two-tab history reset prevents a stale active tab from resurrecting records on Finish or Retry; its actual local report remains available for backup. Concurrent independent writers are tested at repository level. A prior valid in-memory report survives detection of its corrupt stored copy, marked unsaved and unable to overwrite it.
- Root integration separately invokes current/stale APIs immediately around Start, including export/import/reset/print/config/profile/review guards. A browser-forced profile form submit proves the root guard, rather than relying only on disabled appearance. Removing a native disabled attribute alone does not bypass React's disabled-prop event suppression; no stronger claim is made.

## Root causes fixed / usability review

| Finding | Root fix and regression evidence |
|---|---|
| Refresh discarded all history/preferences; no durable save acknowledgement | Transactional repository + serial HistoryStore; explicit hydration/pending/saved/unavailable states; real save/reload equality and root integration. |
| Storage failure could make the only report disposable or incorrectly count as saved | Retain detached actual report, acknowledge only transaction completion, retry/portable backup; rollback/quota/denial/corruption-memory tests and browser failures. |
| Reset/import/cross-tab writers could overwrite or resurrect records | Immutable ID merge + atomic multi-store transaction + reset epochs; rollback/conflict/dedup/concurrent/stale-tab tests. |
| Local/imported records could carry inconsistent scores/logs or silently lose content | Strict bounded versions/shape/canonical equality + generator identity + same evaluator + replay validation; 28 validators, non-destructive quarantine and real tamper rejection. Consistency is not authenticity. |
| Missing latency/empty progress and unequal profile samples could mislead | Null means, n/missing/exclusion counts, actual saved eligibility, attempt-weighted unit mean, baseline/table alternatives and explicit non-normalized comparison. |
| Busy operations could still look “saved” | Import/reset/reload status now shows the operation and saving state; browser waits require genuinely settled pending0. |
| Same-looking records/groups made review/filtering ambiguous | Actual end datetime + ID suffix in session labels/review accessible names; group-accurate Unit title/region and native group filter. |
| Empty component bar had invalid ARIA; retained test copy was stale | No progressbar role/value without a real assessed number; updated real labels and retained axe scans, no exclusions. |
| Invalid draft/retry and corrupt stored copy threatened local work | Last-valid durable config separate from displayed invalid draft; retain prior valid memory report as unsaved without overwriting bad storage; explicit store tests. |

Final source review confirmed that `exerciseType`, conditions, weights and objectives affect the comparison's differing-settings disclosure. `priorKnowledge` is **not a ScenarioConfig field**; no speculative field or duplicate logic was added. Engine/scoring/replay/Worker/package/lock remain unchanged relative to Phase 4. No test-only interception hook is bundled. Screenshots represent actual test states, not fake performance data.

## Visual / accessibility evidence

Current checked viewports:1440×1000 desktop, 1024×768 laptop, 390×844 mobile-sized Chromium. Axe WCAG scans pass in tested named states, with **no rule exclusions**. Keyboard navigation/dialog focus, named scrollable tables, actual-view overflow assertions and real viewport captures execute. Desktop progress/unit/import/failure/comparison/quarantine and mobile progress/import/failure/reset plus laptop progress/unit/comparison/quarantine and the mobile actual AAR were inspected; further retained exercise/replay states were inspected during earlier gates. Mobile import screenshot is a tools viewport, **not a complete visible preview**; DOM/interaction/axe tests verify the below-fold preview. Small SVG text has table/queue/inspector alternatives. This is not a screen-reader study, exhaustive zoom/browser matrix or accessibility certification.

## Acceptance / remaining work

**No known failing critical implemented Phase 5 flow remains after the complete gate.** Full-product closure is intentionally not claimed:

1. **Official brief unavailable:** authoritative attachment needed before external requirement reconciliation.
2. **Phase 6 missing:** competency/weakness estimation and conservative explainable personalized next exercise, sparse/inconsistent-history holds and anti-repeat policy/tests.
3. **Phases7–8 open:** broader browser/assistive-technology/zoom/performance/failure hardening and actual demonstration rehearsal. Current regression success does not accept those full gates.
4. **Deliberate prototype limits:** unsigned origin-local history/manual JSON backup, no authentication/cloud, no legacy migration/active-run recovery/PWA cold start/operational sensor validity. Optional VR remains future work.

See [limits](LIMITATIONS.md), [storage contract](STORAGE_SPEC.md), [phase acceptance](PHASE_5_PLAN.md) and [implementation gates](IMPLEMENTATION_PLAN.md). Phase 5 source is checkpointed only after documentation, link/format/source review and post-documentation unit/build verification; the resulting hash is recorded in Git/delivery, not guessed in this report.
