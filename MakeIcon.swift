//
//  MakeIcon.swift
//  Generates the Rail app icon: dark mirror surface, two white powder rails,
//  a tiny syringe diagonal across the top-right corner. Writes source.png at 1024².
//
//  Build:  swiftc -framework Cocoa MakeIcon.swift -o makeicon
//  Run:    ./makeicon  → writes source.png in cwd
//

import Cocoa

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no CG context")
}

let cornerRadius: CGFloat = size * 0.225 // ~Apple icon corner

// -- Rounded-square mask -------------------------------------------------
let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
let mask = NSBezierPath(roundedRect: bgRect,
                        xRadius: cornerRadius, yRadius: cornerRadius)
mask.addClip()

// -- Background: dark glass radial gradient -----------------------------
let bgGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
    NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.04, alpha: 1.0),
])!
bgGradient.draw(in: bgRect, relativeCenterPosition: NSPoint(x: 0, y: 0.2))

// -- Subtle vignette ring at the edges ----------------------------------
let vignette = NSGradient(colors: [
    NSColor.black.withAlphaComponent(0.0),
    NSColor.black.withAlphaComponent(0.55),
])!
vignette.draw(in: bgRect, relativeCenterPosition: NSPoint(x: 0, y: 0))

// -- Faint mirrored top sheen -------------------------------------------
let sheen = NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.06),
    NSColor.white.withAlphaComponent(0.00),
])!
sheen.draw(in: NSRect(x: 0, y: size * 0.62, width: size, height: size * 0.38),
           angle: 270)

// -- The two white powder rails -----------------------------------------
// Diagonal across the icon: bottom-left to upper-right at ~12° tilt.
// Two parallel "lines" with slightly fuzzy edges.

ctx.saveGState()
// Center & rotate
ctx.translateBy(x: size / 2, y: size / 2)
ctx.rotate(by: 12 * .pi / 180)

func drawRail(yOffset: CGFloat, length: CGFloat, thickness: CGFloat) {
    // White rail with slight gaussian blur for "powdered" look
    let railRect = NSRect(x: -length / 2,
                          y: yOffset - thickness / 2,
                          width: length,
                          height: thickness)
    // Drop shadow under the rail
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18,
                  color: NSColor.black.withAlphaComponent(0.55).cgColor)
    NSColor.white.setFill()
    let path = NSBezierPath(roundedRect: railRect,
                            xRadius: thickness / 2, yRadius: thickness / 2)
    path.fill()
    ctx.restoreGState()

    // Granular highlight on top edge (slightly off-white inner)
    let topHighlight = NSGradient(colors: [
        NSColor(white: 1.00, alpha: 1.00),
        NSColor(white: 0.92, alpha: 0.0),
    ])!
    topHighlight.draw(in: railRect, angle: 90)

    // Random "grains" scattered along the rail for powdered texture
    NSColor.white.withAlphaComponent(0.85).setFill()
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<160 {
        let dx = CGFloat.random(in: -length/2 ... length/2, using: &rng)
        let dy = CGFloat.random(in: -thickness*0.9 ... thickness*0.9, using: &rng) + yOffset
        let r  = CGFloat.random(in: 1.2 ... 4.0, using: &rng)
        NSBezierPath(ovalIn: NSRect(x: dx - r, y: dy - r, width: r*2, height: r*2)).fill()
    }
    // Drifting grains around the rail (the "snow" outside the line)
    NSColor.white.withAlphaComponent(0.35).setFill()
    for _ in 0..<90 {
        let dx = CGFloat.random(in: -length/2 - 30 ... length/2 + 30, using: &rng)
        let dy = CGFloat.random(in: -thickness*2.4 ... thickness*2.4, using: &rng) + yOffset
        let r  = CGFloat.random(in: 0.6 ... 2.4, using: &rng)
        NSBezierPath(ovalIn: NSRect(x: dx - r, y: dy - r, width: r*2, height: r*2)).fill()
    }
}

drawRail(yOffset:  60, length: size * 0.78, thickness: 42)
drawRail(yOffset: -60, length: size * 0.66, thickness: 38)

ctx.restoreGState()

// -- Tiny syringe across the top-right corner ---------------------------
ctx.saveGState()
ctx.translateBy(x: size * 0.78, y: size * 0.80)
ctx.rotate(by: -30 * .pi / 180)

// Drop shadow under whole syringe
ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 10,
              color: NSColor.black.withAlphaComponent(0.6).cgColor)

let metal = NSColor(white: 0.85, alpha: 1.0)
let barrelGlass = NSColor(white: 0.96, alpha: 0.92)

// Needle
metal.setFill()
NSBezierPath(rect: NSRect(x: -90, y: -3, width: 80, height: 6)).fill()
// Needle hub (small triangle/funnel)
metal.setFill()
let hub = NSBezierPath()
hub.move(to: NSPoint(x: -10, y: -7))
hub.line(to: NSPoint(x: -10, y:  7))
hub.line(to: NSPoint(x:  10, y: 12))
hub.line(to: NSPoint(x:  10, y: -12))
hub.close()
hub.fill()
// Barrel
barrelGlass.setFill()
let barrel = NSBezierPath(roundedRect: NSRect(x: 10, y: -16, width: 130, height: 32),
                          xRadius: 4, yRadius: 4)
barrel.fill()
NSColor(white: 0.65, alpha: 1.0).setStroke()
barrel.lineWidth = 3
barrel.stroke()
// Liquid inside (cocaine-white)
NSColor(white: 0.98, alpha: 1.0).setFill()
NSBezierPath(rect: NSRect(x: 14, y: -12, width: 70, height: 24)).fill()
// Plunger rod
metal.setFill()
NSBezierPath(rect: NSRect(x: 84, y: -2, width: 70, height: 4)).fill()
// Thumb plate
metal.setFill()
NSBezierPath(roundedRect: NSRect(x: 148, y: -22, width: 8, height: 44),
             xRadius: 2, yRadius: 2).fill()

ctx.restoreGState()

img.unlockFocus()

// -- Save as PNG --------------------------------------------------------
guard let tiff = img.tiffRepresentation,
      let rep  = NSBitmapImageRep(data: tiff),
      let png  = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG encode failed")
}
let outURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("source.png")
try! png.write(to: outURL)
print("wrote \(outURL.path) (\(png.count) bytes)")
