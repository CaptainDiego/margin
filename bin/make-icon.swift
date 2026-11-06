// Draws the app icon: a Plex Mono "#" on the dark page, with an orange caret.
import AppKit
let out = CommandLine.arguments[1], fontPath = CommandLine.arguments[2]
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: fontPath) as CFURL, .process, nil)
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
    NSColor(srgbRed: 0.063, green: 0.063, blue: 0.063, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225).fill()
    let font = NSFont(name: "IBMPlexMono-Bold", size: s * 0.46)!
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(srgbRed: 0.933, green: 0.933, blue: 0.933, alpha: 1)]
    let hash = NSAttributedString(string: "#", attributes: attrs)
    let size = hash.size()
    hash.draw(at: NSPoint(x: (s - size.width)/2, y: (s - size.height)/2 + s*0.01))
    NSColor(srgbRed: 0.949, green: 0.647, blue: 0.255, alpha: 1).setFill() // Theme.link (dark)
    NSRect(x: s*0.5 + size.width*0.42, y: s*0.33, width: max(1, s*0.035), height: s*0.34).fill()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
