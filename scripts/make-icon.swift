// 用 CoreGraphics 绘制应用图标并导出 iconset / appiconset。
// 用法: swift scripts/make-icon.swift <输出目录>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon", isDirectory: true)

func draw(size: CGFloat) -> CGImage {
    let pixels = Int(size)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let s = size / 1024 // 以 1024 画布为基准缩放
    // macOS 图标网格：圆角方形占 824×824，居中。
    let inset = 100 * s
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.2237
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // 投影
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
    context.addPath(squircle)
    context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.9, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // 渐变背景
    context.saveGState()
    context.addPath(squircle)
    context.clip()
    let colors = [
        CGColor(red: 0.47, green: 0.68, blue: 1.0, alpha: 1),
        CGColor(red: 0.29, green: 0.42, blue: 0.98, alpha: 1),
        CGColor(red: 0.20, green: 0.24, blue: 0.80, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 0.55, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    // 顶部高光
    let highlight = CGGradient(colorsSpace: colorSpace, colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.28), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(highlight, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.midY), options: [])
    context.restoreGState()

    // 运动线（左侧三条圆头短线）
    context.saveGState()
    context.setLineCap(.round)
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    context.setLineWidth(40 * s)
    let lines: [(y: CGFloat, x0: CGFloat, x1: CGFloat)] = [(612, 232, 352), (512, 196, 372), (412, 232, 352)]
    for line in lines {
        context.move(to: CGPoint(x: line.x0 * s, y: line.y * s))
        context.addLine(to: CGPoint(x: line.x1 * s, y: line.y * s))
        context.strokePath()
    }
    context.restoreGState()

    // 光标箭头（经典 macOS 箭头形状，带轻微投影）
    let arrow = CGMutablePath()
    let unit: [(CGFloat, CGFloat)] = [(0, 0), (0, 0.80), (0.215, 0.615), (0.37, 0.985), (0.49, 0.93), (0.335, 0.565), (0.60, 0.565)]
    let arrowSize: CGFloat = 400 * s
    let origin = CGPoint(x: 450 * s, y: 300 * s)
    for (i, p) in unit.enumerated() {
        let point = CGPoint(x: origin.x + p.0 * arrowSize, y: origin.y + (1 - p.1) * arrowSize)
        if i == 0 { arrow.move(to: point) } else { arrow.addLine(to: point) }
    }
    arrow.closeSubpath()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: CGColor(red: 0, green: 0, blue: 0.2, alpha: 0.35))
    context.addPath(arrow)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()
    context.addPath(arrow)
    context.setStrokeColor(CGColor(red: 0.12, green: 0.18, blue: 0.55, alpha: 0.9))
    context.setLineWidth(18 * s)
    context.setLineJoin(.round)
    context.strokePath()

    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("无法创建 \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("写入失败 \(url.path)") }
}

let fm = FileManager.default
let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let appiconset = outputDirectory.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
try? fm.removeItem(at: iconset)
try? fm.removeItem(at: appiconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
try fm.createDirectory(at: appiconset, withIntermediateDirectories: true)

var contents: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixel = CGFloat(base * scale)
        let image = draw(size: pixel)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        write(image, to: iconset.appendingPathComponent(name))
        write(image, to: appiconset.appendingPathComponent(name))
        contents.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(base)x\(base)"])
    }
}
let json: [String: Any] = ["images": contents, "info": ["author": "xcode", "version": 1]]
let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
try data.write(to: appiconset.appendingPathComponent("Contents.json"))
write(draw(size: 1024), to: outputDirectory.appendingPathComponent("icon-1024.png"))
print("图标已生成: \(outputDirectory.path)")
