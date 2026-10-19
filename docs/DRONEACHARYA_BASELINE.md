# DroneAcharya — Version-control baseline

Created: 2026-10-20 (Stage 0)

## What existed before

- No Git repository existed in `E:\Hardik\Programming\DroneAcharya`, in `VIGIL\`, or in any parent folder. There was therefore no history, remote or repository configuration to preserve.
- VIGIL's own `.gitignore` and `.gitattributes` were kept unchanged.

## The baseline

| Item | Value |
|---|---|
| Repository | `E:\Hardik\Programming\DroneAcharya\.git` (new, branch `main`, no remotes) |
| Baseline commit | `24b37d1` "Baseline: VIGIL as received, plus Phase 1 audit docs" |
| Tag | `baseline-vigil-2026-10-20` |
| Contents | 373 files: all of `VIGIL\` (including `docs\screenshots\`), the root `.gitignore`, and the four Phase 1 docs |
| Excluded | `Godot_v4.7.2-stable_win64.exe`, `Godot_v4.7.2-stable_win64_console.exe` (root `.gitignore`) |

Two deliberate choices:

1. **`VIGIL\dist\` was force-added** (`git add -f`). VIGIL's `.gitignore` excludes `dist/`, but `dist\` holds the prebuilt app that `START-VIGIL.cmd` serves. The rule itself was not edited. Because the files were added explicitly, Git tracks them despite the rule.
2. **Repository-local `core.autocrlf=false`.** Your global setting is `true`; it was not changed. With `true`, Git would convert VIGIL's LF files to CRLF on a future checkout, and they would no longer match `VIGIL\RELEASE_MANIFEST.json`. The local setting stores and restores files byte for byte.

## Verification performed

- All **367** files listed in `VIGIL\RELEASE_MANIFEST.json` were hashed (SHA-256) **from the commit** and every one matches the manifest.
- `START-VIGIL.cmd` is stored with LF internally because of VIGIL's own `*.cmd text eol=crlf` rule. A restore through `git archive` gives CRLF bytes whose hash matches the manifest.
- `git status` was clean after the commit.

## How to restore VIGIL to the baseline

These commands only touch `VIGIL\`. **They discard uncommitted changes in `VIGIL\`**, so commit or copy anything you want to keep first.

```powershell
git -C E:\Hardik\Programming\DroneAcharya diff --stat baseline-vigil-2026-10-20 -- VIGIL          # 1. see what differs (read-only)
git -C E:\Hardik\Programming\DroneAcharya restore --source=baseline-vigil-2026-10-20 -- VIGIL     # 2. restore those files
```

To get a separate pristine copy without touching the working folder:

```powershell
git -C E:\Hardik\Programming\DroneAcharya archive --format=zip -o VIGIL-baseline.zip baseline-vigil-2026-10-20 VIGIL
```
