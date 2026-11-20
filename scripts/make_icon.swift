import AppKit
import CoreGraphics
import Foundation

func drawIcon(pixelSize: Int, scale: Int, to url: URL) {
    let s = CGFloat(pixelSize)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return }

    // Set point size explicitly so @2x assets have 144 DPI metadata required by iconutil.
    let pointSize = CGFloat(pixelSize / scale)
    rep.size = NSSize(width: pointSize, height: pointSize)

    NSGraphicsContext.saveGraphicsState()
    guard let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext
    ctx.scaleBy(x: 1.0 / CGFloat(scale), y: 1.0 / CGFloat(scale))
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    let inset = s * 0.085
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let cornerRadius = rect.width * 0.225
    let squircle = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Soft drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.04, color: NSColor(white: 0, alpha: 0.45).cgColor)
    ctx.addPath(squircle)
    ctx.setFillColor(NSColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient clipped to squircle
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.12, green: 0.14, blue: 0.16, alpha: 1.0).cgColor,
        NSColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            bgGrad,
            start: CGPoint(x: s * 0.5, y: rect.maxY),
            end: CGPoint(x: s * 0.5, y: rect.minY),
            options: []
        )
    }

    // Subtle green ambient glow
    let glowColors = [
        NSColor(red: 0.11, green: 0.84, blue: 0.38, alpha: 0.28).cgColor,
        NSColor(red: 0.11, green: 0.84, blue: 0.38, alpha: 0.0).cgColor
    ] as CFArray
    if let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        let center = CGPoint(x: s * 0.5, y: s * 0.52)
        ctx.drawRadialGradient(glowGrad, startCenter: center, startRadius: 0, endCenter: center, endRadius: rect.width * 0.55, options: [])
    }

    // Inner rim highlight
    ctx.addPath(squircle)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.strokePath()
    ctx.restoreGState()

    // Vibrant green circular badge
    let badgeRadius = rect.width * 0.31
    let badgeCenter = CGPoint(x: s * 0.5, y: s * 0.52)
    let badgeRect = CGRect(
        x: badgeCenter.x - badgeRadius,
        y: badgeCenter.y - badgeRadius,
        width: badgeRadius * 2,
        height: badgeRadius * 2
    )

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.035, color: NSColor(red: 0.11, green: 0.84, blue: 0.38, alpha: 0.45).cgColor)
    ctx.addEllipse(in: badgeRect)
    ctx.clip()
    let greenColors = [
        NSColor(red: 0.18, green: 0.90, blue: 0.45, alpha: 1.0).cgColor,
        NSColor(red: 0.08, green: 0.68, blue: 0.30, alpha: 1.0).cgColor
    ] as CFArray
    if let greenGrad = CGGradient(colorsSpace: colorSpace, colors: greenColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            greenGrad,
            start: CGPoint(x: badgeRect.midX, y: badgeRect.maxY),
            end: CGPoint(x: badgeRect.midX, y: badgeRect.minY),
            options: []
        )
    }
    ctx.restoreGState()

    // Sound wave arcs
    ctx.saveGState()
    ctx.setStrokeColor(NSColor(red: 0.06, green: 0.08, blue: 0.08, alpha: 1.0).cgColor)
    ctx.setLineCap(.round)

    let waves: [(yOff: CGFloat, halfW: CGFloat, curve: CGFloat, lw: CGFloat)] = [
        (0.105, 0.195, 0.055, 0.048),
        (0.005, 0.160, 0.045, 0.042),
        (-0.090, 0.125, 0.035, 0.036)
    ]
    for w in waves {
        let p = CGMutablePath()
        let y = badgeCenter.y + rect.width * w.yOff
        let hw = rect.width * w.halfW
        let ctrlY = y + rect.width * w.curve
        p.move(to: CGPoint(x: badgeCenter.x - hw, y: y - rect.width * 0.012))
        p.addQuadCurve(
            to: CGPoint(x: badgeCenter.x + hw, y: y - rect.width * 0.022),
            control: CGPoint(x: badgeCenter.x + rect.width * 0.01, y: ctrlY)
        )
        ctx.addPath(p)
        ctx.setLineWidth(rect.width * w.lw)
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Customization sliders badge at bottom-right
    let pillSize = rect.width * 0.24
    let pillRect = CGRect(
        x: badgeCenter.x + badgeRadius * 0.42,
        y: badgeCenter.y - badgeRadius * 1.08,
        width: pillSize,
        height: pillSize
    )
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.025, color: NSColor(white: 0, alpha: 0.5).cgColor)
    ctx.addEllipse(in: pillRect)
    ctx.setFillColor(NSColor(red: 0.14, green: 0.16, blue: 0.19, alpha: 1.0).cgColor)
    ctx.fillPath()
    ctx.addEllipse(in: pillRect)
    ctx.setStrokeColor(NSColor(red: 0.18, green: 0.90, blue: 0.45, alpha: 0.9).cgColor)
    ctx.setLineWidth(max(1.0, rect.width * 0.022))
    ctx.strokePath()

    let px = pillRect.midX
    let py = pillRect.midY
    let pw = pillRect.width * 0.26
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(max(1.0, pillRect.width * 0.09))
    ctx.setLineCap(.round)
    for (idx, dy) in [-0.15, 0.15].enumerated() {
        let ly = py + pillRect.height * CGFloat(dy)
        ctx.move(to: CGPoint(x: px - pw, y: ly))
        ctx.addLine(to: CGPoint(x: px + pw, y: ly))
        ctx.strokePath()
        let knobX = idx == 0 ? px + pw * 0.35 : px - pw * 0.35
        let kr = pillRect.width * 0.10
        ctx.setFillColor(NSColor(red: 0.18, green: 0.90, blue: 0.45, alpha: 1.0).cgColor)
        ctx.fillEllipse(in: CGRect(x: knobX - kr, y: ly - kr, width: kr * 2, height: kr * 2))
    }
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()

    if let pngData = rep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: url)
    }
}

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: swift make_icon.swift <output_iconset_dir>\n", stderr)
    exit(1)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let specs: [(name: String, px: Int, scale: Int)] = [
    ("icon_16x16.png", 16, 1),
    ("icon_16x16@2x.png", 32, 2),
    ("icon_32x32.png", 32, 1),
    ("icon_32x32@2x.png", 64, 2),
    ("icon_128x128.png", 128, 1),
    ("icon_128x128@2x.png", 256, 2),
    ("icon_256x256.png", 256, 1),
    ("icon_256x256@2x.png", 512, 2),
    ("icon_512x512.png", 512, 1),
    ("icon_512x512@2x.png", 1024, 2)
]

for spec in specs {
    drawIcon(pixelSize: spec.px, scale: spec.scale, to: outDir.appendingPathComponent(spec.name))
}
print("Generated Retina iconset in \(outDir.path)")
