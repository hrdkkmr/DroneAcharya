# Declared scoring rubric · rubric-1 / Phase 4 audited evaluation

This is a deterministic **synthetic training rubric**, not an operational effectiveness measure. One evaluator owns calculation and audit metadata; the UI does not compute a competing score. Interactive recorded replay and evidence-linked AAR are verified in Phase 4. Instructor decision-tree editing and historical comparison remain later work.

Phase 4 retains numerical **rubric-1 / generator-2 / sensor-2** and default fixture scores. **Schema 3** explicitly adds rule anchors and raw per-track audit traces (schema 2 archived at `70c947d`; no migration/import). Phase 3 conditions change available evidence, not the score formula. Capture age is displayed; sufficient support still uses clear deliveries at the relevant action, with no new age penalty. Stored thresholds, not hardcoded display text, explain each assessment.

## Inputs and eligibility
Inputs: the validated hidden scenario, its declared weights/thresholds, and a terminated, ordered session log. No wall-clock time, UI estimates, random score values or external model are used. An **eligible track** has at least one observation actually delivered before termination. Tracks with no delivered evidence are excluded from track denominators and all penalties. Delay is not counted as detection latency before the trainee could see a return.

Every event has a unique ID, session ID, strictly increasing order (starting at 1), integer simulation seconds, type and structured data. Paused/resumed actions may share a time but not an order. Inputs are structurally and statefully validated before evaluation. Observations arriving after a decision never improve the evidence available at that decision.

A **clear observation** has signal confidence ≥60%, resolved motion and resolved pattern. Sufficient evidence means at least two clear deliveries before the relevant action. Confidence is a synthetic display-quality indicator, not a probability of real-world correctness.

## Declared decision tree
1. A track must have a delivered observation before selection, tracking or a request.
2. Mark the track before assigning a broad category and confidence (integer 0–100).
3. Classification may be corrected until the first report; the final assessment is scored.
4. A report requires a recorded assessment and a trimmed 12–500 character summary. Reports are final for that track.
5. Unknown or fewer than two clear observations at reporting → **continue observation**.
6. Otherwise evaluator truth `review` → **training escalation**; evaluator truth `routine`/`background` → **routine log**.
7. Continuing observation instead of an otherwise supported disposition earns half decision credit; it is safer than unjustified escalation. No rule prescribes engagement or interception.

Public pattern guide: steady+regular → routine; variable+irregular → requires review; drifting+diffuse → background; unresolved or contradictory evidence → unknown. These are deliberately simple synthetic teaching cues, not signatures of real aircraft.

## Component definitions
All component scores are percentages. Track component denominators are the number **N of eligible tracks**, including unacted tracks (which earn zero), not just submitted actions. A missing track mark/assessment/report earns zero in that component. Scores are averaged across N. Default weights total 100%; configured weights must be finite, nonnegative, ≤100 each and total 100% (validation tolerance <0.001). Stored rubric weights must exactly equal declared configuration. Strict rubric validation requires all known fields, finite 0–3600s windows with deadline > grace, integer clear count 1–1000, percentage thresholds and individual penalty points 0–100; unknown/missing/mistyped fields are errors.

| Rule / component | Default weight | Per-track credit in [0,1] | Units / denominator |
|---|---:|---|---|
| D1 Detection | 20% | Latency L = first tracking mark time − first delivery time. Full credit at L≤5; `(30−L)/25` clamped to [0,1] thereafter. No mark →0. | L in simulation seconds; denominator N |
| C1 Classification | 20% | Final specific category matches truth →1; wrong →0. Unknown with insufficient evidence **at assessment** →0.75; unknown with sufficient evidence →0.5. | category credit; N |
| U1 Uncertainty | 15% | Unknown with insufficient assessment evidence →1, unknown with sufficient evidence →0.75. Specific category with insufficient evidence →0.25. With sufficient evidence: correct →1, wrong →0. | evidence-handling credit; N |
| R1 Reporting | 20% | `0.6 × timeliness + 0.4 × completeness`. Timeliness full at ≤15s after first delivery, then `(60−L)/45` clamped; after 60s →0. Completeness =1 for a valid final report (assessment, confidence and 12–500 character summary), otherwise0. No report →0. | report L in seconds, completeness fraction; N |
| Q1 Decision | 15% | Final report matches declared tree →1; `observe` when a different disposition is supported →0.5; other mismatch/missing report →0. | decision credit; N |
| O1 Objectives | 10% | Fraction of configured skill objectives whose unrounded component score is ≥70%. | objectives achieved / selected objectives (≥1) |

Component losses are explanatory weighted losses, **not extra subtractions**. Every nonzero component loss has its rule and actual observation/action/termination references. Missing events cite the first delivered observation plus termination as evidence of the elapsed opportunity, not a fictional missing action ID.

## Explicit additional penalties
Only the final assessment and final report per track are used; correcting an assessment before reporting is allowed. Penalties are applied once per eligible track/rule.

| Rule | Points subtracted | Trigger and event evidence |
|---|---:|---|
| P1 Unsupported certainty | 4 | Specific (not unknown) final category with confidence >70 but fewer than two clear deliveries before that assessment. References assessment + delivered evidence. |
| P2 Unjustified training escalation | 8 | Final disposition `escalate` when the tree does not support escalation. References report + assessment + evidence. |
| P3 Missed significant observation | 5 | Hidden significant track (truth `review`) was observed but has no final report by termination. References first observation + termination. Never applied to unobservable truth. |

## Total and edge cases
`weighted = Σ(weight × componentCredit)`. `final = clamp(weighted − Σ(explicit penalties), 0, 100)`. Calculate with full precision; round displayed metric scores, weighted contributions, deductions and final result to one decimal. Raw per-track credits/contributions and finding points retain precision; fractional penalties are summed **before** rounding, not independently rounded away. Minor displayed rounding differences are disclosed. There are no invented bonuses; full credits above are the only positive contributions.

- N=0: all components/final=0, no explicit penalties, explanation “No delivered evidence”; result not comparable.
- No actions with delivered evidence: zero earned components/objectives; applicable P3 only; bounded final0.
- Aborted early: compute the observed partial result but label it partial and `comparable=false`. Never treat it as a completed competency result.
- Timed completion: full duration elapsed; pending observations not yet delivered are excluded.
- Zero-weight components still report evidence but do not change total. At least one positive weight is guaranteed by sum=100.
- Duplicate/malformed/out-of-order events, impossible action transitions, nonfinite values and mismatched scenario IDs are errors, not silently scored.
- Pause has no wall-clock penalty; actions are unavailable while paused. Reset creates a new session and log after explicit discard confirmation.

## Audit anchors and replay agreement

Each metric/finding owns a rule ID, real anchor ID and real references. Per-track audits store unrounded credit, available `weight/N`, earned `credit×weight/N` and explanation. These are evaluator output, not a second grade.

- D1 anchors the tracking action; missing mark anchors actual Finish, with first delivery as opportunity.
- C1/U1/P1 anchor the final assessment and only prior deliveries; tracking/report IDs cannot masquerade as category evidence.
- R1/Q1/P2 anchor the report and only evidence available by then, plus assessment.
- Missing report/Q1 opportunity is explained using termination-time evidence; it **still earns zero** report/decision credit and applicable P3.
- P3 anchors Finish with first delivered observation. O1/E0 anchor Finish; unobserved tracks have no invented per-track credit/actions.
- A global metric collects its track references and deterministically anchors its lowest-credit track; objectives anchor Finish.

Links apply exactly through the anchor in the recorded log, including same-second order. The cursor map/inspector cannot include future deliveries/decisions; final evaluator answer tables are separately labelled post-exercise. A reference must exist; finding/per-track support cannot be later than its anchor.

Verification: retained26 + new41 scoring checks cover every penalty, timing/threshold edges, corrections, denominator/weight/objective/zero/mixed/abort and precision/strict-input cases. Default fixture scores remain 100, 95, 57.8, 0 and 84.3; these are controlled tests, not historical performance. Full gate and exact cases: TEST_RESULTS.md.

## Phase boundary
Evaluator categories, full declared rubric and score audit are exposed **only after termination** and hidden again while any live attempt is active. Read-only recorded replay/evidence links are implemented. Portable exports, persistence, cross-attempt statistics, instructor-editable tree thresholds and adaptive recommendations remain later work.
