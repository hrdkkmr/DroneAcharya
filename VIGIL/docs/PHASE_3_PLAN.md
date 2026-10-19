# Phase 3 — meaningful, reproducible scenario and sensor variation

**Historical verified checkpoint `70c947d`.** This plan preserves the Phase 3 scope and authorization. Current Phase 4 acceptance is in PHASE_4_PLAN.md / TEST_RESULTS.md.

## Entry audit / scope
2026-10-17: audited clean Git checkpoint `44b269f`, shared types/configuration, engine/sensor/clock/evidence/log, worker/bridge, rubric, all affected UI, retained tests, scripts/dependencies/deployment and prior gates. Production preview responds on 5173. Preserve Phase 1/2 and their screenshots; no scaffold replacement or new dependency.

Only Phase 3 is authorized. The quality target is a defensible, competition-ready synthetic prototype; production readiness or competition placement cannot be guaranteed. Full replay/AAR, storage/exports/analytics and adaptation remain later gates.

## Contract and ownership decisions (before implementation)
- One existing authoritative Worker and one evaluator remain. No UI-generated truth or duplicate scoring.
- Add a validated public `trafficPattern`: independent, crossing (at least 2 tracks), grouped (at least 3). Perimeter day / urban dusk crossing / rainy night grouped are meaningfully distinct; rural crossing remains a fourth option. Curated configurations + procedural seeded variation, not tactical behavior.
- Bump serialized contracts to **schema 2**, generated definitions to **generator-2**, and synthetic sensor behavior to **sensor-2**. New observation provenance (`scheduled`/`requested`) and required pattern are explicit changes, not silent regeneration under generator-1. No persisted/imported schema-1 records exist; do not claim a migration or backward import feature. Phase 2 code/evidence stays in Git.
- Public condition functions/constants may describe model settings and static schematic clutter zones; hidden trajectories/categories/future disruption still never cross the active boundary. Patterns are declared exercise settings, not hidden answer labels.
- Separate independently seeded dropout/quality/position/delivery draws. Weather, lighting, urban clutter and scheduled disruption change actual returns/uncertainty/delay. Requests remain bounded, can fail and only identify their provenance after delivery.
- Delayed arrivals may be out of capture order. Retain delivery order in the real log/evidence list, select the newest captured observation as map position, and use **capture age** for stale state. A late old return must not rewind a marker or make old data look current.
- UI additions: meaningful pattern controls, condition explanations in Lab/briefing, public weather/clutter layers, actual delivery monitor and delivered-evidence/request trace. No hidden miss-rate/recall or fake telemetry.

## Acceptance
- [x] Three curated day/dusk/night journeys show distinct live presentation and measurable delivered-evidence differences; no label-only presets.
- [x] Independent/crossing/grouped behavior is real, seeded, bounded and honors count/duration/difficulty; custom invalid combinations show helpful errors.
- [x] Same version/config/seed and simulation-timed commands reproduce identical definitions/evidence/log/evaluation regardless of speed, chunking or concurrent unrelated sessions. Seed changes vary actual paths/timing, not just ID.
- [x] Noise/reliability/delay/lighting/weather/clutter and disruption affect the actual delivered model, with documented formulas/bounds and isolated-factor tests.
- [x] Real request attempts, cooldown, success/failure, schedule coalescing and provenance are verified; pending/failed/late evidence is not invented.
- [x] Capture/delivery separation, late-arrival ordering, newest-capture map semantics and stale ages are verified, including pause/reset and pending-at-termination cases.
- [x] Active Worker snapshots remain observation-only for all presets/patterns; no hidden path, private answer/rubric or future schedule leaks. Diagram/monitor consumes only delivered evidence/public configuration.
- [x] Retained 102 unit/component checks plus new tests, strict build, production Chromium journeys across desktop/laptop/mobile, keyboard/axe/overflow and offline checks pass; failures fixed without deleting tests.
- [x] Actual results/screenshots, architecture/model/rubric/traceability/limitations/progress docs updated and clean Git checkpoint created. Stop at Phase 3.

## Execution sequence
1. Contract/config and deterministic model specification.
2. Generator/sensor, stable delayed evidence, provenance validation; unit/worker tests and build.
3. Connect condition/pattern/evidence UI without scoring/clock ownership changes; component tests.
4. Production browser completion/visual/evidence checks for all three primary presets, seed rerun/requests and all regressions; fix failures.
5. Final combined gate, documentation, inspected screenshots and Git checkpoint. No Phase 4 implementation.

## Executed closeout (2026-10-17)
- Preserved baseline `44b269f`, all 102 earlier unit/component and 42 browser regressions, prior captures and dependency graph. No paid service/backend/agent infrastructure added.
- Implemented schema 2 / generator-2 / sensor-2 and public condition/provenance contracts; rubric-1 unchanged. Added 32 model checks and 12 public evidence/label checks.
- Final combined command `npm run test && npm run build && npm audit --audit-level=moderate && npm run test:e2e` exited 0: **146/146** tests (10 files, 15.71s), strict build (1615 modules, bundling 3.52s), **0 audit vulnerabilities**, **51/51** production-Chromium checks (17 × 3 viewports, about 7.3min, zero retries).
- All three unmodified primary presets completed offline after Worker readiness, with real score/metric/event-ID agreement. Same-seed reset and next-seed evidence variation, requests/cooldown/provenance, actual monitor counts/delay, newest-capture markers, invalid pattern correction, keyboard/axe/overflow and retained error/lifecycle checks passed.
- Inspected actual dusk/night/grouped and laptop/mobile views; separated overlapping identity labels without moving actual evidence. Captured 24 Phase 3 production-browser images; earlier captures remain untouched.
- Initial short regular-only inversion sample and redundant test-only TypeScript role-query option were corrected without weakening assertions or changing the model to force results. Capture-age/breadcrumb ordering hazards were fixed before the full gate. Details: TEST_RESULTS.md.
- Updated README, product/model/architecture/traceability/rubric/gates/progress/verification/limitations/deployment. Git checkpoint identity is in the delivery response/log, avoiding a self-referential hash here.

**Phase 3 acceptance passed. Stop here.** Phase 4 requires new authorization. No full replay/AAR, durable persistence/import-export, historical analytics or adaptive policy is claimed.
