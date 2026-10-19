# VIGIL — full working local handoff

Synthetic observation, assessment and reporting practice. **Not an operational system, certification, validated learner model or official SIH-conformance claim.**

## Run the included prebuilt app (no npm install)

1. Extract the **whole ZIP**, then open its **VIGIL** folder; keep `dist/` and `scripts/` with these instructions. Do not run files inside a compressed-folder viewer.
2. Have **Node.js 20.19+ or 22.12+ LTS** installed. Tested here on Node20.20.2/Linux; Windows helper is supplied but not executed on Windows.
3. Windows: double-click `START-VIGIL.cmd`. macOS/Linux: open a terminal in the extracted folder and run `sh start-vigil.sh`. Cross-platform alternative: `node scripts/serve.mjs`.
4. Open **http://localhost:8787** in a current desktop Chromium-based browser. Keep the terminal open. `Ctrl+C` stops the server.

If the port is busy: `node scripts/serve.mjs --port 8788`, then open http://localhost:8788. Use the **same browser, host and port** each time for the same browser-local history. `localhost` and `127.0.0.1`, different ports, browser profiles and private windows are different stores. Do not double-click `dist/index.html`: module Workers require HTTP.

The launcher uses only Node built-ins. No paid API, cloud service, account, database server, Python, GPU, VR hardware or runtime npm packages are needed for this prebuilt app. It binds0.0.0.0 for preview compatibility; this is an unauthenticated local demonstration server. Use a trusted machine/network/firewall, **not public hosting**. Internet is not needed once the files and Node are available. The page and its Worker must load before disconnecting; a still-loaded page can complete the next-practice cycle without network. No PWA installation or cold-browser offline-cache guarantee is provided.

## First practice

1. Select an anonymous profile. History begins genuinely empty.
2. Open **Scenario Lab** for manual settings, or use **Review recommended exercise** for a Level1 baseline. Review its briefing; nothing starts automatically.
3. Press **Start exercise**. Select a delivered track, **Mark as tracked**, record an assessment and submit a measured training report. The guide explains the fictional cues and uncertainty rules. Optional clock1×/2×/4×; navigation pauses an active attempt.
4. Let the configured duration finish. **End early** is an aborted partial report, not a completed result. A reload during a live attempt creates no fictional report.
5. In AAR, check the score audit, exact recorded-event replay and save status. The same profile's next-practice panel explains actual source reports, targeted component, level decision and new seed.
6. **Individual progress** separates descriptive historical averages from heuristic matching-context competency estimates. `—` means no eligible evidence, not a score of0. Three consistent, distinct, matching-context completions are required before a level can move by one.
7. **Instructor desk** supports anonymous profiles, unit summaries, JSON backup/import, CSV, self-contained HTML and print/PDF. Active/paused attempts lock private report/replay/export/planning operations. Finish or explicitly reset first.

## Protect your actual records

- Use one tab for practice, or reload saved history before multi-tab planning. A known peer-tab change withholds recommendations until reload; this is not automatic global synchronization.
- Watch **Saved on device**. Browser denial/quota problems preserve the in-memory report and expose retry/backup; unsaved scores do not inform adaptation.
- Export a **JSON backup** from Instructor desk before clearing storage or moving browsers/machines. Import validates structure, declared versions, scenario/evaluation/event consistency and conflicts before a merge. CSV/HTML are readable reports, not import formats.
- JSON includes synthetic answer keys and action logs. Share only deliberately. Consistency validation is not identity/authenticity, encryption or an invigilated exam.
- Console reset discards only the current attempt. Confirmed **Reset local history** deletes local saved data and cannot be undone without a backup. No remote recovery exists.

## Source, rebuild and tests (optional)

```sh
npm ci
npm test
npm run test:launcher
npm run build
npx playwright install chromium
npm run test:e2e -- --workers=2
```

Dependency/browser downloads need network on a fresh development machine. Thereafter core development/tests do not use paid services. `npm run dev` opens the editable app on the port printed by Vite (normally5173); `npm run preview -- --port 5173` serves a rebuilt production bundle. The included prebuilt ZIP does not require these development steps. The npm lockfile is included. Run browser suites with an unused5173, or the intended local VIGIL preview already on5173; Playwright's non-CI configuration reuses that port. Use the documented production regression sequence in `docs/TEST_RESULTS.md` for an explicitly production-served gate.

- `docs/ADAPTATION_SPEC.md`: exact explainable rules and eligibility.
- `docs/QA_REPORT_PHASE_6.md`: executed evidence and remaining gaps.
- `docs/REQUIREMENTS_TRACEABILITY.md`: every target classified Verified / Partially implemented / Missing.
- `docs/TEST_RESULTS.md`: final acceptance and package-smoke results.
- `docs/LIMITATIONS.md`: scope, browser, storage and safety limitations.
- `RELEASE_MANIFEST.json` (inside release ZIP): source commit, file list, sizes, SHA-256 integrity hashes. Hashes are integrity checks, not a publisher signature.
