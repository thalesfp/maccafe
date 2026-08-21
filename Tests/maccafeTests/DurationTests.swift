import Testing

@testable import maccafe

@Suite("Reading a duration a person typed")
struct DurationParsingTests {
    @Test("reads a single unit")
    func readsASingleUnit() throws {
        #expect(try DurationText.parse("45s") == 45)
        #expect(try DurationText.parse("90m") == 5_400)
        #expect(try DurationText.parse("2h") == 7_200)
        #expect(try DurationText.parse("1d") == 86_400)
    }

    @Test("reads units written together")
    func readsCombinedUnits() throws {
        #expect(try DurationText.parse("1h30m") == 5_400)
        #expect(try DurationText.parse("1h30m15s") == 5_415)
    }

    @Test("treats a bare number as seconds")
    func treatsABareNumberAsSeconds() throws {
        #expect(try DurationText.parse("120") == 120)
    }

    @Test(
        "rejects input a user can realistically mistype",
        arguments: ["", "abc", "10x", "1h30", "0s"])
    func rejectsMistypedInput(_ input: String) {
        #expect(throws: DurationText.ParseError.self) { try DurationText.parse(input) }
    }

    @Test("writes a readable remaining time")
    func writesAReadableRemainingTime() {
        #expect(DurationText.format(0) == "0s")
        #expect(DurationText.format(45) == "45s")
        #expect(DurationText.format(5_400) == "1h 30m")
        #expect(DurationText.format(3_661) == "1h 1m 1s")
    }
}
