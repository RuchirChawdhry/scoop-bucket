# scoop-bucket

Personal [Scoop](https://scoop.sh/) bucket (local alias: `ruchir`). These manifests reference vendors' downloads; no installers are hosted here.

## Install

```powershell
scoop bucket add ruchir https://github.com/RuchirChawdhry/scoop-bucket
scoop install ruchir/todoist ruchir/toggl ruchir/wispr-flow
# Other manifests:
scoop install ruchir/freefilesync ruchir/directorymonitor ruchir/yq
```

The name `ruchir` is a local Scoop bucket alias; the GitHub repository remains `RuchirChawdhry/scoop-bucket`. If you already registered it as `convenience`, you can add `ruchir` as above. Do not remove `convenience` until you have accounted for any apps installed from that bucket, since Scoop records an app's originating bucket name.

To refresh manifests and installed apps:

```powershell
scoop update
scoop update '*'
```

## Automatic maintenance: review first

**Actions > Excavator** runs every **Monday and Friday at 08:30 IST** (03:00 UTC), or manually with **Run workflow**. One lightweight **`ubuntu-slim` job** performs the entire maintenance pass:

1. It checks out this bucket and the public Scoop core source (read-only) to use Scoop's native PowerShell `checkver.ps1 -Update`.
2. It checks upstream releases and updates versions, download URLs and SHA-256 hashes in the job's temporary checkout.
3. If nothing changed, it finishes without creating a commit or pull request.
4. If something changed, it runs Python's offline manifest tests, validates declared executable paths and SHA-256 formats, and inspects any installer archives already downloaded into Scoop's cache (using 7-Zip). **Windows installers are not executed on Linux.**
5. It pushes updated JSON files to a new `automation/scoop-<run-id>` branch **in this repository** and creates a detailed pull request targeting **this repository's `main`**. The PR contains version comparisons, source URLs, hashes, validation results, errors and a run link. **Nothing is automatically merged.**
6. If a previous update PR is open, the next scheduled run skips opening a duplicate. Merge or close the existing PR to resume proposals.

There is **one job per run**, and only two triggers: the Monday/Friday schedule and optional manual dispatch. No push, pull request, or workflow-completion triggers. There is no separate validator job to round up minutes.

### Runner considerations

`ubuntu-slim` provides 1 vCPU, 5 GB RAM and a 15-minute hard time limit. This workflow sets a 14-minute limit. It includes PowerShell, Python, GitHub CLI and 7-Zip; no Windows virtual machine or Scoop installer setup is required. Scoop's version-checking scripts are Windows-oriented, so Linux compatibility must be verified on the first actual workflow run. A metadata-only check or cached-archive listing **does not prove a Windows installation succeeds**. Windows executable launch, uninstall behavior and ARM64 execution are not tested. Very large upstream downloads may exceed the runner time limit.

### Authentication and permissions

GitHub automatically provides a short-lived, **repository-scoped `GITHUB_TOKEN`** for the workflow. It has `contents: write` (push update branch) and `pull-requests: write` (create proposal) **only on this repository**. It cannot push to Scoop's official repositories. No personal access token is required.

Enable **Settings > Actions > General > Workflow permissions > Allow GitHub Actions to create and approve pull requests**. The workflow does **not** approve or merge PRs.

To update locally installed apps after merging an update PR:

```powershell
scoop update
scoop update todoist wispr-flow
```

## Packaging notes

| App | Installer / update mechanism |
| --- | --- |
| Todoist | Electron NSIS; unpack `app-*.7z`; x64/ARM64; download and hash fresh installers on release changes |
| Toggl | Electron NSIS; unpack `app-64.7z`; use `latest.yml` for version discovery |
| Wispr Flow | Electron/Squirrel; extract `*-full.nupkg`; use vendor `latest.json` for version and SHA-256 |
| FreeFileSync | Inno Setup, extracted by Scoop |
| Directory Monitor | Vendor portable ZIP with persisted `Data` directory |
| yq | Standalone native Windows binaries, including ARM64 |

These are personal-use recipes. Upstream installer contents, URLs, feed layouts, auto-updaters, and vendor terms can change. A successful version/checksum update does **not** prove the GUI app launches. Ubuntu verification checks manifest structure and cached archives where available. **Windows installation tests no longer run**; GUI functionality and ARM64 execution remain untested.

### Known limitations

- Todoist's and Toggl's embedded Electron archives can change names or layouts; guarded `pre_install` steps will fail loudly if their expected executables disappear.
- Wispr Flow's checksum matching assumes the SHA-256 in `latest.json` corresponds to its x64 installer; inspect it if the download hash fails.
- Directory Monitor's `cb` query-string format should be reviewed if an updated manifest starts returning a different ZIP.
- This bucket intentionally mirrors `yq` for convenience even though an official Scoop manifest exists.

## Check locally

```powershell
python -m unittest discover -s tests -v
```

The updater continues checking remaining manifests after an individual version check fails. If any manifest changes, failures are included in the proposal report and the job is marked failed after PR creation. If no manifest changes but an upstream check fails, the job fails without creating a PR.
