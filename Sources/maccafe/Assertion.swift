import Foundation
import IOKit.pwr_mgt

/// Holds one IOKit power assertion and releases it when it goes away.
final class Assertion {
    private let id: IOPMAssertionID

    init(_ kind: AssertionKind) throws {
        let type: String =
            switch kind {
            case .display: kIOPMAssertionTypePreventUserIdleDisplaySleep
            case .system: kIOPMAssertionTypePreventUserIdleSystemSleep
            }

        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "maccafe" as CFString,
            &id
        )

        guard result == kIOReturnSuccess else {
            throw Failure(
                "IOKit refused the power assertion (IOReturn \(String(result, radix: 16)))"
            )
        }

        self.id = id
    }

    deinit {
        IOPMAssertionRelease(id)
    }
}

struct Failure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
