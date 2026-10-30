# No Pester dependency; run with pwsh -NoProfile -File ./tests/test_update.ps1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\update.ps1')

function Assert-Test([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}

$manifest = @{
    shortcuts = @(, @('Todoist.exe', 'Todoist'))
    bin       = @('helper.exe', @('tools\cli.exe', 'cli'))
}
$executables = @(Get-ManifestExecutables -Manifest $manifest)
Assert-Test ($executables.Count -eq 3) 'Expected shortcuts, scalar bin and array bin entries'
foreach ($name in @('Todoist.exe', 'helper.exe', 'tools\cli.exe')) {
    Assert-Test ($executables -contains $name) "Missing executable declaration: $name"
}
$single = @(Get-ManifestExecutables -Manifest @{ bin = 'yq.exe' })
Assert-Test ($single.Count -eq 1 -and $single[0] -eq 'yq.exe') 'Scalar bin should be one executable'
Assert-Test (@(Get-ManifestExecutables -Manifest @{}).Count -eq 0) 'Missing bin and shortcuts should yield no executables'

$change = [pscustomobject]@{
    Name   = 'todoist'
    Path   = 'C:\repo\bucket\todoist.json'
    Before = @{ version = '9.31.0' }
    After  = @{ version = '9.35.0'; architecture = @{
        '64bit' = @{ url = 'https://example.com/todoist.exe'; hash = ('a' * 64) }
        'arm64' = @{ url = 'https://example.com/todoist-arm.exe'; hash = ('b' * 64) }
    } }
    Result = 'PASS (install and executable)'
}
$report = New-PRReport -Repo 'owner/repo' -RunId '42' -Changes @($change) -OfflinePassed $true -Errors @()
foreach ($item in @('9.31.0', '9.35.0', 'PASS', 'https://example.com/todoist-arm.exe', ('b' * 64), 'No auto-merge', 'None detected')) {
    Assert-Test ($report.Contains($item)) "PR report omitted $item"
}
$failed = New-PRReport -Repo 'owner/repo' -RunId '42' -Changes @($change) -OfflinePassed $false -Errors @('Failed to install')
Assert-Test ($failed.Contains('Failed to install') -and $failed.Contains('FAIL')) 'Failed checks must be visible in report'

# Mock command boundaries: no PR or validation if no manifest changed.
$env:GITHUB_REPOSITORY = 'owner/repo'
$env:GH_TOKEN = 'test-token'
$env:GITHUB_STEP_SUMMARY = Join-Path ([IO.Path]::GetTempPath()) ('scoop-test-' + [guid]::NewGuid().ToString() + '.md')
function Get-PendingPR { param($Repo) return $null }
function Update-Manifests { param($Bucket, $Checkver) return [pscustomobject]@{ Changes = @(); Errors = @() } }
function Test-Manifests { throw 'Validation must not run when nothing changed' }
function Publish-PR { throw 'Must not publish when nothing changed' }
Invoke-Maintenance
Assert-Test ((Get-Content -Raw $env:GITHUB_STEP_SUMMARY).Contains('No changes')) 'No-change flow did not summarize'
Remove-Item -LiteralPath $env:GITHUB_STEP_SUMMARY -ErrorAction SilentlyContinue

# Pending proposals must short-circuit before checking upstream.
function Get-PendingPR { param($Repo) return [pscustomobject]@{ url = 'https://github.com/owner/repo/pull/12' } }
function Update-Manifests { throw 'Must not check upstream when a PR is open' }
Invoke-Maintenance
Assert-Test ((Get-Content -Raw $env:GITHUB_STEP_SUMMARY).Contains('pull/12')) 'Pending PR did not short-circuit'

# Failed upstream checks must fail the run, even when no manifests changed.
function Get-PendingPR { param($Repo) return $null }
function Update-Manifests { param($Bucket, $Checkver) return [pscustomobject]@{ Changes = @(); Errors = @('upstream unavailable') } }
$failedAsExpected = $false
try { Invoke-Maintenance } catch { $failedAsExpected = $_.Exception.Message.Contains('upstream unavailable') }
Assert-Test $failedAsExpected 'No-change run must surface failed release checks'

Write-Host 'PowerShell updater behavior tests passed.'
