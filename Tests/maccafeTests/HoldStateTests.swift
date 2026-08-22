import Foundation
import Testing

@testable import maccafe

@Suite("Deciding what a request does to a hold")
struct HoldStateTests {
    let now = Date(timeIntervalSince1970: 1_787_184_892)

    private func holding(_ kind: AssertionKind, secondsLeft: Int?) -> Hold {
        Hold(kind: kind, startedAt: now, lasting: secondsLeft)
    }

    @Test("takes the assertion when nothing is holding it")
    func takesTheAssertionWhenIdle() {
        let outcome = apply(.on(kind: .display, seconds: nil), to: nil, at: now)

        #expect(outcome.effect.assertion == .take(.display))
        #expect(outcome.effect.deadline == .disarm)
        #expect(outcome.hold?.expiresAt == nil)
    }

    @Test("arms the deadline when the request has a duration")
    func armsTheDeadline() {
        let outcome = apply(.on(kind: .display, seconds: 3_600), to: nil, at: now)

        #expect(outcome.effect.deadline == .arm(now.addingTimeInterval(3_600)))
    }

    @Test("keeps the assertion when a new request wants the same kind")
    func keepsTheAssertionForTheSameKind() {
        let outcome = apply(
            .on(kind: .display, seconds: 60),
            to: holding(.display, secondsLeft: 3_600),
            at: now
        )

        #expect(outcome.effect.assertion == .keep)
        #expect(outcome.effect.deadline == .arm(now.addingTimeInterval(60)))
    }

    @Test("swaps the assertion when a new request wants the other kind")
    func swapsTheAssertionForAnotherKind() {
        let outcome = apply(
            .on(kind: .system, seconds: nil),
            to: holding(.display, secondsLeft: 3_600),
            at: now
        )

        #expect(outcome.effect.assertion == .take(.system))
        #expect(outcome.effect.deadline == .disarm)
    }

    @Test("shortens a hold that had longer to run")
    func shortensALongerHold() {
        let outcome = apply(
            .on(kind: .display, seconds: 60),
            to: holding(.display, secondsLeft: 7_200),
            at: now
        )

        #expect(outcome.hold?.remaining(at: now) == 60)
    }

    @Test("changing the kind leaves the countdown alone")
    func changingTheKindKeepsTheDeadline() {
        let running = holding(.display, secondsLeft: 3_600)

        let outcome = apply(.change(kind: .system), to: running, at: now.addingTimeInterval(240))

        #expect(outcome.effect.assertion == .take(.system))
        #expect(outcome.effect.deadline == .keep)
        #expect(outcome.hold?.expiresAt == running.expiresAt)
        #expect(outcome.hold?.startedAt == running.startedAt)
    }

    @Test("changing the kind to the one already held does nothing")
    func changingToTheSameKindDoesNothing() {
        let running = holding(.system, secondsLeft: 3_600)

        let outcome = apply(.change(kind: .system), to: running, at: now)

        #expect(outcome.effect == .unchanged)
        #expect(outcome.hold == running)
    }

    @Test("changing the kind while nothing is held starts no hold")
    func changingTheKindWhileIdleStartsNothing() {
        let outcome = apply(.change(kind: .system), to: nil, at: now)

        #expect(outcome.hold == nil)
        #expect(outcome.reply == .free)
        #expect(outcome.effect == .unchanged)
    }

    @Test("releases the assertion when a hold is turned off")
    func releasesOnOff() {
        let outcome = apply(.off, to: holding(.display, secondsLeft: nil), at: now)

        #expect(outcome.effect.assertion == .release)
        #expect(outcome.reply == .stopped(true))
        #expect(outcome.hold == nil)
    }

    @Test("reports that there was nothing to turn off")
    func reportsNothingToTurnOff() {
        let outcome = apply(.off, to: nil, at: now)

        #expect(outcome.reply == .stopped(false))
        #expect(outcome.effect == .unchanged)
    }

    @Test("treats a hold that ran out as already off")
    func treatsALapsedHoldAsOff() {
        let lapsed = holding(.display, secondsLeft: 60)

        let outcome = apply(.status, to: lapsed, at: now.addingTimeInterval(120))

        #expect(outcome.reply == .free)
        #expect(outcome.effect.assertion == .release)
        #expect(outcome.effect.deadline == .disarm)
        #expect(outcome.hold == nil)
    }

    @Test("turning off a hold that just ran out still releases the assertion")
    func offRacingExpiryStillReleases() {
        let lapsed = holding(.display, secondsLeft: 60)

        let outcome = apply(.off, to: lapsed, at: now.addingTimeInterval(60))

        #expect(outcome.effect.assertion == .release)
        #expect(outcome.reply == .stopped(false))
    }

    @Test("reports a running hold without changing it")
    func statusLeavesTheHoldAlone() {
        let live = holding(.system, secondsLeft: 3_600)

        let outcome = apply(.status, to: live, at: now.addingTimeInterval(240))

        #expect(outcome.hold == live)
        #expect(outcome.effect == .unchanged)
        #expect(outcome.reply == .held(live))
    }
}
