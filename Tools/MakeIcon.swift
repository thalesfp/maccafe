import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// Draws MacCafe.icns from Tools/cup.png. Run it with `make icon`; the result is
/// committed, so a normal build never needs a rendering pass.

/// #8FB39C: the sage already in the artwork's rim band, darkened for separation
/// from the cup's cream rim. Complementary to the amber, and light enough that the
/// near-black outline keeps its edge.
let background = CGColor(red: 0.561, green: 0.702, blue: 0.612, alpha: 1)

/// Apple's rounded rect is a continuous superellipse, not a circular-radius
/// rounded rect; the difference is obvious at icon sizes.
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2
    let b = rect.height / 2
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    let exponent = 2.0 / 5.0

    for step in 0...720 {
        let t = CGFloat(step) / 720 * 2 * .pi
        let x = centre.x + a * copysign(pow(abs(cos(t)), exponent), cos(t))
        let y = centre.y + b * copysign(pow(abs(sin(t)), exponent), sin(t))

        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()

    return path
}

/// The macOS grid leaves the artwork short of the canvas so the drop shadow has
/// somewhere to fall.
func plateRect(_ side: CGFloat) -> CGRect {
    CGRect(x: side * 0.0977, y: side * 0.1074, width: side * 0.8046, height: side * 0.8046)
}

/// The source art carries its own transparent margin, so it is trimmed to the
/// pixels that are actually drawn before it is sized against the plate.
func trimmed(_ image: CGImage) -> CGImage {
    let width = image.width
    let height = image.height
    var alpha = [UInt8](repeating: 0, count: width * height)

    alpha.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
        for x in 0..<width where alpha[y * width + x] > 8 {
            minX = min(minX, x)
            maxX = max(maxX, x)
            minY = min(minY, y)
            maxY = max(maxY, y)
        }
    }

    guard maxX >= minX, maxY >= minY else { return image }

    return image.cropping(
        to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    )!
}

func render(_ cup: CGImage, _ side: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high

    let scale = CGFloat(side)
    let plate = plateRect(scale)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -scale * 0.014),
        blur: scale * 0.030,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28)
    )
    context.setFillColor(background)
    context.addPath(squircle(in: plate))
    context.fillPath()
    context.restoreGState()

    let widest = plate.width * 0.900
    let ratio = CGFloat(cup.height) / CGFloat(cup.width)
    let art = CGSize(width: widest, height: widest * ratio)
    context.draw(
        cup,
        in: CGRect(
            x: plate.midX - art.width / 2,
            y: plate.midY - art.height / 2,
            width: art.width,
            height: art.height
        )
    )

    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let source = URL(fileURLWithPath: "Tools/cup.png")
let cup = trimmed(NSImage(contentsOf: source)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!)

let iconset = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    write(render(cup, base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    write(
        render(cup, base * 2),
        to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png")
    )
}

print("wrote \(iconset.path)")
