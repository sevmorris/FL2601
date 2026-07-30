#!/usr/bin/env swift
//
// Generates the FL2601 app icon set by downscaling the 1024px master to each
// size macOS asks for.
//
// The master already sits on Apple's icon grid — the art occupies ~81% of the
// canvas and the surrounding margin is transparent — so this only resamples.
// Do not inset it again here.
//
// Usage: swift make-icon.swift [output-appiconset-dir] [master-png]
//
import AppKit
import Foundation

let args = CommandLine.arguments

let outputDir = args.count > 1
    ? URL(fileURLWithPath: args[1])
    : URL(fileURLWithPath: "FL2601/Assets.xcassets/AppIcon.appiconset")

let masterPath = args.count > 2
    ? URL(fileURLWithPath: args[2])
    : URL(fileURLWithPath: "icon-master.png")

guard let master = NSImage(contentsOf: masterPath) else {
    fatalError("Could not read master icon at \(masterPath.path)")
}

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

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    master.draw(
        in: rect,
        from: .zero,
        operation: .copy,
        fraction: 1.0,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high.rawValue]
    )

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
