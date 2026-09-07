#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNNER_PATH="$SCRIPT_DIR/codex-window.sh"
CONFIG_PATH="$SCRIPT_DIR/config.env"
LOG_DIR="$SCRIPT_DIR/logs"
LABEL="com.zhouraym.codex-window"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
RUN_NOW=0
MAX_LATENESS_MINUTES=5
TIMEOUT_SECONDS=900
TIMES=()

usage() {
    cat <<'USAGE'
Usage:
  ./install-codex-window-task.sh [options] [HH:mm ...]

Examples:
  ./install-codex-window-task.sh
  ./install-codex-window-task.sh 06:29 11:31
  ./install-codex-window-task.sh --run-now 06:29 11:31
  CODEX_PATH=/opt/homebrew/bin/codex ./install-codex-window-task.sh

Options:
  --run-now                    Run one manual activation after installation.
  --max-lateness MINUTES       Skip launchd wake-up catch-up runs later than this.
                               Default: 5 minutes.
  --timeout SECONDS            Kill a stuck Codex request after this duration.
                               Default: 900 seconds.
  -h, --help                   Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --run-now)
            RUN_NOW=1
            shift
            ;;
        --max-lateness)
            [ "$#" -ge 2 ] || { echo "Missing value for --max-lateness" >&2; exit 2; }
            MAX_LATENESS_MINUTES="$2"
            shift 2
            ;;
        --timeout)
            [ "$#" -ge 2 ] || { echo "Missing value for --timeout" >&2; exit 2; }
            TIMEOUT_SECONDS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            while [ "$#" -gt 0 ]; do TIMES+=("$1"); shift; done
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            TIMES+=("$1")
            shift
            ;;
    esac
done

if [ "${#TIMES[@]}" -eq 0 ]; then
    TIMES=("07:00" "12:00" "17:00" "22:00")
fi

if ! [[ "$MAX_LATENESS_MINUTES" =~ ^[0-9]+$ ]]; then
    echo "--max-lateness must be a non-negative integer." >&2
    exit 2
fi
if ! [[ "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "--timeout must be a positive integer." >&2
    exit 2
fi

for time_value in "${TIMES[@]}"; do
    if ! [[ "$time_value" =~ ^([01][0-9]|2[0-3]):([0-5][0-9])$ ]]; then
        echo "Invalid time '$time_value'. Use HH:mm, for example 07:00 or 22:00." >&2
        exit 2
    fi
done

if [ ! -f "$RUNNER_PATH" ]; then
    echo "Runner script not found: $RUNNER_PATH" >&2
    exit 1
fi

if [ -n "${CODEX_PATH:-}" ]; then
    if [ ! -e "$CODEX_PATH" ]; then
        echo "CODEX_PATH does not exist: $CODEX_PATH" >&2
        exit 1
    fi
else
    CODEX_PATH="$(command -v codex || true)"
fi

if [ -z "$CODEX_PATH" ]; then
    cat >&2 <<'ERROR'
Codex CLI was not found in PATH.

Install it with:
    npm install -g @openai/codex

Then open a new Terminal and verify:
    codex --version
    codex exec --skip-git-repo-check --ephemeral "Reply exactly: READY"

If Codex is installed through nvm or another custom location, you can also run:
    CODEX_PATH="$(command -v codex)" ./install-codex-window-task.sh
ERROR
    exit 1
fi

mkdir -p "$LOG_DIR" "$HOME/Library/LaunchAgents"
chmod +x "$RUNNER_PATH" "$SCRIPT_DIR/uninstall-codex-window-task.sh" 2>/dev/null || true

SCHEDULE="$(IFS=,; echo "${TIMES[*]}")"
{
    printf 'CODEX_PATH=%q\n' "$CODEX_PATH"
    printf 'SCHEDULE=%q\n' "$SCHEDULE"
    printf 'MAX_LATENESS_MINUTES=%q\n' "$MAX_LATENESS_MINUTES"
    printf 'TIMEOUT_SECONDS=%q\n' "$TIMEOUT_SECONDS"
} > "$CONFIG_PATH"
chmod 600 "$CONFIG_PATH"

xml_escape() {
    printf '%s' "$1" |
        sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

ESCAPED_RUNNER="$(xml_escape "$RUNNER_PATH")"
ESCAPED_WORKDIR="$(xml_escape "$SCRIPT_DIR")"
ESCAPED_STDOUT="$(xml_escape "$LOG_DIR/launchd.stdout.log")"
ESCAPED_STDERR="$(xml_escape "$LOG_DIR/launchd.stderr.log")"
ESCAPED_PATH="$(xml_escape "$PATH")"

{
    cat <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$ESCAPED_RUNNER</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$ESCAPED_WORKDIR</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>CODEX_WINDOW_SCHEDULED</key>
        <string>1</string>
        <key>PATH</key>
        <string>$ESCAPED_PATH</string>
    </dict>
    <key>StartCalendarInterval</key>
    <array>
EOF_PLIST

    for time_value in "${TIMES[@]}"; do
        hour=$((10#${time_value%:*}))
        minute=$((10#${time_value#*:}))
        cat <<EOF_INTERVAL
        <dict>
            <key>Hour</key>
            <integer>$hour</integer>
            <key>Minute</key>
            <integer>$minute</integer>
        </dict>
EOF_INTERVAL
    done

    cat <<EOF_PLIST
    </array>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>$ESCAPED_STDOUT</string>
    <key>StandardErrorPath</key>
    <string>$ESCAPED_STDERR</string>
</dict>
</plist>
EOF_PLIST
} > "$PLIST_PATH"

plutil -lint "$PLIST_PATH" >/dev/null

# Remove an older loaded copy if present. bootout can fail when the service is
# not loaded, which is harmless.
launchctl bootout "$DOMAIN" "$PLIST_PATH" >/dev/null 2>&1 || true

if ! launchctl bootstrap "$DOMAIN" "$PLIST_PATH"; then
    echo "launchctl bootstrap failed; trying legacy load mode..." >&2
    launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
    launchctl load "$PLIST_PATH"
fi

cat <<EOF_SUMMARY

Installed successfully.
Label      : $LABEL
Codex      : $CODEX_PATH
Schedule   : ${TIMES[*]}
Runner     : $RUNNER_PATH
LaunchAgent: $PLIST_PATH
Logs       : $LOG_DIR
Tolerance  : ${MAX_LATENESS_MINUTES} minute(s)
Timeout    : ${TIMEOUT_SECONDS} second(s)

macOS launchd may replay missed calendar events after wake. This runner intentionally
skips scheduled invocations that are later than the configured tolerance so the
usage-window start time does not drift unexpectedly.
EOF_SUMMARY

if [ "$RUN_NOW" -eq 1 ]; then
    echo
    echo "Running one activation now..."
    CODEX_WINDOW_SCHEDULED=0 /bin/bash "$RUNNER_PATH"
fi
