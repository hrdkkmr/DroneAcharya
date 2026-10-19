# Recorded replay and AAR audit specification · replay-1 / schema 3

Written before Phase 4 integration; persistence notes updated at Phase5 and the current Phase6 gate retained below. Replay remains a read-only reconstruction of an actual terminated synthetic exercise, not regeneration, live telemetry or an alternative evaluator.

## Source and validation
`SessionRecord` remains the source. The simulation Worker creates the ordered log and one evaluation; AAR consumes those values. Replay validates termination, schema/version, matching record/session/status/end time, ordered events, transitions and real evaluator reference/anchor IDs. Invalid logs are rejected, not sorted, extended or silently repaired. Phase 5 now validates full supported portable/stored records separately (strict versions/shape, seeded definition, same evaluator and replay consistency). This is **consistency, not authenticity**. See STORAGE_SPEC.md; replay itself never regenerates/rescores.

`ReplayTimeline` owns a detached, immutable copy of public scenario metadata and recorded events, plus actual elapsed duration. It contains no hidden tracks/answer key, generator/trajectory function or evaluator. Public scenario projection is shared with the Worker through an explicit whitelist. `ReplayFrame` contains only the applied event prefix, recorded selection, last event and public observed view. Returned mutable view copies cannot corrupt the source record/timeline.

## Cursor and time
A `ReplayCursor` has integer `time` and integer `eventCount` (0 through total). The last applied event cannot be after time; the next unapplied event cannot be before time. Equal-time events can remain unapplied to inspect their precise order.

- Begin: `{time:0,eventCount:0}` before Start, with no observations/actions.
- Seek second t: clamp to actual elapsed duration, apply all events with `event.time <= t`, retaining their original order. No interpolation or guessed observations between events.
- Jump to event: apply exactly through that event's order, not all other events sharing its second.
- Next event: apply the next event and move to its time. Previous event removes the current event; from a gap it first returns to the last applied event. Begin stays before Start.
- End: actual final event and elapsed time, not configured duration for aborted runs.
- Playback: advance simulation seconds at chosen 1x/2x/4x; apply all due recorded events in original order, stop at the actual end. Pause/seek/jump/step stop automatic playback. Result switch/unmount tears down the timer.
- Zero-duration abort: Start, an optional recorded confirmation pause, and Finish can all be at 0. Exact event stepping still works; time scrubbing cannot distinguish these events. Do not divide by zero or invent duration.

Recorded pause/resume events may share a second; event stepping reveals each state. There is no recorded wall-clock pause length or speed-change event. Replay must disclose that it is simulation-time playback, not recreate those missing wall-time details.

## Evidence / state projection
Fold accepted actions with the existing evidence reducer. Fold recorded Start/Pause/Resume/Finish and sensor-change events for source status/health. Only delivered observations already in the prefix are visible. Maintain arrival-ordered history, newest capture as latest (delivery tie-break), capture-age stale, capture-sorted map breadcrumbs and actual source/delay. A delayed old arrival never rewinds or refreshes a marker. Undelivered attempts/pending returns/hidden truth never appear.

Map identity selection is an inspector choice, not a new trainee action. Show recorded selections separately. The replay map has explicit replay/empty presentation and no live pause overlay or fake listening state. Trainee assessment/report/summary are shown only once their recorded events have applied. No interactive training actions are present.

## Evaluator-owned audit trace
Schema 3 adds `EvaluationFinding.anchorEventId` and per-track metric audit records (rule/key, unrounded credit/available/earned, explanation, actual reference IDs and anchor). This is explanatory metadata, not another score. Model versions remain generator-2/sensor-2 and the score equations remain rubric-1.

- D1: first delivered observation + tracking mark; missing mark anchors Finish.
- C1/U1/P1: final assessment + evidence delivered before that action; missing assessment anchors Finish. Later evidence cannot support earlier certainty.
- R1: first delivery + assessment/report and relevant delivered evidence; missing report anchors Finish.
- Q1/P2: final assessment/report + evidence available before report; missing report anchors Finish and explains the branch supported by termination-time evidence (no report still scores zero).
- P3: first delivery + Finish, never a fictional missing-action ID.
- O1/E0: actual opportunities/terminal evidence; anchor Finish.

Every metric/finding reference must exist in the same recorded log. Per-track weighted credits use the eligible-track denominator, not submitted-action count. Component losses are explanatory; only explicit penalties subtract again. Strict rubric validation rejects missing/nonfinite/invalid windows/weights; use stored thresholds in explanations. Keep precision internally and round only display/result summaries, not before aggregating deductions. Default scores and final-assessment correction policy remain unchanged.

## UI and information boundary
Report summary remains the fixed terminal evaluation. Its links jump to exact recorded event order and highlight the same event in the full log; they never change the score. The declared rubric and track audits explain weights, thresholds, branch, timing, missing/excluded observations and contribution. Final evaluator answers are labelled post-exercise; replay evidence is labelled what had actually been delivered at the cursor.

Current and prior replay/answer components are not mounted while a live attempt is running/paused/disconnected. Read-only replay sends no Worker commands and writes no session/progress data. Phase 5 HistoryStore/IndexedDB now retain valid actual terminal records and supply private JSON/CSV/HTML/print operations separately from replay. Save/failure/quarantine/backup status is explicit. All private operations remain root-guarded while active; replay writes no history or score. No adaptive feature is implied.

## Verification requirements
Pure prefix-vs-source folding for every event/time; same-second before/after decisions; arrival inversions; isolated record mutation; deterministic seek/rewind/end; malformed/reordered/version/session/status/ref inputs; no-evidence/abort; full rubric boundaries/precision and every penalty; controller lifecycle; real-Worker browser penalty/absence/empty/active-lock/switch journeys plus all prior regressions, keyboard/axe/responsive/offline checks. Record actual results only after execution in TEST_RESULTS.md and PHASE_4_PLAN.md.


## Verified Phase 4 checkpoint
Historical `75e68a9`, 2026-10-17: **235 unit/component/protocol checks and 63 production-browser cases passed**, strict build/audit 0. Replay 30/controller 8/report 10 and audit 41 were added; real P1/P2/P3/empty-abort/active-lock/switch cases execute at 3 sizes, no replay commands/mutations. See TEST_RESULTS_PHASE_4.md / PHASE_4_PLAN.md. That checkpoint was memory-only; this is not the current lifetime claim.

## Phase 5 retained regression / persisted replay
Historical Phase5 full gate: **315 tests +93 production-browser cases**, strict build/audit 0. All prior replay cases remain. A real native-IDB saved report survives reload with the same score/events/replay; real JSON import/reset/merge restores the same actual record. Worker/engine/scoring/replay source and Worker asset remain unchanged from Phase 4. See TEST_RESULTS.md / QA_REPORT_PHASE_5.md. Phase6 now adds a separate history-derived planner slot outside the pure replay/report model; it cannot change that report’s result/events.

## Phase6 current retained regression
All prior replay cases pass again in the complete **369 tests +9 launcher checks +111 production-browser** gate. The actual offline next-exercise cycle preserves replay/event counts and immutable actual scores across native-IDB save/reload. No replay/engine/evaluator/Worker source changes or competing scorer were introduced. See TEST_RESULTS.md / QA_REPORT_PHASE_6.md / ADAPTATION_SPEC.md.
