# Phase 2 — one verified end-to-end exercise

**Historical Phase 2 gate passed: 2026-10-17, commit `44b269f`.** 102 unit/component tests, strict production build, 42/42 production-browser checks and npm audit with 0 reported vulnerabilities. At that checkpoint Phases 3–8 were unchecked. The later Phase 3 result is recorded in PHASE_3_PLAN.md and TEST_RESULTS.md; this plan preserves the Phase 2 scope.

## Entry audit

2026-10-17: Git was clean at Phase 1 checkpoint `4a36bee`. Reviewed the Phase 1 contracts, architecture, configuration editor, workspace state, shell, all screens, unit/browser tests and toolchain. The existing production preview was available. Preserved the foundation; no re-scaffold and no dependency additions.

## Scope / acceptance

- [x] A configured exercise starts from a meaningful briefing with a frozen active profile/configuration. Start is explicit; preparing a briefing never starts the clock.
- [x] A module Web Worker owns the hidden scenario, fixed-step clock, observations, actions and evaluation. Active snapshots exclude hidden tracks/trajectories/evaluator categories, rubric/weights and the future disruption schedule.
- [x] The unmodified curated **Perimeter watch** journey is playable through its full 90 simulation seconds at desktop/laptop/mobile-sized viewports. Configured count, seed, timing and sensor parameters are respected by the baseline engine, not ignored.
- [x] Delivered observations change with time; capture and delivery are distinct. A scheduled synthetic link disruption has real quality/delivery consequences. Coordinates are normalized training units, not operational locations.
- [x] Select → track → category/unknown + confidence → report is validated. Additional observation requests have a bounded cooldown and schedule a real capture attempt, not an invented return.
- [x] Pause/resume preserves simulation time/fractional remainder; playback speed does not change generated data. Reset confirms discard, clears this attempt/log and re-briefs the same configuration with a new session ID on Start. Early termination is aborted/noncomparable, never completed performance evidence.
- [x] Completion yields one deterministic baseline evaluation and the actual ordered log. Scored losses cite actual event IDs and declared rules; no fictional history, replay or recommendations.
- [x] Leaving the console pauses an exercise, active identity/configuration is protected, prior/current answer views lock, reload warns, worker failure is visible and cannot invent a result. A disconnected snapshot is explicitly labelled and discard/reset is available.
- [x] Domain/engine/scoring/worker/component tests, retained foundation regression tests, strict build and actual offline Chromium exercise/log-agreement journeys pass. Responsive label/status failures were fixed before checking this gate.

## Implementation order — executed

1. Extended shared contracts only where the integration needed a ready handshake and public presentation boundary. Wrote the baseline scoring rubric before the evaluator.
2. Implemented generator, bounded capture model, fixed-step clock, actual event projection, action validation and pure evaluation; executed module tests/build.
3. Implemented worker runtime/host/bridge; tested commands, clock transitions, errors and serialized observation-only snapshots. No UI-thread simulation fallback.
4. Connected live console, track workflow, briefing, terminal review and truthful memory-only result lists/counts; executed component tests/build.
5. Completed real browser exercises, exact log/result agreement, reset/abort/navigation/profile/error checks, responsive/keyboard/axe checks; inspected actual screenshots and updated documentation. Git checkpoint follows this verified gate.

## Evidence

- `src/engine/engine.test.ts`: 27 checks.
- `src/scoring/evaluate.test.ts`: 26 checks, including mixed observed/hidden eligibility.
- `src/workers/runtime.test.ts`: 6 checks.
- Retained config/contracts/App/dialog tests: 43 checks; unit/component total **102**.
- `tests/e2e/exercise.spec.ts`: 5 journeys × 3 viewports = 15 checks; retained foundation 27; browser total **42**.
- Complete exercise network disabled after local worker load; UI score/metrics/counts/log IDs compared with the actual terminal worker record.
- `docs/screenshots/phase2-{console,result}-{desktop,laptop,mobile}.png`: actual served-build captures.
- TEST_RESULTS.md records the final combined command, failures investigated and verification limits. SCORING_RUBRIC.md declares baseline equations/penalties.

## Boundaries / what is not claimed

A small seeded generator and synthetic effects are necessary foundations for a reproducible Phase 2 exercise. **Phase 3 still needs its wider variation/demo acceptance.** The baseline score/full actual log is not the full **Phase 4 interactive replay/AAR** product. Phase 5 IndexedDB, portable imports/exports and historical/unit analytics, Phase 6 adaptation and all ML claims remain out of scope. Accessibility evidence covers current states; it does not complete the wider Phase 7 gate.

Records remain in root memory only and disappear on reload. Source/devtools inspection cannot be prevented by a local browser worker; observation separation is not adversary-proof examination security. No operational targeting/engagement capability is included. Implementation stops at Phase 2.
