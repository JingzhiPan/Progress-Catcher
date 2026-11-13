// 把 SVG 畫成指定邊長的 PNG（保留透明）。這台機器沒有別的 SVG 轉圖工具，用系統自帶的 NSImage。
// 用法：swift scripts/icon/svg2png.swift <輸入.svg> <輸出.png> <寬，像素> [高，像素]
import AppKit

let args = CommandLine.arguments
guard args.count >= 4, let width = Int(args[3]) else {
    FileHandle.standardError.write(Data("usage: svg2png.swift in.svg out.png width [height]\n".utf8))
    exit(2)
}
guard let image = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write(Data("讀不了 \(args[1])\n".utf8))
    exit(1)
}
let aspect = image.size.height / max(image.size.width, 1)
let height = args.count >= 5 ? (Int(args[4]) ?? width) : Int((Double(width) * aspect).rounded())

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = NSSize(width: width, height: height)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
