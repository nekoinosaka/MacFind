// 生成 MacFind 应用图标:深色 squircle + 琥珀色放大镜(「探照灯」主题)。
// 用法:  swift Tools/make_icon.swift <输出.iconset 目录>
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func render(size: Int) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / 1024.0, y: CGFloat(size) / 1024.0)   // 统一在 1024 坐标系作画

    // macOS 图标网格:内容 824×824,四周留 100
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // 投影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 46,
                  color: NSColor.black.withAlphaComponent(0.40).cgColor)
    ctx.addPath(squircle)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 背景:深石墨渐变
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let bg = [CGColor(red: 0.17, green: 0.20, blue: 0.28, alpha: 1),
              CGColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 1)] as CFArray
    if let g = CGGradient(colorsSpace: cs, colors: bg, locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    // 顶部微弱反光
    let gloss = [CGColor(red: 1, green: 1, blue: 1, alpha: 0.10),
                 CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)] as CFArray
    if let g = CGGradient(colorsSpace: cs, colors: gloss, locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    ctx.restoreGState()

    // 放大镜
    let c = CGPoint(x: 468, y: 566)
    let r: CGFloat = 205
    let ringW: CGFloat = 74

    // 镜片玻璃(浅色 + 高光)
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: c.x - r + ringW/2, y: c.y - r + ringW/2,
                              width: (r - ringW/2) * 2, height: (r - ringW/2) * 2))
    ctx.clip()
    let glass = [CGColor(red: 0.65, green: 0.80, blue: 0.95, alpha: 0.16),
                 CGColor(red: 0.65, green: 0.80, blue: 0.95, alpha: 0.03)] as CFArray
    if let g = CGGradient(colorsSpace: cs, colors: glass, locations: [0, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: c.x - r, y: c.y + r),
                               end: CGPoint(x: c.x + r, y: c.y - r), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    ctx.restoreGState()

    // 手柄(先画,内端藏到镜环之下)+ 镜环,分别描边转填充
    let angle = -45.0 * Double.pi / 180.0
    let dir = CGPoint(x: CGFloat(cos(angle)), y: CGFloat(sin(angle)))

    let handle = CGMutablePath()
    handle.move(to: CGPoint(x: c.x + dir.x * (r - ringW * 1.2),
                            y: c.y + dir.y * (r - ringW * 1.2)))
    handle.addLine(to: CGPoint(x: c.x + dir.x * (r + 188),
                               y: c.y + dir.y * (r + 188)))
    let strokedHandle = handle.copy(strokingWithWidth: ringW, lineCap: .round,
                                    lineJoin: .round, miterLimit: 10)

    let ring = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
    let strokedRing = ring.copy(strokingWithWidth: ringW, lineCap: .round,
                                lineJoin: .round, miterLimit: 10)

    let amber = [CGColor(red: 1.00, green: 0.84, blue: 0.42, alpha: 1),
                 CGColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1)] as CFArray
    let amberGradient = CGGradient(colorsSpace: cs, colors: amber, locations: [0.15, 1.0])
    let gStart = CGPoint(x: 360, y: 780)
    let gEnd = CGPoint(x: 720, y: 300)

    // 投影:先填充实色(带阴影)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24,
                  color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(strokedHandle)
    ctx.addPath(strokedRing)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // 琥珀渐变:叠加在形状上
    ctx.saveGState()
    ctx.addPath(strokedHandle)
    ctx.addPath(strokedRing)
    ctx.clip()
    if let g = amberGradient {
        ctx.drawLinearGradient(g, start: gStart, end: gEnd, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    ctx.restoreGState()

    // 玻璃高光弧
    ctx.saveGState()
    ctx.setLineWidth(26)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
    ctx.addArc(center: c, radius: r - ringW/2 - 30,
               startAngle: CGFloat(118.0 * Double.pi / 180.0),
               endAngle: CGFloat(168.0 * Double.pi / 180.0), clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()
}

// ---- 主流程 ----
let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: make_icon.swift <out.iconset>\n".data(using: .utf8)!)
    exit(2)
}
let outDir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, px) in variants {
    guard let img = render(size: px) else { continue }
    let url = outDir.appendingPathComponent(name)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { continue }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(name) (\(px)px)")
}
