import Foundation

enum AssertionKind: String, Codable, Sendable {
    case display
    case system

    static func forSystemOnly(_ systemOnly: Bool) -> AssertionKind {
        systemOnly ? .system : .display
    }

    /// The sleep this assertion prevents, named the way a person would say it.
    var label: String {
        switch self {
        case .display: "display and system sleep"
        case .system: "system sleep"
        }
    }
}

struct Hold: Codable, Sendable, Equatable {
    var kind: AssertionKind
    var startedAt: Date
    var expiresAt: Date?

    init(kind: AssertionKind, startedAt: Date, expiresAt: Date?) {
        self.kind = kind
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }

    init(kind: AssertionKind, startedAt: Date, lasting seconds: Int?) {
        self.init(
            kind: kind,
            startedAt: startedAt,
            expiresAt: seconds.map { startedAt.addingTimeInterval(TimeInterval($0)) }
        )
    }

    func elapsed(at now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(startedAt)))
    }

    func remaining(at now: Date) -> Int? {
        expiresAt.map { max(0, Int($0.timeIntervalSince(now))) }
    }

    func hasExpired(at now: Date) -> Bool {
        guard let expiresAt else { return false }

        return now >= expiresAt
    }
}

enum Request: Codable, Sendable, Equatable {
    case on(seconds: Int?, systemOnly: Bool)
    case off
    case status

    /// Both front ends take the duration as text and the kind as a flag.
    static func hold(duration: String?, systemOnly: Bool) throws -> Request {
        .on(seconds: try duration.map(DurationText.parse), systemOnly: systemOnly)
    }
}

enum Reply: Codable, Sendable, Equatable {
    case held(Hold)
    case free
    case stopped(Bool)
    case failure(String)
}
