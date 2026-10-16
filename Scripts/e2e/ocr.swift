// On-device text recognition (Vision) for E2E checks of text the app draws but hides from
// accessibility (H4: the hover label is AX-hidden; the tile's button carries name and state).
// Only ever run on a capture of the APP UNDER TEST's own window (screencapture -l <its window id>),
// never on the screen, so no other app's content is read.
//
// Build: swiftc -O Scripts/e2e/ocr.swift -o build/e2e/ocr
// Run:   build/e2e/ocr <image.png>
//        one JSON object per recognised line: {"text","x","y","w","h","iw","ih"}: the box in image
//        pixels, top-left origin; iw/ih: the image size (to map back to points).
//        build/e2e/ocr mean <image.png> <fx0> <fy0> <fx1> <fy1>
//        {"r","g","b","a"} (0…255): the mean colour of a region given as fractions of the image
//        (top-left origin), e.g. the Settings sidebar vs its content column (T37b)
//        build/e2e/ocr stats <image.png>
//        {"distinct","alpha_max","iw","ih"} over a pixel sample; exit 1 when the capture is blank
//        (fully transparent, or under 8 distinct colours), e.g. no Screen Recording for the host.

import AppKit
import Vision

func fail(_ m: String) -> Never { FileHandle.standardError.write("ocr: \(m)\n".data(using: .utf8)!); exit(2) }

let args = Array(CommandLine.arguments.dropFirst())
let statsMode = args.first == "stats", meanMode = args.first == "mean"
guard let path = (statsMode || meanMode) ? args.dropFirst().first : args.first else { fail("usage: ocr [stats|mean] <image.png> [fx0 fy0 fx1 fy1]") }
guard let img = NSImage(contentsOfFile: path),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fail("cannot read \(path)") }
let (iw, ih) = (Double(cg.width), Double(cg.height))

if meanMode {
    let f = args.dropFirst(2).compactMap(Double.init)
    guard f.count == 4, let rep = NSBitmapImageRep(cgImage: cg) as NSBitmapImageRep? else { fail("mean <png> fx0 fy0 fx1 fy1") }
    let (x0, y0) = (Int(f[0] * iw), Int(f[1] * ih)), (x1, y1) = (Int(f[2] * iw), Int(f[3] * ih))
    var sum = [0.0, 0.0, 0.0, 0.0], n = 0.0
    for y in stride(from: max(0, y0), to: min(cg.height, y1), by: 2) {
        for x in stride(from: max(0, x0), to: min(cg.width, x1), by: 2) {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            sum[0] += c.redComponent; sum[1] += c.greenComponent; sum[2] += c.blueComponent; sum[3] += c.alphaComponent; n += 1
        }
    }
    guard n > 0 else { fail("empty region") }
    let d: [String: Any] = ["r": sum[0] / n * 255, "g": sum[1] / n * 255, "b": sum[2] / n * 255, "a": sum[3] / n * 255]
    print(String(data: try! JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]), encoding: .utf8)!)
    exit(0)
}
if statsMode {
    guard let rep = NSBitmapImageRep(cgImage: cg) as NSBitmapImageRep? else { fail("no bitmap") }
    var seen = Set<UInt32>(), alphaMax: CGFloat = 0
    let step = max(1, Int((Double(cg.width * cg.height) / 40_000).squareRoot()))
    for y in stride(from: 0, to: cg.height, by: step) {
        for x in stride(from: 0, to: cg.width, by: step) {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            alphaMax = max(alphaMax, c.alphaComponent)
            let q = { (v: CGFloat) in UInt32(max(0, min(255, (v * 255).rounded()))) }
            seen.insert(q(c.redComponent) << 24 | q(c.greenComponent) << 16 | q(c.blueComponent) << 8 | q(c.alphaComponent))
        }
    }
    let d: [String: Any] = ["distinct": seen.count, "alpha_max": Double(alphaMax), "iw": iw, "ih": ih]
    print(String(data: try! JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]), encoding: .utf8)!)
    exit(alphaMax > 0 && seen.count >= 8 ? 0 : 1)
}

let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.usesLanguageCorrection = false
do { try VNImageRequestHandler(cgImage: cg).perform([req]) } catch { fail("vision: \(error)") }

for o in req.results ?? [] {
    guard let c = o.topCandidates(1).first else { continue }
    let b = o.boundingBox  // normalised, bottom-left origin
    let d: [String: Any] = ["text": c.string, "x": b.minX * iw, "y": (1 - b.maxY) * ih, "w": b.width * iw, "h": b.height * ih,
                            "iw": iw, "ih": ih]
    let data = try! JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}
