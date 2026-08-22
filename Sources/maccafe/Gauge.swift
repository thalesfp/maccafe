import Foundation

/// How full the cup is drawn, and when that will change.
///
/// This is the pure half of the menu bar gauge: it takes the hold and a clock
/// reading and answers with values, so the rule is testable without AppKit.
struct Gauge: Equatable, Sendable {
    /// How many steps the gauge has. Fewer steps mean fewer redraws, and the
    /// menu carries the exact remaining time anyway.
    static let steps = 8

    /// A live hold never drains past this, so "nearly over" cannot be mistaken
    /// for "off". The gauge is deliberately coarse; the menu is exact.
    static let floor = steps / 4

    /// 0 is an empty cup, `steps` a full one.
    var step: Int

    /// When the drawn step next changes on its own, or nil when it never does:
    /// nothing is held, the hold is open ended, or it has already sunk to the
    /// floor and will not move again until the agent ends it.
    var changesAt: Date?

    static func reading(for hold: Hold?, at now: Date) -> Gauge {
        guard let hold, !hold.hasExpired(at: now) else {
            return Gauge(step: 0, changesAt: nil)
        }

        guard let expiresAt = hold.expiresAt, let left = hold.remaining(at: now) else {
            return Gauge(step: steps, changesAt: nil)
        }

        let total = expiresAt.timeIntervalSince(hold.startedAt)

        guard total > 0 else { return Gauge(step: steps, changesAt: nil) }

        let filled = Double(left) / total * Double(steps)
        let raw = max(1, min(steps, Int(filled.rounded(.up))))
        let next = raw - 1

        return Gauge(
            step: max(floor, raw),
            changesAt: next >= floor
                ? expiresAt.addingTimeInterval(-total * Double(next) / Double(steps))
                : nil
        )
    }
}
