import AppKit
import Foundation
import Synchronization
import XPC

/// Owns the assertion and the hold it describes. The pure core decides; this
/// runs what it decided.
///
/// The state is behind a lock rather than on the main actor because the XPC
/// handler must answer synchronously, and the main thread is parked inside
/// `NSApplication.run()` for the life of the agent.
final class Agent: Sendable {
    private struct Guarded {
        var hold: Hold?
        var assertion: Assertion?
        var timer: DispatchSourceTimer?
        var observer: (@Sendable () -> Void)?
    }

    private let guarded = Mutex(Guarded())
    private let timerQueue = DispatchQueue(label: "\(Service.machName).deadline")

    var hold: Hold? {
        guarded.withLock { $0.hold }
    }

    /// The observer is told that something changed, never what it changed to:
    /// two requests can commit under the lock and then race to notify, so only
    /// a fresh read of `hold` is guaranteed not to be stale.
    func observe(_ observer: @escaping @Sendable () -> Void) {
        guarded.withLock { $0.observer = observer }

        observer()
    }

    func handle(_ request: Request) -> Reply {
        switch request {
        case .on(let seconds, let systemOnly):
            run(.on(kind: .forSystemOnly(systemOnly), seconds: seconds))
        case .off:
            run(.off)
        case .status:
            run(.status)
        }
    }

    /// Swapping the kind keeps the hold it applies to, so the menu can offer it
    /// without restarting the countdown.
    @discardableResult
    func change(to kind: AssertionKind) -> Reply {
        run(.change(kind: kind))
    }

    @discardableResult
    private func run(_ action: Action) -> Reply {
        do {
            let (reply, observer) = try guarded.withLock { held in
                let outcome = apply(action, to: held.hold, at: Date())

                try execute(outcome.effect, on: &held)
                held.hold = outcome.hold

                return (outcome.reply, held.observer)
            }

            observer?()

            return reply
        } catch {
            return .failure("\(error)")
        }
    }

    private func execute(_ effect: Effect, on held: inout Guarded) throws {
        switch effect.assertion {
        case .take(let kind):
            held.assertion = try Assertion(kind)
        case .release:
            held.assertion = nil
        case .keep:
            break
        }

        switch effect.deadline {
        case .arm(let deadline):
            held.timer?.cancel()
            held.timer = armed(for: deadline)
        case .disarm:
            held.timer?.cancel()
            held.timer = nil
        case .keep:
            break
        }
    }

    /// A wall deadline so a hold that runs out while the Mac sleeps ends on wake.
    private func armed(for deadline: Date) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(wallDeadline: .now() + deadline.timeIntervalSinceNow)
        timer.setEventHandler { [self] in
            run(.status)
        }
        timer.resume()

        return timer
    }
}

/// Binding the Mach service is what keeps a second agent from taking a second
/// assertion; launchd only guarantees one agent that launchd itself started.
@MainActor
func serveAgent() throws {
    let agent = Agent()
    let queue = DispatchQueue(label: Service.machName, target: .global())

    let listener = try XPCListener(
        service: Service.machName,
        targetQueue: queue,
        options: .inactive
    ) { request in
        request.accept { (message: Request) -> (any Encodable)? in
            agent.handle(message)
        }
    }

    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)

    let menu = MenuBarController(agent: agent)
    application.delegate = menu

    try listener.activate()
    application.run()
}
