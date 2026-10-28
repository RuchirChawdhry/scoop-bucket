# scoop-bucket

Personal convenience [Scoop](https://scoop.sh/) bucket. These manifests reference vendors' downloads; no installers are hosted here.

## Install

```powershell
scoop bucket add convenience https://github.com/RuchirChawdhry/scoop-bucket
scoop install convenience/todoist convenience/toggl convenience/wispr-flow
# Other manifests:
scoop install convenience/freefilesync convenience/directorymonitor convenience/yq
```

To refresh manifests and installed apps:

```powershell
scoop update
scoop update '*'
```

## Automatic maintenance

- **Excavator** runs every **Monday and Friday at 08:30 IST** (03:00 UTC), and on demand via **Actions > Excavator > Run workflow**.
- Scoop's official [GithubActions/Excavator](https://github.com/ScoopInstaller/GithubActions) checks each manifest's `checkver`, resolves `autoupdate` URLs, calculates or retrieves SHA-256 values, and commits updates directly to `main`.
- **Validate bucket** runs offline manifest tests and, on Windows x64, installs/uninstalls the three Electron packages and confirms the extracted executables are present. It runs on regular pushes, pull requests, manual dispatch, and after Excavator completes. The `workflow_run` hook is necessary because commits made with `GITHUB_TOKEN` don't themselves trigger new `push` workflows.
- GitHub Actions maintains only **manifests**, not the software installed on your own PCs. Run `scoop update` locally to upgrade.
- Allow Actions **read and write repository permissions** (Settings > Actions > General), if the automatic commits are blocked.

## Packaging notes

| App | Installer / update mechanism |
| --- | --- |
| Todoist | Electron NSIS; unpack `app-*.7z`; x64/ARM64; download and hash fresh installers on release changes |
| Toggl | Electron NSIS; unpack `app-64.7z`; use `latest.yml` for version discovery |
| Wispr Flow | Electron/Squirrel; extract `*-full.nupkg`; use vendor `latest.json` for version and SHA-256 |
| FreeFileSync | Inno Setup, extracted by Scoop |
| Directory Monitor | Vendor portable ZIP with persisted `Data` directory |
| yq | Standalone native Windows binaries, including ARM64 |

These are personal-use recipes. Upstream installer contents, URLs, feed layouts, auto-updaters, and vendor terms can change. A successful version/checksum update does **not** prove the GUI app launches. The Windows smoke tests validate extraction on x64 only; ARM64 downloads are not executed.

### Known limitations

- Todoist's and Toggl's embedded Electron archives can change names or layouts; guarded `pre_install` steps will fail loudly if their expected executables disappear.
- Wispr Flow's checksum matching assumes the SHA-256 in `latest.json` corresponds to its x64 installer; inspect it if the download hash fails.
- Directory Monitor's `cb` query-string format should be reviewed if an updated manifest starts returning a different ZIP.
- This bucket intentionally mirrors `yq` for convenience even though an official Scoop manifest exists.

## Check locally

```powershell
python -m unittest discover -s tests -v
```

The scheduled updates run with `THROW_ERROR` omitted so one transient upstream failure does not prevent other manifests being processed. Review the Excavator logs after the first manual run.
