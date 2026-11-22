import AppKit
// Platewise icon: a white plate with a basil leaf and a camera-viewfinder frame, on fresh green.
let out = CommandLine.arguments[1]
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let bg = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.70, blue: 0.47, alpha: 1),
                    NSColor(srgbRed: 0.15, green: 0.47, blue: 0.31, alpha: 1)])!.draw(in: bg, angle: -90)

// Viewfinder corners
NSColor(white: 1, alpha: 0.85).setStroke()
let c: CGFloat = 90, inset: CGFloat = 190, w: CGFloat = 22
for (x, y, dx, dy) in [(inset, inset, 1.0, 1.0), (size - inset, inset, -1.0, 1.0), (inset, size - inset, 1.0, -1.0), (size - inset, size - inset, -1.0, -1.0)] {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: x, y: y + dy * c)); p.line(to: NSPoint(x: x, y: y)); p.line(to: NSPoint(x: x + dx * c, y: y))
    p.lineWidth = w; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
}

// Plate with shadow
let shadow = NSShadow(); shadow.shadowColor = NSColor(white: 0, alpha: 0.25); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState(); shadow.set()
NSColor(srgbRed: 0.99, green: 0.98, blue: 0.95, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 272, y: 272, width: 480, height: 480)).fill()
NSGraphicsContext.restoreGraphicsState()
NSColor(srgbRed: 0.90, green: 0.88, blue: 0.83, alpha: 1).setStroke()
let rim = NSBezierPath(ovalIn: NSRect(x: 342, y: 342, width: 340, height: 340)); rim.lineWidth = 8; rim.stroke()

// Saffron food mound
NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.70, blue: 0.30, alpha: 1),
                    NSColor(srgbRed: 0.90, green: 0.48, blue: 0.18, alpha: 1)])!
    .draw(in: NSBezierPath(ovalIn: NSRect(x: 382, y: 392, width: 260, height: 220)), angle: -90)

// Basil leaf
let leaf = NSBezierPath()
leaf.move(to: NSPoint(x: 520, y: 520))
leaf.curve(to: NSPoint(x: 660, y: 640), controlPoint1: NSPoint(x: 560, y: 640), controlPoint2: NSPoint(x: 620, y: 660))
leaf.curve(to: NSPoint(x: 520, y: 520), controlPoint1: NSPoint(x: 660, y: 570), controlPoint2: NSPoint(x: 600, y: 520))
leaf.close()
NSColor(srgbRed: 0.18, green: 0.55, blue: 0.30, alpha: 1).setFill(); leaf.fill()
NSColor(srgbRed: 0.12, green: 0.40, blue: 0.22, alpha: 1).setStroke()
let vein = NSBezierPath(); vein.move(to: NSPoint(x: 530, y: 528)); vein.line(to: NSPoint(x: 645, y: 628)); vein.lineWidth = 6; vein.lineCapStyle = .round; vein.stroke()

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
