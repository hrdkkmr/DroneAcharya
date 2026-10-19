# Local history, portable reports and descriptive analytics · Phase 6 retained storage contract

**Implemented and tested, 2026-10-17.** Record schema **3**, generator-2 / sensor-2 / rubric-1 / replay-1 are unchanged. Separate storage/portable versioning does not relabel older simulation records. See [executed results](TEST_RESULTS.md) and [QA verdict](QA_REPORT_PHASE_5.md).

## Ownership and lifecycle

- The existing Worker remains the only live simulation authority. It supplies the actual terminal record and its one evaluation; the UI does not create a substitute score or run a fallback engine.
- `HistoryStore` is an external observable state machine integrated through `useSyncExternalStore`. It owns anonymous profiles, the valid saved draft/selection, actual terminal records, acknowledged saved IDs, pending changes, quarantine and operation/error status. React route/briefing and the Worker bridge remain separate.
- Startup explicitly loads and validates local history before showing exercise controls. Denied/unavailable storage resolves to a visibly labelled in-memory mode, not silent replacement of unknown saved data. A loading operation cannot start an exercise or mutate identities.
- Termination immediately retains a detached completed **or aborted** record. Only an IndexedDB transaction's `complete` event acknowledges persistence. A serial/coalescing writer handles later draft/profile/record changes without losing an update. Duplicate terminal delivery cannot create a second row.
- Write/validation failure keeps the actual AAR in memory. The banner offers reload/retry and portable backup when no live attempt is active. Pending valid changes and active attempts install the reload warning. The browser may suppress native prompts without user activation; it is not a save mechanism.
- Invalid configuration edits remain visible; only the last validated configuration is persisted. Retrying storage does not turn NaN into JSON null or silently replace those edits.
- No active simulation state is saved. Refresh of an unfinished run starts no replacement run and creates no fictitious completion/abort. Saved reports remain available; the valid Lab draft is restored, not an auto-started briefing.

## IndexedDB v1

Database: **`vigil-training-history`**, version **1**. Stores:

| Store | Key path | Value |
|---|---|---|
| `profiles` | `id` | strict schema-3 anonymous `TraineeProfile` |
| `sessions` | `id` | actual strict supported terminal `SessionRecord` |
| `meta` | `key` | workspace v1 metadata: epoch, revision, valid config/profile/review selection |

A genuinely empty database is initialized atomically with three explicitly synthetic profile definitions and **zero session records**. Their stable IDs/definition dates make portable demo identities mergeable; they are not learner-performance fixtures. Actual added profiles use a fresh UUID and current creation date.

Read-modify-write operations span all three stores in one transaction. Asynchronous computation never runs inside an open transaction; synchronous validation precedes writes. All-or-nothing immutable-ID merge accepts equal duplicates and rejects changed same-ID values, orphan references and duplicate anonymous names. Concurrent writers cannot replace the entire history with a stale array.

Reset clears this database's profiles/sessions/meta and seeds only empty anonymous definitions in one confirmed transaction. It changes the epoch. A stale writer/import/retry cannot resurrect cleared data; a visible reset/replacement error keeps its local report available for backup. BroadcastChannel, when supported, discloses other-tab changes. The repository epoch check remains authoritative even without notification. A same-epoch refresh can merge new rows without discarding pending records.

A corrupt stored profile/session is excluded from acknowledged history and analytics, listed as quarantined and **not deleted or overwritten**. Valid siblings remain available. If a previously valid in-memory copy exists when its stored copy becomes corrupt, it is retained as unsaved; conflicting IDs still cannot overwrite the stored corruption. Raw diagnostic export preserves the original entries. Missing/schema-invalid metadata blocks automatic loading/writing rather than reseeding over unknown data; v1 raw export and explicit confirmed reset are recovery options.

## Portable format 1

```text
{
  format: 'vigil-session-export',
  formatVersion: 1,
  schemaVersion: 3,
  exportedAt: ISO-8601,
  profiles: TraineeProfile[],
  sessions: SessionRecord[]
}
```

Imports have strict keys/versions, up to **20 MiB**, **500 profiles** and **500 reports** per file; each report is limited to **2 MiB / 5000 events**. Identity strings, text, ISO dates, numbers/configuration and arrays are bounded. Anonymous names are unique ignoring case. Dates cannot run backwards. Every report references an included profile; duplicate session IDs inside a file are rejected.

Validation checks the unchanged generated definition/rubric for the declared validated configuration, actual terminated log/state/order/provenance, matching identity/outcome/duration, evaluator anchors/references and **exact recomputation by the same `evaluateSession`**. Canonical input comparison rejects event-text trimming/repair. Unsupported versions, forged scores/audits, changed definitions and invalid logs are rejected, not repaired/migrated. Definition generation is a consistency check **only during record validation**, never replay or a second live simulation. Replay still folds original recorded events.

The file is previewed before confirmation. Merge is rechecked against current data inside the transaction, so a concurrent ID conflict rejects the complete incoming merge. Equal duplicates do not double-count reports. An empty merge adds no sessions and never means reset. Failed or conflicting imports do not replace existing stored records. Successful imports become acknowledged history; they are labelled local training records, not signed/authenticated performance.

**Consistency is not authenticity.** An editable unsigned client-only JSON file can be manufactured consistently. These checks are not authorship, tamper-proof examination security, a real-world assessment or proof a human performed a run.

## Export / print and active boundaries

- JSON backup includes actual terminal records and referenced anonymous profiles, including unsaved valid in-memory reports. Whole-workspace, current-profile and single-report exports are available. Pretty formatting falls back to compact JSON if needed to stay within the portable size limit. For larger histories, export individual reports; no older data is silently dropped.
- CSV is an actual-result summary with explicit outcome/comparability/saved status, score/components/penalties/event count. Every cell is RFC4180-quoted, quotes/newlines escaped, and leading `= + - @` / whitespace-control formula prefixes neutralized with an apostrophe. It is not an import format.
- Self-contained HTML and native print use the same actual record, score/rules/audit/outcomes and ordered event descriptions. All user text is HTML-escaped; no network resources are needed. PDF is delegated to the browser print dialog, not an invented server-side PDF feature. Browser tests additionally render exported HTML and produce a nonempty Chromium PDF.
- Raw storage diagnostic JSON contains untouched database data for inspection, including quarantine; its distinct format is deliberately **not importable**.
- Import/reset/profile/config changes, report/JSON/CSV/raw export, print and evaluator review are guarded in the root API, including a stale closure during synchronous Start. Private controls are also disabled or absent during active attempts. No private-data action is unlocked merely by pausing or disconnecting the Worker. Confirmed console discard is different from confirmed history reset.

## Descriptive analytics

Only acknowledged **saved + completed + comparable** records enter means, plotted scores, component averages, latency summaries and numeric comparisons. Aborted, completed/no-evidence and unsaved reports remain reviewable, with visible exclusion counts. Missing tracking marks/reports are counted as missing, not imputed as zero-second responses.

An eligible attempt has equal weight in mean training score/component averages. Latency averages use actual eligible delivered-track tracking/report events and their own denominators. Unit means are across attempts, **not an average of unequally sampled profile means**. Profiles with no evidence show dashes/n = 0, not fictional zero scores. Training-group filters operate on actual anonymous profile group labels.

The chart shows the last20 actual eligible completions in end-date order, ties broken by ID rather than invented execution time. A single point is a baseline, not a trend. A readable data table is available; separate difficulty samples show their n/mean. Side-by-side differences are raw B−A teaching-score differences, not normalized improvement or ranking; changed settings are disclosed. These descriptive aggregates are not themselves competency/mastery estimates. The separate Phase6 rules-1 planner consumes the same acknowledged eligibility boundary, but restricts its estimates to distinct matching-context seeds and exposes actual source evidence; see ADAPTATION_SPEC.md. Recommendations are derived, not added to the portable SessionRecord or stored as historical decisions. No DB/schema/portable-version change is required.

## Limits

Origin/browser-local and unsigned; no authentication, cloud sync, automatic backup, site-data-eviction guarantee or legacy migration. Clearing/changing the preview host/browser profile changes storage scope; use JSON to transfer actual history. No active-run recovery or full durability guarantee against OS/browser crash. Browser native IndexedDB, controlled failures and all flows were tested in Chromium at three viewports; no claim about every browser, prolonged/large-dataset performance, all disk/OS failures or accessibility certification. See LIMITATIONS.md.

## Phase6 peer-snapshot freshness
A known same-epoch BroadcastChannel change sets an ephemeral needsReload flag. Existing acknowledged records are not falsely marked unsaved, but the planner/estimates/current-or-stale apply are withheld until actual reload includes peer evidence. Local preference saves do not clear it. Reset-epoch rejection remains separate and unchanged. This adds no DB/portable record field; without BroadcastChannel there is no automatic peer-change discovery, so explicitly reload before multi-tab planning.
