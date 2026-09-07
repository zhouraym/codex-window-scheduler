# Codex 5h Window Activator for Windows

Windows-native equivalent of the cron-based "consistent usage windows" idea.

Default trigger times:

- 07:00
- 12:00
- 17:00
- 22:00

At each trigger the task runs a minimal Codex CLI request:

    codex exec --skip-git-repo-check --ephemeral --json "Reply exactly: READY"

The purpose is to make the first Codex request happen at predictable times so your
server-side 5-hour usage window is aligned with your work schedule.

Important: this script can force a Codex request at a chosen time, but the actual
quota/window behavior is controlled by OpenAI and may vary by plan or change over time.

## 1. Prerequisites

Open PowerShell and verify:

    codex --version

Then verify a non-interactive request:

    codex exec --skip-git-repo-check --ephemeral "Reply exactly: READY"

You should already be logged into Codex under the same Windows user account.

## 2. Install

Extract this folder somewhere permanent, for example:

    C:\Tools\codex-window-windows

Do not delete or move the folder after installation unless you reinstall the task.

Open PowerShell in that folder and run:

    Set-ExecutionPolicy -Scope Process Bypass

Then:

    .\install-codex-window-task.ps1

To install and immediately test one request:

    .\install-codex-window-task.ps1 -RunNow

If Task Scheduler returns Access Denied, reopen PowerShell with "Run as administrator"
and execute the installer again.

## 3. Customize times

For example, use 08:00 / 13:00 / 18:00 / 23:00:

    .\install-codex-window-task.ps1 -Times "08:00","13:00","18:00","23:00"

Running the installer again replaces the existing task definition.

## 4. Test manually

Run the worker directly:

    .\codex-window.ps1

Or start the scheduled task:

    Start-ScheduledTask -TaskName "Codex 5h Window Activator"

Then check:

    .\logs\codex-window-YYYY-MM-DD.log

Quickly show the latest log:

    Get-Content (Get-ChildItem .\logs\*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1) -Tail 50

## 5. Check the task

    Get-ScheduledTask -TaskName "Codex 5h Window Activator"

Or open:

    Task Scheduler -> Task Scheduler Library -> Codex 5h Window Activator

## 6. Remove it

    .\uninstall-codex-window-task.ps1

## Behavior

- Runs under the current Windows user's interactive session.
- Reuses that user's existing Codex login/authentication.
- Starts a missed task after the computer resumes when possible.
- Requests Task Scheduler to wake the computer for a scheduled run.
- Prevents overlapping copies of the activation task.
- Allows scheduled runs while the laptop is on battery.
- Uses `--ephemeral` so this health-check request does not persist a normal Codex session.
- Writes one log file per day.
- Automatically removes log files older than 14 days.
- Never reads, copies, or stores your Codex auth token itself.

## Notes about sleep / shutdown

WakeToRun can wake a sleeping machine if Windows, firmware, and power policy allow wake timers.
It cannot run while the PC is fully powered off.

The task is configured to run in your interactive user session. This is deliberate: it makes
Codex PATH/auth behavior much more predictable than running under SYSTEM or a different account.
