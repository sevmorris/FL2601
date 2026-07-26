#!/usr/bin/env swift
//
// Generates the FL2601 app icon set: a terminal prompt in phosphor green on a
// near-black squircle, matching the app's palette.
//
// Usage: swift make-icon.swift <output-appiconset-dir>
//
import AppKit
import Foundation

let outputDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "FL2601/Assets.xcassets/AppIcon.appiconset")

// Palette, lifted from Theme.swift.
let panel = NSColor(srgbRed: 0x11 / 255.0, green: 0x11 / 255.0, blue: 0x11 / 255.0, alpha: 1)
let green = NSColor(srgbRed: 0x33 / 255.0, green: 0xFF / 255.0, blue: 0x33 / 255.0, alpha: 1)
let greenLo = NSColor(srgbRed: 0x1A / 255.0, green: 0x6B / 255.0, blue: 0x1A / 255.0, alpha: 1)

func render(size: CGFloat) -> Data {
    // Draw into an explicitly sized bitmap rather than NSImage.lockFocus():
    // lockFocus() adopts the current display's backing scale, which silently
    // produces 2x-oversized PNGs on a Retina Mac.
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to allocate \(pixels)px bitmap")
    }
    // Pin the point size to the pixel size so 1pt == 1px while drawing.
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    // Apple's macOS icon grid: the art occupies ~80% of the canvas with a
    // corner radius of ~22% of the art's width.
    let inset = size * 0.1
    let artSize = size - inset * 2
    let rect = NSRect(x: inset, y: inset, width: artSize, height: artSize)
    let radius = artSize * 0.2237

    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    panel.setFill()
    squircle.fill()

    greenLo.setStroke()
    squircle.lineWidth = max(1, size * 0.008)
    squircle.stroke()

    // ">_" — a shell prompt. Drawn with paths rather than text so it stays
    // crisp at 16pt and does not depend on a font being installed.
    let stroke = artSize * 0.075
    green.setStroke()

    let chevron = NSBezierPath()
    chevron.lineWidth = stroke
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    let cx = rect.minX + artSize * 0.30
    let cyMid = rect.midY + artSize * 0.045
    let armH = artSize * 0.15
    let armW = artSize * 0.13
    chevron.move(to: NSPoint(x: cx - armW / 2, y: cyMid + armH))
    chevron.line(to: NSPoint(x: cx + armW / 2, y: cyMid))
    chevron.line(to: NSPoint(x: cx - armW / 2, y: cyMid - armH))
    chevron.stroke()

    // Underscore cursor.
    let cursor = NSBezierPath()
    cursor.lineWidth = stroke
    cursor.lineCapStyle = .round
    let uy = cyMid - armH
    cursor.move(to: NSPoint(x: rect.minX + artSize * 0.50, y: uy))
    cursor.line(to: NSPoint(x: rect.minX + artSize * 0.74, y: uy))
    cursor.stroke()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode \(pixels)px icon")
    }
    return png
}

// (point size, scale)
let variants: [(Int, Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

var images: [[String: String]] = []

for (points, scale) in variants {
    let pixels = points * scale
    let suffix = scale == 1 ? "" : "@\(scale)x"
    let filename = "icon_\(points)x\(points)\(suffix).png"

    try render(size: CGFloat(pixels))
        .write(to: outputDir.appendingPathComponent(filename))

    images.append([
        "filename": filename,
        "idiom": "mac",
        "scale": "\(scale)x",
        "size": "\(points)x\(points)",
    ])
}

let manifest: [String: Any] = [
    "images": images,
    "info": ["author": "xcode", "version": 1],
]

let json = try JSONSerialization.data(
    withJSONObject: manifest,
    options: [.prettyPrinted, .sortedKeys]
)
try json.write(to: outputDir.appendingPathComponent("Contents.json"))

print("Wrote \(variants.count) icons + Contents.json to \(outputDir.path)")
