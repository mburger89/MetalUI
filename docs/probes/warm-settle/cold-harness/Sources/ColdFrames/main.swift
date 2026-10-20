import Foundation
import MetalUI
import MetalUITesting

// C14-e (b): the bracket window's first frames, timed. A fresh window per round (BracketFixture.swift is copied in beside this
// file by cold-profile.sh), thread-CPU and wall time of each of the first six frames, medians over the rounds, beside the counters
// the attribution reads. Only fields present at 6273e3a4 are read, so the same source builds at both commits.
// Output: `scenario<TAB>metric<TAB>value`. Dated measurements, never pins.
//   frame 0 = TestWindow.init (it draws the window's first frame), frames 1-2 = unchanged redraws (the records are made on
//   frame 0 and hit on frame 1), frames 3-5 = orbit frames (the viewport token bumped, nothing in the panels changing).

func now() -> Double {
    var t = timespec(); clock_gettime(CLOCK_MONOTONIC, &t)
    return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1e6
}
func cpuNow() -> Double {
    var t = timespec(); clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
    return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1e6
}
func median(_ xs: [Double]) -> Double { let s = xs.sorted(); return s[s.count / 2] }
func report(_ scenario: String, _ metric: String, _ value: String) { print("\(scenario)\t\(metric)\t\(value)") }
func ms(_ v: Double) -> String { String(format: "%.3f", v) }

@MainActor func coldScenario(arm: BracketArm, name: String, rounds: Int) throws {
    var wall = [[Double]](repeating: [], count: 6), cpu = [[Double]](repeating: [], count: 6)
    var work = [FrameWork](repeating: FrameWork(), count: 6)
    for _ in 0..<rounds {
        let model = BracketModel(), viewport = BracketViewport()
        let t0 = now(), c0 = cpuNow()
        let w = try TestWindow(size: bracketWindowSize, colorScheme: .dark, scaleFactor: 2) {
            bracketRoot(arm: arm, model: model, viewport: viewport)
        }
        wall[0].append(now() - t0); cpu[0].append(cpuNow() - c0)
        work[0] = w.frameWork.first ?? w.lastFrameWork
        for frame in 1..<6 {
            if frame >= 3 { viewport.token += 1 }
            w.window.setNeedsRedraw()
            let t = now(), c = cpuNow()
            w.tick()
            wall[frame].append(now() - t); cpu[frame].append(cpuNow() - c)
            work[frame] = w.lastFrameWork
        }
    }
    var load = [Double](repeating: 0, count: 3); getloadavg(&load, 3)
    report(name, "load_average", String(format: "%.1f %.1f %.1f", load[0], load[1], load[2]))
    for frame in 0..<6 {
        report(name, "frame\(frame)_cpu_ms_median", ms(median(cpu[frame])))
        report(name, "frame\(frame)_cpu_ms_min", ms(cpu[frame].min()!))
        report(name, "frame\(frame)_wall_ms_median", ms(median(wall[frame])))
        report(name, "frame\(frame)_work", counters(work[frame]))
    }
}

let args = CommandLine.arguments.dropFirst()
let rounds = Int(args.first(where: { Int($0) != nil }) ?? "") ?? 12
MainActor.assumeIsolated {
    do {
        try coldScenario(arm: .panels, name: "cold_panels", rounds: rounds)
        try coldScenario(arm: .value, name: "cold_value", rounds: rounds)
    } catch { print("error: \(error)") }
}
