import Foundation
import Testing

@testable import maccafe

@Suite("Reporting a hold to a person and to a script")
struct RenderTests {
    let startedAt = Date(timeIntervalSince1970: 1_787_184_892)
    var now: Date { startedAt.addingTimeInterval(240) }

    private func hold(expiresIn seconds: Int?) -> Hold {
        Hold(kind: .display, startedAt: startedAt, lasting: seconds)
    }

    @Test("tells a person how long the hold has run and how long is left")
    func describesAHoldThatRunsOut() {
        let text = Render.reply(.held(hold(expiresIn: 3_600)), at: now, asJSON: false)

        #expect(text == "on: preventing display and system sleep for 4m, 56m left")
    }

    @Test("says an open ended hold has no time limit")
    func describesAnOpenEndedHold() {
        let text = Render.reply(.held(hold(expiresIn: nil)), at: now, asJSON: false)

        #expect(text == "on: preventing display and system sleep for 4m, no time limit")
    }

    @Test("gives a script the times and the seconds it derives from them")
    func reportsAHoldAsJSON() {
        let text = Render.reply(.held(hold(expiresIn: 3_600)), at: now, asJSON: true)

        #expect(
            text == #"{"elapsed_seconds":240,"expires_at":"2026-08-20T01:14:52Z","held":true,"#
                + #""kind":"display","remaining_seconds":3360,"started_at":"2026-08-20T00:14:52Z"}"#
        )
    }

    @Test("leaves the end of an open ended hold empty")
    func reportsAnOpenEndedHoldAsJSON() {
        let text = Render.reply(.held(hold(expiresIn: nil)), at: now, asJSON: true)

        #expect(text.contains(#""expires_at":null"#))
        #expect(text.contains(#""remaining_seconds":null"#))
    }

    @Test("reports a Mac that is free to sleep")
    func reportsAFreeMac() {
        #expect(Render.reply(.free, at: now, asJSON: true) == #"{"held":false}"#)
        #expect(Render.reply(.free, at: now, asJSON: false) == "off: this Mac can sleep normally")
    }

    @Test("tells a stopped hold apart from one that was never running")
    func distinguishesAStoppedHold() {
        #expect(
            Render.reply(.stopped(true), at: now, asJSON: true) == #"{"held":false,"stopped":true}"#
        )
        #expect(
            Render.reply(.stopped(false), at: now, asJSON: false)
                == "off: this Mac was already free to sleep"
        )
    }

    @Test("reports a failure in the shape the caller asked for")
    func reportsAFailure() {
        #expect(
            Render.failure("cannot reach the agent", asJSON: true)
                == #"{"error":"cannot reach the agent"}"#)
        #expect(
            Render.failure("cannot reach the agent", asJSON: false)
                == "maccafe: cannot reach the agent")
    }
}
