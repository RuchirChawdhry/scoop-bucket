# Scoop updates: discover changes, validate installations, propose a reviewable PR.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Get-PendingPR([string]$Repo) {
    $json = gh pr list --repo $Repo --base main --state open --limit 100 --json headRefName,url
    if ($LASTEXITCODE -ne 0) { throw 'Could not list existing PRs.' }
    $json | ConvertFrom-Json | Where-Object headRefName -like 'automation/scoop-*' |
        Select-Object -First 1
}

function Update-Manifests([string]$Bucket, [string]$Checkver) {
    if (!(Test-Path -LiteralPath $Checkver)) { throw "Missing Scoop checkver.ps1: $Checkver" }
    $files = @(Get-ChildItem $Bucket -Filter '*.json' -File | Sort-Object Name)
    $before = @{}
    $errors = @()

    foreach ($file in $files) {
        $before[$file.BaseName] = Get-Content -Raw $file.FullName | ConvertFrom-Json -AsHashtable
        Write-Host "Checking $($file.BaseName)"
        & pwsh -NoProfile -File $Checkver -App $file.FullName -Update -ThrowError | Out-Host
        if ($LASTEXITCODE -ne 0) { $errors += "$($file.BaseName): checkver exited $LASTEXITCODE" }
    }

    $changed = @(git diff --name-only -- bucket | Where-Object { $_ -match '^bucket/.+\.json$' })
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect updated manifests.' }
    $changes = @(foreach ($relative in $changed) {
        $name = [IO.Path]::GetFileNameWithoutExtension($relative)
        $path = (Resolve-Path -LiteralPath (Join-Path $Bucket "$name.json")).Path
        [pscustomobject]@{
            Name = $name; Path = $path; Before = $before[$name]
            After = (Get-Content -Raw $path | ConvertFrom-Json -AsHashtable)
            Result = 'NOT RUN'
        }
    })
    [pscustomobject]@{ Changes = $changes; Errors = $errors }
}

function Get-ManifestExecutables($Manifest) {
    foreach ($item in $Manifest.shortcuts) { $item[0] }
    foreach ($item in $Manifest.bin) {
        if ($item -is [array]) { $item[0] } else { $item }
    }
}

function Test-Manifests([object[]]$Changes) {
    $errors = @()
    & python -m unittest discover -s tests -v 2>&1 | Out-Host
    $offlinePassed = ($LASTEXITCODE -eq 0)
    if (!$offlinePassed) { $errors += 'Offline manifest tests failed.' }

    & scoop install 7zip | Out-Host
    $ready = ($LASTEXITCODE -eq 0)
    if (!$ready) { $errors += 'Could not install 7zip for extraction tests.' }

    foreach ($change in $Changes) {
        if (!$ready) { $change.Result = 'SKIPPED (7zip unavailable)'; continue }
        try {
            # Scoop resolves absolute JSON paths; './bucket/...' is misread as a bucket ID.
            Write-Host "Installing $($change.Name) from $($change.Path)"
            & scoop install $change.Path | Out-Host
            if ($LASTEXITCODE -ne 0) { throw "scoop install failed ($LASTEXITCODE)" }

            $lines = @(scoop prefix $change.Name)
            if ($LASTEXITCODE -ne 0 -or !$lines.Count) { throw 'scoop prefix failed' }
            $prefix = $lines[-1].Trim()
            if (!(Test-Path -LiteralPath $prefix -PathType Container)) { throw "Missing install directory: $prefix" }

            $executables = @(Get-ManifestExecutables -Manifest $change.After | Select-Object -Unique)
            if (!$executables.Count) { throw 'No executable declared in shortcuts or bin.' }
            foreach ($file in $executables) {
                $exe = Join-Path $prefix ($file -replace '/', '\')
                if (!(Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Missing executable: $exe" }
            }
            $change.Result = 'PASS (install and executable)'
        } catch {
            $change.Result = 'FAIL'
            $errors += ('{0}: {1}' -f $change.Name, $_.Exception.Message)
        }
    }
    [pscustomobject]@{ OfflinePassed = $offlinePassed; Errors = $errors }
}

function New-PRReport([string]$Repo, [string]$RunId, [object[]]$Changes,
                      [bool]$OfflinePassed, [string[]]$Errors) {
    $rows = foreach ($change in $Changes) {
        '| {0} | {1} | {2} | {3} |' -f $change.Name, $change.Before.version,
            $change.After.version, $change.Result
    }
    $downloads = foreach ($change in $Changes) {
        "#### $($change.Name)"
        $sources = if ($change.After.Contains('architecture')) {
            $change.After.architecture
        } else { @{ default = $change.After } }
        foreach ($arch in $sources.Keys) {
            '- **{0}**: {1}' -f $arch, $sources[$arch].url
            '  - SHA-256: {0}' -f $sources[$arch].hash
        }
        ''
    }
    $issues = if ($Errors.Count) { $Errors | ForEach-Object { "- $_" } } else { '- None detected.' }
    $offline = if ($OfflinePassed) { 'PASS' } else { 'FAIL' }

    @"
## Proposed Scoop manifest updates

Workflow run: https://github.com/$Repo/actions/runs/$RunId

### Changes and validation results

| App | Previous version | Proposed version | Windows validation |
| --- | --- | --- | --- |
$($rows -join [Environment]::NewLine)

### Validation

- Offline manifest tests: $offline
- Changed apps: installed via absolute JSON manifest paths and checked for expected executables on Windows x64.
- No bucket registration or uninstall; GUI launch and ARM64 execution are not tested.

### Upstream download URLs and SHA-256

$($downloads -join [Environment]::NewLine)
### Errors and warnings

$($issues -join [Environment]::NewLine)

### Review policy

- This PR affects only this repository, not any official ScoopInstaller repository.
- No auto-merge: review the versions, hashes, and validation before merging.
"@
}

function Publish-PR([string]$Repo, [string]$RunId, [object[]]$Changes, [string]$Report) {
    $body = Join-Path $env:RUNNER_TEMP 'scoop-update.md'
    $Report | Set-Content -LiteralPath $body -Encoding utf8
    $Report | Add-Content -Path $env:GITHUB_STEP_SUMMARY -Encoding utf8
    $branch = "automation/scoop-$RunId"

    & git switch -c $branch | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Could not create PR branch.' }
    & git add -- bucket | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Could not stage manifests.' }
    & git -c user.name='github-actions[bot]' -c user.email='41898282+github-actions[bot]@users.noreply.github.com' commit -m ('chore(scoop): update ' + ($Changes.Name -join ', ')) | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Could not commit manifests.' }
    & git push origin "HEAD:refs/heads/$branch" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Could not push PR branch.' }
    & gh pr create --repo $Repo --base main --head $branch --title ('chore(scoop): update ' + ($Changes.Name -join ', ')) --body-file $body | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Could not open PR; check repository Actions permissions.' }
}

function Invoke-Maintenance {
    $repo = $env:GITHUB_REPOSITORY
    if (!$repo -or !$env:GH_TOKEN) { throw 'GitHub repository and GH_TOKEN are required.' }
    Push-Location (Join-Path $PSScriptRoot '..')
    try {
        $pending = Get-PendingPR -Repo $repo
        if ($pending) {
            $message = "Existing update PR: $($pending.url). Merge or close it before proposing another update."
            Write-Host $message
            Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $message
            return
        }

        $bucket = (Resolve-Path './bucket').Path
        $checkver = Join-Path $env:USERPROFILE 'scoop\apps\scoop\current\bin\checkver.ps1'
        $updates = Update-Manifests -Bucket $bucket -Checkver $checkver
        if (!$updates.Changes.Count) {
            Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value 'No changes; no pull request needed.'
            if ($updates.Errors.Count) { throw ($updates.Errors -join '; ') }
            return
        }

        $validation = Test-Manifests -Changes $updates.Changes
        $errors = @($updates.Errors) + @($validation.Errors)
        $report = New-PRReport -Repo $repo -RunId $env:GITHUB_RUN_ID -Changes $updates.Changes -OfflinePassed $validation.OfflinePassed -Errors $errors
        Publish-PR -Repo $repo -RunId $env:GITHUB_RUN_ID -Changes $updates.Changes -Report $report
        if ($errors.Count) { throw 'PR created with validation failures; review its report.' }
    } finally { Pop-Location }
}

# Dot-source in tests without executing any external commands.
if ($MyInvocation.InvocationName -ne '.') { Invoke-Maintenance }
