# Synthetic scenario and sensor model · generator-2 / sensor-2

Phase 3 model specification, written before model integration. All positions and behaviors are fictional normalized teaching data. Not a physical sensor, aircraft signature model, engagement tool or measured detection-performance claim.

## Version / reproducibility
This Phase 3 model introduced schema 2: required `trafficPattern` and delivered `source: scheduled | requested`. Current **schema 3** adds Phase 4 evaluator audit metadata without changing generator-2, sensor-2, the formulas below or numerical rubric-1. Phase 2/schema-1/generator-1 is archived at `44b269f`; Phase 3/schema-2 at `70c947d`. No legacy import/migration or persistent history exists.

Mulberry32 and FNV-1a seed tools remain. Canonical validated configuration + version label form the scenario identity. One stream generates categories/individual values; an independent seeded layout stream builds crossing/group motion. Per-track/per-capture dropout, quality, position and delay draws use separately labelled seeds. No Math.random, wall clock, rendering cadence or mutable global RNG is used. Same versions/configuration/seed and simulation-timed commands yield the same definition, observations, ordered log and evaluation. Different action timing can change a score.

## Patterns / bounds
- Independent: 1–8 separate paths, seeded heading/speed/origin/phase.
- Crossing: 2–8 paths share a seeded central reference region/time; initial position is derived from heading and crossing reference. Speed is bounded relative to duration so origins stay in the training space. Wavy category-dependent motion makes this a near-crossing, not identical tracks.
- Grouped: 3–8 returns share a seeded velocity, phase and close initial offsets. Categories remain independent. Similar motion/proximity is not evidence of a category or threat. This is a swarm-like visual observation challenge, not coordinated adversarial tactics.
- First spawn is second 1. Others are seeded/bounded; all end at configured duration (60–300s). Coordinates reflect inside [5,95]; observed noise is separately clamped to [0,100]. Difficulty adds a bounded speed increment; no automatic difficulty policy exists.
- Primary curated configurations: Perimeter watch (rural/day/clear/independent1), Urban ambiguity (urban/dusk/haze/crossing3), Nightfall protocol (rural/night/rain/grouped4). Rural crossing is a fourth preset. Each can be reloaded to its curated seed or varied with the existing next-seed control/custom editor.

## Public condition model
Let R be configured reliability [.35,1], N configured noise [0,.3], D configured delay [0,8]. Apply these public additions/factors:

| Condition | Return multiplier | Noise addition | Confidence loss | Fixed delay addition | Jitter max addition |
|---|---:|---:|---:|---:|---:|
| Rural / daylight / clear | 1 each | 0 | 0 | 0 | 0 |
| Urban | .9 | .03 | 6 | 1s | 2s |
| Dusk | .96 | .01 | 2 | 0 | 0 |
| Night | .9 | .025 | 5 | 1s | 1s |
| Haze | .93 | .02 | 2.45 | 0 | 1s |
| Rain | .85 | .04 | 5.25 | 1s | 2s |

Nominal return setting = R × applicable multipliers. Nominal noise = min(.6, N + additions). Nominal fixed delay = D + additions. Jitter is an independently seeded integer from 0 through min(4, summed jitter maxima). These are **model parameters, not observed recall/precision or real-world probabilities**. The UI labels settings separately from measured delivery facts.

Two static public hatched urban rectangles, documented in `domain/conditions.ts`, model teaching clutter. A hidden true position inside one reduces return consistency by ×.65, adds .03 noise, loses 6 confidence and adds 2s delay. The map shows only schematic zones and delivered observations—not hidden positions or a future path.

One seeded 18-second link disruption begins at second12–16. While degraded: consistency ×.3, noise ×1.8 + .04, confidence −28, delay +2s. A capture's quality/delay stays tied to capture time even if the link recovers before delivery.

## Capture algorithm / requests
Regular attempts occur every 4s from each track's spawn. A valid request schedules an attempt 2s later with an 8s cooldown; coincident regular/request captures coalesce into one requested attempt.

- Actual return threshold = clamp(nominal setting × clutter factor × disruption factor + requested .12, .05, 1).
- Independent dropout draw above the threshold yields **no observation**. No hidden failed-attempt counts are sent to the UI.
- Noise = clamp(nominal noise × disruption multiplier + disruption addition + clutter addition, 0,.6); a requested attempt then uses ×.75 noise.
- Confidence = round(clamp(95 − 120×noise − 28×(1−R) − condition losses − clutter6 − disruption28 + requested8 + uniform[−6,6), 12,98)). Synthetic display quality, not calibrated confidence of correctness.
- Observed x/y = true synthetic x/y plus independently seeded uniform ±10×noise, rounded to .01 and clamped [0,100].
- Uncertainty = round to .1 of clamp(2 + 25×noise + (100−confidence)/20, 1,25).
- Confidence ≥60 resolves the deliberately simple public category cues; lower quality yields unresolved cues. Scoring still needs at least 2 clear deliveries before a specific assessment is supported.
- Delay = fixed condition delay + independent integer jitter + clutter2 + disruption2. Absolute bound: 0–19s for validated settings. A request is identified as `source=requested` **only after delivery**, never as a guaranteed pending return.

## Ordering / stale semantics
Log is ordered by actual delivery/command time, with strictly increasing event order. Equal delivery times are deterministically ordered by track and capture. Jitter can deliver an older capture after a newer one: retain it in delivery history, but the map's latest observation is the **newest capture**, never simply the last arrival. History paths are sorted by capture time before drawing. Stale uses `now − capturedAt >10s`; capture age, arrival time and measured delay remain separately visible. No extrapolation of a hidden position.

Requested-source log entries must reference an earlier matching request/capture time; scheduled-source captures must align with the regular schedule. Pending deliveries beyond termination are not shown or counted as delivered. Pause freezes capture, delivery and request cooldown in simulation time; reset discards pending queues with a fresh engine.

## Verification gate
Reproducibility, variation, counterfactual single-factor effects, group/cross geometry, many-seed extreme bounds, versioning, no cross-session interference, request success/failure/coalescing, out-of-order capture safety, stale/delay age, pending termination and observation-only serialized snapshots require automated checks. Three curated production-browser journeys must demonstrate real changing evidence and distinct presentation, not just titles. Actual results are recorded only after execution in TEST_RESULTS.md / PHASE_3_PLAN.md.

## Verified Phase 3 result
The model/presentation gate passed on 2026-10-17: 146 unit/component tests (including 32 new model checks and 12 evidence/label checks), strict production build, 51 production-browser checks and npm audit with 0 reported vulnerabilities. All three primary curated exercises completed offline after code loading at desktop/laptop/mobile sizes. Actual event IDs, scores, counts and delays agreed with Worker records; observed label decluttering did not move markers. Exact commands, bounds coverage, investigated failures and limits are in TEST_RESULTS.md. This does not validate real-world sensor performance or complete later gates.
