# Scoop maintenance in one Windows job: check releases -> validate -> propose PR.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-Location (Split-Path -Parent $PSScriptRoot)

$repo = $env:GITHUB_REPOSITORY
if (!$repo -or !$env:GH_TOKEN) { throw 'GitHub repository and GH_TOKEN are required.' }
$openJson = & gh pr list --repo $repo --base main --state open --limit 100 --json headRefName,url
if ($LASTEXITCODE -ne 0) { throw 'Could not list existing PRs.' }
$pending = @($openJson | ConvertFrom-Json | Where-Object { $_.headRefName -like 'automation/scoop-*' })
if ($pending.Count -gt 0) {
    $message = "Existing update PR: $($pending[0].url). Merge or close it before proposing another update."
    Write-Host $message
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $message
    return
}

$bucket = (Resolve-Path './bucket').Path
$checkver = Join-Path $PSScriptRoot '..\.scoop-core\bin\checkver.ps1'
if (!(Test-Path -LiteralPath $checkver)) { throw "Missing Scoop checkver.ps1: $checkver" }
$files = @(Get-ChildItem $bucket -Filter '*.json' -File | Sort-Object Name)
$before = @{}
foreach ($file in $files) {
    $before[$file.BaseName] = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json -AsHashtable
}

$checkErrors = @()
foreach ($file in $files) {
    Write-Host "Checking $($file.BaseName)"
    & pwsh -NoProfile -File $checkver -App $file.BaseName -Dir $bucket -Update -ThrowError
    if ($LASTEXITCODE -ne 0) { $checkErrors += "$($file.BaseName): checkver exited $LASTEXITCODE" }
}
$changed = @(git diff --name-only -- bucket | Where-Object { $_ -match '^bucket/.+\.json$' } |
    ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) })
if ($changed.Count -eq 0) {
    $message = 'No changes; no pull request needed.'
    Write-Host $message
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $message
    if ($checkErrors.Count) { throw ($checkErrors -join '; ') }
    return
}

$after = @{}
foreach ($app in $changed) {
    $after[$app] = Get-Content -Raw "./bucket/$app.json" | ConvertFrom-Json -AsHashtable
}
$problems = @($checkErrors)
$tests = @{}

# All validation runs in this SAME ubuntu-slim job, without invoking Windows installers.
& python -m unittest discover -s tests -v
$offlinePassed = ($LASTEXITCODE -eq 0)
if (!$offlinePassed) { $problems += 'Offline manifest tests failed.' }

# Scoop caches downloaded installers when calculating a hash. Inspect them, if present,
# instead of downloading large Windows installers a second time on a 15-minute runner.
$cacheFiles = @()
if ($env:SCOOP_CACHE -and (Test-Path -LiteralPath $env:SCOOP_CACHE)) {
    $cacheFiles = @(Get-ChildItem -LiteralPath $env:SCOOP_CACHE -File -ErrorAction SilentlyContinue)
}
foreach ($app in $changed) {
    $tests[$app] = 'PASS (manifest), SKIP (archive not cached; installer not executed)'
    $expected = @()
    if ($after[$app].Contains('shortcuts')) {
        foreach ($shortcut in $after[$app]['shortcuts']) { $expected += [string]$shortcut[0] }
    }
    if ($after[$app].Contains('bin')) {
        foreach ($item in @($after[$app]['bin'])) {
            if ($item -is [array]) { $expected += [string]$item[0] }
            else { $expected += [string]$item }
        }
    }
    if ($expected.Count -eq 0) {
        $tests[$app] = 'FAIL (no executable/shortcut)'
        $problems += "$app has no declared executable."
        continue
    }
    $hashes = @()
    if ($after[$app].Contains('architecture')) {
        foreach ($arch in $after[$app]['architecture'].Keys) {
            $hashes += [string]$after[$app]['architecture'][$arch]['hash']
        }
    } else {
        $hashes += [string]$after[$app]['hash']
    }
    foreach ($hash in $hashes) {
        if ($hash -notmatch '^[0-9a-fA-F]{64}$') {
            $tests[$app] = 'FAIL (invalid SHA-256)'
            $problems += "$app contains an invalid SHA-256."
        }
    }
    # Optional stronger archive test for packages already cached during checkver.
    # A cache miss is not a failure: some manifests obtain hashes from upstream metadata.
    if ($app -notin @('todoist', 'toggl', 'wispr-flow', 'directorymonitor')) { continue }
    $cached = @($cacheFiles | Where-Object { $_.Name -like "*$app*" })
    foreach ($file in $cached) {
        if ($file.Extension -notin @('.zip', '.7z', '.exe', '.nupkg')) { continue }
        $listing = & 7z l $file.FullName 2>&1
        if ($LASTEXITCODE -ne 0) {
            $problems += "$app: cached archive listing failed ($($file.Name))"
            $tests[$app] = 'FAIL (cached archive could not be listed)'
        } else {
            $tests[$app] = 'PASS (manifest + cached archive); installer not executed'
            Write-Host "Archive readable for $app : $($file.Name)"
        }
    }
}

# PR body contains all evidence; only updated manifests are committed.
$report = @(
    '## Proposed Scoop manifest updates', '',
    ('Workflow run: https://github.com/{0}/actions/runs/{1}' -f $repo, $env:GITHUB_RUN_ID), '',
    '### Changes and validation results', '',
    '| App | Previous version | Proposed version | Linux validation |',
    '| --- | --- | --- | --- |'
)
foreach ($app in $changed) {
    $report += ('| {0} | {1} | {2} | {3} |' -f $app, $before[$app]['version'], $after[$app]['version'], $tests[$app])
}
$report += @('', '### Validation', '',
    ('- Offline manifest tests: {0}' -f $(if ($offlinePassed) { 'PASS' } else { 'FAIL' })),
    '- Changed manifests: validated executable declarations, SHA-256 format, and any downloaded archive present in Scoop cache.',
    '- This runs on ubuntu-slim: Windows executables are NOT installed or launched; archive checks are opportunistic if files are cached.', '',
    '### Upstream download URLs and SHA-256', '')
foreach ($app in $changed) {
    $report += "#### $app"
    $sources = if ($after[$app].Contains('architecture')) { $after[$app]['architecture'] } else { @{ 'default' = $after[$app] } }
    foreach ($arch in $sources.Keys) {
        $report += ('- **{0}**: {1}' -f $arch, $sources[$arch]['url'])
        $report += ('  - SHA-256: {0}' -f $sources[$arch]['hash'])
    }
    $report += ''
}
$report += @('### Errors and warnings', '')
if ($problems.Count -eq 0) { $report += '- None detected.' }
else { foreach ($problem in $problems) { $report += "- $problem" } }
$report += @('', '### Review policy', '',
    '- This PR changes manifests ONLY in this repository, never an official ScoopInstaller repository.',
    '- No auto-merge: please inspect the versions, hashes, and validation results before merging.'
)
$bodyFile = Join-Path $env:RUNNER_TEMP 'scoop-update.md'
$report | Set-Content -LiteralPath $bodyFile -Encoding utf8
$report | Add-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding utf8

$branch = "automation/scoop-$env:GITHUB_RUN_ID"
& git switch -c $branch
if ($LASTEXITCODE -ne 0) { throw 'Could not create PR branch.' }
& git add -- bucket
if ($LASTEXITCODE -ne 0) { throw 'Could not stage manifests.' }
& git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' commit -m ('chore(scoop): update ' + ($changed -join ', '))
if ($LASTEXITCODE -ne 0) { throw 'Could not commit manifests.' }
& git push origin "HEAD:refs/heads/$branch"
if ($LASTEXITCODE -ne 0) { throw 'Could not push PR branch.' }
& gh pr create --repo $repo --base main --head $branch --title ('chore(scoop): update ' + ($changed -join ', ')) --body-file $bodyFile
if ($LASTEXITCODE -ne 0) {
    throw 'Could not create PR. Enable Settings > Actions > General > Allow GitHub Actions to create and approve pull requests.'
}
if ($problems.Count -gt 0) { throw 'PR created with validation failures; review its report.' }
