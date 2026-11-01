import Foundation

// `METALUI_TRACE_RETAINED=1` and its package sink (C14-j, `DM-E`, `DM-F`, record 140): the instrument that says why a retained
// occurrence did not replay. Nothing here decides anything: a decision reads `PaintInvalidation`/`PrepaintInvalidation`, which
// the trace prints, and never a trace value.

/// The trace's switches and plumbing. **Off costs nothing**: every line is an autoclosure built only after `active` is read
/// (`emit`), and the fire-cause capture sits behind the same switch (`PA-J`: pinned differentially, `linesBuilt`).
package enum RetainedTrace {
    /// Where lines go instead of stdout (tests install it and restore it). Package API: a tool's seam (guard `TR.1`).
    nonisolated(unsafe) package static var sink: (@MainActor (String) -> Void)? {
        didSet { sinkInstalled = sink != nil }
    }
    nonisolated(unsafe) private static var sinkInstalled = false

    /// Whether anything listens: the environment switch or an installed sink. Read from any thread (the fire-cause capture).
    package static var active: Bool { retainedTraces || sinkInstalled }

    /// Lines built since a test reset it: stays 0 while nothing listens.
    nonisolated(unsafe) package static var linesBuilt = 0
    /// Paths rendered since a test reset it (every line renders one): stays 0 while nothing listens, whichever layer's guard goes (`PA-J`).
    nonisolated(unsafe) package static var pathsBuilt = 0
    /// Misses whose reason list came out empty: a test may never see this nonzero (`DM-F`).
    nonisolated(unsafe) package static var unclassified = 0

    package static let defaultPathLength = 120
    /// How many characters of an identity's path a line prints (`METALUI_TRACE_RETAINED_PATH=<n>`, read once).
    nonisolated(unsafe) package static var pathLength: Int = {
        if let text = ProcessInfo.processInfo.environment["METALUI_TRACE_RETAINED_PATH"], let n = Int(text), n > 0 { return n }
        return defaultPathLength
    }()

    /// The tail of `path` that fits in `length` characters, cut at a `/` boundary (`AM-F`): the path itself when it fits, else `…/`
    /// and the longest run of whole trailing components that fits; a last component longer than that prints `…` and its last
    /// `length - 1` characters. Never starts mid component, never longer than `length`.
    package static func tail(of path: String, length: Int) -> String {
        guard path.count > length else { return path }
        guard length > 2 else { return String(path.suffix(max(length, 0))) }
        let prefix = "…/"
        let budget = length - prefix.count
        // The candidates are the suffixes that start right after a `/`, longest first.
        var index = path.startIndex
        while let slash = path[index...].firstIndex(of: "/") {
            let start = path.index(after: slash)
            let candidate = path[start...]
            if candidate.count <= budget {
                return candidate.isEmpty ? "…" + String(path.suffix(length - 1)) : prefix + candidate
            }
            index = start
        }
        return "…" + String(path.suffix(length - 1))
    }

    /// One trace line, built only when something listens.
    @MainActor
    static func emit(_ line: @autoclosure () -> String) {
        guard active else { return }
        let text = line()
        linesBuilt += 1
        if let sink { sink(text) } else { print(text) }
    }

    /// ` cause: <writer>` when the entry's last fire recorded one, else empty.
    @MainActor
    static func causeSuffix(of entry: ContentMemoStore.Entry?) -> String {
        guard let cause = entry?.flags.lastFireCause else { return "" }
        return " cause: \(cause)"
    }

    /// The path of an identity as a line prints it.
    static func path(_ id: GlobalElementID) -> String {
        pathsBuilt += 1
        return tail(of: sbPath(id), length: pathLength)
    }

    /// The writer behind the observation fire this is called from, best effort (`AM-G`, probes `observation-fire-cause.swift` and
    /// `observation-fire-cause-release.swift`): the demangled `<Type>.<property>.setter` frame in a debug build; in a release build
    /// the setter is inlined into its caller, so `via <function>` names the nearest frame above the observation machinery; `release-inlined`
    /// when nothing is above it; `?` only where stack symbols carry no names at all (Windows).
    static func writerCause() -> String {
        var named = false
        let frames = Thread.callStackSymbols.map { line -> String in
            for token in line.split(whereSeparator: { " ()+[]".contains($0) }) where token.hasPrefix("$s") || token.hasPrefix("_$s") {
                if let name = demangle(String(token)) { named = true; return name }
            }
            return line
        }
        return named ? writerCause(from: frames) : "?"
    }

    /// The rule of `writerCause()` over demangled frames, innermost first (pure, so a test feeds it synthetic stacks).
    package static func writerCause(from frames: [String]) -> String {
        if frames.isEmpty { return "?" }
        if let setter = frames.first(where: { $0.contains(".setter") }) {
            return String(setter.split(separator: ":", maxSplits: 1)[0]).trimmingCharacters(in: .whitespaces)
        }
        // The machinery is the contiguous run from the capture up to the registrar; the writer is the first frame after its last member.
        let machinery = ["Observation.", "ObservationRegistrar", "ObservationTracking", "withObservationTracking", "withMutation",
                         "RetainedTrace.", "MemoFlags", "RetainedSession", "ContentMemoStore"]
        guard let last = frames.lastIndex(where: { frame in machinery.contains { frame.contains($0) } }) else { return "release-inlined" }
        for frame in frames[(last + 1)...] {
            let name = functionName(of: frame)
            if name.isEmpty || runtimeFrame(name) { continue }
            return "via " + name
        }
        return "release-inlined"
    }

    /// `function signature specialization <…> of main.arm(…) -> ()` becomes `main.arm`: the specialization wrapper and the signature
    /// are dropped.
    static func functionName(of frame: String) -> String {
        var name = Substring(frame)
        for wrapper in ["function signature specialization", "generic specialization", "merged ", "specialized "] where name.hasPrefix(wrapper) {
            if let of = name.range(of: "> of ") ?? name.range(of: " of ") { name = name[of.upperBound...] }
        }
        if let paren = name.firstIndex(of: "(") { name = name[..<paren] }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// A frame that is the process or runtime, not a writer: an unsymbolicated line, a thunk, a loader or dispatch entry.
    private static func runtimeFrame(_ name: String) -> Bool {
        if name.contains("0x") || name.hasPrefix("reabstraction thunk") || name.hasPrefix("partial apply") { return true }
        if name.contains(".") { return false }   // a module-qualified Swift name
        return ["swift_", "_swift", "start", "main", "_main", "dyld", "_dispatch", "thread_start"].contains { name.hasPrefix($0) }
    }

    private static func demangle(_ mangled: String) -> String? {
        mangled.withCString { p in
            guard let out = swiftDemangle(p, UInt(strlen(p)), nil, nil, 0) else { return nil }
            defer { free(out) }
            return String(cString: out)
        }
    }
}

@_silgen_name("swift_demangle")
private func swiftDemangle(_ name: UnsafePointer<CChar>?, _ length: UInt, _ out: UnsafeMutablePointer<CChar>?,
                           _ outLength: UnsafeMutablePointer<UInt>?, _ flags: UInt32) -> UnsafeMutablePointer<CChar>?

// MARK: - The paint decision's conjunction

/// The conjuncts of the paint decision's `valid` (`retainedPaintDecision`), one flag each, computed by one pure function the
/// decision and the trace share so the two cannot drift. A `false` flag is a conjunct that holds.
package struct PaintInvalidation {
    /// The primitives of each conjunct; the defaults are a record that passes every one.
    package struct Inputs {
        package var observedChange = false
        package var coverageBuild = true
        package var coveragePrepaint = true
        package var serialMatches = true
        package var versionsUnchanged = true
        package var underPointer = false
        /// A replayed prepaint's ledger is not the record's (`old.prepaint !== phase.replayed`).
        package var ledgerIdentityDiffers = false
        /// `RW-S`: the record holds no ledger and this frame's prepaint made one.
        package var ledgerGain = false
        package init() {}
    }

    package let inputs: Inputs
    package init(_ inputs: Inputs) { self.inputs = inputs }

    package var isValid: Bool {
        !inputs.observedChange && inputs.coverageBuild && inputs.coveragePrepaint && inputs.serialMatches
            && inputs.versionsUnchanged && !inputs.underPointer && !inputs.ledgerIdentityDiffers && !inputs.ledgerGain
    }

    /// The failing conjuncts' names, in a fixed order.
    package var names: [String] {
        var out: [String] = []
        if inputs.observedChange { out.append("observed") }
        if !inputs.serialMatches { out.append("serial") }
        if !inputs.coverageBuild { out.append("coverage.build") }
        if !inputs.coveragePrepaint { out.append("coverage.prepaint") }
        if !inputs.versionsUnchanged { out.append("versions") }
        if inputs.underPointer { out.append("pointer") }
        if inputs.ledgerIdentityDiffers { out.append("ledger.identity") }
        if inputs.ledgerGain { out.append("ledger.gain") }
        return out
    }
}

// MARK: - The prepaint decision's guard

/// The guard of `retainedPrepaintDecision` before any key is compared (`RK-C`), the same shape: shared by the decision and the trace.
package struct PrepaintInvalidation {
    package struct Inputs {
        /// A redo or its backoff turned prepaint replay off for this build.
        package var replayDisallowed = false
        package var quarantined = false
        package var hasRecord = true
        package var hasLedger = true
        package var observedChange = false
        package var coverageBuild = true
        package var coveragePrepaint = true
        package var serialMatches = true
        package var versionsUnchanged = true
        package var pointerInLedger = false
        package init() {}
    }

    package let inputs: Inputs
    package init(_ inputs: Inputs) { self.inputs = inputs }

    package var isReplayable: Bool { names.isEmpty }

    package var names: [String] {
        var out: [String] = []
        if inputs.replayDisallowed { out.append("replayDisallowed") }
        if inputs.quarantined { out.append("quarantine") }
        if !inputs.hasRecord { out.append("noRecord") } else if !inputs.hasLedger { out.append("noLedger") }
        if inputs.observedChange { out.append("observed") }
        if inputs.hasRecord {
            if !inputs.coverageBuild { out.append("coverage.build") }
            if !inputs.coveragePrepaint { out.append("coverage.prepaint") }
            if !inputs.serialMatches { out.append("serial") }
            if !inputs.versionsUnchanged { out.append("versions") }
        }
        if inputs.pointerInLedger { out.append("pointerInLedger") }
        return out
    }
}

// MARK: - Key differences

extension AmbientKey {
    /// Every member of this key that differs from `other`, by name.
    func differences(from other: AmbientKey) -> [String] {
        var out: [String] = []
        if clip != other.clip { out.append("clip") }
        if offset != other.offset { out.append("offset") }
        if layerOpacityScale != other.layerOpacityScale { out.append("layerOpacityScale") }
        if depths != other.depths { out.append("depths") }
        if scopes != other.scopes { out.append("scopes") }
        if environment != other.environment {
            // `AM-E`: the differing field, so a miss says which environment value moved (`environment` alone if none is named).
            let fields = environment.differences(from: other.environment)
            if fields.isEmpty { out.append("environment") } else { for field in fields { out.append("environment.\(field)") } }
        }
        if snappingTransaction != other.snappingTransaction { out.append("snappingTransaction") }
        if disablesAnimations != other.disablesAnimations { out.append("disablesAnimations") }
        if atlasGeneration != other.atlasGeneration { out.append("atlasGeneration") }
        return out
    }
}

extension ReplayKey {
    /// Every stored field of this key that differs from `other`, `key.<field>` (`ambient` members `key.ambient.<member>`). A
    /// `Mirror` guard (`everyReplayKeyFieldIsNamedWhenItDiffersAlone`) makes a new field owe a row.
    func describeDifference(from other: ReplayKey) -> [String] {
        var out: [String] = []
        if rects != other.rects { out.append("key.rects") }
        if interior != other.interior { out.append("key.interior") }
        if shapeInterior != other.shapeInterior { out.append("key.shapeInterior") }
        if nodeCount != other.nodeCount { out.append("key.nodeCount") }
        for member in ambient.differences(from: other.ambient) { out.append("key.ambient.\(member)") }
        return out
    }
}
