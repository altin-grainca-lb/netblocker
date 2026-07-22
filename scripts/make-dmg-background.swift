// Generates assets/dmg-background.png — the installer window background:
// a soft gradient with an arrow between the app icon and Applications alias.
// Run once: swift scripts/make-dmg-background.swift
import AppKit

let width: CGFloat = 660
let height: CGFloat = 400

// Must match the icon positions set in scripts/make-dmg.sh (Finder
// coordinates: origin top-left, y grows downward).
let iconCenterY: CGFloat = 190
let appX: CGFloat = 180
let destX: CGFloat = 480

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

// AppKit drawing here is bottom-left origin — flip Finder's y.
func flip(_ y: CGFloat) -> CGFloat { height - y }

let bg = NSGradient(
    starting: NSColor(calibratedWhite: 0.99, alpha: 1),
    ending: NSColor(calibratedRed: 0.90, green: 0.93, blue: 0.98, alpha: 1))!
bg.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

// Arrow from the app icon to the Applications alias, level with the icons.
let arrowY = flip(iconCenterY)
let startX = appX + 100
let endX = destX - 110
let stroke = NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.95, alpha: 0.55)

let shaft = NSBezierPath()
shaft.lineWidth = 5
shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: startX, y: arrowY))
shaft.line(to: NSPoint(x: endX - 16, y: arrowY))
stroke.setStroke()
shaft.stroke()

let head = NSBezierPath()
head.move(to: NSPoint(x: endX - 16, y: arrowY + 16))
head.line(to: NSPoint(x: endX, y: arrowY))
head.line(to: NSPoint(x: endX - 16, y: arrowY - 16))
head.lineWidth = 5
head.lineCapStyle = .round
head.lineJoinStyle = .round
stroke.setStroke()
head.stroke()

let caption = "Drag to Applications to install"
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1),
    .paragraphStyle: paragraph,
]
let captionRect = NSRect(x: 0, y: flip(340) - 8, width: width, height: 20)
(caption as NSString).draw(in: captionRect, withAttributes: attrs)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("render failed")
}
try! png.write(to: URL(fileURLWithPath: "assets/dmg-background.png"))
print("wrote assets/dmg-background.png")
