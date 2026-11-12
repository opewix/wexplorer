// Рисует значок программы в .iconset для iconutil: плитка — сама папка, сверху ушко и листы,
// снизу передняя стенка. См. scripts/bundle.sh.
import AppKit

// Плитка по сетке значков macOS: холст 1024, отступ 100, сторона 824, радиус 185,4. Только такую форму
// macOS 26 показывает во весь скруглённый квадрат; иную сажает на серую подложку и уменьшает.
let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let tile = NSBezierPath(roundedRect: tileRect, xRadius: 185.4, yRadius: 185.4)

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
func gradient(_ path: NSBezierPath, _ top: NSColor, _ bottom: NSColor) {
    NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: -90)
}
func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}
func withShadow(blur: CGFloat, dy: CGFloat, alpha: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow()
    s.shadowBlurRadius = blur
    s.shadowOffset = NSSize(width: 0, height: -dy)
    s.shadowColor = NSColor(white: 0, alpha: alpha)
    s.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon() {
    gradient(tile, rgb(236, 172, 44), rgb(206, 138, 22))
    // Задняя стенка с ушком
    rgb(200, 132, 20).setFill()
    NSRect(x: 100, y: 840, width: 824, height: 84).fill()
    let back = NSBezierPath()
    back.move(to: NSPoint(x: 100, y: 760))
    back.line(to: NSPoint(x: 100, y: 924))
    back.line(to: NSPoint(x: 470, y: 924))
    back.line(to: NSPoint(x: 540, y: 840))
    back.line(to: NSPoint(x: 924, y: 840))
    back.line(to: NSPoint(x: 924, y: 760))
    back.close()
    gradient(back, rgb(244, 182, 52), rgb(226, 160, 36))
    // Лист со строчками
    NSColor.white.setFill()
    rounded(170, 560, 684, 260, 16).fill()
    rgb(225, 232, 240).setFill()
    for i in 0..<3 {
        NSRect(x: 220, y: 760 - CGFloat(i) * 60, width: 420 - CGFloat(i) * 80, height: 22).fill()
    }
    // Передняя стенка
    let front = NSBezierPath(rect: NSRect(x: 100, y: 100, width: 824, height: 520))
    withShadow(blur: 30, dy: -6, alpha: 0.22) { rgb(255, 214, 90).setFill(); front.fill() }
    gradient(front, rgb(255, 226, 118), rgb(246, 188, 48))
    rgb(255, 244, 190).setFill()
    NSRect(x: 100, y: 606, width: 824, height: 14).fill()
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = base * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let scaleTo = NSAffineTransform()
        scaleTo.scale(by: CGFloat(pixels) / 1024)
        scaleTo.concat()
        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        drawIcon()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    }
}

