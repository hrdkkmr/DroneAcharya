# Phase 4 — recorded replay and evidence-linked after-action review

> Historical accepted checkpoint `75e68a9`. The stop/memory-only statements here describe that phase, not the current app. Phase5 was subsequently authorized; see PHASE_5_PLAN.md.

## Entry audit / authorization
2026-10-17: user authorized Phase 4 conditional on completed Phases 1–3. Verified clean main at `70c947d`, earlier `44b269f` / `4a36bee`, checked prior executed gates, dependencies/scripts/config, source/domain/engine/Worker/evaluator, UI/routes, tests and deployment. Existing production preview on 5173 returned HTTP 200. Fresh baseline **146/146 (15.89s)** and strict build (bundling **3.97s**) passed before implementation. Preserved existing work/captures; no dependency or scaffold replacement. No subagent facility was available.

Only Phase 4 was authorized. **Stop at its verified checkpoint.** No storage/export/history analytics/adaptive policy, operational-validity, production-readiness or competition-placement claims.

## Contracts agreed before code
- One authoritative simulation Worker and **one evaluator**. Replay is a read-only projection of a terminated record, not an engine/seed/model run, live command source or competing score.
- Evaluator-owned rule anchors and raw per-track credit/contribution traces explicitly change serialized contracts to **schema 3**. Retain **generator-2 / sensor-2 / rubric-1** because generation and numerical equations are unchanged. Schema 2 stays archived at `70c947d`; no legacy import/migration.
- Preserve credits, final-assessment correction policy, once/track penalties, eligibility/bounds/default scores. Strict complete finite rubric fields, stored weights/thresholds and real action-specific references; aggregate before rounding. Missing-report explanation can use termination-time evidence but **still earns zero** report/decision credit and applicable P3.
- Cursor `(integer simulation time, applied event count)` distinguishes equal-time decisions. Time scrub includes all events through a second; exact jump/step preserves order. Begin before Start; end at actual Finish, including aborted/zero-duration.
- Validate termination/order/transitions/schema/session/status/duration/references. Reject rather than sort/repair malformed history. Fold delivered public evidence, newest capture, recorded health/status/selection and accepted actions; no hidden truth/future prefix.
- Full recorded timeline and separately labelled evaluator answers are post-exercise only. All current/prior answers/audit/replay are locked before mount during a live attempt.
- Original wall-clock pause lengths/speed changes are unlogged and not reconstructed. Playback paces simulation seconds only.
- Accessible read-only transport/range/event steps, actual-event timeline/map/inspector and metric/finding/audit/log links. No record/score/progress mutation or Worker command. Clear timers on unmount, reset safely on result switch. Memory-only lifetime remains explicit.

## Acceptance gate
- [x] Pure validated recorded-prefix replay, same-second actions, genuine out-of-capture-order arrivals, requests/gaps/disruption/pause, abort/empty/terminal cases; no regeneration/future-prefix leakage.
- [x] Start/end/seek/step/play/pause/speed and event/finding/metric/audit links/result switching; keyboard controls, no mutations/live commands and honest state.
- [x] Declared rubric and per-track credits/denominators, real action-time anchors, no double subtraction/NaN/malformed-log repair.
- [x] Every penalty, timing/threshold/correction/objective/weight/rounding/zero/mixed/abort case; retained fixture scores unchanged.
- [x] Retained 146 unit/component and 51 browser checks, with explicit schema 3 assertions; new 89 unit/component/controller and 12 browser checks pass.
- [x] Strict production build, npm audit and production-browser desktop/laptop/mobile offline journeys, score/log/frame agreement, keyboard/axe/overflow and visually inspected captures. Prior images untouched.
- [x] Current product/architecture/rubric/replay/traceability/gates/progress/results/limitations/deployment records updated; verified Git checkpoint recorded in delivery/log. Stop after Phase 4.

## Executed acceptance
Full command, exit 0: `npm run test && npm run build && npm audit && npm run test:e2e -- --workers=2`.
- **235/235** unit/component/protocol checks, 14 files, **19.76s**.
- Strict TypeScript/Vite 7.3.7 production build: **1625 modules**, bundling **3.70s**.
- **0 audit vulnerabilities reported**, manifests unchanged.
- **63/63 production-Chromium checks**, 21×3 viewports, two workers, **about 6.0 min**, zero retries; combined tool duration **391.659s**.
- Unmodified 90s/120s/150s presets complete offline; actual score/metrics/ordered events agree. New real-Worker P1/P2/P3/empty-abort/active-lock/switch replay journeys pass; original record stays identical and replay sends no commands.
- **39 Phase 4 viewport captures**; inspected desktop replay, laptop audit and mobile replay/inspector/empty states. Phase 1–3 images preserved.
- Fixed highlighted log contrast, actual confirmation-pause expectation, async new-session wait, scoped timeline icon CSS and padded audit; changed capture helper to respect the workspace scroller. No failing regression or accessibility rule removed. Full details and asset hashes: TEST_RESULTS_PHASE_4.md.

**Phase 4 acceptance passed.** Memory-only reports remain. Phase 5 is the next dependency and is not started or authorized by this checkpoint.
