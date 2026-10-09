#!/bin/bash
set -euo pipefail

binary_path="$HOME/.local/bin/appswitch"
agent_path="$HOME/Library/LaunchAgents/io.github.appswitch.plist"
domain="gui/$(id -u)"

/bin/launchctl bootout "$domain/io.github.appswitch" 2>/dev/null || true
/bin/rm -f "$agent_path" "$binary_path"

echo "Removed the AppSwitcher agent and executable."
echo "Kept $HOME/.config/appswitch/config.json"
