import Foundation
@testable import MetalUI
import MetalUITesting
import Testing

@Test @MainActor func ctMeasure() async throws {
    let pair = try ctPair()
    var rows: [String] = []
    var req = 0, pre = 0, redos = 0, back = 0, grafts = 0
    let n = 40
    var traced: [String] = []
    for step in 0..<n {
        var frames: [FrameWork] = []
        let lines = collectTrace { }
        _ = lines
        RetainedTrace.sink = { traced.append($0) }
        frames = await ctStep(pair)
        RetainedTrace.sink = nil
        let f = frames.reduce(FrameWork(), +)
        req += f.elementRequests; pre += f.elementPrepaints; redos += f.retainedRedos; back += f.retainedBackoffFrames; grafts += f.retainedGrafts
        rows.append("\(step):r\(f.elementRequests)/p\(f.elementPrepaints)/x\(f.retainedRedos)/b\(f.retainedBackoffFrames)/g\(f.retainedGrafts)")
        try pair.compare("step \(step)")
    }
    print("MEASURE mean requests \(Double(req) / Double(n)) prepaints \(Double(pre) / Double(n)) redos \(redos) backoffFrames \(back) grafts \(grafts)")
    print("MEASURE", rows.joined(separator: " "))
    var counts: [String: Int] = [:]
    for l in traced { counts[String(l.replacingOccurrences(of: #"positional\(\d+\)|named\([^)]*\)\)?|/+"#, with: "", options: .regularExpression).prefix(150)), default: 0] += 1 }
    for (k, v) in counts.sorted(by: { $0.value > $1.value }).prefix(12) { print("MEASURE T", v, k) }
}
