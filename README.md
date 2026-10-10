# appswtich

appswtich is a lightweight, configuration-driven macOS utility that launches or activates applications with global keyboard shortcuts. It can focus a useful application window and optionally move the pointer to that window. It has no graphical interface or third-party runtime dependencies.

Repeated presses traverse an application's normal windows in order. Pressing again on its last—or only—window hides the app and returns to the previously active application. Invoking it later starts again at its first window.

## Requirements

- macOS 13 or newer
- Swift 5.10 or newer
- Accessibility permission for window focusing and cursor following

## Build and Test

```bash
swift build
swift test
swift run appswitch print-example
```

Configuration is read from `~/.config/appswitch/config.json`. Run `swift run appswitch check` to validate applications, Accessibility permission, and shortcut availability.

## Configuration

The installer creates these mappings when no configuration exists:

| Shortcut | Application |
| --- | --- |
| Right Cmd+Shift+T | Terminal |
| Right Cmd+Shift+C | ChatGPT |
| Right Cmd+Shift+H | Google Chrome |
| Right Cmd+Shift+I | iPhone Mirroring |
| Right Cmd+Shift+O | OrbStack |
| Right Cmd+Shift+D | TablePlus |
| Right Cmd+Shift+M | Microsoft Teams |
| Right Cmd+Shift+V | Visual Studio Code |
| Right Cmd+Shift+P | Postman |

The complete file is [`Resources/config.example.json`](Resources/config.example.json). Terminal keeps `T`; Teams uses `M` because duplicate shortcuts are invalid. The native hotkey API represents both Command keys as `cmd`, so either Command key activates these shortcuts even though the intended usage is Right Command.

Set `"moveCursor": true` to move the pointer to the focused window. appswtich does not directly control macOS Spaces; application activation follows your system settings.

Find another app's bundle identifier with:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /Applications/Example.app/Contents/Info.plist
```

## Install and Run at Login

Install the release binary, default configuration, and LaunchAgent:

```bash
cd /path/to/keybind
./scripts/install.sh
```

Next, open the Accessibility settings and reveal the exact installed executable:

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
open -R ~/.local/bin/appswitch
```

In **System Settings → Privacy & Security → Accessibility**, drag `~/.local/bin/appswitch` from Finder into the application list and enable it. If an older `appswitch` entry exists, remove it first. macOS requires this permission to be granted manually; the installer cannot enable it.

Grant permission *after* installation. Rebuilding or reinstalling changes the executable's identity and may require removing and adding it again.

Restart the LaunchAgent and confirm that it is running:

```bash
launchctl kickstart -k gui/$(id -u)/io.github.appswitch
launchctl print gui/$(id -u)/io.github.appswitch | head -n 20
```

The output should include `state = running`. Validate the configuration, installed apps, and registered shortcuts with:

```bash
~/.local/bin/appswitch check
```

As a live test, open two Terminal windows. From another app, press Cmd+Shift+T repeatedly: the first press focuses Terminal, the second selects its next window, and the final press hides Terminal and returns to the previous app.

### Configuration and Updates

Edit `~/.config/appswitch/config.json`, then reload the agent:

```bash
launchctl kickstart -k gui/$(id -u)/io.github.appswitch
```

The installer preserves an existing configuration. After installing a newly built binary, repeat the Accessibility removal/addition and restart steps above.

### Troubleshooting

Inspect the agent state and recent errors:

```bash
launchctl print gui/$(id -u)/io.github.appswitch
tail -n 20 ~/Library/Logs/AppSwitcher/stderr.log
```

If the log says Accessibility is not enabled, remove the existing Accessibility entry, run `open -R ~/.local/bin/appswitch`, add that exact file again, enable it, and restart the agent.

### Uninstall

Remove the binary and LaunchAgent while preserving `~/.config/appswitch/config.json`:

```bash
./scripts/uninstall.sh
```

## Contributing

Keep platform calls behind the existing protocols and add behavior-focused tests. Before submitting a change, run `swift build -c release`, `swift test`, shell syntax checks, and plist validation. Use concise Conventional Commit subjects such as `feat: add cursor targeting` or `fix: preserve valid hotkeys`.

## Release Notes

Automated checks run on macOS 27.0.1. Physical multi-display behavior, login startup, idle CPU use, and real Accessibility/hotkey interaction must be verified manually before the first release.
