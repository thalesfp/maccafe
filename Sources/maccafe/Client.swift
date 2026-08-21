import Foundation
import ServiceManagement
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
            return Failure("maccafe is not installed; run `maccafe install`")
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

    static func uninstall() throws {
        do {
            try service.unregister()
        } catch {
            throw Failure("cannot remove the maccafe agent: \(error.localizedDescription)")
        }
    }
}
