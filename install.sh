#!/usr/bin/env bash
# Install or upgrade the Claude Usage Plasma widget for the current user.
set -euo pipefail

cd "$(dirname "$0")"
ID=org.primis.claudeusage

if ! command -v kpackagetool5 >/dev/null; then
    echo "kpackagetool5 not found — this widget needs KDE Plasma 5." >&2
    exit 1
fi

chmod +x package/contents/code/usage.py

if kpackagetool5 -t Plasma/Applet -s "$ID" >/dev/null 2>&1; then
    kpackagetool5 -t Plasma/Applet -u package
    echo "Upgraded. Restart Plasma to load changes: systemctl --user restart plasma-plasmashell"
else
    kpackagetool5 -t Plasma/Applet -i package
    echo "Installed. Right-click the panel → Add Widgets… → search \"Claude Usage\"."
fi
