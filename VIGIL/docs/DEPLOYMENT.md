# Installation, demonstration and backup · Phase 6 handoff

## Included full ZIP: no runtime dependency install

See [QUICK_START](../QUICK_START.md). Extract the whole archive and have Node20.19+ or22.12+ LTS available. From its root, `node scripts/serve.mjs` (or double-click START-VIGIL.cmd / run `sh start-vigil.sh`) serves the included tested dist on **http://localhost:8787**. `--port 8788` handles a busy port. Keep the terminal open. No npm install, Python, server database, paid API or account is needed for the prebuilt app.

The Node-built-ins host accepts GET/HEAD, supplies Worker/module MIME types, confines real paths to dist (including symlink checks), rejects missing resources rather than sending fake HTML assets, and has9 native Node tests. It binds0.0.0.0 for preview compatibility; **unauthenticated local demonstration only**, trusted machine/network/firewall, not public deployment. Windows/macOS execution has not been claimed from Linux-only tests. Path helpers are included, but a portable source/build ZIP is not a signed native OS installer.

The archive's `RELEASE_MANIFEST.json` lists the clean source commit, versions, every source/production file size/hash; manifest itself is not self-hashed. Generated ZIP/receipt artifacts live outside the source inventory. No node_modules, .git internals, credentials, caches or user history is bundled. SHA-256 is integrity, not publisher-signature/authenticity.

## Prerequisites
- Node **20.19+** or compatible newer LTS; tested Linux / Node 20.20.2 / npm 10.8.2.
- Modern browser with module Web Workers and IndexedDB. Storage failure is visible and permits in-memory training with actual-report retry/backup; no silent alternative database/engine.
- Internet for initial dependency/browser downloads or hosted loading, no runtime remote/paid APIs or external assets/fonts.
- No environment variables/secrets, database server, Python backend, accounts or specialized hardware.
- Trusted localhost HTTP or hosted HTTPS; `file://` unsupported.

## Development

```sh
npm ci
npm run dev
```

Vite binds `0.0.0.0` on 5173 by default; host filtering allows the Arena preview proxy. This is an unauthenticated synthetic local prototype; use a trusted development network.

## Production build / preview

```sh
npm run build
npm run preview -- --port 5173
```

Strict TypeScript checks precede Vite bundling. Serve the **whole dist directory**, including `assets/simulation.worker-*.js`, with JavaScript MIME types and a CSP permitting the same-origin module Worker. No browser-facing localhost backend/API calls exist. Hash routes need no server route rewriting. Default base is site-root; subpath hosting needs the right Vite base and rebuild. **Preview does not compile source edits**: rebuild first.

Arena's **VIGIL Training Workspace** production preview is on 5173/0.0.0.0; Arena supplies its proxy URL. If unavailable, check preview process/port, not file://. No public deployment has been claimed.

## Reproduce the tested gate

```sh
npm run test
npm run test:launcher
npm run build
npx playwright install --with-deps chromium  #once; system packages may need admin
npm audit
# Keep npm run preview -- --port 5173 running, then in another terminal:
npm run test:e2e -- --workers=2
```

**Playwright tests whatever server is already on 5173 outside CI.** Stop any dev server and start the rebuilt production preview for production acceptance. If none exists, the convenience webServer fallback starts development mode; CI also starts a dev server with reuse disabled. Neither fallback establishes production-server testing. Phase6's full369/9/111 gate used the known running production preview. [Executed counts/timings/assets/limits](TEST_RESULTS.md).

Fresh Linux environments may need `npx playwright install-deps chromium`; earlier missing libnspr4 was resolved through documented prerequisites. Dependencies/browser/system installs and ignored dist may need regeneration after environment restoration.

Playwright reports/traces/downloads are generated under `playwright-report/` / `test-results/` and ignored. `docs/screenshots/` retains actual selected captures:84 Phase6,66 Phase5 and75 earlier historical. No script's existence is substituted for execution.

## Demonstration workflow

1. Wait for **Saved on device** or read any storage warning. Fresh history contains3 explicitly synthetic identities and **zero reports**.
2. Scenario Lab → preset → Review briefing → Start exercise. Perimeter/Urban/Night/Rural are all browser-proven at 3 sizes. Inspect synthetic conditions, capture/arrival/age/source; request is not guaranteed. Queue/map/track/assessment/report actions are actual. Use 4× for pacing without changing model values, pause before stepping away. Console/guide/confirmations pause; backgrounding does not.
3. Terminate normally or confirm a partial exit. Inspect fixed score/rubric/penalties/audit; evidence links and read-only replay use actual event order. Original wall-clock pause lengths/speed changes were unlogged. All prior/current private answers/replays/exports stay locked during a live attempt.
4. After transaction acknowledgement, refresh: same actual AAR/log/replay returns, no new automatic run. Individual/Unit views show real saved/completed/comparable means/n/exclusions, latency missingness, difficulty/table alternatives and group filters. A separate rules-1 planner shows nullable matching-context estimates, actual sources, target/level decision and fresh seed. Review freezes the next briefing without automatic Start; manual Lab remains available.
5. Instructor desk → download JSON; optional preview/confirmed merge into another browser/origin. Try CSV and single-report HTML/JSON/browser print. Use synthetic identifiers only. Do not present controlled test scores as learner performance.

## Storage, backup, reset and recovery

IndexedDB **vigil-training-history v1** is **browser-profile + origin local**. A different preview host/protocol/port/profile, private browser, site-data clear or eviction can lose access to history. No cloud sync/automatic backup/strong durability or secure identity. **Download JSON before clearing/changing the origin or resetting.**

- Whole-workspace JSON/CSV: Instructor desk. Profile JSON/CSV: Individual progress. Actual single-report JSON/HTML/print: AAR. JSON includes valid actual reports and referenced anonymous identities, including available unsaved memory reports. CSV/raw diagnostics are not import formats.
- Portable format 1/schema 3:≤20 MiB,≤500 profiles/500 reports per file,≤2 MiB/5000 events per report. Larger accumulated history requires smaller/single-report exports; no silent trimming. Import validates versions/configuration/definition/log/evaluator/references, previews counts and confirms an atomic immutable-ID merge. Equal duplicates skip; conflicts/unsupported/tampered/orphan records reject with no partial writes. **Consistency is not signed authenticity.**
- **Reset exercise** discards only that active attempt; saved history stays. **Reset local history** separately confirms deletion of local reports/added profiles/preferences/quarantine/unsaved state and restores zero-history demo definitions. No undo. Cross-tab epoch protection blocks stale resurrection; export retained stale-tab reports, then reload rather than expecting Retry to undo a reset.
- Quota/denial failure: actual AAR remains in memory, status is unsaved, summaries exclude it. End/reset any live attempt, export a backup, resolve browser space/permission and choose **Reload / retry saving**. Beforeunload warnings are advisory, not a save.
- Corrupt individual rows remain untouched/quarantined; valid siblings stay reviewable. Download raw diagnostic to preserve originals (not importable). Missing/schema-invalid metadata blocks normal load to avoid overwriting unknown data; raw backup + explicit reset are recovery options. No automatic repair/legacy migration.
- Active simulation state is never persisted. Refresh/Worker loss does not fabricate an interrupted report. Lost active truth cannot be recovered/scored from a retained public snapshot.

See [storage contract](STORAGE_SPEC.md) and [limitations](LIMITATIONS.md). Do not use real personnel or training records.

## Offline scope / stopping point

All runtime assets/Worker are local. Real browser tests wait for code/Worker readiness, disable browser network and complete all4 presets, evidence-linked replay and the actual two-exercise next-practice cycle; exports need no network. **Not a PWA/cold-start offline installer**: fresh hosted loading needs the host, or a running local server. No service worker/cache. Reconnect before document reload in the offline demo.

Current automated scope is Chromium at 1440×1000/1024×768/390×844, not all browsers/hardware or accessibility/security certification. Official PS source remained403/no attachment. **Phase6 local core and runnable handoff accepted**; broader browser/AT/performance/real-event rehearsal gates7–8 are not blanket-complete. No public/authenticated deployment, operational-validity, production-readiness or competition guarantee.

## Reproduce archive verification (maintainer)

After the gates/docs and a clean Git commit: `python3 scripts/package_release.py`. Python is a maintainer packaging tool, not a runtime requirement. It inventories committed source plus exact dist, refuses a dirty final release, creates a single-root ZIP/manifest and rereads every byte/hash. `--candidate` is explicitly provisional for pre-commit payload rehearsal, never the delivered artifact. Extract to a clean directory, run its `node scripts/serve.mjs --port 8787`, and from a development checkout with Playwright installed run `npm run test:package -- http://127.0.0.1:8787 deliverables/package-validation.json`. The browser smoke completes two actual offline Worker exercises, checks explicit next briefing/config/score/replay/native-IDB equality and reload; it writes an execution receipt, not simulated success.

For the development checkout production gate use the known preview5173 as above; archive smoke uses the independently extracted host, not Vite or another copy's dist. Final ZIP integrity/source/asset comparison and launch receipt complement the full111-case application regression. Never describe script availability alone as a passed package test.
