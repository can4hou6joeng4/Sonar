import AppKit

let width: CGFloat = 660
let height: CGFloat = 400
let scale: CGFloat = 2.0

let pixelWidth = Int(width * scale)
let pixelHeight = Int(height * scale)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelWidth,
    pixelsHigh: pixelHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Failed to create NSBitmapImageRep")
}
rep.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("Failed to create NSGraphicsContext")
}
NSGraphicsContext.current = context
let cgContext = context.cgContext

// 1. Background gradient (Obsidian dark theme matching Sonar)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bgColors = [
    NSColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0).cgColor,
    NSColor(red: 0.12, green: 0.14, blue: 0.20, alpha: 1.0).cgColor
] as CFArray
let bgLocations: [CGFloat] = [0.0, 1.0]
if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
    cgContext.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: width / 2, y: height),
        end: CGPoint(x: width / 2, y: 0),
        options: []
    )
}

// 2. Subtle decorative glow behind icons
func drawGlow(center: CGPoint, radius: CGFloat, color: NSColor) {
    cgContext.saveGState()
    let glowColors = [
        color.withAlphaComponent(0.22).cgColor,
        color.withAlphaComponent(0.0).cgColor
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        cgContext.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: []
        )
    }
    cgContext.restoreGState()
}

// In Cocoa NSGraphicsContext, (0,0) is bottom-left, whereas Finder icon coordinates are top-left!
// Finder icon centers: X=175, Y=195 from top => Cocoa Y = 400 - 195 = 205
let iconLeft = CGPoint(x: 175, y: 205)
let iconRight = CGPoint(x: 485, y: 205)

drawGlow(center: iconLeft, radius: 110, color: NSColor(red: 0.35, green: 0.55, blue: 0.95, alpha: 1.0))
drawGlow(center: iconRight, radius: 110, color: NSColor(red: 0.20, green: 0.80, blue: 0.60, alpha: 1.0))

// 3. Icon drop target placeholders (dashed rounded rects)
func drawTargetBox(center: CGPoint) {
    let boxSize: CGFloat = 138
    let rect = CGRect(x: center.x - boxSize/2, y: center.y - boxSize/2, width: boxSize, height: boxSize)
    let path = NSBezierPath(roundedRect: rect, xRadius: 28, yRadius: 28)
    path.lineWidth = 1.5
    let pattern: [CGFloat] = [6, 4]
    path.setLineDash(pattern, count: 2, phase: 0)
    NSColor.white.withAlphaComponent(0.20).setStroke()
    path.stroke()

    // Inner subtle fill
    NSColor.white.withAlphaComponent(0.04).setFill()
    path.fill()
}

drawTargetBox(center: iconLeft)
drawTargetBox(center: iconRight)

// 4. Center Arrow & instruction
// Arrow path from X=270 to X=390 at Y=205
cgContext.saveGState()
let arrowY: CGFloat = 205
let arrowPath = NSBezierPath()
arrowPath.move(to: NSPoint(x: 270, y: arrowY))
arrowPath.line(to: NSPoint(x: 372, y: arrowY))
arrowPath.lineWidth = 3.0
let arrowDash: [CGFloat] = [8, 4]
arrowPath.setLineDash(arrowDash, count: 2, phase: 0)
NSColor(white: 1.0, alpha: 0.50).setStroke()
arrowPath.stroke()

// Arrow Head
let headPath = NSBezierPath()
headPath.move(to: NSPoint(x: 368, y: arrowY + 9))
headPath.line(to: NSPoint(x: 390, y: arrowY))
headPath.line(to: NSPoint(x: 368, y: arrowY - 9))
headPath.close()
NSColor(white: 1.0, alpha: 0.80).setFill()
headPath.fill()
cgContext.restoreGState()

// "拖移安装" / "Drag to Install" Pill Tag
let tagText = "拖移以完成安装"
let tagFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
let tagAttrs: [NSAttributedString.Key: Any] = [
    .font: tagFont,
    .foregroundColor: NSColor.white.withAlphaComponent(0.90)
]
let tagSize = (tagText as NSString).size(withAttributes: tagAttrs)
let tagRect = CGRect(x: 330 - (tagSize.width + 24) / 2, y: arrowY + 24, width: tagSize.width + 24, height: 26)
let tagBg = NSBezierPath(roundedRect: tagRect, xRadius: 13, yRadius: 13)
NSColor.white.withAlphaComponent(0.14).setFill()
tagBg.fill()
let tagBorder = NSBezierPath(roundedRect: tagRect, xRadius: 13, yRadius: 13)
tagBorder.lineWidth = 1.0
NSColor.white.withAlphaComponent(0.28).setStroke()
tagBorder.stroke()
(tagText as NSString).draw(at: NSPoint(x: tagRect.midX - tagSize.width / 2, y: tagRect.midY - tagSize.height / 2 + 1), withAttributes: tagAttrs)

// 5. Header Title and Subtitle (at top: Cocoa Y = 320 to 370)
let titleParagraph = NSMutableParagraphStyle()
titleParagraph.alignment = .center

let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 26, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: titleParagraph
]
let titleStr = "Sonar for Mac"
(titleStr as NSString).draw(in: CGRect(x: 0, y: 335, width: width, height: 35), withAttributes: titleAttrs)

let subAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor.white.withAlphaComponent(0.65),
    .paragraphStyle: titleParagraph
]
let subStr = "轻量优雅的刘海与状态栏音乐控制器 · 支持本地曲库与在线流媒体"
(subStr as NSString).draw(in: CGRect(x: 0, y: 312, width: width, height: 22), withAttributes: subAttrs)

// 6. Bottom footer hint (Cocoa Y = 25 to 55)
let footAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 11, weight: .regular),
    .foregroundColor: NSColor.white.withAlphaComponent(0.40),
    .paragraphStyle: titleParagraph
]
let footStr = "如首次启动提示安全拦截，请在系统设置「隐私与安全性」中点击允许，或在终端执行 xattr -cr /Applications/SonarMac.app"
(footStr as NSString).draw(in: CGRect(x: 20, y: 32, width: width - 40, height: 20), withAttributes: footAttrs)

NSGraphicsContext.restoreGraphicsState()

// Save to destination
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/dmg_background.png"
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to convert image to PNG")
}

try pngData.write(to: URL(fileURLWithPath: outputPath))
print("Successfully generated DMG background at: \(outputPath)")
