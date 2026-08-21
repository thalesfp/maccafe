import Foundation

enum Action: Sendable, Equatable {
    case on(kind: AssertionKind, seconds: Int?)
    case change(kind: AssertionKind)
    case off
    case status
}

enum AssertionCommand: Sendable, Equatable {
    case take(AssertionKind)
    case release
    case keep
}

enum DeadlineCommand: Sendable, Equatable {
    case arm(Date)
    case disarm
    case keep
}

struct Effect: Sendable, Equatable {
    var assertion: AssertionCommand
    var deadline: DeadlineCommand

    static let unchanged = Effect(assertion: .keep, deadline: .keep)
}

struct Outcome: Sendable, Equatable {
    var hold: Hold?
    var reply: Reply
    var effect: Effect
}

/// Every transition the agent can make, as a value. The caller runs the effect.
func apply(_ action: Action, to hold: Hold?, at now: Date) -> Outcome {
    let live = hold.flatMap { $0.hasExpired(at: now) ? nil : $0 }
    let lapsed = hold != nil && live == nil

    switch action {
    case .on(let kind, let seconds):
        let started = Hold(kind: kind, startedAt: now, lasting: seconds)

        return Outcome(
            hold: started,
            reply: .held(started),
            effect: Effect(
                assertion: live?.kind == kind ? .keep : .take(kind),
                deadline: started.expiresAt.map { .arm($0) } ?? .disarm
            )
        )

    case .change(let kind):
        guard var swapped = live, swapped.kind != kind else {
            return observed(live, lapsed: lapsed)
        }

        swapped.kind = kind

        return Outcome(
            hold: swapped,
            reply: .held(swapped),
            effect: Effect(assertion: .take(kind), deadline: .keep)
        )

    case .off:
        return Outcome(
            hold: nil,
            reply: .stopped(live != nil),
            effect: hold == nil ? .unchanged : Effect(assertion: .release, deadline: .disarm)
        )

    case .status:
        return observed(live, lapsed: lapsed)
    }
}

/// Looking at a hold that already ran out is what ends it, so the deadline timer
/// only has to ask the same question the clients ask.
private func observed(_ live: Hold?, lapsed: Bool) -> Outcome {
    guard let live else {
        return Outcome(
            hold: nil,
            reply: .free,
            effect: lapsed ? Effect(assertion: .release, deadline: .disarm) : .unchanged
        )
    }

    return Outcome(hold: live, reply: .held(live), effect: .unchanged)
}
