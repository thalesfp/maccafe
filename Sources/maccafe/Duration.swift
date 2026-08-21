import Foundation

enum DurationText {
    static let examples = "45s, 90m, 2h, or 1h30m"

    struct ParseError: Error, CustomStringConvertible {
        let input: String

        var description: String {
            "invalid duration \"\(input)\": expected a value like \(examples)"
        }
    }

    static func parse(_ input: String) throws -> Int {
        var total = 0
        var value = 0
        var digits = false
        var units = false

        for character in input.trimmingCharacters(in: .whitespaces) {
            if let digit = character.wholeNumberValue, character.isNumber {
                let (shifted, overflow) = value.multipliedReportingOverflow(by: 10)
                guard !overflow else { throw ParseError(input: input) }
                value = shifted + digit
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

            total += value * multiplier
            value = 0
            digits = false
            units = true
        }

        if digits {
            guard !units else { throw ParseError(input: input) }
            total = value
        }

        guard total > 0 else { throw ParseError(input: input) }

        return total
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
