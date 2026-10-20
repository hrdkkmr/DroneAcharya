# DroneAcharya — Windows release

How the evaluator ZIP is built and what has been checked. Prepared 2026-10-20 on branch `deploy/web-and-windows`. For the browser build, see `DEPLOYMENT.md`.

## 1. Audit

| Question | Finding (from the code) |
|---|---|
| Engine | Godot 4.7.2 stable, standard (non-.NET) build. `project.godot`: `config/features=("4.7", "Forward Plus")`, so the renderer is Forward+ on Vulkan. No rendering overrides, so the engine's default driver fallbacks apply |
| Native code / plugins | None: no `.gdextension` files, no `addons/` |
| Python at run time | **Not used.** There is no `OS.execute` or `create_process`, and no network or IPC code. Python (`ml/`, `ml/requirements.txt`) is only used offline, to train the model and for tests |
| ML inference | `scripts/ai/ml_classifier.gd` loads `res://models/track_classifier_v1.json`, a scikit-learn random forest with 40 trees exported by `ml/train.py`, and evaluates it in GDScript. The model and `track_classifier_v1.metrics.json` are tracked in Git (`simulator/models/`) and bundled in the exe. If the model is missing or invalid, decision support falls back to the rule-based baseline and says so |
| Data files | `res://scenarios/*.json` (4 scenarios) and `res://models/*.json`, both in the preset's `include_filter`. Everything else is a scene, script or shader |
| Writable paths | Only `user://`, which is `%APPDATA%\DroneAcharya\`: `settings.cfg`, `sessions/`, `flight_sessions/`, `exports/`, `logs/` (Godot file logging) and the shader cache. Nothing is written next to the exe |
| Environment variables, services, secrets | None read or used. A scan of `simulator/`, `ml/`, `deploy/` and `schemas/` for keys, tokens or passwords found nothing |
| Runs without the dev environment | Yes. The exported exe needs only Windows and a GPU driver |
| Blockers | None found |

## 2. Package design

- **Export preset:** "Windows Desktop" (`simulator/export_presets.cfg`, unchanged). It uses the official 4.7.2 release template and embeds the game pack in the exe (`binary_format/embed_pck=true`). `tests/*` and `tools/*` are excluded.
- **ZIP contents:** one folder, `DroneAcharya-<version>-win64\`, holding:
  - `DroneAcharya.exe` (about 111 MB);
  - `README.txt` (from `deploy/windows/README.txt`, stamped with the version and commit);
  - `GODOT_LICENSE.txt`.

  The ZIP has no installer, DLLs or Python runtime, because none is needed.
- **Paths:** all game data is read from `res://` inside the exe, so the folder can be extracted anywhere.
- **Build script:** `deploy/build-release.ps1`. It was already used for the web build; `-Target Windows` is new.

## 3. Prerequisites (on the build PC)

1. Godot 4.7.2 stable, Windows 64-bit standard build. Put `Godot_v4.7.2-stable_win64.exe` and `Godot_v4.7.2-stable_win64_console.exe` in the repo root (see README, "Requirements").
2. Godot's official export templates for 4.7.2:
   - Download `Godot_v4.7.2-stable_export_templates.tpz` from the same release page.
   - Check it against the release's `SHA512-SUMS.txt`.
   - Install it, either with Editor → Manage Export Templates → Install from File, or by extracting `windows_release_x86_64.exe` and `windows_debug_x86_64.exe` (plus their `_console` files) into `%APPDATA%\Godot\export_templates\4.7.2.stable\`.
3. Windows PowerShell 5.1 or later, and `tar.exe`. Both are included with Windows 10 and 11.

Python is not needed to build. It is only needed to run the ML and schema tests.

## 4. Build the ZIP

From the repo root, after committing (so the README's commit id describes the build):

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy\build-release.ps1 -Target Windows -Version 2026.10.20
```

The output is `build\release\DroneAcharya-<version>-win64.zip`, plus the unpacked folder `build\windows\DroneAcharya-<version>-win64\`. The script prints the ZIP's size and SHA-256. `build/` is git-ignored; upload the ZIP to Google Drive by hand and put the link in the README's "Download and Run" section.

## 5. Verification (2026-10-20, Windows 11, Intel Core Ultra 5 125H, Intel Arc graphics, 16 GB)

### Executed

| Check | Result |
|---|---|
| Godot test suite before the build | 170 passed, 0 failed |
| ML tests (`ml/tests`) / schema tests (`schemas`) | 11 / 4 passed |
| Export `Windows Desktop` via the script | exit 0. ZIP 37.1 MB, 3 files in one folder |
| ZIP extracted with Python `zipfile` to a path containing spaces and accented letters (`…\rel test é ü\x\`) | Extracted; the exe starts from there |
| Contents of the embedded pack (303 entries) | Compiled scripts, scenes, shaders, 4 scenarios, the model and its metrics. **No** `tests/`, `tools/`, `ml/` data, Python files or development paths (`E:\`, user name) |
| Normal launch of the released exe, with `APPDATA` pointed at an empty scratch folder (a "new user") | Window opens. Vulkan Forward+ on Intel Arc. `godot.log` has no errors. Data is created only under the redirected `%APPDATA%\DroneAcharya\` |
| Scripted smoke test of the release pack (`--main-pack DroneAcharya.exe` with the Godot 4.7.2 engine, because exported templates ignore `--script`) | See the next table |

Results of the scripted smoke test:

| Step | Result |
|---|---|
| Main menu | All 8 buttons enabled (every scene present) |
| ML model | Loaded from the pack: track-classifier-v1, random forest, 40 trees, features-1 |
| Threat exercise | Scenario 01 ran to the end in the real observation scene with ML decision support on. 8 decisions were made, and the ML classifier returned a prediction for all 8 |
| Session record | Saved to `user://sessions/`; History lists it and reports nothing invalid; it reloads and validates |
| Report | Built (score 71.3 / 100, 2 correct · 1 incorrect) |
| Verify replay | Identical events and score |

### Not yet executed

| Check | Status |
|---|---|
| History screen opened on that report, and the City flight (climb, pause) from the release pack | Not run. The smoke run was stopped by Claude Code because the PC was low on memory (2 GB free), not by a game error |
| Direct3D 12 and OpenGL fallbacks (`--rendering-driver d3d12`, `--rendering-method gl_compatibility`) | Not run |
| Other PCs, Windows 10, other GPUs (NVIDIA, AMD, older Intel), high-DPI displays | Not run; one PC only |
| Download through Google Drive, and SmartScreen on a PC that has never seen the file | Not run (no link yet) |
| Flight training in the packaged exe | Not run by hand. Previously checked in the same exe build from this branch (see `DEPLOYMENT.md`, section 3, last row) |

## 6. Known limitations

- The exe is not code-signed, so SmartScreen warns on first run ("More info" → "Run anyway").
- Google Drive cannot virus-scan files over 25 MB, so it shows a "Download anyway" prompt.
- Tested on a single PC (above).
- Saved data is shared with a development checkout run on the same PC (both use `%APPDATA%\DroneAcharya`).
- The Settings screen's ML latency line is not shown in exported builds, because its fixture lives in `tests/` (by design).
