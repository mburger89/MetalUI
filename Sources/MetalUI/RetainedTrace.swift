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
    /// Misses whose reason list came out empty: a test may never see this nonzero (`DM-F`).
    nonisolated(unsafe) package static var unclassified = 0

    package static let defaultPathLength = 120
    /// How many characters of an identity's path a line prints (`METALUI_TRACE_RETAINED_PATH=<n>`, read once).
    nonisolated(unsafe) package static var pathLength: Int = {
        if let text = ProcessInfo.processInfo.environment["METALUI_TRACE_RETAINED_PATH"], let n = Int(text), n > 0 { return n }
        return defaultPathLength
    }()

    /// The last `length` characters of `path`.
    package static func tail(of path: String, length: Int) -> String { String(path.suffix(length)) }

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
    static func path(_ id: GlobalElementID) -> String { tail(of: sbPath(id), length: pathLength) }

    /// The writer behind the observation fire this is called from, best effort: the demangled `<Type>.<property>.setter` frame of the
    /// stack (a debug build; a release build inlines the setter and this answers `?`, probe `observation-fire-cause.swift`).
    static func writerCause() -> String {
        for line in Thread.callStackSymbols {
            for token in line.split(whereSeparator: { " ()+[]".contains($0) }) where token.hasPrefix("$s") || token.hasPrefix("_$s") {
                if let name = demangle(String(token)), name.contains(".setter") {
                    return String(name.split(separator: ":", maxSplits: 1)[0]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return "?"
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
        if environment != other.environment { out.append("environment") }
        if snappingTransaction != other.snappingTransaction { out.append("snappingTransaction") }
        if disablesAnimations != other.disablesAnimations { out.append("disablesAnimations") }
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
