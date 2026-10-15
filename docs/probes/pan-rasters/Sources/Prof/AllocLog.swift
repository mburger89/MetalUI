import Foundation
// MARK: malloc_logger allocation profiler (PROF_ALLOC=1): counts every malloc on the main thread and samples stacks.
typealias MallocLogger = @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void
nonisolated(unsafe) var gAllocs = 0, gBytes = 0, gFrees = 0, gSampleEvery = Int(ProcessInfo.processInfo.environment["PROF_ALLOC"] ?? "") ?? 8, gSampled = 0
nonisolated(unsafe) var gInLogger = false
nonisolated(unsafe) var gStacks: UnsafeMutablePointer<UInt>? = nil
nonisolated(unsafe) var gSizes: UnsafeMutablePointer<UInt>? = nil
let gDepth = 40, gCap = 400_000
func installMallocLogger() {
    gStacks = .allocate(capacity: gDepth * gCap); gSizes = .allocate(capacity: gCap)
    let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger")!
    let p = sym.assumingMemoryBound(to: Optional<MallocLogger>.self)
    p.pointee = { type, a1, a2, a3, result, skip in
        if gInLogger { return }
        gInLogger = true; defer { gInLogger = false }
        if type & 2 != 0 {   // allocate
            // arg2 = size for malloc (zone,size,0,result) when HAS_ZONE
            let size = (type & 8 != 0) ? a2 : a1
            gAllocs += 1; gBytes += Int(size)
            if gAllocs % gSampleEvery == 0 && gSampled < gCap {
                var buf = [UnsafeMutableRawPointer?](repeating: nil, count: gDepth)
                let n = backtrace(&buf, Int32(gDepth))
                let base = gStacks! + gSampled * gDepth
                for i in 0..<gDepth { base[i] = i < Int(n) ? UInt(bitPattern: buf[i]) : 0 }
                gSizes![gSampled] = size
                gSampled += 1
            }
        }
        if type & 4 != 0 { gFrees += 1 }
    }
}
func dumpAllocStacks(path: String) {
    var ids: [UInt: Int] = [:]; var names: [String] = []
    func id(_ a: UInt) -> Int {
        if let s = ids[a] { return s }
        var info = Dl_info()
        let s: String
        if dladdr(UnsafeRawPointer(bitPattern: a), &info) != 0, let sn = info.dli_sname { s = String(cString: sn) } else { s = "?" }
        // intern by name too
        let k = names.count; names.append(s); ids[a] = k; return k
    }
    var out = ""
    for i in 0..<gSampled {
        let base = gStacks! + i * gDepth
        var parts: [String] = ["\(gSizes![i])"]
        for j in 0..<gDepth { let a = base[j]; if a == 0 { break }; parts.append(String(id(a))) }
        out += parts.joined(separator: " ") + "\n"
    }
    try? out.write(toFile: path, atomically: true, encoding: .utf8)
    try? names.joined(separator: "\n").write(toFile: path + ".names", atomically: true, encoding: .utf8)
}
