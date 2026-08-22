import Foundation

enum Render {
    static func reply(_ reply: Reply, at now: Date, asJSON: Bool) -> String {
        asJSON ? json(reply, at: now) : prose(reply, at: now)
    }

    static func failure(_ message: String, asJSON: Bool) -> String {
        asJSON ? encode(["error": message]) : "maccafe: \(message)"
    }

    private static func prose(_ reply: Reply, at now: Date) -> String {
        switch reply {
        case .held(let hold):
            let limit =
                hold.remaining(at: now).map { ", \(DurationText.format($0)) left" }
                ?? ", no time limit"

            return "on: preventing \(hold.kind.label) for "
                + DurationText.format(hold.elapsed(at: now))
                + limit

        case .free, .stopped(true):
            return "off: this Mac can sleep normally"

        case .stopped(false):
            return "off: this Mac was already free to sleep"

        case .failure(let message):
            return failure(message, asJSON: false)
        }
    }

    private static func json(_ reply: Reply, at now: Date) -> String {
        switch reply {
        case .held(let hold):
            encode([
                "held": true,
                "kind": hold.kind.rawValue,
                "started_at": rfc3339(hold.startedAt),
                "expires_at": hold.expiresAt.map(rfc3339) ?? NSNull(),
                "elapsed_seconds": hold.elapsed(at: now),
                "remaining_seconds": hold.remaining(at: now) ?? NSNull(),
            ])

        case .free:
            encode(["held": false])

        case .stopped(let stopped):
            encode(["held": false, "stopped": stopped])

        case .failure(let message):
            failure(message, asJSON: true)
        }
    }

    private static let rfc3339Style = Date.ISO8601FormatStyle(timeZone: .gmt)

    static func rfc3339(_ date: Date) -> String {
        date.formatted(rfc3339Style)
    }

    private static func encode(_ body: [String: Any]) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return #"{"error":"cannot encode the report"}"#
        }

        return text
    }
}
