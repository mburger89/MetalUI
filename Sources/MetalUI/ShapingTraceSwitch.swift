import Foundation
import MetalUITextSystem

/// `METALUI_TRACE_SHAPING=1` (value exactly `"1"`, `TS-E`), read once when the first window or frame is made: it turns on
/// `ShapingTrace.active`, which every shaping cache checks. A test sets `ShapingTrace.active` and `ShapingTrace.sink` directly and
/// never reads the process environment. Off, nothing is written here.
let shapingTraceFromEnvironment: Bool = {
    let on = ProcessInfo.processInfo.environment["METALUI_TRACE_SHAPING"] == "1"
    if on { ShapingTrace.active = true }
    return on
}()
