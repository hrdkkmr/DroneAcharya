# Explainable local adaptation · rules-1

Implemented in `src/adaptive/policy.ts`; presentation in `NextPractice`, guarded application in `useWorkspace`. This is a **deterministic teaching heuristic**, not ML, a calibrated competency probability, mastery certification, normalized learner ranking or evidence of real-world readiness. No model weights/training/accuracy or learning-effectiveness claim exists.

## Authority and eligibility

`recommendNext(records, savedIds, profileId)` is pure: same validated inputs give the same output, independent of array/Set ordering. It uses no clock, network, scenario generation, evaluator invocation, live truth or record mutation. It reads the existing evaluator's five skill credits, not a second scoring system. Only the selected profile's **acknowledged saved + completed + comparable** actual records inform performance.

Unsaved/in-memory, aborted, completed-with-no-delivered-evidence and other-profile performance is excluded. Quarantined invalid rows never enter the validated record input. Counts/reasons disclose exclusions. Aborted/no-evidence attempts remain reviewable. Their saved seeds are used **only to avoid repeating evidence**, never to infer ability. Initial history contains zero reports and empty competency estimates are `null`/`—`, not initialized zero scores.

Input records have already passed the shared strict storage/portable validation. For a valid comparable record, every skill metric has the same positive delivered-track eligibility denominator; a missing action has actual credit0, not absent component evidence. A contract-violating/nonfinite skill metric throws rather than fabricating an estimate. Such records are rejected/quarantined at the persistence boundary, not accepted as ordinary input.

## Context, independent sample and estimate

1. Deduplicate session IDs and sort by actual `endedAt`, then stable codepoint session-ID order on ties. A tie is explicitly not an inferred real-world sequence.
2. The **latest eligible actual configuration** is the baseline, including its actual difficulty. With no eligible performance, use the genuine Level1 foundation (`PRESETS[0]`), not a fictional weakness.
3. Matching context includes exercise type, difficulty, environment/light/weather, reliability/noise/delay, pattern/track count, duration, weights and objective set. Ignore only seed, cosmetic preset ID and objective order. There is no normalization across changed contexts.
4. Within this context keep the **latest actual attempt per distinct seed**; then the latest at most5 such samples. This is intentionally stricter than scenario-ID dedup: changing a cosmetic preset label at the same seed cannot inflate independence.
5. Each skill estimate is its arithmetic mean of existing metric `score` values over this window. Return the actual values, range/spread, sample n and source session IDs. Estimates are displayed to one decimal; decision arithmetic uses the existing metric values, not displayed-rounded means.
6. Choose the lowest mean. Ties use shared `SKILLS` order: detection, classification, uncertainty, reporting, decision. A high minimum is consolidation, not a declaration of deficiency or mastery. No history selects detection only as an introductory workflow focus.

Internal sample labels: provisional below3 or when spread>20; developing for3–4 samples with spread≤20; established for5 with spread≤20. UI calls the last label **Repeated sample**, not statistical confidence. A table shows actual score ranges; broad descriptive historical means remain a separate view.

## Conservative difficulty decision

Consider the **latest3 eligible actual attempts**, not three cherry-picked favorable/independent results from older history. Rule precedence:

| Condition | Rule / action |
|---|---|
| No eligible completion | `foundation`, Level1, no inferred skill |
| Fewer than3 eligible actual attempts | `sparse`, hold baseline level |
| Any of those3 has a different context | `mixed-context`, hold |
| Fewer than3 distinct seeds among them | `repeated`, hold |
| Total-score spread **or any of five component spreads** >20 points | `inconsistent`, hold |
| Every total≥80, every skill≥75, every explicit penalty total=0 | `increase` exactly1, or `ceiling` hold at5 |
| Every total<55 and weakest current-window estimate<60 | `decrease` exactly1, or `floor` hold at1 |
| Otherwise | `consolidate`, hold |

These are fixed public teaching thresholds, not empirically calibrated pedagogy. Difficulty remains within1–5. Every recommendation exposes baseline→next level, rule/reasons and all current-window/decision-source report links. In particular a single noisy/high/low result cannot raise the level. Sparse evidence takes precedence over a mixed-context diagnosis when there are only two attempts; both context exclusion and sample n remain disclosed.

## Next configuration and non-repeat

Preserve baseline environment/light/weather, sensor settings, pattern/count/duration and weights. Set `presetId=custom`, targeted objective only, and teaching exercise type: detection→observation; classification/uncertainty→assessment; reporting/decision→reporting. A no-history foundation retains its normal full objective set.

Start the next seed at `(lastEligibleSeed +7919) >>>0`; with no eligible result start at the foundation seed. If already used by **any saved attempt of that profile**, advance by7919 modulo2^32 until unused. This odd stride traverses uint32 values; return a validated bounded config or an explicit failure, never silently repeat. Imported older seeds and aborted/no-evidence seeds participate in avoidance. This is novelty within known local saved history, not global uniqueness or resistance to source inspection. A manually chosen repeated seed remains allowed for reproducibility, but will not inflate the policy's independent sample count.

## Root / UI lifecycle

Home, Individual progress and the active profile's AAR mount the planner. A different-profile report does not silently switch learner or apply that report's plan. Individual progress additionally shows the five heuristic estimates separately from descriptive analytics. Reasons expand to actual source-report controls. Manual Lab configuration remains available.

Planning/estimate details are not mounted while running, paused or disconnected-active. No plan is supplied while history loads, writes, imports/resets/retries, has errors/pending work, lacks an acknowledged saved state or has a known peer-tab change awaiting reload. HistoryStore marks same-epoch peer notices with an ephemeral needsReload flag; only actual successful reload/reset clears it, not a local preferences write. Current and stale apply callbacks also check it. A newer actual weak report therefore cannot be ignored in favor of an older strong snapshot after notification. Without BroadcastChannel there is no automatic peer-change discovery; explicitly reload before planning when using multiple tabs. This is not global synchronization. Unsaved-report recovery retains the actual AAR but cannot use its score for adaptation.

**Review recommended exercise** calls a root handler that synchronously checks the live guard and obtains a fresh HistoryStore snapshot. It recomputes for the currently selected profile rather than trusting caller-supplied/stale settings. Only then does it save the new valid draft, freeze the briefing and navigate. **It never starts an exercise.** Start remains a separate explicit action. A stale callback after a profile change reads the new profile; a stale callback in the Start event is blocked.

Preparing a next/manual terminal briefing clears presentation state while retaining the healthy, already loaded authoritative Worker. A subsequent explicit Start sends a new validated configure/start; Runtime refuses replacement while active. This permits a second actual exercise after network disconnection. Confirmed **Reset exercise** is different: it discards/recreates the Worker. A failed/lost Worker or fresh document still needs its module source; no service-worker cold-cache promise is made.

Recommendations are derived, **not persisted as immutable historical decisions**. Reports/portable schema remain3, generator-2/sensor-2/rubric-1/replay-1 unchanged, DBv1/portable-format1 unchanged. Revisiting a report may show a newer plan based on all currently saved eligible history. Stored evaluator results never change. JSON/HTML/print continue to represent the actual report, not a later inferred plan.

## Executed evidence

- 36 policy cases using actual-engine/evaluator terminal records: validity, all five target types, genuine no-delivery/abort/unsaved/profile exclusions, empty/sparse/strong/weak/noisy/penalty/context/objective/weight/seed/dedup/bounds/immutability and exact80/75 teaching thresholds.
- 9 planner component cases: nulls, actual source links, manual choice/review, active/saving failure locks, errors and heuristic/table labelling.
- 8 added root integration cases (16 total): fresh apply/frozen briefing/no auto-start, actual persisted Runtime record, stale profile callback, synchronous Start/paused guard, pending/unavailable recovery and import/reset. Healthy Worker reuse asserted; no score mock.
- 6 new real-module-Worker/native-IndexedDB journeys ×3 viewports: empty/manual override; **offline completion→saved AAR→sourced plan→explicit briefing→second actual completion→reload**; three genuine qualifying attempts→one-level increase→profile isolation→real JSON reset/import→same plan; active locks/abort exclusion; actual unsaved completion withheld until retry acknowledgement; peer completion→withheld older planner→native reload→exact new source evidence.
- 1 additional Store case proves same-epoch invalidation, retained acknowledged records, no clearing on local writes and actual reload/merge.

The full **369 unit/integration/component +9 launcher +111 production-browser** gate passed on2026-10-17. Tests establish the stated local rules/flows, not training efficacy or official conformance. See [results](TEST_RESULTS.md), [QA](QA_REPORT_PHASE_6.md) and [limitations](LIMITATIONS.md).
