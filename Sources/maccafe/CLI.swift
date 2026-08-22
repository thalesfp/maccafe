import ArgumentParser
import Foundation
import Synchronization

struct Maccafe: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "maccafe",
        abstract: "Keep this Mac awake",
        version: "0.2.0",
        subcommands: [
            On.self, Off.self, Status.self, Serve.self, Install.self, Uninstall.self, RunAgent.self,
        ]
    )
}

/// Only the commands that print a report take `--json`; `mcp` and the install
/// commands never accept it, so the combination cannot be typed.
struct Reporting: ParsableArguments {
    @Flag(name: .long, help: "Print machine-readable output")
    var json = false

    func report(_ reply: Reply) {
        print(Render.reply(reply, at: Date(), asJSON: json))
    }
}

struct HoldOptions: ParsableArguments {
    @Option(name: .long, help: "Stop after this long, for example \(DurationText.examples)")
    var duration: String?

    @Flag(name: .long, help: "Let the display sleep, and only keep the system awake")
    var systemOnly = false

    func request() throws -> Request {
        try .hold(duration: duration, systemOnly: systemOnly)
    }
}

struct On: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Keep this Mac awake until `maccafe off`"
    )

    @OptionGroup var hold: HoldOptions
    @OptionGroup var reporting: Reporting

    func run() throws {
        reporting.report(try Client.send(hold.request()))
    }
}

struct Off: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Let this Mac sleep normally again")

    @OptionGroup var reporting: Reporting

    func run() throws {
        reporting.report(try Client.send(.off))
    }
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show whether this Mac is being kept awake"
    )

    @OptionGroup var reporting: Reporting

    func run() throws {
        reporting.report(try Client.send(.status))
    }
}

struct Serve: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Serve the maccafe tools over MCP on stdio"
    )

    func run() throws {
        try blocking { try await serveMCP() }
    }
}

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Register the maccafe agent so it starts at login"
    )

    func run() throws {
        try Installer.install()

        print("maccafe: the agent is registered; approve it in System Settings if asked")
    }
}

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Remove the maccafe agent")

    func run() throws {
        switch try Installer.uninstall() {
        case .removed:
            print("maccafe: the agent is removed")
        case .notRegistered:
            let bundle = Bundle.main.bundlePath
            print("maccafe: no agent is registered for \(bundle), so nothing was removed")
        }
    }
}

struct RunAgent: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "agent", shouldDisplay: false)

    func run() throws {
        try MainActor.assumeIsolated { try serveAgent() }
    }
}

/// `agent` nests an AppKit run loop in main and has to own the thread: entering
/// it from inside a main-actor job leaves the main queue undrained, so the menu
/// bar never redraws. Nothing here is async, so the async work waits on a task.
func blocking(_ operation: @escaping @Sendable () async throws -> Void) throws {
    let outcome = Mutex<Result<Void, any Error>?>(nil)
    let finished = DispatchSemaphore(value: 0)

    Task {
        do {
            try await operation()
            outcome.withLock { $0 = .success(()) }
        } catch {
            outcome.withLock { $0 = .failure(error) }
        }

        finished.signal()
    }

    finished.wait()

    try outcome.withLock { $0 }?.get()
}

@main
enum Entry {
    /// The commands that declare `--json`. Every other command rejects the flag
    /// as an unknown option, so its rejection must not be rendered as JSON.
    private static let reportingCommands: Set<String> = ["on", "off", "status"]

    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        let wantsJSON =
            arguments.first.map(reportingCommands.contains) == true
            && arguments.contains("--json")

        do {
            var command = try Maccafe.parseAsRoot()

            try command.run()
        } catch {
            fail(error, asJSON: wantsJSON)
        }
    }

    /// clap-style: a `--json` caller meets a mistyped argument far more often
    /// than a runtime failure, so both answer in the shape it asked for.
    private static func fail(_ error: Error, asJSON: Bool) -> Never {
        guard asJSON, !(error is CleanExit) else {
            Maccafe.exit(withError: error)
        }

        print(Render.failure(Maccafe.message(for: error), asJSON: true))
        Maccafe.exit(withError: ExitCode(Maccafe.exitCode(for: error).rawValue))
    }
}
