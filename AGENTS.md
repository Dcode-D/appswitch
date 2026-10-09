# Repository Guidelines

## Project Structure & Module Organization

`Sources/AppSwitchCore/` contains testable configuration, hotkey, application, Accessibility, cursor, diagnostics, and runtime logic. `Sources/appswitch/main.swift` wires native adapters into the CLI executable. Swift Testing suites live in `Tests/AppSwitchCoreTests/`; macro-free regression runners are in `Tests/Manual/`. Packaging resources and the default configuration are under `Resources/`, while installation scripts live in `scripts/`. The implementation plan and design specification are in `plan.md` and `docs/superpowers/specs/`.

## Build, Test, and Development Commands

- `swift build` — compile the debug executable and library.
- `swift build -c release` — produce the optimized binary used by the installer.
- `swift test` — run the automated Swift Testing suites.
- `swift run appswitch print-example` — print valid configuration JSON.
- `swift run appswitch check` — validate config, applications, permission, and hotkeys.
- `bash -n scripts/*.sh` — syntax-check installation scripts.
- `plutil -lint Resources/io.github.appswitch.plist.template` — validate the LaunchAgent template.

## Coding Style & Naming Conventions

Use four-space indentation and standard Swift naming: `UpperCamelCase` types, `lowerCamelCase` members, and descriptive protocol names ending in `-ing` where appropriate. Keep native macOS calls behind small protocols and pure selection or geometry logic independent of AppKit objects. Prefer Foundation and public macOS APIs over new dependencies. Format multiline calls with one argument per line and avoid force unwraps.

## Testing Guidelines

Use Swift Testing with `@Suite` and behavior-focused `@Test` names. Cover success, error, and boundary paths; adapters should use focused fakes rather than controlling the desktop. Run `swift test` before submitting. When the local macro loader is unavailable, use the matching `Tests/Manual/TaskNTestRunner.swift` fallback.

## Commit & Pull Request Guidelines

Use short Conventional Commit subjects following the planned history, such as `feat: focus the best application window` or `docs: add installation and usage guide`. Keep commits limited to one task. Pull requests should explain user-visible behavior, list verification commands, link relevant issues, and call out manually unverified macOS permission, multi-display, or LaunchAgent behavior. Do not commit `.build/`, logs, or personal configuration files.

## Security & Configuration

Never request root access or attempt to grant Accessibility permission automatically. Installation and uninstall must preserve `~/.config/appswitch/config.json`; never log its contents. Validate the complete file before registering hotkeys.
