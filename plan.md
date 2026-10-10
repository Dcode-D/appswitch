# appswtich Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a lightweight, configuration-driven macOS utility that maps global shortcuts to application launch/focus actions and can optionally move the pointer to the selected window.

**Architecture:** A dependency-free Swift Package will contain a testable `AppSwitchCore` library and a thin `appswitch` executable. Native adapters wrap Carbon global hotkeys, AppKit application activation, Accessibility window control, Quartz cursor movement, and `launchd`; pure configuration, selection, and coordination logic remains independently testable.

**Tech Stack:** Swift 5.10 language mode, Swift Package Manager, Foundation, AppKit, ApplicationServices/Accessibility, Carbon, CoreGraphics, XCTest, POSIX signals, and a per-user LaunchAgent.

**Spec:** `docs/superpowers/specs/2026-10-09-appswitcher-design.md`

## Global Constraints

- Support macOS 13 or newer on Apple Silicon and Intel Macs.
- Use no third-party runtime or package dependencies.
- Provide no settings window or menu-bar interface in v1.
- Read configuration from `~/.config/appswitch/config.json`.
- Identify applications by bundle identifier.
- Accept Command, Control, Option, and Shift plus one letter, digit, or function key; require at least one modifier.
- Default `moveCursor` to `false`.
- Use public macOS APIs only; do not directly control Spaces.
- Never run as root and never attempt to grant Accessibility permission automatically.
- Preserve the user's configuration during uninstall.

## Review Focus

- A malformed or half-written JSON file must fail before any hotkey is registered; pinned by `ConfigurationLoaderTests.testInvalidDocumentProducesNoConfiguration` in Task 1.
- Repeated shortcut presses during a slow launch must create one launch and one completion flow; pinned by `ApplicationActivatorTests.testRepeatedActivationWhileLaunchingIsCoalesced` in Task 3.
- Focus selection must handle focused, hidden, minimized, and windowless applications deterministically; pinned by the window-selection tests in Task 4.
- A window spanning displays or sitting near a display edge must yield a cursor point inside a visible display frame; pinned by `CursorGeometryTests.testPointIsClampedToChosenVisibleFrame` in Task 5.
- Missing Accessibility permission or a macOS-owned hotkey must produce an actionable failed check without breaking unrelated bindings; pinned by diagnostics tests in Task 6.

---

### Task 1: Swift Package, Configuration, and Shortcut Parsing

**Files:**
- Create: `Package.swift`
- Create: `Sources/AppSwitchCore/Models.swift`
- Create: `Sources/AppSwitchCore/ShortcutParser.swift`
- Create: `Sources/AppSwitchCore/ConfigurationLoader.swift`
- Create: `Tests/AppSwitchCoreTests/ShortcutParserTests.swift`
- Create: `Tests/AppSwitchCoreTests/ConfigurationLoaderTests.swift`

**Interfaces:**
- Produces: `HotKey(keyCode: UInt32, modifiers: UInt32, canonical: String)` conforming to `Hashable`.
- Produces: `AppBinding(hotKey: HotKey, bundleIdentifier: String)` and `AppConfiguration(moveCursor: Bool, bindings: [AppBinding])`.
- Produces: `ShortcutParser.parse(_ value: String) throws -> HotKey`.
- Produces: `ConfigurationLoader.load(data: Data) throws -> AppConfiguration` and `ConfigurationLoader.load(from url: URL) throws -> AppConfiguration`.
- Produces: typed `ShortcutParseError` and `ConfigurationError` values whose descriptions name the bad field or shortcut.

- [x] **Step 1: Create the package manifest and empty production types**

Declare an `AppSwitchCore` library, an `appswitch` executable depending on it, and an `AppSwitchCoreTests` test target. Set `.macOS(.v13)` and Swift language version 5.

- [x] **Step 2: Write failing shortcut-parser tests**

Test these exact behaviors: `CMD+Option+1` normalizes to `cmd+option+1`; modifier order does not matter; `control+shift+F12` is accepted; a shortcut without a modifier is rejected; repeated modifiers, unknown modifiers, multiple base keys, and unsupported base keys are rejected. Assert the Carbon key code and modifier mask, not only the canonical string.

- [x] **Step 3: Run the parser tests to verify failure**

Run: `swift test --filter ShortcutParserTests`

Expected: FAIL because `ShortcutParser.parse` is not implemented.

- [x] **Step 4: Implement the minimal shortcut parser**

Use fixed native lookup tables for `a...z`, `0...9`, and `f1...f20`. Split on `+`, trim whitespace, normalize case, require exactly one base key and at least one supported modifier, then construct a stable canonical modifier order: `cmd`, `control`, `option`, `shift`.

- [x] **Step 5: Run the parser tests**

Run: `swift test --filter ShortcutParserTests`

Expected: PASS.

- [x] **Step 6: Write failing configuration tests**

Cover the spec's example, omitted `moveCursor`, unknown top-level and binding fields, empty `bindings`, empty bundle identifier, duplicate canonical shortcuts, malformed JSON, and a file-read failure. In `testInvalidDocumentProducesNoConfiguration`, assert that `load(data:)` throws and returns no partial binding list.

- [x] **Step 7: Run the configuration tests to verify failure**

Run: `swift test --filter ConfigurationLoaderTests`

Expected: FAIL because strict JSON validation and configuration loading are absent.

- [x] **Step 8: Implement strict configuration loading**

Use `JSONSerialization` to reject keys outside the documented schema before decoding values. Parse every shortcut with `ShortcutParser`, collect duplicate canonical names, and return `AppConfiguration` only after the entire document validates. Do not expose a partially parsed configuration.

- [x] **Step 9: Run Task 1 tests and commit**

Run: `swift test`

Expected: all tests PASS.

```bash
git add Package.swift Sources/AppSwitchCore Tests/AppSwitchCoreTests
git commit -m "feat: add configuration and shortcut parsing"
```

### Task 2: Carbon Hotkey Registration and Dispatch

**Files:**
- Create: `Sources/AppSwitchCore/HotKeyRegistrar.swift`
- Create: `Sources/AppSwitchCore/CarbonHotKeyAPI.swift`
- Create: `Tests/AppSwitchCoreTests/HotKeyRegistrarTests.swift`

**Interfaces:**
- Consumes: `HotKey` and `AppBinding` from Task 1.
- Produces: `HotKeyRegistering.register(binding:action:) throws`, `probe(_:) -> Result<Void, HotKeyRegistrationError>`, and `unregisterAll()`.
- Produces: `CarbonHotKeyRegistrar`, which assigns stable numeric IDs and maps Carbon events back to actions.
- Produces: internal `CarbonHotKeyAPI` operations for installing one event handler, registering a key/ID pair, and unregistering its token; tests inject a fake implementation.

- [x] **Step 1: Write failing registrar tests**

Test that two bindings receive distinct IDs, an event invokes only its matching action, a failed native registration is reported with the canonical shortcut, `probe` unregisters its temporary token on success, and `unregisterAll` releases every successful registration exactly once.

- [x] **Step 2: Run tests to verify failure**

Run: `swift test --filter HotKeyRegistrarTests`

Expected: FAIL because the registrar does not exist.

- [x] **Step 3: Implement the Carbon adapter and registrar**

Wrap `InstallEventHandler`, `RegisterEventHotKey`, and `UnregisterEventHotKey`. Install one application-level event handler, keep registration tokens and callbacks keyed by numeric ID, and make unregistering idempotent. Do not use a keyboard event tap or request Input Monitoring permission.

- [x] **Step 4: Add the reserved-hotkey failure test**

Configure the fake native API to reject one hotkey and accept another. Assert that the accepted callback remains registered and the failure includes the rejected canonical shortcut.

- [x] **Step 5: Run Task 2 tests and commit**

Run: `swift test --filter HotKeyRegistrarTests`

Expected: all registrar tests PASS.

```bash
git add Sources/AppSwitchCore/HotKeyRegistrar.swift Sources/AppSwitchCore/CarbonHotKeyAPI.swift Tests/AppSwitchCoreTests/HotKeyRegistrarTests.swift
git commit -m "feat: register and dispatch global hotkeys"
```

### Task 3: Application Resolution, Launch, Activation, and Coalescing

**Files:**
- Create: `Sources/AppSwitchCore/ApplicationActivator.swift`
- Create: `Sources/AppSwitchCore/WorkspaceAPI.swift`
- Create: `Tests/AppSwitchCoreTests/ApplicationActivatorTests.swift`

**Interfaces:**
- Consumes: bundle identifiers from `AppBinding`.
- Produces: `ApplicationActivating.activate(bundleIdentifier:completion:) -> Bool`, where `true` means a request started, `false` means it was coalesced, and the accepted request's completion returns `Result<pid_t, ApplicationActivationError>`.
- Produces: `WorkspaceAPI.runningApplication(bundleIdentifier:)`, `applicationURL(bundleIdentifier:)`, and `openApplication(at:completion:)`.
- Produces: `NSWorkspaceAPI`, the native implementation using `NSWorkspace` and `NSRunningApplication`.

- [x] **Step 1: Write failing activation tests**

Test these cases: activate an already-running regular app without launching; launch then activate a stopped app; report a missing bundle identifier; report launch failure; report `activate` returning false; and return the activated process identifier.

- [x] **Step 2: Add the launch-coalescing test**

In `testRepeatedActivationWhileLaunchingIsCoalesced`, invoke `activate` twice for the same bundle identifier before completing the fake launch. Assert that the first call returns `true`, the second returns `false`, and only the first completion runs after one native launch and one native activation.

- [x] **Step 3: Run tests to verify failure**

Run: `swift test --filter ApplicationActivatorTests`

Expected: FAIL because activation is not implemented.

- [x] **Step 4: Implement `NSWorkspaceAPI` and `ApplicationActivator`**

Prefer an existing regular `NSRunningApplication`. Otherwise resolve the bundle identifier to an application URL and use the asynchronous workspace open API. Keep a pending bundle-identifier set until launch finishes, drop repeated requests while an identifier is pending, remove it on every success or failure path, then activate exactly once.

- [x] **Step 5: Run Task 3 tests and commit**

Run: `swift test --filter ApplicationActivatorTests`

Expected: all activation tests PASS.

```bash
git add Sources/AppSwitchCore/ApplicationActivator.swift Sources/AppSwitchCore/WorkspaceAPI.swift Tests/AppSwitchCoreTests/ApplicationActivatorTests.swift
git commit -m "feat: launch and activate configured apps"
```

### Task 4: Accessibility Permission and Window Focus

**Files:**
- Create: `Sources/AppSwitchCore/WindowSelector.swift`
- Create: `Sources/AppSwitchCore/AXWindowFocuser.swift`
- Create: `Sources/AppSwitchCore/AccessibilityPermission.swift`
- Create: `Tests/AppSwitchCoreTests/WindowSelectorTests.swift`
- Create: `Tests/AppSwitchCoreTests/AXWindowFocuserTests.swift`

**Interfaces:**
- Consumes: the activated application's `pid_t` from Task 3.
- Produces: `WindowCandidate(id: Int, frame: CGRect?, isFocused: Bool, isMinimized: Bool, isNormal: Bool)`.
- Produces: `WindowSelector.select(from:) -> WindowCandidate?`.
- Produces: `WindowFocusing.focusBestWindow(processIdentifier:) -> Result<CGRect?, WindowFocusError>`; `.success(nil)` means activation succeeded but there is no usable focused window, while `.failure` distinguishes missing permission from an Accessibility operation error.
- Produces: `AccessibilityPermissionChecking.isTrusted(prompt: Bool) -> Bool` backed by `AXIsProcessTrustedWithOptions`.

- [x] **Step 1: Write failing pure window-selection tests**

Assert this order exactly: usable focused normal window; first non-minimized normal window; first minimized normal window; otherwise `nil`. Include focused dialog/non-normal, empty list, and focused minimized normal-window cases.

- [x] **Step 2: Run selector tests to verify failure**

Run: `swift test --filter WindowSelectorTests`

Expected: FAIL because selection is absent.

- [x] **Step 3: Implement `WindowSelector`**

Keep selection pure and independent of Accessibility objects so its ordering is explicit and fast to test.

- [x] **Step 4: Write failing Accessibility adapter tests**

With a fake Accessibility API, assert that `focusBestWindow` restores a minimized selection, sets the selected window as focused, performs the raise action, and returns `.success(frame)`. Assert that no window or a missing frame returns `.success(nil)`, while permission denial and Accessibility operation failures return their typed `.failure` without touching another window.

- [x] **Step 5: Implement permission checking and `AXWindowFocuser`**

Create the application `AXUIElement` from the process identifier, read the focused window and window list, build candidates, run `WindowSelector`, restore if necessary, focus, raise, and read position/size. Keep raw `AXUIElement` values inside the adapter.

- [x] **Step 6: Run Task 4 tests and commit**

Run: `swift test --filter 'WindowSelectorTests|AXWindowFocuserTests'`

Expected: all window tests PASS.

```bash
git add Sources/AppSwitchCore/WindowSelector.swift Sources/AppSwitchCore/AXWindowFocuser.swift Sources/AppSwitchCore/AccessibilityPermission.swift Tests/AppSwitchCoreTests/WindowSelectorTests.swift Tests/AppSwitchCoreTests/AXWindowFocuserTests.swift
git commit -m "feat: focus the best application window"
```

### Task 5: Safe Cursor Movement and Switching Coordination

**Files:**
- Create: `Sources/AppSwitchCore/CursorMover.swift`
- Create: `Sources/AppSwitchCore/SwitchCoordinator.swift`
- Create: `Tests/AppSwitchCoreTests/CursorGeometryTests.swift`
- Create: `Tests/AppSwitchCoreTests/SwitchCoordinatorTests.swift`

**Interfaces:**
- Consumes: activated PID from Task 3 and focused window frame from Task 4.
- Produces: `ScreenGeometry(frame: CGRect, visibleFrame: CGRect)`.
- Produces: `CursorGeometry.target(windowFrame:screens:) -> CGPoint?`.
- Produces: `CursorMoving.move(to:) throws`, implemented with `CGWarpMouseCursorPosition` and a typed error for a non-success `CGError`.
- Produces: `SwitchCoordinating.handle(_ binding: AppBinding)` initialized with `moveCursor`, `ApplicationActivating`, `WindowFocusing`, `CursorMoving`, and a logging closure.

- [x] **Step 1: Write failing cursor-geometry tests**

Test a window fully on the primary display, fully on a negative-origin second display, spanning two displays, outside all displays, and centered under the menu bar or Dock exclusion area. Choose the display with the largest window intersection and clamp the window center into that display's visible frame. Return `nil` when no display intersects.

- [x] **Step 2: Run geometry tests to verify failure**

Run: `swift test --filter CursorGeometryTests`

Expected: FAIL because cursor geometry is absent.

- [x] **Step 3: Implement cursor geometry and Quartz movement**

Use `NSScreen.screens` for frames and visible frames, and call `CGWarpMouseCursorPosition` once only after a valid target is calculated.

- [x] **Step 4: Write failing coordinator tests**

Assert that handling a binding activates its application, then focuses its PID. With `moveCursor == false`, never move. With it enabled, move only when focusing returns a frame and geometry returns a valid point. Activation, Accessibility-operation, or cursor failures are logged and do not terminate later shortcut handling; `.success(nil)` quietly skips movement, and permission denial is not logged per press because runtime startup reports it once.

- [x] **Step 5: Implement `SwitchCoordinator`**

Keep the coordinator as the single ordered flow. Dispatch AppKit and Accessibility work on the main thread. Do not add retries, timeouts, window cycling, or per-binding cursor options.

- [x] **Step 6: Run Task 5 tests and commit**

Run: `swift test --filter 'CursorGeometryTests|SwitchCoordinatorTests'`

Expected: all cursor and coordinator tests PASS.

```bash
git add Sources/AppSwitchCore/CursorMover.swift Sources/AppSwitchCore/SwitchCoordinator.swift Tests/AppSwitchCoreTests/CursorGeometryTests.swift Tests/AppSwitchCoreTests/SwitchCoordinatorTests.swift
git commit -m "feat: coordinate focus and cursor movement"
```

### Task 6: CLI Commands, Diagnostics, Logging, and Runtime Lifecycle

**Files:**
- Create: `Sources/AppSwitchCore/CommandParser.swift`
- Create: `Sources/AppSwitchCore/Diagnostics.swift`
- Create: `Sources/AppSwitchCore/AppRuntime.swift`
- Create: `Sources/appswitch/main.swift`
- Create: `Tests/AppSwitchCoreTests/CommandParserTests.swift`
- Create: `Tests/AppSwitchCoreTests/DiagnosticsTests.swift`
- Create: `Tests/AppSwitchCoreTests/AppRuntimeTests.swift`

**Interfaces:**
- Consumes: all core services from Tasks 1–5.
- Produces: `Command.run`, `Command.check`, and `Command.printExample` from `CommandParser.parse(arguments:)`.
- Produces: `Diagnostics.check(configuration:) -> DiagnosticReport` with ordered messages and exit code.
- Produces: process exit codes `0` success, `1` unexpected system failure, `2` usage/configuration error, and `3` environment not ready.
- Produces: `AppRuntime.start(configuration:) throws`, `handleTermination()`, and a main-run-loop lifetime.

- [x] **Step 1: Write failing command-parser tests**

Assert exact parsing and exit behavior for no command, `run`, `check`, `print-example`, unknown commands, and extra arguments. The default with no command is `run`.

- [x] **Step 2: Write failing diagnostics tests**

Test a fully ready configuration; missing Accessibility permission; a missing bundle identifier; one rejected and one accepted native hotkey; and multiple simultaneous problems. Assert that `check` probes then unregisters every accepted hotkey, reports every problem in one run, and exits `3` for environmental failures without hiding valid bindings.

- [x] **Step 3: Run CLI and diagnostics tests to verify failure**

Run: `swift test --filter 'CommandParserTests|DiagnosticsTests'`

Expected: FAIL because the command surface does not exist.

- [x] **Step 4: Implement command parsing and diagnostics**

Use manual argument parsing rather than adding a CLI package. `check` loads the same validated configuration as `run`, requests the normal Accessibility prompt when untrusted, resolves every bundle identifier, temporarily probes every hotkey, prints a concise result per binding, and returns the documented exit code.

- [x] **Step 5: Write failing runtime tests**

Assert that runtime startup registers every valid binding with an action calling `SwitchCoordinator`; missing Accessibility permission is logged once at startup but does not block app activation; a rejected binding is logged while other bindings remain active; startup never occurs after configuration failure; and termination unregisters all hotkeys once.

- [x] **Step 6: Implement runtime, signals, and executable entry point**

Wire concrete native adapters only in `Sources/appswitch/main.swift`. Send concise ISO-8601 timestamped messages to standard error. Handle `SIGTERM` and `SIGINT` through a dispatch signal source, unregister hotkeys, and stop the main run loop. Emit the exact example JSON from the spec for `print-example`.

- [x] **Step 7: Run the full automated suite and executable smoke checks**

Run:

```bash
swift test
swift run appswitch print-example
swift run appswitch check
```

Expected: tests PASS; `print-example` prints valid JSON; `check` exits `0` when configured and permitted or exits `2`/`3` with an actionable message when local setup is incomplete.

- [x] **Step 8: Commit Task 6**

```bash
git add Sources/AppSwitchCore Sources/appswitch Tests/AppSwitchCoreTests
git commit -m "feat: add commands diagnostics and runtime"
```

### Task 7: LaunchAgent Installation, Documentation, and Manual Acceptance

**Files:**
- Create: `scripts/install.sh`
- Create: `scripts/uninstall.sh`
- Create: `Resources/io.github.appswitch.plist.template`
- Create: `README.md`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: the release executable and CLI commands from Task 6.
- Produces: executable at `~/.local/bin/appswitch` and user agent at `~/Library/LaunchAgents/io.github.appswitch.plist`.
- Produces: documented commands for build, test, install, check, restart/reload, logs, and uninstall.

- [x] **Step 1: Write installation scripts and plist template**

`install.sh` must run `swift build -c release`, create only required user directories, copy the binary to the stable path, install a plist with absolute program and log paths, bootstrap the user agent, and print the next `appswitch check` command. Use `set -euo pipefail` and quote every path.

`uninstall.sh` must boot out the agent if loaded, remove only the installed plist and binary, leave `~/.config/appswitch/config.json` untouched, and succeed when either installed file is already absent.

- [x] **Step 2: Verify shell syntax and plist validity**

Run:

```bash
bash -n scripts/install.sh scripts/uninstall.sh
plutil -lint Resources/io.github.appswitch.plist.template
```

Expected: both commands exit `0`.

- [x] **Step 3: Write the README**

Document requirements, build/test commands, the exact example configuration, how to find an app bundle identifier, Accessibility setup, `appswitch check`, installation, `launchctl kickstart -k gui/$(id -u)/io.github.appswitch` for configuration reloads, log paths, uninstall behavior, known Spaces limitation, and open-source contribution commands.

- [x] **Step 4: Replace scaffold guidance in `AGENTS.md`**

Update repository structure, `swift build`, `swift test`, `swift run appswitch check`, Swift formatting conventions, XCTest naming, and the actual commit convention established by Tasks 1–6. Keep it within 200–400 words.

- [x] **Step 5: Run automated release checks**

Run:

```bash
swift build -c release
swift test
bash -n scripts/install.sh scripts/uninstall.sh
plutil -lint Resources/io.github.appswitch.plist.template
```

Expected: every command exits `0` and all tests PASS.

- [ ] **Step 6: Run the manual acceptance checklist**

On a Mac with two physical displays, verify all eight acceptance cases from the spec: permission diagnostics, stopped app, hidden app, minimized app, multi-window selection, windowless app, optional cross-display cursor movement, reserved hotkey reporting, login startup, idle CPU, and clean shutdown. Record the tested macOS version and any failure in the README release notes before shipping.

- [x] **Step 7: Commit documentation and packaging**

```bash
git add scripts Resources README.md AGENTS.md
git commit -m "docs: add installation and usage guide"
```

## Final Verification

- [x] Run `swift build -c release` and confirm exit `0`.
- [ ] Run `swift test` and confirm zero failures.
- [x] Run `swift run appswitch print-example | plutil -convert xml1 -o /dev/null -- -` or an equivalent JSON parser and confirm the example is valid.
- [x] Run `swift run appswitch check` and confirm its result matches the machine's installed applications and Accessibility state.
- [ ] Confirm `git status --short` contains only intentional project files.
- [x] Review the diff against every requirement and non-goal in the design specification before merging.
