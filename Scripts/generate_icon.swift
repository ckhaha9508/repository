import AppKit

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : "Icon.iconset"
let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)

try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let sizes: [(points: Int, pixels: Int)] = [
    (16, 16),
    (16, 32),
    (32, 32),
    (32, 64),
    (128, 128),
    (128, 256),
    (256, 256),
    (256, 512),
    (512, 512),
    (512, 1024)
]

for entry in sizes {
    let pixels = CGFloat(entry.pixels)
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    let cornerRadius = pixels * 0.22
    let background = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.12, alpha: 1),
        NSColor(calibratedRed: 0.96, green: 0.18, blue: 0.08, alpha: 1)
    ])!
    gradient.draw(in: background, angle: -70)

    let inset = pixels * 0.10
    let glowRect = rect.insetBy(dx: inset, dy: inset)
    let glow = NSBezierPath(ovalIn: glowRect)
    NSColor.white.withAlphaComponent(0.16).setFill()
    glow.fill()

    if let symbol = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil) {
        symbol.isTemplate = true
        let symbolSize = pixels * 0.56
        let symbolRect = NSRect(
            x: (pixels - symbolSize) / 2,
            y: (pixels - symbolSize) / 2,
            width: symbolSize,
            height: symbolSize
        )
        NSColor.white.set()
        symbol.draw(in: symbolRect)
    }

    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        continue
    }

    let scaleName = entry.points == entry.pixels ? "" : "@2x"
    let name = "icon_\(entry.points)x\(entry.points)\(scaleName).png"
    try? png.write(to: outputURL.appendingPathComponent(name))
}

print("Generated iconset at \(outputURL.path)")
