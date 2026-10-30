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
$checkver = Join-Path $env:USERPROFILE 'scoop\apps\scoop\current\bin\checkver.ps1'
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

# Offline tests and Windows installation checks share this single Windows job.
& python -m unittest discover -s tests -v
$offlinePassed = ($LASTEXITCODE -eq 0)
if (!$offlinePassed) { $problems += 'Offline manifest tests failed.' }

& scoop install 7zip
$sevenZipReady = ($LASTEXITCODE -eq 0)
if (!$sevenZipReady) { $problems += 'Could not install 7zip for extraction tests.' }

foreach ($app in $changed) {
    if (!$sevenZipReady) {
        $tests[$app] = 'SKIPPED (7zip unavailable)'
        continue
    }
    $installed = $false
    try {
        Write-Host "Installing updated $app from local manifest..."
        & scoop install "./bucket/$app.json"
        if ($LASTEXITCODE -ne 0) { throw "scoop install failed ($LASTEXITCODE)" }
        $installed = $true

        $prefixLines = @(scoop prefix $app)
        if ($LASTEXITCODE -ne 0 -or $prefixLines.Count -eq 0) { throw 'scoop prefix failed' }
        $prefix = $prefixLines[-1].Trim()
        if (!(Test-Path -LiteralPath $prefix -PathType Container)) {
            throw "Install directory missing: $prefix"
        }

        $expected = @()
        if ($after[$app].Contains('shortcuts')) {
            foreach ($shortcut in $after[$app]['shortcuts']) {
                $expected += [string]$shortcut[0]
            }
        }
        if ($after[$app].Contains('bin')) {
            foreach ($item in @($after[$app]['bin'])) {
                if ($item -is [array]) { $expected += [string]$item[0] }
                else { $expected += [string]$item }
            }
        }
        if ($expected.Count -eq 0) { throw 'No executable declared in shortcuts or bin.' }
        foreach ($relative in ($expected | Select-Object -Unique)) {
            $exe = Join-Path $prefix ($relative -replace '/', '\')
            if (!(Test-Path -LiteralPath $exe -PathType Leaf)) {
                throw "Expected executable missing: $exe"
            }
        }
        $tests[$app] = 'PASS (install and executable)'
        Write-Host "Verified $app in $prefix"
    } catch {
        $tests[$app] = 'FAIL'
        $problems += ('{0}: {1}' -f $app, $_.Exception.Message)
    } finally {
        if ($installed) {
            & scoop uninstall $app | Out-Host
            if ($LASTEXITCODE -ne 0) {
                $tests[$app] = 'FAIL (uninstall)'
                $problems += "${app}: scoop uninstall exited $LASTEXITCODE"
            }
        }
    }
}

# PR body contains all evidence; only updated manifests are committed.
$report = @(
    '## Proposed Scoop manifest updates', '',
    ('Workflow run: https://github.com/{0}/actions/runs/{1}' -f $repo, $env:GITHUB_RUN_ID), '',
    '### Changes and validation results', '',
    '| App | Previous version | Proposed version | Windows validation |',
    '| --- | --- | --- | --- |'
)
foreach ($app in $changed) {
    $report += ('| {0} | {1} | {2} | {3} |' -f $app, $before[$app]['version'], $after[$app]['version'], $tests[$app])
}
$report += @('', '### Validation', '',
    ('- Offline manifest tests: {0}' -f $(if ($offlinePassed) { 'PASS' } else { 'FAIL' })),
    '- Changed apps: installed with Scoop, checked for expected executables, and uninstalled on Windows x64.',
    '- Unchanged apps are not reinstalled; graphical launch and ARM64 execution are not tested.', '',
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
