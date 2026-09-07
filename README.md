# Codex 5h Window Activator

A small cross-platform scheduler for sending a minimal Codex CLI request at predictable times on **Windows** and **macOS**.

The request is:

```text
codex exec --skip-git-repo-check --ephemeral --json "Reply exactly: READY"
```

The goal is to make the first Codex request happen near chosen clock times so the server-side 5-hour usage window is easier to align with your work schedule.

> Important: this project does **not** call a special quota-reset API. It sends a real Codex request. Whether that request starts a new 5-hour window is controlled by OpenAI's current quota behavior and may vary by plan or change over time.

## Default schedule

The default schedule is:

- `06:29`
- `11:31`

The 2-minute buffer beyond exactly five hours helps avoid firing the second request on the reset boundary.

## Prerequisites

Install Codex CLI:

```bash
npm install -g @openai/codex
```

Then verify:

```bash
codex --version
codex exec --skip-git-repo-check --ephemeral "Reply exactly: READY"
```

Sign in to Codex under the same OS user account that will run the scheduler.

## Windows

Windows uses **Task Scheduler** and PowerShell.

### Install

Open PowerShell in the `windows` directory:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-codex-window-task.ps1
```

Install with custom times:

```powershell
.\install-codex-window-task.ps1 -Times "06:29","11:31"
```

If `codex` is not currently available in PowerShell PATH, pass the executable/shim explicitly:

```powershell
.\install-codex-window-task.ps1 `
    -CodexPath "C:\Users\you\AppData\Roaming\npm\codex.cmd" `
    -Times "06:29","11:31"
```

Install and immediately send one test request:

```powershell
.\install-codex-window-task.ps1 -RunNow
```

### Test and inspect

Run the worker directly:

```powershell
.\codex-window.ps1
```

Start the registered task:

```powershell
Start-ScheduledTask -TaskName "Codex 5h Window Activator"
```

Inspect task status:

```powershell
Get-ScheduledTaskInfo -TaskName "Codex 5h Window Activator" |
    Format-List LastRunTime,LastTaskResult,NextRunTime
```

View the latest log:

```powershell
Get-Content (
    Get-ChildItem .\logs\*.log |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
) -Tail 50
```

### Uninstall

```powershell
.\uninstall-codex-window-task.ps1
```

### Windows scheduling behavior

- Runs as the current Windows user with limited privileges.
- Uses the user's existing Codex authentication.
- `WakeToRun` is enabled, although actual wake behavior depends on Windows power settings and firmware.
- Missed tasks are **not** configured with `StartWhenAvailable`; a late catch-up request would shift the quota window away from the intended time.
- Overlapping task instances are ignored.
- A task is limited to 15 minutes.
- Logs older than 14 days are removed automatically.

## macOS

macOS uses a per-user **LaunchAgent (`launchd`)**.

### Install

From Terminal:

```bash
cd macos
chmod +x *.sh
./install-codex-window-task.sh
```

Install with custom times:

```bash
./install-codex-window-task.sh 06:29 11:31
```

Install and immediately send one test request:

```bash
./install-codex-window-task.sh --run-now 06:29 11:31
```

If Codex is installed through `nvm`, Homebrew, or another custom location, the installer captures the current full Codex path and PATH. You can also force it explicitly:

```bash
CODEX_PATH="$(command -v codex)" ./install-codex-window-task.sh 06:29 11:31
```

### Test and inspect

Run the worker directly:

```bash
./codex-window.sh
```

Trigger the LaunchAgent manually:

```bash
launchctl kickstart -k "gui/$(id -u)/com.zhouraym.codex-window"
```

Inspect it:

```bash
launchctl print "gui/$(id -u)/com.zhouraym.codex-window"
```

View today's log:

```bash
tail -n 50 "logs/codex-window-$(date +%Y-%m-%d).log"
```

LaunchAgent-level stdout/stderr are also stored in:

```text
macos/logs/launchd.stdout.log
macos/logs/launchd.stderr.log
```

### Uninstall

Keep local config/logs:

```bash
./uninstall-codex-window-task.sh
```

Remove the LaunchAgent plus generated config/logs:

```bash
./uninstall-codex-window-task.sh --purge
```

### macOS scheduling behavior

`launchd`'s `StartCalendarInterval` can replay a missed calendar event after the Mac wakes from sleep. That behavior is undesirable for quota-window alignment, because a request scheduled for 06:29 but replayed at 09:00 would shift the window.

The macOS runner therefore has a **late-run guard**. Scheduled invocations are accepted only within 5 minutes of a configured time by default; later wake-up replays are logged and skipped.

Customize that tolerance if needed:

```bash
./install-codex-window-task.sh --max-lateness 3 06:29 11:31
```

Other protections:

- Uses the existing logged-in Codex CLI; it never reads or copies your auth token.
- Stores the resolved Codex path and installer PATH locally in generated runtime configuration / LaunchAgent state.
- Prevents overlapping runs with an atomic lock directory.
- Terminates a Codex request after 15 minutes by default.
- Logs older than 14 days are removed automatically.
- A fully powered-off Mac cannot run a LaunchAgent.

## Security and quota notes

This project intentionally keeps the automation small:

- It does not read `~/.codex/auth.json` or extract access tokens.
- It does not use private quota/reset endpoints.
- It executes a normal authenticated Codex CLI request, so each activation consumes a small amount of real usage.
- Keep the scripts in a directory only your user can modify: scheduled scripts are executable code, so anyone who can alter them can change what runs later.
- The success log means the Codex request completed successfully; it cannot independently prove that the service created a new 5-hour quota window.

## Repository layout

```text
.
├── README.md
├── windows/
│   ├── codex-window.ps1
│   ├── install-codex-window-task.ps1
│   └── uninstall-codex-window-task.ps1
└── macos/
    ├── codex-window.sh
    ├── install-codex-window-task.sh
    └── uninstall-codex-window-task.sh
```
