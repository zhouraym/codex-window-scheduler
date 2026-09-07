[CmdletBinding()]
param(
    [string[]]$Times = @("07:00", "12:00", "17:00", "22:00"),
    [string]$TaskName = "Codex 5h Window Activator",
    [string]$CodexPath,
    [switch]$RunNow
)

$ErrorActionPreference = "Stop"

$RunnerPath = Join-Path $PSScriptRoot "codex-window.ps1"
$ConfigPath = Join-Path $PSScriptRoot "config.json"

if (-not (Test-Path $RunnerPath)) {
    throw "Runner script not found: $RunnerPath"
}

if ([string]::IsNullOrWhiteSpace($CodexPath)) {
    # Prefer the native executable when available, then fall back to whatever
    # `codex` resolves to (for example an npm-generated .cmd/.ps1 shim).
    $CodexCommand = Get-Command codex.exe -ErrorAction SilentlyContinue
    if ($null -eq $CodexCommand) {
        $CodexCommand = Get-Command codex -ErrorAction SilentlyContinue
    }

    if ($null -eq $CodexCommand) {
        throw @"
Codex CLI was not found in PATH.

Install it with:
    npm install -g @openai/codex

Then open a new PowerShell window and confirm:
    codex --version
    codex exec --skip-git-repo-check --ephemeral "Reply exactly: READY"

Alternatively, rerun this installer with an explicit path:
    .\install-codex-window-task.ps1 -CodexPath "C:\path\to\codex.cmd"
"@
    }

    $CodexPath = $CodexCommand.Source
    if ([string]::IsNullOrWhiteSpace($CodexPath)) {
        $CodexPath = $CodexCommand.Path
    }
}

if ([string]::IsNullOrWhiteSpace($CodexPath)) {
    throw "Could not resolve the full path of the Codex CLI."
}

if (-not (Test-Path $CodexPath)) {
    throw "Codex CLI path does not exist: $CodexPath"
}

$CodexPath = (Resolve-Path $CodexPath).Path

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

# Intentionally do NOT use -StartWhenAvailable. A late catch-up run would shift
# the server-side usage window away from the configured clock time.
$Settings = New-ScheduledTaskSettingsSet `
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
Write-Host "Missed executions are not replayed later, by design, so quota-window timing does not drift."
Write-Host "WakeToRun is enabled, but actual wake behavior depends on Windows power settings and firmware."

if ($RunNow) {
    Write-Host ""
    Write-Host "Running one activation now..." -ForegroundColor Yellow
    & $PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
    exit $LASTEXITCODE
}
