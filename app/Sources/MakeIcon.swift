import Cocoa

// Рисует иконку приложения и раскладывает ее в .iconset для iconutil.
// Запуск: makeicon <папка.iconset>

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func drawIcon(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(pixels)

    // фон: фиолетово-розовый градиент в скругленном квадрате с полями как у системных иконок
    let inset = s * 0.06
    let bg = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let bgPath = NSBezierPath(roundedRect: bg, xRadius: s * 0.205, yRadius: s * 0.205)
    ctx.saveGState()
    bgPath.addClip()
    let colors = [rgb(124, 58, 237).cgColor, rgb(219, 39, 119).cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: bg.minX, y: bg.maxY),
                           end: CGPoint(x: bg.maxX, y: bg.minY), options: [])
    ctx.restoreGState()

    // карточка-скриншот с мягкой тенью
    let cw = bg.width * 0.64, ch = bg.height * 0.50
    let card = CGRect(x: bg.midX - cw / 2, y: bg.midY - ch / 2 - s * 0.015, width: cw, height: ch)
    let cardR = s * 0.045
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.035), blur: s * 0.09,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: card, xRadius: cardR, yRadius: cardR).fill()
    ctx.restoreGState()

    ctx.saveGState()
    NSBezierPath(roundedRect: card, xRadius: cardR, yRadius: cardR).addClip()

    // панель мокапа со светофором
    let barH = ch * 0.2
    rgb(241, 243, 245).setFill()
    NSBezierPath(rect: CGRect(x: card.minX, y: card.maxY - barH, width: cw, height: barH)).fill()
    let dotR = barH * 0.22
    let dots = [rgb(255, 95, 87), rgb(254, 188, 46), rgb(40, 200, 64)]
    for (i, col) in dots.enumerated() {
        col.setFill()
        let x = card.minX + barH * 0.45 + CGFloat(i) * dotR * 3.1
        NSBezierPath(ovalIn: CGRect(x: x, y: card.maxY - barH / 2 - dotR, width: dotR * 2, height: dotR * 2)).fill()
    }

    // содержимое: фиолетовый заголовок и серые строки
    let pad = cw * 0.09
    let contentTop = card.maxY - barH - pad
    rgb(124, 58, 237).setFill()
    NSBezierPath(roundedRect: CGRect(x: card.minX + pad, y: contentTop - ch * 0.17, width: cw - pad * 2, height: ch * 0.17),
                 xRadius: s * 0.012, yRadius: s * 0.012).fill()
    rgb(226, 232, 240).setFill()
    var y = contentTop - ch * 0.17 - pad * 0.8
    for w in [0.85, 0.65, 0.75] {
        let h = ch * 0.09
        y -= h
        NSBezierPath(roundedRect: CGRect(x: card.minX + pad, y: y, width: (cw - pad * 2) * w, height: h),
                     xRadius: s * 0.01, yRadius: s * 0.01).fill()
        y -= pad * 0.5
    }
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, px) in sizes {
    let data = drawIcon(pixels: px)
    try! data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
print("Иконка готова: \(outDir)")
