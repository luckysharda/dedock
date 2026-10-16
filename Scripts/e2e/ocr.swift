// On-device text recognition (Vision) for E2E checks of text the app draws but hides from
// accessibility (H4: the hover label is AX-hidden; the tile's button carries name and state).
// Only ever run on a capture of the APP UNDER TEST's own window (screencapture -l <its window id>),
// never on the screen, so no other app's content is read.
//
// Build: swiftc -O Scripts/e2e/ocr.swift -o build/e2e/ocr
// Run:   build/e2e/ocr <image.png>
//        one JSON object per recognised line: {"text","x","y","w","h","iw","ih"}: the box in image
//        pixels, top-left origin; iw/ih: the image size (to map back to points).

import AppKit
import Vision

func fail(_ m: String) -> Never { FileHandle.standardError.write("ocr: \(m)\n".data(using: .utf8)!); exit(2) }

let args = CommandLine.arguments.dropFirst()
guard let path = args.first else { fail("usage: ocr <image.png>") }
guard let img = NSImage(contentsOfFile: path),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fail("cannot read \(path)") }
let (iw, ih) = (Double(cg.width), Double(cg.height))

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
