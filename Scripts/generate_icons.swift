#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let projectDir = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let resourcesDir = projectDir.appendingPathComponent("Resources")
let svgURL = resourcesDir.appendingPathComponent("AppIcon.svg")
let iconsetURL = resourcesDir.appendingPathComponent("AppIcon.iconset")
let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")

guard let svgImage = NSImage(contentsOf: svgURL) else {
    fputs("Error: Could not load SVG at \(svgURL.path)\n", stderr)
    exit(1)
}

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(name: String, pixelSize: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for item in sizes {
    let px = item.pixelSize
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fputs("Failed to create bitmap rep for \(px)px\n", stderr)
        continue
    }

    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { continue }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high

    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    svgImage.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to get PNG representation for \(item.name)\n", stderr)
        continue
    }

    let fileURL = iconsetURL.appendingPathComponent(item.name)
    try pngData.write(to: fileURL)
    print("Generated \(item.name) (\(px)x\(px))")
}

// Compile iconset to icns using iconutil
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]

do {
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus == 0 {
        print("Successfully generated \(icnsURL.path)")
    } else {
        fputs("iconutil failed with code \(process.terminationStatus)\n", stderr)
        exit(1)
    }
} catch {
    fputs("Failed to execute iconutil: \(error)\n", stderr)
    exit(1)
}
