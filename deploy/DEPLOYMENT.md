# DroneAcharya — Browser demo and Windows fallback

Prepared 2026-10-20 on branch `deploy/web-and-windows`. Engine: Godot 4.7.2 stable (official), with the official 4.7.2 export templates (`Godot_v4.7.2-stable_export_templates.tpz`, SHA-512 checked against the release's `SHA512-SUMS.txt`).

**Short version:** both training modes export and run in the browser with no feature removed. The only web-specific changes are a bundled symbol font, export-as-download, and hiding or disabling three desktop-only buttons. The Windows build is unchanged and remains the recommended fallback. Browser performance on a GPU-accelerated browser is **not yet verified** (see section 4).

---

## 1. Web-compatibility audit

| Area | Finding | Class |
|---|---|---|
| Native extensions | None (no `.gdextension`, no `addons/`) | 1 · works |
| Threads | None (`Thread`, `WorkerThreadPool`, `Mutex` unused) → single-threaded web export; no COOP/COEP headers needed | 1 · works |
| Networking | None (no HTTP, sockets or WebSocket) | 1 · works |
| Python / backend | Python is only used offline for training and tests. The ML model is a JSON random forest evaluated in GDScript | 1 · works (verified: decision support shows the ML classifier in the browser) |
| Model and scenario files | Loaded from `res://` with `FileAccess`; in both presets' `include_filter` | 1 · works |
| Case-sensitive paths | Every `res://` string in scripts and scenes matches a tracked file name exactly | 1 · works |
| Renderer | Project uses Forward+; web automatically uses the **Compatibility** renderer (WebGL 2). All three shaders compile; lighting looks flatter than on desktop | 1 · works, looks different |
| Fonts | UI symbols (■ □ ◆ ▲ ⬡ ▶ ✓ ↑ ↓ → …) come from Windows system fonts on desktop; the browser has none, so they showed as boxes | 2 · **adapted**: bundled 19 KB DejaVu Sans subset, loaded as a fallback on web only |
| Audio | Generated `AudioStreamWAV`, no files. Browser audio needs a user gesture; Godot handles this | 1 · works (Web Audio context running; audible output not checked by ear) |
| Mouse | Left-click, wheel and right-click; Godot suppresses the browser context menu on the canvas | 1 · works (verified) |
| Keyboard | Space, WASD, Q/E, Esc, Tab, arrows, Enter, Backspace | 1 · works (verified: takeoff, pause, flying) |
| Saved data (`user://`) | Browser storage (IndexedDB), per site | 1 · works: settings and reports survive a page reload (verified). Cleared if the user clears site data; not shared with the Windows version |
| History → Export | Wrote into browser-internal storage the user cannot reach | 2 · **adapted**: also offered as a browser download |
| History → Import | Native file dialog plus filesystem access | 3 · desktop-only; button disabled on web with a tooltip |
| History → Open folder | Opens Explorer | 3 · desktop-only; button disabled on web with a tooltip |
| Main menu → Exit | `quit()` freezes the page in a browser | 3 · hidden on web (close the tab instead) |
| Performance | See section 4 | 4 · **not verified** on a GPU-accelerated browser |
| Browsers other than Chrome; mobile | Not tested; the game needs a mouse and keyboard | 4 · not verified |

**Both Flight Training and Threat Detection Training export with all their features.**

## 2. Changes on this branch (desktop behaviour unchanged)

| File | Change |
|---|---|
| `simulator/export_presets.cfg` | New "Web" preset: single-threaded, `../build/web/index.html`, includes `fonts/*`, plus a loading-screen caption and controls guide (`html/head_include`, removed once the game starts). Windows preset untouched |
| `simulator/fonts/dejavu_sans_symbols.ttf.bin`, `LICENSE_DEJAVU.txt` | Subset of DejaVu Sans (33 glyphs used by the UI). Free licence; it is a modified font, but the family name contains neither "Bitstream" nor "Vera", as that licence requires. The `.bin` extension means no import step is needed |
| `simulator/scripts/ui/ui_kit.gd`, `menu/main_menu.gd` | `install_symbol_font()` on web only; Exit hidden on web |
| `simulator/scripts/menu/history.gd` | On web: export also triggers a browser download; Import and Open folder disabled with a tooltip |
| `deploy/` | This file, `build-release.ps1`, Windows player README, licence notices |
| `.gitignore` | `build/` (all generated exports) |
| `simulator/**/*.gd.uid` (31 files) | Godot UID files created by the editor-import step of the export, for scripts that had none; the repo already tracks `.uid` files for the older scripts |

## 3. Tests

| Run | Result |
|---|---|
| Before changes: Godot suite | 170 passed, 0 failed, exit 0 |
| Before changes: ML / schema | 11 / 4 passed |
| After changes: Godot suite | 170 passed, 0 failed, exit 0 (the same two expected warnings) |
| After changes: ML / schema | 11 / 4 passed |
| VIGIL | `git diff baseline-vigil-2026-10-20 -- VIGIL` empty |
| Web export (`--export-release "Web"`) | exit 0, no errors or warnings |
| Windows export (`--export-release "Windows Desktop"`) | exit 0, no errors or warnings |

**Browser test** (Chrome 155, Windows 11, served by a local HTTP server, never from `file://`):

| Check | Result |
|---|---|
| Starts, loads every resource | ✓ no console errors or warnings in any session |
| Main menu and navigation | ✓ |
| Flight: start, take off, pause (clock stopped), resume, restart, back to menu | ✓ |
| City and village environments; Recon, Heavy utility profiles | ✓ (village hostile with Heavy utility; city delivery with Recon) |
| Radar (friendly/unknown traffic, hostile-area rings), hostile-drone hit | ✓ |
| Threat exercise to the end (2 min), wheel, right-click, decision card | ✓ classify and respond with the mouse; no browser context menu |
| ML classifier in decision support | ✓ "ML classifier track-classifier-v1" shown next to the rule-based baseline |
| Report from the saved session; Verify replay | ✓ report matches the actions taken; replay reproduced every event and the score |
| Export as download | ✓ 193,817-byte file in Downloads, valid against `schemas/droneacharya-session-1.schema.json` |
| Fresh browser session (new origin) | ✓ tutorial opens on the first Threat Detection visit |
| Persistence after reload | ✓ tutorial completion and reports kept |
| Audio | Web Audio context "running" at 48 kHz; mute uses the same engine code as desktop. Not checked by ear |
| Symbols after the font fix | ✓ rating bars, arrows, ▶, ● render |
| Loading screen | ✓ caption and controls above the Godot splash; progress bar visible; removed when the game starts |
| Packaged ZIPs, unzipped into new folders | ✓ web package loads to the menu; Windows exe starts with a clean log |

## 4. Performance — not verified on a typical setup

On the test PC, Chrome's "Use graphics acceleration when available" is **off**, so WebGL ran on the Microsoft Basic Render Driver (CPU software rendering):

| Scene (1920×962 canvas) | Frame rate |
|---|---|
| History screen (2D) | 53 fps |
| Threat observation | 13 fps |
| City flight, standard quality | 10 fps |
| City flight, reduced quality | 12 fps |

These numbers describe software rendering, not a GPU. The same scenes run at 400–580 fps natively on this PC's Intel Arc GPU. **To verify:** turn graphics acceleration on (chrome://settings/system), restart Chrome, open the game, start City delivery, and check that it is smooth. If evaluators may use browsers without GPU acceleration (some locked-down or virtual machines), recommend the Windows build.

## 5. Build the packages

From the repo root, with Godot 4.7.2 in the root and the templates installed:

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy\build-release.ps1 -Version 2026.10.20
```

Outputs (git-ignored):

- `build\release\DroneAcharya-<ver>-web.zip`: about 10.6 MB; 11 files, `index.html` at the root, about 41 MB unpacked.
- `build\release\DroneAcharya-<ver>-win64.zip`: about 37 MB; folder with `DroneAcharya.exe` (data embedded), `README.txt`, `GODOT_LICENSE.txt`.

Test locally before uploading: `python -m http.server 8060 --directory build\web`, then open http://127.0.0.1:8060/ (not the file directly).

## 6. Upload to itch.io (manual)

1. Sign in at itch.io → **Upload new project**.
2. **Kind of project:** HTML.
3. **Uploads:** upload `DroneAcharya-<ver>-web.zip` and tick **"This file will be played in the browser"**.
4. **Embed options:** viewport 1600 × 900 (or "Click to launch in fullscreen"); tick **Fullscreen button**. Leave **SharedArrayBuffer support** unticked (the export is single-threaded and does not need it).
5. **Visibility:** *Restricted* or *Draft* while testing; share the page (or a secret URL) with evaluators.
6. Optionally upload `DroneAcharya-<ver>-win64.zip` as a second, downloadable file on the same page and mark it "Windows".
7. Description suggestion: "Synthetic drone-flight and counter-drone threat-recognition training prototype. Desktop browser with mouse and keyboard; hardware-accelerated graphics recommended. A Windows download is provided if the browser version is slow."
8. Open the page in a fresh browser window and play through the menu, a flight and a threat exercise before sharing it.

## 7. GitHub Release for the Windows build (manual)

1. Push the branch you built from, then tag that exact commit: `git tag -a v2026.10.20-demo -m "Evaluator demo build"` and `git push origin v2026.10.20-demo`.
2. On GitHub: **Releases → Draft a new release** → choose the tag.
3. Title "DroneAcharya 2026.10.20 (demo)". In the notes, list the requirements (Windows 10/11 64-bit, Vulkan), the SmartScreen "More info → Run anyway" step (not code-signed), and the SHA-256 printed by `build-release.ps1`.
4. Attach `DroneAcharya-<ver>-win64.zip` (and optionally the web ZIP), tick **Set as a pre-release**, publish.
   Or with the CLI: `gh release create v2026.10.20-demo build\release\DroneAcharya-2026.10.20-win64.zip --prerelease --title "DroneAcharya 2026.10.20 (demo)" --notes-file <notes.md>`.

## 8. Known limitations

- Web: Compatibility renderer, so lighting is flatter than on desktop.
- Web performance is unverified with GPU acceleration (section 4).
- Web: Import and Open folder are not available; the browser's saved data stays in that browser only (clearing site data deletes it).
- Web: needs a desktop browser with mouse and keyboard; untested on Firefox, Safari and mobile.
- Windows: the exe is not code-signed, so SmartScreen shows a warning on first run. It shares `%APPDATA%\DroneAcharya` with the development build.
- Exported builds exclude `tests/`, so the Settings screen's ML latency line is not shown (by design).
