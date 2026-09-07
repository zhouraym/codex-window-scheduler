[CmdletBinding()]
param(
    [string[]]$Times = @("07:00", "12:00", "17:00", "22:00"),
    [string]$TaskName = "Codex 5h Window Activator",
    [switch]$RunNow
)

$ErrorActionPreference = "Stop"

$RunnerPath = Join-Path $PSScriptRoot "codex-window.ps1"
$ConfigPath = Join-Path $PSScriptRoot "config.json"

if (-not (Test-Path $RunnerPath)) {
    throw "Runner script not found: $RunnerPath"
}

# Prefer the native executable when available, then fall back to whatever
# `codex` resolves to (for example an npm-generated .cmd/.ps1 shim).
$CodexCommand = Get-Command codex.exe -ErrorAction SilentlyContinue
if ($null -eq $CodexCommand) {
    $CodexCommand = Get-Command codex -ErrorAction SilentlyContinue
}

if ($null -eq $CodexCommand) {
    throw @"
Codex CLI was not found in PATH.

Open a new PowerShell window and confirm this works first:
    codex --version
    codex exec --skip-git-repo-check --ephemeral "Reply exactly: READY"

Then run this installer again.
"@
}

$CodexPath = $CodexCommand.Source
if ([string]::IsNullOrWhiteSpace($CodexPath)) {
    $CodexPath = $CodexCommand.Path
}

if ([string]::IsNullOrWhiteSpace($CodexPath)) {
    throw "Could not resolve the full path of the Codex CLI."
}

$ParsedTimes = @()
foreach ($Time in $Times) {
    if ($Time -notmatch '^([01]\d|2[0-3]):([0-5]\d)$') {
        throw "Invalid time '$Time'. Use HH:mm, for example 07:00 or 22:00."
    }

    $Hour = [int]$Matches[1]
    $Minute = [int]$Matches[2]
    $ParsedTimes += (Get-Date).Date.AddHours($Hour).AddMinutes($Minute)
}

$Config = [ordered]@{
    codex_path = $CodexPath
    schedule = $Times
    created_at = (Get-Date).ToString("o")
    task_name = $TaskName
}

$Config | ConvertTo-Json -Depth 4 | Set-Content -Path $ConfigPath -Encoding UTF8

$Triggers = @(
    foreach ($At in $ParsedTimes) {
        New-ScheduledTaskTrigger -Daily -At $At
    }
)

$PowerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $RunnerPath

$Action = New-ScheduledTaskAction `
    -Execute $PowerShellExe `
    -Argument $Arguments `
    -WorkingDirectory $PSScriptRoot

$UserId = if ($env:USERDOMAIN) {
    "$env:USERDOMAIN\$env:USERNAME"
} else {
    $env:USERNAME
}

# Interactive logon keeps the task in the same user context as your Codex login.
$Principal = New-ScheduledTaskPrincipal `
    -UserId $UserId `
    -LogonType Interactive `
    -RunLevel Limited

$Settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -WakeToRun `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Triggers `
    -Principal $Principal `
    -Settings $Settings `
    -Description "Send a minimal Codex CLI request at fixed times to align the account's 5-hour usage window." `
    -Force | Out-Null

Write-Host ""
Write-Host "Installed successfully." -ForegroundColor Green
Write-Host "Task name : $TaskName"
Write-Host "Codex     : $CodexPath"
Write-Host "Schedule  : $($Times -join ', ')"
Write-Host "Runner    : $RunnerPath"
Write-Host "Logs      : $(Join-Path $PSScriptRoot 'logs')"
Write-Host ""
Write-Host "The task runs in your Windows user session, so keep the PC on and your user logged in."
Write-Host "If Windows was asleep at a scheduled time, StartWhenAvailable allows a missed run to start after resume."

if ($RunNow) {
    Write-Host ""
    Write-Host "Running one activation now..." -ForegroundColor Yellow
    & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
    exit $LASTEXITCODE
}
