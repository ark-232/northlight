// Renders Northlight's tvOS brand assets, the layered app icons and the Top Shelf
// images, into an asset catalog. Usage: swift Tools/render-icon.swift <Assets.xcassets>
import AppKit
import CoreImage

enum Layer: String, CaseIterable { case back = "Back", middle = "Middle", front = "Front" }
enum Part { case sky, aurora, star, ridge }

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// A fixed value in 0..<1 for each n, so every render draws the same stars.
func hash(_ n: Int) -> CGFloat {
    var x = UInt64(truncatingIfNeeded: n) &* 0x9E37_79B9_7F4A_7C15
    x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
    x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
    return CGFloat((x ^ (x >> 31)) >> 11) / CGFloat(1 << 53)
}

func canvas(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Positions are in units of the canvas height, with y running down, so a wider
/// canvas shows more of the same scene.
func draw(_ part: Part, width: CGFloat, height: CGFloat, scale: CGFloat) -> CGImage {
    let h = Int(height * scale)
    let ctx = canvas(Int(width * scale), h)
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: CGFloat(h), y: -CGFloat(h))
    let span = width / height
    let px = 1 / CGFloat(h)

    switch part {
    case .sky:
        let sky = CGGradient(colorsSpace: nil, colors: [rgb(0x03070D), rgb(0x0A1424), rgb(0x18324E)] as CFArray,
                             locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: 1), options: [])
        for i in 0..<Int(span * 90) {
            let x = hash(i * 3) * span, y = hash(i * 3 + 1) * 0.62
            let r = (0.6 + 1.1 * hash(i * 3 + 2)) * 0.0022
            ctx.setFillColor(rgb(0xDCE8FF, 0.25 + 0.6 * hash(i * 7 + 5)))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }

    case .aurora:
        // Curtains of vertical rays: brightest just above the foot, fading upward
        // into violet and quickly below it.
        let curtains: [(foot: CGFloat, sway: CGFloat, waves: CGFloat, phase: CGFloat, tall: CGFloat, glow: UInt32, crown: UInt32, strength: CGFloat)] = [
            (0.50, 0.07, 0.55, 0.4, 0.42, 0x4ADE80, 0x7C6CF0, 0.85),
            (0.60, 0.05, 0.85, 2.1, 0.30, 0x22D3EE, 0x4ADE80, 0.6),
            (0.43, 0.04, 1.30, 4.0, 0.22, 0x86EFAC, 0xA78BFA, 0.6),
        ]
        for (n, c) in curtains.enumerated() {
            let k = CGFloat(n)
            var x: CGFloat = 0
            while x < span {
                let streak = 0.55 + 0.25 * sin(x * 61 + k) + 0.2 * sin(x * 143 + 2 * k)
                let foot = c.foot + c.sway * sin(2 * .pi * c.waves * x + c.phase)
                let top = foot - c.tall * (0.75 + 0.25 * sin(x * 23 + k * 3))
                let edge = min(1, x / 0.25, (span - x) / 0.25)
                let alpha = max(0, streak) * edge * c.strength
                let below: CGFloat = 0.035
                let footAt = below / (foot + below - top)
                let ray = CGGradient(colorsSpace: nil,
                                     colors: [rgb(c.glow, 0), rgb(c.glow, alpha), rgb(c.glow, alpha * 0.45), rgb(c.crown, 0)] as CFArray,
                                     locations: [0, footAt, footAt + 0.3, 1])!
                ctx.saveGState()
                ctx.clip(to: CGRect(x: x, y: top, width: px * 1.5, height: foot + below - top))
                ctx.drawLinearGradient(ray, start: CGPoint(x: 0, y: foot + below), end: CGPoint(x: 0, y: top), options: [])
                ctx.restoreGState()
                x += px
            }
        }

    case .star:
        let star = CGPoint(x: span * 0.70, y: 0.20)
        let glow = CGGradient(colorsSpace: nil, colors: [rgb(0xFFFFFF, 0.9), rgb(0xBFE9FF, 0.25), rgb(0xBFE9FF, 0)] as CFArray,
                              locations: [0, 0.25, 1])!
        ctx.drawRadialGradient(glow, startCenter: star, startRadius: 0, endCenter: star, endRadius: 0.06, options: [])
        // Two thin diamonds, one tall and one wide.
        ctx.setFillColor(rgb(0xFFFFFF))
        for (rx, ry) in [(0.006, 0.075), (0.045, 0.006)] as [(CGFloat, CGFloat)] {
            ctx.move(to: CGPoint(x: star.x, y: star.y - ry))
            ctx.addLine(to: CGPoint(x: star.x + rx, y: star.y))
            ctx.addLine(to: CGPoint(x: star.x, y: star.y + ry))
            ctx.addLine(to: CGPoint(x: star.x - rx, y: star.y))
            ctx.closePath()
            ctx.fillPath()
        }

    case .ridge:
        // Sharp peaks, repeating every 1.7 heights on wide canvases.
        let peaks: [(at: CGFloat, rise: CGFloat, slope: CGFloat)] = [
            (0.10, 0.20, 1.4), (0.38, 0.30, 1.1), (0.55, 0.22, 1.6), (0.86, 0.34, 1.0),
            (1.08, 0.24, 1.5), (1.30, 0.28, 1.2), (1.52, 0.18, 1.7),
        ]
        func ridge(_ x: CGFloat) -> CGFloat {
            var lift: CGFloat = 0
            for k in -1...Int(span / 1.7) + 1 {
                for p in peaks { lift = max(lift, p.rise - abs(x - (p.at + CGFloat(k) * 1.7)) * p.slope) }
            }
            return 0.92 - lift * 0.8 - 0.006 * sin(x * 90)
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 1))
        var x: CGFloat = 0
        while x <= span + px {
            path.addLine(to: CGPoint(x: x, y: ridge(x)))
            x += px * 2
        }
        path.addLine(to: CGPoint(x: span, y: 1))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(rgb(0x04070C))
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(rgb(0x2B4A6B, 0.7))
        ctx.setLineWidth(px * 1.2 * scale)
        ctx.strokePath()
    }
    return ctx.makeImage()!
}

func stacked(_ images: [CGImage]) -> CGImage {
    let ctx = canvas(images[0].width, images[0].height)
    for image in images { ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)) }
    return ctx.makeImage()!
}

func render(_ layer: Layer, _ size: CGSize, _ scale: CGFloat) -> CGImage {
    func part(_ p: Part) -> CGImage { draw(p, width: size.width, height: size.height, scale: scale) }
    switch layer {
    case .back: return part(.sky)
    case .middle:
        let aurora = CIImage(cgImage: part(.aurora))
        let soft = aurora.clampedToExtent().applyingGaussianBlur(sigma: size.height * scale * 0.004).cropped(to: aurora.extent)
        return stacked([CIContext().createCGImage(soft, from: aurora.extent)!, part(.star)])
    case .front: return part(.ridge)
    }
}

func write(_ image: CGImage, to url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let rep = NSBitmapImageRep(cgImage: image)
    let data = url.pathExtension == "jpg"
        ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])!
        : rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

func json(_ object: [String: Any], to url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}

let info: [String: Any] = ["author": "xcode", "version": 1]
let brand = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("App Icon & Top Shelf Image.brandassets")

for (name, size, scales) in [("App Icon", CGSize(width: 400, height: 240), [1, 2]),
                             ("App Icon - App Store", CGSize(width: 1280, height: 768), [1])] as [(String, CGSize, [CGFloat])] {
    let stack = brand.appendingPathComponent("\(name).imagestack")
    json(["info": info, "layers": Layer.allCases.reversed().map { ["filename": "\($0.rawValue).imagestacklayer"] }],
         to: stack.appendingPathComponent("Contents.json"))
    for layer in Layer.allCases {
        let set = stack.appendingPathComponent("\(layer.rawValue).imagestacklayer")
        json(["info": info], to: set.appendingPathComponent("Contents.json"))
        let images = scales.map { scale -> [String: Any] in
            let file = layer.rawValue.lowercased() + (scale == 1 ? "" : "@\(Int(scale))x") + ".png"
            write(render(layer, size, scale), to: set.appendingPathComponent("Content.imageset/\(file)"))
            return ["filename": file, "idiom": "tv", "scale": "\(Int(scale))x"]
        }
        json(["images": images, "info": info], to: set.appendingPathComponent("Content.imageset/Contents.json"))
    }
}

// Top Shelf images are opaque, so JPEG holds them at a tenth of PNG's size.
for (name, size) in [("Top Shelf Image", CGSize(width: 1920, height: 720)),
                     ("Top Shelf Image Wide", CGSize(width: 2320, height: 720))] {
    let set = brand.appendingPathComponent("\(name).imageset")
    let images = [1, 2].map { (scale: CGFloat) -> [String: Any] in
        let file = name.lowercased().replacingOccurrences(of: " ", with: "-") + (scale == 1 ? "" : "@2x") + ".jpg"
        write(stacked(Layer.allCases.map { render($0, size, scale) }), to: set.appendingPathComponent(file))
        return ["filename": file, "idiom": "tv", "scale": "\(Int(scale))x"]
    }
    json(["images": images, "info": info], to: set.appendingPathComponent("Contents.json"))
}

json(["assets": [
    ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
    ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
    ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
    ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
], "info": info], to: brand.appendingPathComponent("Contents.json"))
