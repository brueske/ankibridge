import AppKit

// Renders a 1024x1024 app icon: a gradient squircle with a stack of flashcards,
// a bold "A", and a small spark suggesting AI generation.

let size = 1024.0
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a)
}

// Background squircle with vertical gradient.
let margin = 84.0
let bgRect = NSRect(x: margin, y: margin, width: size - margin*2, height: size - margin*2)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 200, yRadius: 200)
ctx.saveGState()
bgPath.addClip()
let grad = NSGradient(colors: [color(99, 102, 241), color(14, 165, 233)])!  // indigo -> sky
grad.draw(in: bgRect, angle: -90)
ctx.restoreGState()

// Helper to draw a rounded white card with shadow, optionally rotated about its center.
func drawCard(center: NSPoint, w: CGFloat, h: CGFloat, rotationDeg: CGFloat, fill: NSColor) {
    ctx.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()

    let t = NSAffineTransform()
    t.translateX(by: center.x, yBy: center.y)
    t.rotate(byDegrees: rotationDeg)
    t.concat()

    let r = NSRect(x: -w/2, y: -h/2, width: w, height: h)
    let p = NSBezierPath(roundedRect: r, xRadius: 64, yRadius: 64)
    fill.setFill()
    p.fill()
    ctx.restoreGState()
}

let cardCenter = NSPoint(x: size/2, y: size/2 - 10)
// Back card, tilted.
drawCard(center: NSPoint(x: cardCenter.x + 26, y: cardCenter.y - 18),
         w: 470, h: 560, rotationDeg: -9, fill: color(226, 232, 255))
// Front card.
drawCard(center: cardCenter, w: 470, h: 560, rotationDeg: 0, fill: .white)

// Divider line on the front card (flashcard front/back separator).
ctx.saveGState()
color(99, 102, 241, 0.25).setStroke()
let divider = NSBezierPath()
divider.lineWidth = 6
divider.move(to: NSPoint(x: cardCenter.x - 150, y: cardCenter.y - 40))
divider.line(to: NSPoint(x: cardCenter.x + 150, y: cardCenter.y - 40))
divider.stroke()
ctx.restoreGState()

// Big "A".
let para = NSMutableParagraphStyle()
para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 300, weight: .heavy),
    .foregroundColor: color(67, 56, 202),
    .paragraphStyle: para,
]
let a = NSAttributedString(string: "A", attributes: attrs)
let aSize = a.size()
a.draw(at: NSPoint(x: cardCenter.x - aSize.width/2, y: cardCenter.y - 20))

// Spark / lightning bolt badge to suggest AI generation.
func bolt(at p: NSPoint, scale: CGFloat) -> NSBezierPath {
    let pts: [(CGFloat, CGFloat)] = [
        (0.55, 1.0), (0.0, 0.45), (0.40, 0.45), (0.30, 0.0),
        (0.95, 0.62), (0.52, 0.62),
    ]
    let path = NSBezierPath()
    for (i, pt) in pts.enumerated() {
        let q = NSPoint(x: p.x + (pt.0 - 0.45) * scale, y: p.y + (pt.1 - 0.5) * scale)
        if i == 0 { path.move(to: q) } else { path.line(to: q) }
    }
    path.close()
    return path
}
let badgeCenter = NSPoint(x: cardCenter.x + 150, y: cardCenter.y - 150)
ctx.saveGState()
let badge = NSBezierPath(ovalIn: NSRect(x: badgeCenter.x - 70, y: badgeCenter.y - 70, width: 140, height: 140))
color(14, 165, 233).setFill()
badge.fill()
let b = bolt(at: badgeCenter, scale: 120)
NSColor.white.setFill()
b.fill()
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! data.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
