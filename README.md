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

**Actions > Excavator** checks for new versions every **Monday and Friday at 08:30 IST** (03:00 UTC). It also has a manual **Run workflow** option. There is **one Windows job** per invocation:

1. Scoop's **native `checkver.ps1 -Update`** updates manifest versions and SHA-256 hashes in the runner's checkout.
2. If nothing changed, the job exits without a commit or pull request.
3. If manifests changed, the **same Windows job** runs the Python manifest tests and installs, verifies, and uninstalls **only the changed apps**.
4. The job pushes changed JSON files to a new **`automation/scoop-<run-id>`** branch **in this repository**, then opens a **pull request targeting this repository's `main` branch**.
5. Each PR contains previous/new versions, upstream installer URLs, per-architecture SHA-256 hashes, the verification outcomes, any warnings, and a link to the Actions run. **Nothing is merged automatically.**
6. If a previous auto-update PR remains open, the job skips the next proposal. Merge or close that PR before another update; this avoids duplicate pending PRs.

The old separate validation workflow is deliberately removed. There are no `push`, `pull_request`, or `workflow_run` triggers. Update and validation happen in the **same billable job**, avoiding separately rounded runner minutes.

### Authentication and permissions

GitHub supplies a **temporary `GITHUB_TOKEN`** scoped to this repository. The workflow requests only `contents: write` (to push a proposal branch) and `pull-requests: write` (to create a PR). **It never writes to ScoopInstaller's official repositories.** No personal access token is needed.

**Required GitHub setting:** Go to **Settings > Actions > General > Workflow permissions** and enable **Allow GitHub Actions to create and approve pull requests**. New personal repositories generally disable this by default. The workflow creates PRs but never approves or merges them.

To upgrade apps on your own PC, independently run `scoop update` and then `scoop update todoist` (or whichever apps you want).

## Packaging notes

| App | Installer / update mechanism |
| --- | --- |
| Todoist | Electron NSIS; unpack `app-*.7z`; x64/ARM64; download and hash fresh installers on release changes |
| Toggl | Electron NSIS; unpack `app-64.7z`; use `latest.yml` for version discovery |
| Wispr Flow | Electron/Squirrel; extract `*-full.nupkg`; use vendor `latest.json` for version and SHA-256 |
| FreeFileSync | Inno Setup, extracted by Scoop |
| Directory Monitor | Vendor portable ZIP with persisted `Data` directory |
| yq | Standalone native Windows binaries, including ARM64 |

These are personal-use recipes. Upstream installer contents, URLs, feed layouts, auto-updaters, and vendor terms can change. A successful version/checksum update does **not** prove the GUI app launches. The Windows smoke tests validate extraction on x64 only; ARM64 downloads are not executed. Only **changed apps** are installation-tested during an update run.

### Known limitations

- Todoist's and Toggl's embedded Electron archives can change names or layouts; guarded `pre_install` steps will fail loudly if their expected executables disappear.
- Wispr Flow's checksum matching assumes the SHA-256 in `latest.json` corresponds to its x64 installer; inspect it if the download hash fails.
- Directory Monitor's `cb` query-string format should be reviewed if an updated manifest starts returning a different ZIP.
- This bucket intentionally mirrors `yq` for convenience even though an official Scoop manifest exists.

## Check locally

```powershell
python -m unittest discover -s tests -v
```

The updater continues checking other manifests after one check fails. Any failures are included in the proposed PR, and the job is marked failed after the PR is created. If no manifests change but a check fails, the job fails without opening a PR.
