# AppSwitcher Design Specification

## Purpose

AppSwitcher is a small, open-source macOS background utility. A user assigns a global keyboard shortcut to an application; pressing it launches or activates the application, focuses a useful window, and can move the mouse pointer to that window. The first version is for one local user and roughly 10–50 bindings. It has no graphical interface and no third-party runtime dependencies.

Success means application switching feels immediate, multi-monitor behavior is predictable, configuration mistakes do not disable a previously working setup, and failures are visible from a foreground diagnostic command.

## User Needs

1. Bind memorable global shortcuts to installed applications.
2. Launch an application that is not running.
3. Activate a running application and raise the window the user is most likely to want.
4. Follow the selected window to its physical display and optionally move the pointer there.
5. Configure behavior in a readable file without rebuilding the executable.
6. Detect invalid shortcuts, missing applications, permission problems, and hotkey conflicts.
7. Start automatically after login while using negligible CPU when idle.

## Scope

### Included in v1

- macOS 13 or newer on Apple Silicon and Intel Macs.
- A native Swift executable built with Swift Package Manager.
- Global shortcuts made from Command, Control, Option, and Shift plus one letter, digit, or function key.
- Application lookup by stable bundle identifier, such as `com.apple.Safari`.
- Application launch, activation, deterministic window selection, optional cursor movement, configuration validation, and per-user background startup.
- Structured messages to standard error so `launchd` can retain useful logs.

### Not included in v1

- A settings window or menu-bar interface.
- Remapping keys inside applications.
- Window tiling, resizing, or arbitrary window placement.
- Private APIs for direct control of macOS Spaces. Activating an application may change Spaces according to the user's macOS settings.
- Per-application cursor policies, shortcut sequences, shell commands, or plugins.

## User-Facing Commands and Configuration

The executable is named `appswitch` and supports:

- `appswitch run` — validate configuration, register shortcuts, and remain active for `launchd`.
- `appswitch check` — validate configuration, list resolved applications and shortcut conflicts, report Accessibility permission, then exit nonzero if action is required.
- `appswitch print-example` — print a valid minimal configuration to standard output without modifying files.

Configuration lives at `~/.config/appswitch/config.json`:

```json
{
  "moveCursor": false,
  "bindings": [
    {
      "shortcut": "cmd+option+1",
      "bundleID": "com.apple.Safari"
    },
    {
      "shortcut": "cmd+option+2",
      "bundleID": "com.microsoft.VSCode"
    }
  ]
}
```

Modifier names are case-insensitive and normalized to `cmd`, `control`, `option`, and `shift`. Every shortcut must contain at least one modifier. Unknown fields, unknown key names, duplicate shortcuts, empty bundle identifiers, and an empty binding list are validation errors. `moveCursor` defaults to `false` when omitted.

The agent reads configuration at startup. A documented `launchctl kickstart -k` command restarts it and loads edits; live file watching is deliberately excluded from v1. Configuration changes never require recompilation.

## Architecture

The project contains one executable target and focused modules:

- **Configuration:** decode JSON, normalize shortcut strings, and return either a fully valid configuration or specific errors.
- **Hotkeys:** translate validated shortcuts to macOS key codes, register them using `RegisterEventHotKey`, dispatch presses, and unregister cleanly on shutdown.
- **Applications:** resolve bundle identifiers, find or launch applications with `NSWorkspace`, and activate them with `NSRunningApplication`.
- **Windows:** use the macOS Accessibility API to select and raise a window.
- **Cursor:** calculate a safe point and move the pointer with `CGWarpMouseCursorPosition` only when enabled.
- **Diagnostics:** perform the same validation and resolution used by `run`, report permission and registration readiness, and use stable exit codes.
- **Process:** own startup, signal handling, event-loop lifetime, and concise logging.

Platform calls sit behind small protocols so selection and error behavior can be unit-tested without controlling the developer's desktop.

## Switching Flow

1. A registered hotkey supplies its binding.
2. Find a running regular application with the configured bundle identifier. If none exists, resolve its application URL and ask `NSWorkspace` to launch it.
3. Wait for launch completion, then activate the application. Failure stops the flow and records an error.
4. Ask Accessibility for the application's focused window. If it is unusable, choose the first normal, non-minimized window; if none exists, choose the first minimized normal window. Restore a minimized selection, then set it as focused and perform the raise action.
5. If the application has no usable window, treat successful application activation as success and do not move the pointer.
6. When `moveCursor` is enabled, read the selected window's position and size, calculate its center, clamp that point to the containing display's visible frame, and move the pointer once.

Presses for one binding are serialized. Repeated presses while its launch is still pending are coalesced so the tool does not launch duplicate instances. Each binding keeps independent pending state while all platform UI calls remain on the main event loop.

## Permissions, Installation, and Background Operation

Application activation alone does not require elevated privileges. Inspecting and raising another application's window requires Accessibility permission. `appswitch check` uses `AXIsProcessTrustedWithOptions` to report status and request the standard macOS prompt when appropriate. The tool never attempts to grant itself permission or run as root.

An `install.sh` script places the executable at `~/.local/bin/appswitch`, creates the configuration directory when absent, and installs `~/Library/LaunchAgents/io.github.appswitch.plist`. An `uninstall.sh` script unloads the agent and removes only files installed by this project, preserving the user's configuration. The LaunchAgent runs `appswitch run`, keeps it in the logged-in graphical session, captures standard output and error, and never forks or daemonizes itself.

Unsigned local builds may require Accessibility permission again after replacement. A signed and notarized release can be added later without changing the runtime architecture.

## Error Handling

- Invalid configuration: print all validation errors and exit before registering any hotkeys.
- Missing application: `check` fails with the bundle identifier; `run` logs the failed binding but keeps other bindings active.
- Duplicate shortcut: reject the complete configuration before startup.
- macOS registration conflict: `check` temporarily registers then unregisters each hotkey, identifies any rejection, and exits unsuccessfully; `run` logs rejected shortcuts while keeping successfully registered bindings active.
- Missing Accessibility permission: application launch and activation still work; window raising and cursor movement are skipped with one actionable diagnostic rather than repeated log spam.
- Application launch or activation failure: log the bundle identifier and macOS error without terminating the agent.
- Accessibility window failure: retain successful app activation and skip cursor movement.

The running process handles `SIGTERM` by unregistering hotkeys and exiting promptly. Unexpected per-binding failures must not terminate the event loop.

## Testing and Acceptance

Unit tests cover JSON decoding, unknown fields, defaults, shortcut normalization, unsupported keys, duplicate shortcuts, application/window selection rules, cursor-point calculation, repeat coalescing, and error-to-exit-code mapping. Adapter tests use fakes for AppKit, Accessibility, Carbon, and Quartz boundaries.

A manual release checklist verifies:

1. `check` reports missing permission and malformed configuration clearly.
2. A stopped application launches and receives focus.
3. A running, hidden, and minimized application returns to the front.
4. An application with several windows raises the focused window.
5. An application with no normal window does not move the pointer.
6. A window on a second physical display receives focus; pointer movement is off by default and lands within that window when enabled.
7. Duplicate and system-reserved hotkeys produce actionable errors while unrelated valid bindings remain understandable.
8. The LaunchAgent starts after login, remains idle without measurable busy-loop CPU usage, and exits cleanly.

## Work Breakdown

Implementation planning should cover these independently reviewable outcomes:

1. Swift package foundation plus configuration schema and validation.
2. Shortcut parsing, native registration, event dispatch, and conflict reporting.
3. Application resolution, launch, activation, and repeated-press control.
4. Accessibility permission checks and deterministic window focusing.
5. Optional safe cursor movement across physical displays.
6. Command-line diagnostics, logging, signals, and process lifecycle.
7. Per-user LaunchAgent packaging, installation documentation, and end-to-end verification.
