import AppKit

/// The menu bar glyph, drawn rather than loaded: a template image tints itself
/// for light and dark menu bars, and drawing it needs no bundle resource.
///
/// The outline never changes, so the item keeps its width and stays recognisable
/// beside its neighbours. What changes is how full the cup is.
@MainActor
enum CupGlyph {
    static let size = NSSize(width: 15, height: 15)

    private static let bowlBottom: CGFloat = 4.8
    private static let bowlTop: CGFloat = 12.2

    private static var cache: [Int: NSImage] = [:]

    /// `step` runs from 0 for an empty cup to `Gauge.steps` for a full one.
    static func image(step: Int) -> NSImage {
        let key = min(max(0, step), Gauge.steps)

        if let cached = cache[key] {
            return cached
        }

        let image = NSImage(size: size, flipped: false) { _ in
            draw(level: CGFloat(key) / CGFloat(Gauge.steps))

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = key == 0 ? "maccafe: off" : "maccafe: on"
        cache[key] = image

        return image
    }

    private static func draw(level: CGFloat) {
        let stroke: CGFloat = 1.4

        let body = NSBezierPath()
        body.move(to: NSPoint(x: 1.8, y: bowlTop))
        body.line(to: NSPoint(x: 2.25, y: 7.2))
        body.curve(
            to: NSPoint(x: 6.6, y: bowlBottom),
            controlPoint1: NSPoint(x: 2.4, y: 5.6),
            controlPoint2: NSPoint(x: 4.2, y: bowlBottom)
        )
        body.curve(
            to: NSPoint(x: 10.95, y: 7.2),
            controlPoint1: NSPoint(x: 9.0, y: bowlBottom),
            controlPoint2: NSPoint(x: 10.8, y: 5.6)
        )
        body.line(to: NSPoint(x: 11.4, y: bowlTop))
        body.close()

        let handle = NSBezierPath()
        handle.appendArc(
            withCenter: NSPoint(x: 11.14, y: 9.3),
            radius: 2.15,
            startAngle: -80,
            endAngle: 80
        )
        handle.lineWidth = stroke
        handle.lineCapStyle = .round
        handle.stroke()

        if level > 0 {
            NSGraphicsContext.saveGraphicsState()
            body.addClip()
            NSBezierPath(
                rect: NSRect(
                    x: 0,
                    y: bowlBottom,
                    width: size.width,
                    height: (bowlTop - bowlBottom) * level
                )
            ).fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        body.lineWidth = stroke
        body.lineJoinStyle = .round
        body.stroke()

        NSBezierPath(
            roundedRect: NSRect(x: 1.3, y: 2.8, width: 12.4, height: 1.8),
            xRadius: 0.9,
            yRadius: 0.9
        ).fill()
    }
}
