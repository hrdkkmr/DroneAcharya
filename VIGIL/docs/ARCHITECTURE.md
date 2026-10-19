# Architecture · schema 3 / Phase 6 handoff

**Status:** Phases 0–6 accepted in the tested local scope: one authoritative Worker, seeded conditions/evidence/actions, deterministic evaluation, actual-event replay/AAR, validated native IndexedDB history, portable reporting and actual descriptive analytics. **rules-1 now derives explicit heuristic estimates/next practice from actual acknowledged saved history; no ML or second scorer.** Full official conformance is unverified (no official attachment, portal 403); broader gates 7–8 remain open. See QA_REPORT_PHASE_6.md / REQUIREMENTS_TRACEABILITY.md.

## Decisions
React 19 + TypeScript + Vite; hand-authored CSS/local SVGs/icons; Zod validates configuration/actions/commands/events and strict portable/storage boundaries. No backend/remote API/main-thread engine fallback. Native IndexedDB and actual SVG/data-table charts are connected; fake-indexeddb is test-only, Recharts remains an existing unused dependency rather than a claimed chart implementation. No dependencies added in Phases2–6.

## Boundaries and ownership

| Directory | Responsibility / current state | Inputs → outputs |
|---|---|---|
| `domain` | Schema-3 contracts, strict schemas, public condition constants/evidence facts/teaching thresholds | external values → validated data; public settings/events → display facts |
| `engine` | Mulberry32/FNV tools, generator-2, sensor-2, fixed clock, ordered log/evidence state | validated config + commands/steps → public snapshots / terminal record |
| `workers` | Authoritative engine lifetime and monotonic wall-clock scheduling | validated commands → ready/view/completed/error messages |
| `scoring` | strict rubric-1 and one evaluator; raw credit/contribution audit with real anchors; numerical equations unchanged | hidden scenario + terminated valid log → event-linked evaluation |
| `replay` | Validated detached public timeline and exact prefix projection | terminated record → immutable model → `(time,eventCount)` public frame |
| `hooks` | Worker bridge, playback, root route/briefing/lifecycle and private-operation integration | public/terminal messages → UI/HistoryStore; pacing → cursor; no competing score |
| `components`, `pages` | Editor/briefing/console/monitor, linked AAR/replay/audit, HistoryStatus/Tools, actual progress/groups/export/print | public views / allowed terminal history → accessible UI |
| `persistence` | Strict profile/record/bundle validation, native-IDB repository + serial observable HistoryStore | actual terminal records/profiles/valid preferences ↔ transaction-acknowledged history/quarantine |
| `analytics` | Descriptive actual saved/completed/comparable summaries and JSON/CSV/HTML/print helpers | actual records + acknowledged IDs → means/n/missing/trend/difficulty/raw comparison/escaped exports |
| `adaptive` | Pure deterministic rules-1; bounded competency/target/context/difficulty/seed policy | actual validated completed saved profile history + acknowledged IDs → nullable estimates/evidence/reasons/next valid config |

## Authoritative state and transport

`SimulationEngine` owns the hidden definition, status, simulation time, pending captures/requests, delivered evidence, accepted actions, ordered log and evaluation. Components do not generate track truth, advance time or compute a competing score. Root workspace owns route/frozen briefing and the Worker bridge. A single `HistoryStore` owns profiles/configuration draft and last-valid durable config, selected identity/report, actual detached terminal history, pending changes/saved acknowledgements, operation/error/quarantine state. `useSyncExternalStore` subscribes React; no page maintains a competing history/score store.

`simulation.worker.ts` hosts one `SimulationRuntime`, polling every 100ms. `useSimulation` eagerly loads this local module and handles readiness, but **only Start configures and starts an exercise**. The bridge has an 8-second start timeout, capability/load/decode/error handling and teardown/recreation on reset. Preparing another terminal/manual briefing clears presentation but retains a healthy loaded Worker, enabling a second actual offline exercise; explicit reset still recreates it. No Worker means an explicit error, never replacement telemetry or an invented score. Fatal transport failure retains the last public snapshot, marks it disconnected and disables commands except explicit discard/reset; the unfinished attempt cannot be recovered or scored from that snapshot.

Runtime validates commands and ticks to command arrival time at the **old** speed before applying pause/resume/speed/actions. Reconfiguration cannot overwrite a running/paused attempt. One terminal `completed` response carries the record and matching public log. That protocol message can carry either a timed `completed` or early `aborted` record; record status is authoritative.

## Information flow / isolation

Current path:

`validated configuration → Worker hidden definition → fixed steps → capture/dropout/noise/jitter → delivered observations → validated actions + ordered log → one evaluator → actual terminal record → immediate retained AAR/replay → validated IndexedDB transaction acknowledgement → actual saved descriptive progress / portable reports`.

Connected planning path: `acknowledged eligible saved profile history → matching-context heuristic means/source evidence → conservative rules-1 next configuration → explicit review/frozen briefing → separate Start → authoritative Worker`. Root recomputes from the latest snapshot and synchronously guards active/stale/pending/error cases; no caller-supplied stale configuration is applied. Planning does not mutate records, evaluate or generate truth. Manual Lab controls and descriptive analytics remain separate.

`domain/publicScenario.ts` explicitly whitelists allowed fields rather than spreading a private definition. Active responses contain public settings/model versions, delivered `TrackEvidence` and actual public events. They exclude hidden tracks/positions/velocities/categories, rubric/weights, path-layout phase/center and future disruption schedule. Declared independent/crossing/grouped patterns are public exercise settings, not category answers. User-entered assessment categories are public actions.

`domain/conditions.ts` owns public condition factors and static schematic clutter rectangles used by both sensor and presentation. Public geometry is not a hidden trajectory. `SensorSummary` derives labelled model settings, not measured accuracy. `DeliveryMonitor` folds only delivered event IDs/times/sources, with a real denominator for mean delay and a 30-second arrival plot. No hidden attempted/missed-return count, detection recall or guaranteed return is inferred.

The map uses the newest captured public observation, not extrapolated truth. Capture-sorted breadcrumbs connect observed samples only. Label decluttering changes identity-text positions/leader lines, **never marker coordinates**, and receives only public latest observations. Weather/clutter art is static, not a simulated sensor feed. `TrackWorkspace` separates capture age, arrival time, measured delay and delivered provenance; request status confirms a return only after its event exists.

Only termination/reset unlocks private `SessionRecord.scenario` and evaluator categories. AAR locks current **and prior** answers/replay before mount. Root API guards use a synchronous active ref set at Start to also block stale export/import/reset/print/profile/config/review callbacks; async raw export rechecks after reading. Pausing/disconnecting does not unlock private operations. Runtime and real-browser tests inspect serialized active messages; type contracts alone are not secrecy proof. Source/devtools inspection remains possible in a client-only app: this is data/presentation separation, not adversary-proof examination security.

## Versioning / reproducibility / model

Schema **3** adds evaluator-owned metric/finding anchors and raw per-track credit/contribution audit metadata. Prior schema-2 pattern/provenance fields remain. Definitions keep **generator-2 / sensor-2**; numerical equations remain **rubric-1**. Schema-1/generator-1 Phase 2 is archived at `44b269f`; schema-2 Phase 3 at `70c947d`. IndexedDB v1/portable format 1 are separate versions. Only current schema 3 records import; no legacy migration exists, and replay rejects other schemas rather than relabelling generated replacements.

Mulberry32, canonical validated configuration hashing and labelled independent streams yield stable definitions and evidence. Category/individual values and pattern geometry have separate streams; dropout/quality/position/delay have independent per-track/capture seeds. Same versions/configuration/seed and **simulation-timed commands** reproduce definition/evidence/log/evaluation regardless of render speed, step chunking or unrelated sessions. A seed does not make different trainee timing equivalent.

Validated 1–8 returns support independent paths, bounded near-crossing (minimum 2), and shared-velocity/phase grouped paths (minimum 3). Group categories remain independent; proximity is not a threat classification. Difficulty changes bounded motion. Weather/light/urban clutter alter return consistency, noise, confidence, uncertainty and variable delay; one seeded 18-second disruption begins at seconds 12–16. Requests capture after 2 seconds with 8-second cooldown, can drop, improve the synthetic return setting/quality and coalesce with coincident scheduled attempts. Configured base delay is 0–8 seconds; total validated delay is 0–19 seconds. Exact formulas and limits: SCENARIO_MODEL.md. These are fictional teaching rules, not physical sensor validity.

## Clock, lifecycle and event order

A fractional millisecond accumulator feeds integer one-second steps. Speeds 1×/2×/4× change pacing, not generated values. Pausing preserves the active fractional remainder and ignores paused wall time. Running timer delays catch up only to remaining duration and complete exactly at the configured end. Leaving console/opening guide pauses; merely backgrounding a running tab does not.

Events have `{id, sessionId, order, time, type, data}`. Order strictly increases even when timestamps match. Pending equal-time deliveries sort by delivery time, track ID, then capture time. Arrival history remains arrival-ordered; latest is maximal capture time, using delivery time as tie-break. **Stale = now − capturedAt >10s**. Late old evidence cannot rewind a marker or falsely refresh its age. Pending observations after termination are not delivered/counted.

Log validation checks requested provenance against an earlier matching request and scheduled provenance against spawn/regular cadence, as well as event/action order and state. Duplicate track/capture evidence is rejected even with different IDs; coalesced request captures cannot masquerade as scheduled; total delay must be ≤19s. Invalid actions append no action event. Selection/tracking/requests require observed evidence; assessment requires tracking; final report requires assessment, confidence and valid summary and locks that track.

Identity/configuration stay locked while active. Reset confirms discard, recreates Worker and returns to frozen briefing/seed; fresh Start gives a new session ID and empty log, discarding pending deliveries. Prior terminal records remain in HistoryStore and its acknowledged local database. Early exit creates an actual aborted noncomparable partial and saves it for review, not score trends. Reload warning covers unfinished/pending work but saves no active state; refresh invents no interrupted report.

## Evaluation / review

`evaluateSession` strictly validates config/rubric/log, folds evidence available at the relevant action and applies rubric-1. Complete finite/bounded thresholds/windows and matching configured/stored weights are required. Raw credits/penalties aggregate before one-decimal summaries; finding points and per-track traces retain precision. Later deliveries never justify earlier confidence. Six weighted components and three once-per-track penalties yield a bounded [0, 100] total. Unobservable truth is excluded from eligibility/penalties; no-evidence/aborted results are noncomparable. SCORING_RUBRIC.md gives equations, denominators and tested examples.

Review renders that one evaluation, declared rubric, denominators, penalties, raw per-track audit, post-exercise expected/actual outcomes, exact evidence links and full chronological log. Console limits display to 50 recent events; review retains all actual events. Missing action anchors are actual Finish, not invented events; assessment support stops at assessment and report support at report. Global component evidence can span tracks; the component jump anchors the lowest-credit track deterministically.

## Read-only recorded replay boundary

`createReplayTimeline` validates current versions, terminated order/transitions, identity/outcome/duration and real audit references. It deep-detaches/freezes only public settings + recorded events. No hidden definition/evaluation enters that model. Strict full supported-record consistency validation is implemented separately in persistence; it is **not authenticity/signature validation**.

`replayFrame` uses the shared evidence fold and recorded lifecycle/health/selection events at `(integer time, applied event count)`. This distinguishes same-second actions. Time seek applies all events through a second; event jump/step applies an exact prefix. Start is before Start; end is actual termination, including aborted/zero-duration. Newest-capture/latest/stale and original arrival provenance remain intact. No engine, generator, sensor or scorer is invoked; no gap is extrapolated.

`useRecordedReplay` only paces seconds at 1×/2×/4×. Pause/seek/step/inspection stop playback; actual end auto-stops; unmount/result switch clears timers and resets safely even for shorter records. Inspector selection is separate from recorded trainee selection. Original wall-clock pause lengths and speed changes were not logged and are explicitly not reconstructed.

`SessionReview` checks active state **before** mounting any current/prior score, answer table/audit or replay. Validated report children are keyed by result identity. `RecordedReplay` receives only the public controller; source records and scores cannot be changed through it. Evidence links move to the same actual event highlighted in the full log. An invalid log produces an explicit review error, not a replacement score/replay. Replay sends no Worker commands and writes no session/progress state. See REPLAY_SPEC.md.

## Durable history / validation / exports

`createHistoryRepository` uses native `vigil-training-history`v1 stores profiles/sessions/meta. Startup is explicit; a truly empty DB seeds3 anonymous definitions and zero reports. Missing/schema-invalid metadata refuses automatic overwrite. Invalid individual profile/session rows are quarantined untouched, valid siblings remain reviewable and raw diagnostic preserves originals. An already valid memory report whose stored copy corrupts remains unsaved/exportable, not lost or allowed to overwrite corruption.

`HistoryStore` accepts detached actual terminal records immediately, serializes/coalesces pending profiles/reports/preferences and marks saved only after transaction completion. Valid drafts/selection/profile persist; invalid edits stay visible while only last-valid config is durable. Failure keeps actual AAR, status/retry/backup; storage-unavailable training is explicitly memory-only. Startup/import/reset/reload disable conflicting actions. Active state itself is never persisted/reconstructed. Actual saved reports survive reload without an auto-start.

The repository atomically reads/validates/merges immutable IDs across all 3 stores and updates metadata revision. Same IDs + equal values deduplicate; changed values, missing references and duplicate names reject. Native transactions serialize independent writers; no stale whole-array overwrite. Confirmed history reset clears rows/preferences and changes epoch. A stale tab cannot resurrect records; its retained actual report can be exported. BroadcastChannel discloses changes, repository epoch checks enforce correctness. Console discard remains separate from history reset.

Portable `vigil-session-export` format 1/schema 3 validates strict bounded shape, dates/identities/references, seeded definition/rubric identity, original terminated log/provenance, exact same-evaluator result and replay consistency. Reject, never trim/repair/relabel. Generator/evaluator reuse occurs only in record validation, not live UI scoring or replay.20 MiB/500 profiles/500 reports per file; 2 MiB/5000 events per report. Preview/confirmation precedes all-or-nothing transactional merge; duplicate/empty merges cannot reset history. **Unsigned consistency is not authorship/authenticity or verified performance.**

Actual JSON uses referenced profiles/full records, including valid unsaved memory reports. CSV uses explicit persistence/outcome/score data and quoted/formula-neutralized cells; HTML/print escape user content and retain actual audit/ordered events with no external assets. PDF delegates to browser print; print entrypoint/cleanup and real Chromium PDF generation are tested, not all OS/printers. Raw diagnostic has a separate non-importable format. Full contract/limits: STORAGE_SPEC.md.

## Descriptive history / connected heuristic learner policy

Only acknowledged saved + completed + comparable records enter means/trends/component averages/raw comparisons. Missing latencies have actual n/missing, never zero imputation. Aborted/no-evidence/unsaved reports stay reviewable with exclusions. Unit mean weights actual attempts, not unequally sized profile means; local-group filter selects actual profile labels. Chart/table display last20 actual eligible completions, difficulty buckets show n; empty means are null. Raw comparison discloses exercise/conditions/weights/objectives differences and seed caveats, not normalized improvement.

These remain descriptive teaching summaries. Separate rules-1 uses at most5 distinct matching-context seeds and the latest3 eligible actual attempts for conservative level changes. It exposes source IDs, n/range, exclusions and every decision reason, with null empty estimates and saved-seed avoidance. No plan/estimate details mount during an active attempt; saved/pending/error/profile/stale application guards are root-owned. Plans are derived, not persisted as historical decisions or included in fixed report exports. See ADAPTATION_SPEC.md for exact context/threshold/precedence and tests; no ML or calibrated mastery claim. Origin-local unsigned storage, eviction/manual backup, active-run loss, no authentication/cloud/legacy migration and browser/accessibility/performance limits remain. An authenticated backend/optional VR are future extensions; operational targeting/engagement is out of scope. Phase6 local core and package handoff are accepted; broader gates7–8 remain bounded/unverified. See LIMITATIONS.md and the independent QA verdict.

## Runnable release boundary

The full ZIP adds committed source/lock/tests/docs plus the exact tested dist and a Node-built-ins-only static host (`scripts/serve.mjs`), Windows/POSIX helpers and SHA-256 manifest. GET/HEAD/MIME/path/symlink/missing-bundle behavior has native Node tests. It is not a backend/API/authentication service, PWA or public deployment. Extracted-bundle browser rehearsal is recorded in TEST_RESULTS.md; the release manifest identifies the clean source commit without embedding Git internals, caches, secrets or node_modules.

Known same-epoch peer notices now set an ephemeral `HistorySnapshot.needsReload`; existing acknowledged records remain valid for labelled descriptive review, but all next-practice estimates/applies are withheld until an actual reload includes peer evidence. Current/stale root callbacks check the flag; local preference writes cannot clear it. This is not DB-schema change or automatic cross-tab synchronization; absent BroadcastChannel, users must explicitly reload a multi-tab workspace before planning.
