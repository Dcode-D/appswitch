import AppSwitchCore
import AppKit
import Darwin
import Foundation

private let configurationURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/appswitch/config.json")

private func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    fputs("\(timestamp) \(message)\n", stderr)
}

private func loadConfiguration() throws -> AppConfiguration {
    try ConfigurationLoader.load(from: configurationURL)
}

private func runDiagnostics() throws -> Int32 {
    let configuration = try loadConfiguration()
    let registrar = try CarbonHotKeyRegistrar()
    let report = Diagnostics(
        permissionChecker: SystemAccessibilityPermissionChecker(),
        workspace: NSWorkspaceAPI(),
        hotKeyRegistrar: registrar
    ).check(configuration: configuration)
    report.messages.forEach { print($0) }
    return report.exitCode
}

private func runService() throws -> Int32 {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let configuration = try loadConfiguration()
    let registrar = try CarbonHotKeyRegistrar()
    let permissionChecker = SystemAccessibilityPermissionChecker()
    let quickSwitchSelector = configuration.quickSwitchHotKeys.isEmpty
        ? nil
        : NSWorkspaceRunningApplicationSelector()
    let coordinator = SwitchCoordinator(
        moveCursor: configuration.moveCursor,
        activator: ApplicationActivator(),
        windowFocuser: AXWindowFocuser(permissionChecker: permissionChecker),
        cursorMover: QuartzCursorMover(),
        log: log
    )
    let runtime = AppRuntime(
        hotKeyRegistrar: registrar,
        coordinator: coordinator,
        permissionChecker: permissionChecker,
        quickSwitchSelector: quickSwitchSelector,
        log: log
    )
    try runtime.start(configuration: configuration)

    let signalSources = [SIGINT, SIGTERM].map { signalNumber in
        Darwin.signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler {
            runtime.handleTermination()
            application.stop(nil)
            if let wakeEvent = NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0
            ) {
                application.postEvent(wakeEvent, atStart: false)
            }
        }
        source.resume()
        return source
    }

    withExtendedLifetime(signalSources) {
        application.run()
    }
    runtime.handleTermination()
    return 0
}

private func execute(_ command: Command) -> Int32 {
    do {
        switch command {
        case .printExample:
            print(ExampleConfiguration.json)
            return 0
        case .check:
            return try runDiagnostics()
        case .run:
            return try runService()
        }
    } catch let error as ConfigurationError {
        log("configuration error: \(error)")
        return 2
    } catch {
        log("unexpected system failure: \(error.localizedDescription)")
        return 1
    }
}

let command: Command
do {
    command = try CommandParser.parse(arguments: Array(CommandLine.arguments.dropFirst()))
} catch let error as CommandParseError {
    fputs("\(error)\n", stderr)
    exit(error.exitCode)
} catch {
    fputs("usage: appswitch [run|check|print-example]\n", stderr)
    exit(2)
}

exit(execute(command))
