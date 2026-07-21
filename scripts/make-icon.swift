// Generates assets/AppIcon.icns — a blue rounded-square with a shield-slash
// symbol. Run once: swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS icon grid: content inset from the canvas edge
let inset: CGFloat = size * 0.098
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bg = NSBezierPath(roundedRect: rect, xRadius: size * 0.18, yRadius: size * 0.18)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.95, alpha: 1),
    ending: NSColor(calibratedRed: 0.05, green: 0.16, blue: 0.45, alpha: 1))!
gradient.draw(in: bg, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .medium)
if let symbol = NSImage(systemSymbolName: "shield.slash.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    NSColor.white.set()
    let r = NSRect(origin: .zero, size: symbol.size)
    symbol.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()

    let s = symbol.size
    let scale = (size * 0.55) / max(s.width, s.height)
    let w = s.width * scale, h = s.height * scale
    tinted.draw(in: NSRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h))
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff) else { fatalError("render failed") }

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "assets/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for px in [16, 32, 64, 128, 256, 512, 1024] {
    let scaled = NSImage(size: NSSize(width: px, height: px))
    scaled.lockFocus()
    rep.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    scaled.unlockFocus()
    guard let t = scaled.tiffRepresentation,
          let r = NSBitmapImageRep(data: t),
          let png = r.representation(using: .png, properties: [:]) else { continue }
    let base = px == 1024 ? 512 : px
    let suffix = px == 1024 ? "512x512@2x" : "\(base)x\(base)"
    try! png.write(to: iconset.appendingPathComponent("icon_\(suffix).png"))
    if px >= 32 && px < 1024 {
        try! png.write(to: iconset.appendingPathComponent("icon_\(px / 2)x\(px / 2)@2x.png"))
    }
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "assets/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "wrote assets/AppIcon.icns" : "iconutil failed")
