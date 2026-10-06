import AppKit

// Export the selected artwork at exact macOS icon resolutions, preserving alpha.
let arguments = CommandLine.arguments
guard arguments.count == 3, let source = NSImage(contentsOfFile: arguments[1]) else {
    fatalError("Usage: swift Scripts/package_icon.swift input.png output.iconset")
}
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sizes = [(16, 16), (16, 32), (32, 32), (32, 64), (128, 128),
             (128, 256), (256, 256), (256, 512), (512, 512), (512, 1024)]
for (points, pixels) in sizes {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
        pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Unable to create icon bitmap")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero, operation: .copy, fraction: 1)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode icon")
    }
    let scale = points == pixels ? "" : "@2x"
    try png.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(scale).png"))
}
print("Generated \(output.path)")
