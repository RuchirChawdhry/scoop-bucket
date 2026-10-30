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

**Actions > Excavator** runs **every morning at 08:47 IST** (03:17 UTC), or manually with **Run workflow**. One standard **`windows-2025` job** handles the entire maintenance process:

1. Installs Scoop in the ephemeral Windows runner. Scoop's native `checkver.ps1 -Update` checks upstream versions, URLs and hashes for all six manifests.
2. If no manifests changed, the job finishes without opening a pull request.
3. If changes exist, the **same Windows job** runs offline Python tests and installs **only the updated applications**, directly from each manifest's resolved absolute JSON file path. It verifies expected executables. **No bucket registration or uninstall is needed** on the temporary runner. Failed checks are included in the proposal.
4. It pushes updated JSON files to a new `automation/scoop-<run-id>` branch **in this repository** and creates a detailed PR targeting **this repository's `main`**. Each PR includes old/new versions, download URLs, SHA-256 hashes, validation outcomes, failures, and the Actions run URL. **Nothing merges automatically.**
5. If a prior automated update PR remains open, the next run skips creating a duplicate. Review, merge or close that PR first.

GitHub Actions can defer or drop scheduled jobs during load, particularly at the start of an hour. The off-hour minute reduces the likelihood of queueing but **does not guarantee an exact start time**. See [GitHub's schedule documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule).

The workflow has only **two triggers**, the daily schedule and optional manual dispatch. There are no push, pull-request, or workflow-completion triggers, and no separately billed validator job.

### Runner and cost

GitHub explicitly provides **free and unlimited standard GitHub-hosted runner minutes for public repositories**, including `windows-2025` (4 vCPU, 16 GB RAM). This bucket is public. The minute-rounding charges that matter for private repositories do **not** apply to these standard public-repository jobs. Larger runners, storage, concurrency and execution limits are separate.

Windows extraction checks do **not** verify GUI startup or ARM64 execution, but they do test actual Scoop installation behavior and expected executable locations. Scheduled workflows may begin slightly later than their configured cron time if GitHub is busy.

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

These are personal-use recipes. Upstream installer contents, URLs, feed layouts, auto-updaters, and vendor terms can change. A successful version/checksum update does **not** prove the GUI app launches. Native Windows installation tests run for changed apps only; graphical launch and ARM64 execution remain untested.

### Known limitations

- Todoist's and Toggl's embedded Electron archives can change names or layouts; guarded `pre_install` steps will fail loudly if their expected executables disappear.
- Wispr Flow's checksum matching assumes the SHA-256 in `latest.json` corresponds to its x64 installer; inspect it if the download hash fails.
- Directory Monitor's `cb` query-string format should be reviewed if an updated manifest starts returning a different ZIP.
- This bucket intentionally mirrors `yq` for convenience even though an official Scoop manifest exists.

## Check locally

```powershell
python -m unittest discover -s tests -v
pwsh -NoProfile -File ./tests/test_update.ps1
```

The updater is organized as small PowerShell functions for PR discovery, manifest updates, installation verification, report formatting, and PR publishing. The separate PowerShell behavior tests run on the Windows Actions runner before Scoop is installed.

The updater continues checking remaining manifests after an individual version check fails. If any manifest changes, failures are included in the proposal report and the job is marked failed after PR creation. If no manifest changes but an upstream check fails, the job fails without creating a PR.
