#!/usr/bin/env bash
# Remove the Claude Usage Plasma widget and its cache.
set -euo pipefail

kpackagetool5 -t Plasma/Applet -r org.primis.claudeusage
rm -f "$HOME/.cache/claude-usage-widget.json"
echo "Removed. Remove the widget from your panel if it's still shown."
