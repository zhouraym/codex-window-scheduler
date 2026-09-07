#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.zhouraym.codex-window"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
PURGE=0

if [ "${1:-}" = "--purge" ]; then
    PURGE=1
elif [ "$#" -gt 0 ]; then
    echo "Usage: ./uninstall-codex-window-task.sh [--purge]" >&2
    exit 2
fi

launchctl bootout "$DOMAIN" "$PLIST_PATH" >/dev/null 2>&1 || \
    launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true

rm -f "$PLIST_PATH"

echo "Removed LaunchAgent: $LABEL"

if [ "$PURGE" -eq 1 ]; then
    rm -f "$SCRIPT_DIR/config.env"
    rm -rf "$SCRIPT_DIR/logs" "$SCRIPT_DIR/.run-lock"
    echo "Removed local config and logs."
else
    echo "Local config and logs were kept. Use --purge to remove them too."
fi
