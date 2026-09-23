// Helper for docs/probes/demo-pixels/compare.sh; see its header.
//
// Two modes over the raw BGRA dumps `ZZDemoPixels.swift` writes:
//
//   rawdiff a.bgra b.bgra [w]  count differing PIXELS (4 bytes each) and the
//                              bounding box of the difference (rows w wide;
//                              square when omitted)
//   rawdiff --distinct a.bgra  count distinct 32-bit pixel values in one image
//
// The distinct count is the control that says an image is not blank: record
// §25 §7.6 pins `default-light-f0` at 544 and `chrome-legacy` at 216. A
// harness that wrote a uniform field would read 1 and every pairwise
// comparison would still read 0.

import Foundation

func load(_ p: String) -> [UInt8] {
    guard let d = FileManager.default.contents(atPath: p) else {
        FileHandle.standardError.write("missing \(p)\n".data(using: .utf8)!); exit(2)
    }
    return [UInt8](d)
}

let args = Array(CommandLine.arguments.dropFirst())

if args.first == "--distinct" {
    let a = load(args[1])
    var seen = Set<UInt32>()
    for i in stride(from: 0, to: a.count, by: 4) {
        seen.insert(UInt32(a[i]) | UInt32(a[i+1]) << 8 | UInt32(a[i+2]) << 16 | UInt32(a[i+3]) << 24)
    }
    print("distinct=\(seen.count) pixels=\(a.count / 4)")
    exit(0)
}

let a = load(args[0]), b = load(args[1])
guard a.count == b.count else { print("SIZE \(a.count) vs \(b.count)"); exit(1) }
// Square unless a third argument names the row width: stage 6b's two 920x560
// production-size images (`LR-DO` item 3) pass `920`.
let side = args.count > 2 ? Int(args[2])! : Int(Double(a.count / 4).squareRoot().rounded())
var n = 0, minx = Int.max, miny = Int.max, maxx = -1, maxy = -1
for i in stride(from: 0, to: a.count, by: 4) where
    a[i] != b[i] || a[i+1] != b[i+1] || a[i+2] != b[i+2] || a[i+3] != b[i+3] {
    let p = i / 4, x = p % side, y = p / side
    n += 1
    minx = min(minx, x); miny = min(miny, y); maxx = max(maxx, x); maxy = max(maxy, y)
}
print("differing=\(n)" + (n > 0 ? " bbox=(\(minx),\(miny))-(\(maxx),\(maxy))" : ""))
