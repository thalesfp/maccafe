import Foundation

enum DurationText {
    static let examples = "45s, 90m, 2h, or 1h30m"

    /// A year of hold is already indistinguishable from no time limit, and it
    /// keeps every later conversion, including the dispatch deadline in
    /// nanoseconds, far inside what its type can hold.
    static let longest = 365 * 86_400

    struct ParseError: Error, CustomStringConvertible {
        let input: String

        var description: String {
            "invalid duration \"\(input)\": expected a value like \(examples), up to 365d"
        }
    }

    static func parse(_ input: String) throws -> Int {
        var total = 0
        var value = 0
        var digits = false
        var units = false

        for character in input.trimmingCharacters(in: .whitespaces) {
            if let digit = character.wholeNumberValue, character.isNumber {
                value = try step(value, times: 10, plus: digit, input)
                digits = true
                continue
            }

            let multiplier: Int
            switch character {
            case "s", "S": multiplier = 1
            case "m", "M": multiplier = 60
            case "h", "H": multiplier = 3_600
            case "d", "D": multiplier = 86_400
            default: throw ParseError(input: input)
            }

            guard digits else { throw ParseError(input: input) }

            total = try step(
                total, times: 1, plus: try step(value, times: multiplier, plus: 0, input), input)
            value = 0
            digits = false
            units = true
        }

        if digits {
            guard !units else { throw ParseError(input: input) }
            total = value
        }

        guard total > 0, total <= longest else { throw ParseError(input: input) }

        return total
    }

    /// Overflow is a parse error, not a trap: the text came from a person or an
    /// MCP client, and either can send a number this big.
    private static func step(_ value: Int, times: Int, plus: Int, _ input: String) throws -> Int {
        let (scaled, scaleOverflowed) = value.multipliedReportingOverflow(by: times)
        guard !scaleOverflowed else { throw ParseError(input: input) }

        let (sum, sumOverflowed) = scaled.addingReportingOverflow(plus)
        guard !sumOverflowed, sum <= longest else { throw ParseError(input: input) }

        return sum
    }

    static func format(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60

        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if remainder > 0 || parts.isEmpty { parts.append("\(remainder)s") }

        return parts.joined(separator: " ")
    }
}
