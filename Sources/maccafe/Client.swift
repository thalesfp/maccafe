import Foundation
import ServiceManagement
import Synchronization
import XPC

/// Every command other than `agent` is a client of the agent launchd starts.
enum Client {
    static func send(_ request: Request) throws -> Reply {
        let reply: Reply
        do {
            let session = try XPCSession(machService: Service.machName)
            defer { session.cancel(reason: "the request is finished") }

            reply = try session.sendSync(request)
        } catch {
            throw unreachable(error)
        }

        if case .failure(let message) = reply {
            throw Failure(message)
        }

        return reply
    }

    /// Not being installed is the likely reason the agent cannot be reached, but
    /// asking launchd first would cost a round trip on every call that works.
    private static func unreachable(_ error: any Error) -> Failure {
        guard Installer.service.status == .enabled else {
            return Failure(Installer.advice(for: Installer.service.status))
        }

        return Failure("cannot reach the maccafe agent: \(error)")
    }
}

enum Installer {
    static var service: SMAppService {
        SMAppService.agent(plistName: Service.plistName)
    }

    /// Registering only ever pins; renewing a pinned signature needs the
    /// unregister to happen in an earlier process, which `make install` does.
    static func install() throws {
        do {
            try service.register()
        } catch {
            throw Failure("cannot register the maccafe agent: \(error.localizedDescription)")
        }
    }

    /// `unregisterAndReturnError` returns before launchd has killed the agent,
    /// and registering in that window re-pins the old signature. The completion
    /// handler is the documented point at which re-registering is safe, so the
    /// command does not exit until it has run.
    static func uninstall() throws {
        guard service.status != .notRegistered else { return }

        let failure = Mutex<(any Error)?>(nil)
        let reaped = DispatchSemaphore(value: 0)

        service.unregister { error in
            failure.withLock { $0 = error }
            reaped.signal()
        }

        guard reaped.wait(timeout: .now() + 30) == .success else {
            throw Failure("the maccafe agent did not finish unregistering")
        }

        if let error = failure.withLock({ $0 }), !isAlreadyGone(error) {
            throw Failure("cannot remove the maccafe agent: \(error.localizedDescription)")
        }
    }

    /// The service can be reaped between the status check and the call, and a
    /// service that is already gone is what the caller asked for.
    private static func isAlreadyGone(_ error: any Error) -> Bool {
        (error as NSError).code == kSMErrorJobNotFound
    }

    /// `requiresApproval` is the normal state right after registering, and
    /// telling that user to install again sends them nowhere.
    static func advice(for status: SMAppService.Status) -> String {
        switch status {
        case .requiresApproval:
            "maccafe is waiting for approval; allow it in System Settings under General, Login Items"
        case .notFound:
            "the maccafe agent is registered but its bundle is missing; run `make install` again"
        case .enabled:
            "the maccafe agent is registered but did not answer"
        default:
            "maccafe is not installed; run `maccafe install`"
        }
    }
}
