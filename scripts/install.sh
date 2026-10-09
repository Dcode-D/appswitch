#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
binary_dir="$HOME/.local/bin"
binary_path="$binary_dir/appswitch"
config_dir="$HOME/.config/appswitch"
config_path="$config_dir/config.json"
agent_dir="$HOME/Library/LaunchAgents"
agent_path="$agent_dir/io.github.appswitch.plist"
log_dir="$HOME/Library/Logs/AppSwitcher"
domain="gui/$(id -u)"

swift build -c release -debug-info-format none --package-path "$repo_root"
build_dir="$(swift build -c release --package-path "$repo_root" --show-bin-path)"

mkdir -p "$binary_dir" "$config_dir" "$agent_dir" "$log_dir"
/usr/bin/install -m 755 "$build_dir/appswitch" "$binary_path"

if [[ ! -e "$config_path" ]]; then
    /usr/bin/install -m 644 "$repo_root/Resources/config.example.json" "$config_path"
    echo "Created $config_path"
else
    echo "Kept existing $config_path"
fi

/usr/bin/install -m 644 "$repo_root/Resources/io.github.appswitch.plist.template" "$agent_path"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $binary_path" "$agent_path"
/usr/bin/plutil -replace StandardOutPath -string "$log_dir/stdout.log" "$agent_path"
/usr/bin/plutil -replace StandardErrorPath -string "$log_dir/stderr.log" "$agent_path"

/bin/launchctl bootout "$domain/io.github.appswitch" 2>/dev/null || true
/bin/launchctl bootstrap "$domain" "$agent_path"

echo "Installed AppSwitcher. Check setup with:"
echo "  $binary_path check"
