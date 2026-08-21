import Foundation
import Testing

@testable import maccafe

@Suite("Showing how much of a hold is left")
struct GaugeTests {
    let startedAt = Date(timeIntervalSince1970: 1_787_184_892)

    private func hold(lasting seconds: Int?) -> Hold {
        Hold(kind: .display, startedAt: startedAt, lasting: seconds)
    }

    @Test("draws an empty cup when nothing is held")
    func drawsAnEmptyCupWhenIdle() {
        let reading = Gauge.reading(for: nil, at: startedAt)

        #expect(reading.step == 0)
        #expect(reading.changesAt == nil)
    }

    @Test("draws a full cup for a hold with no time limit, and never wakes for it")
    func drawsAFullCupForAnOpenEndedHold() {
        let reading = Gauge.reading(for: hold(lasting: nil), at: startedAt.addingTimeInterval(600))

        #expect(reading.step == Gauge.steps)
        #expect(reading.changesAt == nil)
    }

    @Test("drains a step at a time as the hold runs")
    func drainsAsTheHoldRuns() {
        let running = hold(lasting: 800)

        #expect(Gauge.reading(for: running, at: startedAt).step == 8)
        #expect(Gauge.reading(for: running, at: startedAt.addingTimeInterval(150)).step == 7)
        #expect(Gauge.reading(for: running, at: startedAt.addingTimeInterval(350)).step == 5)
    }

    @Test("never drains past the floor, so a hold about to end cannot look like off")
    func neverDrainsPastTheFloor() {
        let running = hold(lasting: 800)

        let nearlyOver = Gauge.reading(for: running, at: startedAt.addingTimeInterval(799))

        #expect(nearlyOver.step == Gauge.floor)
        #expect(nearlyOver.step > 0)
    }

    @Test("says when the drawn step next changes")
    func saysWhenTheStepNextChanges() {
        let running = hold(lasting: 800)

        let reading = Gauge.reading(for: running, at: startedAt)

        #expect(reading.changesAt == startedAt.addingTimeInterval(100))
    }

    @Test("stops asking to be woken once it has sunk to the floor")
    func stopsWakingAtTheFloor() {
        let running = hold(lasting: 800)

        let atFloor = Gauge.reading(for: running, at: startedAt.addingTimeInterval(650))

        #expect(atFloor.step == Gauge.floor)
        #expect(atFloor.changesAt == nil)
    }

    @Test("draws an empty cup for a hold that already ran out")
    func drawsAnEmptyCupForALapsedHold() {
        let reading = Gauge.reading(for: hold(lasting: 60), at: startedAt.addingTimeInterval(120))

        #expect(reading.step == 0)
        #expect(reading.changesAt == nil)
    }
}
