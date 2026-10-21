// Draws the LiveWall icon: a sunset landscape behind a glass play button,
// on Apple's macOS icon grid (an 824 pt body centered on a 1024 pt canvas).
//
//   swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: stops.map { color($0.0, $0.1) } as CFArray,
        locations: stops.map(\.2))!
}

/// A mountain ridge from the left edge to the right edge, filled down to the bottom.
func ridge(_ points: [(CGFloat, CGFloat)]) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: body.minX, y: body.minY))
    for (x, y) in points { path.addLine(to: CGPoint(x: x, y: y)) }
    path.addLine(to: CGPoint(x: body.maxX, y: body.minY))
    path.closeSubpath()
    return path
}

let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let bodyPath = CGPath(roundedRect: body, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

// Soft drop shadow under the body.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0x000000, 0.35))
context.addPath(bodyPath)
context.setFillColor(color(0x1A0F3C))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(bodyPath)
context.clip()

// Sky: night at the top, warm horizon at the bottom.
context.drawLinearGradient(
    gradient([(0x120B3A, 1, 0), (0x4B237F, 1, 0.38), (0xC8467F, 1, 0.68), (0xFFB36B, 1, 1)]),
    start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: 300), options: [.drawsAfterEndLocation])

// A few stars in the night sky.
for (x, y, r, a) in [(236, 840, 5, 0.8), (330, 760, 3.5, 0.6), (700, 850, 4.5, 0.75), (790, 760, 3, 0.55),
                     (610, 880, 3, 0.5), (180, 700, 3, 0.45), (850, 660, 3.5, 0.5)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
    context.setFillColor(color(0xFFFFFF, a))
    context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// Setting sun with a glow, sitting in a valley between the far peaks.
let sun = CGPoint(x: 560, y: 410)
context.drawRadialGradient(
    gradient([(0xFFE2B0, 0.85, 0), (0xFF9F6E, 0.35, 0.45), (0xFF9F6E, 0, 1)]),
    startCenter: sun, startRadius: 0, endCenter: sun, endRadius: 300, options: [])
context.setFillColor(color(0xFFEBC9))
context.fillEllipse(in: CGRect(x: sun.x - 84, y: sun.y - 84, width: 168, height: 168))

// Two mountain ridges.
context.addPath(ridge([(100, 360), (230, 470), (330, 400), (440, 520), (560, 380), (690, 500), (800, 410), (924, 470)]))
context.setFillColor(color(0x6E2A6B))
context.fillPath()
context.addPath(ridge([(100, 300), (210, 350), (350, 270), (500, 330), (640, 250), (780, 330), (924, 280)]))
context.setFillColor(color(0x241038))
context.fillPath()

// Gloss across the top half and a thin glass edge.
context.drawLinearGradient(
    gradient([(0xFFFFFF, 0.22, 0), (0xFFFFFF, 0, 1)]),
    start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: 512), options: [])
context.restoreGState()
context.addPath(bodyPath)
context.setStrokeColor(color(0xFFFFFF, 0.18))
context.setLineWidth(3)
context.strokePath()

// Glass play button.
let badge = CGPoint(x: 512, y: 650)
let radius: CGFloat = 138
let badgeRect = CGRect(x: badge.x - radius, y: badge.y - radius, width: radius * 2, height: radius * 2)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.25))
context.setFillColor(color(0xFFFFFF, 0.16))
context.fillEllipse(in: badgeRect)
context.restoreGState()
context.saveGState()
context.addEllipse(in: badgeRect)
context.clip()
context.drawLinearGradient(
    gradient([(0xFFFFFF, 0.42, 0), (0xFFFFFF, 0.04, 0.55), (0xFFFFFF, 0.12, 1)]),
    start: CGPoint(x: 0, y: badgeRect.maxY), end: CGPoint(x: 0, y: badgeRect.minY), options: [])
context.restoreGState()
context.addEllipse(in: badgeRect.insetBy(dx: 1.5, dy: 1.5))
context.setStrokeColor(color(0xFFFFFF, 0.55))
context.setLineWidth(3)
context.strokePath()

let triangle = CGMutablePath()
triangle.move(to: CGPoint(x: badge.x - 38, y: badge.y + 64))
triangle.addLine(to: CGPoint(x: badge.x - 38, y: badge.y - 64))
triangle.addLine(to: CGPoint(x: badge.x + 72, y: badge.y))
triangle.closeSubpath()
// Drawn as one layer so its shadow falls behind it, not across its own fill.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: color(0x2A0E4A, 0.35))
context.beginTransparencyLayer(auxiliaryInfo: nil)
context.addPath(triangle)
context.setFillColor(color(0xFFFFFF))
context.setLineJoin(.round)
context.setLineWidth(18)
context.setStrokeColor(color(0xFFFFFF))
context.drawPath(using: .fillStroke)
context.endTransparencyLayer()
context.restoreGState()

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "icon.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(output.path)") }
print("Wrote \(output.path)")
