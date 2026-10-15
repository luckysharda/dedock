// Pixel measurement on screen captures (docs/evaluation.md §8 motion, §9.3 pixel check).
// CoreGraphics + ImageIO only. Captures on this Mac are 1x, so 1 px = 1 pt.
//
// Build: swiftc -O Scripts/measure-pixels.swift -o build/e2e/measure-pixels
//
//   measure-pixels rgba <png> x,y [x,y ...]
//       CSV x,y,r,g,b,a (0-255) at each point. Pixels are read in the image's own
//       colour space (no conversion), so values match what `screencapture` stored.
//   measure-pixels edge <png> row=<y> from=<left|right> [bg=r,g,b] [tol=24]
//   measure-pixels edge <png> col=<x> from=<top|bottom> [bg=r,g,b] [tol=24]
//       First pixel along the scanline that differs from the background by more than
//       `tol` in any channel. bg defaults to the first pixel of the scan. Prints the
//       coordinate, or -1 if none.
//   measure-pixels series <dir> row=<y>|col=<x> from=<side> [bg=r,g,b] [tol=24]
//       `edge` on every *.png in <dir> (sorted by name): CSV frame,file,pos. The
//       motion series for §8 (leading edge of the capsule per frame).
//   measure-pixels diff <a.png> <b.png> [tol=4]
//       Share of pixels where any channel differs by more than `tol`
//       (§9.3 material rule: <= 0.5 % at tol 4). Images must be the same size.
//   measure-pixels run <png> row=<y>|col=<x> from=<side> [bg=r,g,b] [tol=24]
//       Every run of non-background pixels along the scanline: CSV start,end,length.
//       Measures thickness, padding, tile size and gaps in one pass.

import CoreGraphics
import Foundation
import ImageIO

struct Bitmap {
    let width: Int, height: Int
    let data: [UInt8] // RGBA8, premultiplied last, row-major, top row first
    let colorSpaceName: String

    init(path: String) {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let src = CGImageSourceCreateWithURL(url, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail("cannot read image \(path)") }
        let w = img.width, h = img.height
        width = w
        height = h
        let space = (img.colorSpace?.model == .rgb ? img.colorSpace : nil) ?? CGColorSpace(name: CGColorSpace.sRGB)!
        colorSpaceName = (space.name as String?) ?? "unnamed"
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("no context") }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        data = buf
    }

    func px(_ x: Int, _ y: Int) -> [Int] {
        guard x >= 0, y >= 0, x < width, y < height else { fail("point \(x),\(y) outside \(width)x\(height)") }
        let i = (y * width + x) * 4
        return (0..<4).map { Int(data[i + $0]) }
    }
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("measure-pixels: \(msg)\n".data(using: .utf8)!)
    exit(2)
}

/// key=value options after the positional arguments.
func options(_ args: ArraySlice<String>) -> [String: String] {
    var o: [String: String] = [:]
    for a in args { let kv = a.split(separator: "=", maxSplits: 1); if kv.count == 2 { o[String(kv[0])] = String(kv[1]) } }
    return o
}

func rgb(_ s: String?) -> [Int]? {
    guard let s else { return nil }
    let v = s.split(separator: ",").compactMap { Int($0) }
    guard v.count == 3 else { fail("bg must be r,g,b") }
    return v
}

/// The points of one scanline in scan order.
func scan(_ b: Bitmap, _ o: [String: String]) -> [(Int, Int, Int)] { // (x, y, position along scan)
    guard let from = o["from"] else { fail("from=<left|right|top|bottom> required") }
    if let r = o["row"], let y = Int(r) {
        let xs = from == "right" ? Array((0..<b.width).reversed()) : Array(0..<b.width)
        guard from == "left" || from == "right" else { fail("row= scans need from=left|right") }
        return xs.map { ($0, y, $0) }
    }
    if let c = o["col"], let x = Int(c) {
        guard from == "top" || from == "bottom" else { fail("col= scans need from=top|bottom") }
        let ys = from == "bottom" ? Array((0..<b.height).reversed()) : Array(0..<b.height)
        return ys.map { (x, $0, $0) }
    }
    fail("row=<y> or col=<x> required")
}

func differs(_ p: [Int], _ bg: [Int], _ tol: Int) -> Bool { (0..<3).contains { abs(p[$0] - bg[$0]) > tol } }

func leadingEdge(_ b: Bitmap, _ o: [String: String]) -> Int {
    let line = scan(b, o), tol = Int(o["tol"] ?? "24") ?? 24
    let bg = rgb(o["bg"]) ?? Array(b.px(line[0].0, line[0].1).prefix(3))
    return line.first { differs(b.px($0.0, $0.1), bg, tol) }?.2 ?? -1
}

let args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else {
    print("usage: measure-pixels rgba|edge|series|diff|run ... (see header of Scripts/measure-pixels.swift)")
    exit(0)
}

switch cmd {
case "rgba":
    guard args.count >= 3 else { fail("rgba <png> x,y ...") }
    let b = Bitmap(path: args[1])
    print("x,y,r,g,b,a  # colourspace=\(b.colorSpaceName)")
    for pt in args[2...] {
        let v = pt.split(separator: ",").compactMap { Int($0) }
        guard v.count == 2 else { fail("bad point \(pt)") }
        print(([v[0], v[1]] + b.px(v[0], v[1])).map(String.init).joined(separator: ","))
    }

case "edge":
    guard args.count >= 3 else { fail("edge <png> row=|col= from= ...") }
    print(leadingEdge(Bitmap(path: args[1]), options(args[2...])))

case "series":
    guard args.count >= 3 else { fail("series <dir> row=|col= from= ...") }
    let o = options(args[2...])
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: args[1])) ?? [])
        .filter { $0.lowercased().hasSuffix(".png") }.sorted()
    guard !files.isEmpty else { fail("no png files in \(args[1])") }
    print("frame,file,pos")
    for (i, f) in files.enumerated() {
        print("\(i),\(f),\(leadingEdge(Bitmap(path: args[1] + "/" + f), o))")
    }

case "run":
    guard args.count >= 3 else { fail("run <png> row=|col= from= ...") }
    let b = Bitmap(path: args[1]), o = options(args[2...])
    let line = scan(b, o), tol = Int(o["tol"] ?? "24") ?? 24
    let bg = rgb(o["bg"]) ?? Array(b.px(line[0].0, line[0].1).prefix(3))
    print("start,end,length")
    var start: Int? = nil, last = 0
    for (x, y, pos) in line {
        let on = differs(b.px(x, y), bg, tol)
        if on, start == nil { start = pos }
        if !on, let s = start { print("\(s),\(last),\(abs(last - s) + 1)"); start = nil }
        last = pos
    }
    if let s = start { print("\(s),\(last),\(abs(last - s) + 1)") }

case "diff":
    guard args.count >= 3 else { fail("diff <a.png> <b.png> [tol=4]") }
    let a = Bitmap(path: args[1]), b = Bitmap(path: args[2])
    guard a.width == b.width, a.height == b.height else { fail("sizes differ: \(a.width)x\(a.height) vs \(b.width)x\(b.height)") }
    let tol = Int(options(args[3...])["tol"] ?? "4") ?? 4
    var n = 0
    for i in stride(from: 0, to: a.data.count, by: 4) where (0..<3).contains(where: { abs(Int(a.data[i + $0]) - Int(b.data[i + $0])) > tol }) { n += 1 }
    let pct = Double(n) / Double(a.width * a.height) * 100
    print(String(format: "differing_pixels=%d total=%d pct=%.4f tol=%d verdict=%@", n, a.width * a.height, pct, tol, pct <= 0.5 ? "PASS" : "FAIL"))

default:
    fail("unknown command \(cmd)")
}
