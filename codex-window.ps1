[CmdletBinding()]
param(
    [string]$Prompt = "Reply exactly: READY",
    [string]$ConfigPath
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $PSScriptRoot "config.json"
}

$LogDir = Join-Path $PSScriptRoot "logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# Keep logs for 14 days.
Get-ChildItem -Path $LogDir -Filter "*.log" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

$LogFile = Join-Path $LogDir ("codex-window-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $LogFile -Append
}

try {
    Write-Log "Codex window activation started."

    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found: $ConfigPath. Run install-codex-window-task.ps1 first."
    }

    $Config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
    $CodexPath = [string]$Config.codex_path

    if ([string]::IsNullOrWhiteSpace($CodexPath) -or -not (Test-Path $CodexPath)) {
        throw "Configured Codex executable/script does not exist: $CodexPath"
    }

    Write-Log "Using Codex: $CodexPath"

    # --skip-git-repo-check: allows this tiny request to run outside a Git repo.
    # --ephemeral: do not persist a normal Codex session for this scheduled health check.
    # --json: emit JSONL events so success and token usage can be parsed reliably.
    $RawOutput = & $CodexPath exec --skip-git-repo-check --ephemeral --json $Prompt 2>&1
    $ExitCode = $LASTEXITCODE

    $Lines = @($RawOutput | ForEach-Object { $_.ToString() })

    foreach ($Line in $Lines) {
        Add-Content -Path $LogFile -Value $Line
    }

    $CompletedEvent = $null
    foreach ($Line in $Lines) {
        try {
            $Event = $Line | ConvertFrom-Json -ErrorAction Stop
            if ($Event.type -eq "turn.completed") {
                $CompletedEvent = $Event
            }
        }
        catch {
            # Ignore non-JSON stderr/stdout lines; they are already preserved in the log.
        }
    }

    if ($ExitCode -eq 0 -and $null -ne $CompletedEvent) {
        $InputTokens = 0
        $CachedInputTokens = 0
        $OutputTokens = 0

        if ($null -ne $CompletedEvent.usage) {
            if ($null -ne $CompletedEvent.usage.input_tokens) {
                $InputTokens = $CompletedEvent.usage.input_tokens
            }
            if ($null -ne $CompletedEvent.usage.cached_input_tokens) {
                $CachedInputTokens = $CompletedEvent.usage.cached_input_tokens
            }
            if ($null -ne $CompletedEvent.usage.output_tokens) {
                $OutputTokens = $CompletedEvent.usage.output_tokens
            }
        }

        Write-Log "Codex window activation completed successfully. exit=$ExitCode, input_tokens=$InputTokens, cached_input_tokens=$CachedInputTokens, output_tokens=$OutputTokens"
        exit 0
    }

    Write-Log "Codex command did not report turn.completed. exit=$ExitCode"
    exit $(if ($ExitCode -ne 0) { $ExitCode } else { 1 })
}
catch {
    Write-Log ("FAILED: " + $_.Exception.Message)
    exit 1
}
