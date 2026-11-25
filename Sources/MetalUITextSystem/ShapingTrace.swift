// `METALUI_TRACE_SHAPING=1` (`TS-E`, record 406): the instrument that says which strings missed a text system's shaping cache
// in a frame. Nothing here decides anything: a cache reads its own dictionaries and never a trace value.

/// The shaping trace's switch, sink and per-frame recorder, shared by every ``TextSystem`` that caches shapes (`CoreTextTextSystem`
/// over its `ShapingCache`, `PortableTextSystem` over its layout caches). **Off costs one `Bool` read per shape call and allocates
/// nothing**: every description is built inside `if ShapingTrace.active`, and a ``Recorder`` holds only integers and empty arrays
/// until something records.
///
/// This target imports no Foundation, so the environment variable is read by `MetalUI` (once, at the first window or frame),
/// which sets ``active``; a test sets ``active`` and ``sink`` directly.
package enum ShapingTrace {
    /// Whether anything is recorded. Set once from `METALUI_TRACE_SHAPING` (value exactly `"1"`) by `MetalUI`; a test sets it.
    nonisolated(unsafe) package static var active = false
    /// Where lines go instead of standard output (a test installs it and restores it).
    nonisolated(unsafe) package static var sink: ((String) -> Void)?

    /// Strings quoted since a test reset it: stays 0 while ``active`` is `false` (the off path builds no description).
    nonisolated(unsafe) package static var described = 0

    /// The most missed strings a line lists before `+K more`.
    package static let maxListed = 20
    /// The most characters of a string a line prints before `…`.
    package static let maxCharacters = 40

    /// One line, to the sink or standard output.
    package static func emit(_ line: String) {
        if let sink { sink(line) } else { print(line) }
    }

    /// `string` cut to ``maxCharacters`` characters with `…`, quoted, with newlines, returns, tabs, quotes and backslashes escaped.
    package static func quoted(_ string: String) -> String {
        described += 1
        var out = "\""
        var count = 0
        for character in string {
            if count == maxCharacters { out += "…"; break }
            count += 1
            switch character {
            case "\n": out += "\\n"
            case "\r\n": out += "\\r\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            default: out.append(character)
            }
        }
        return out + "\""
    }

    private static func number(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e9 { return String(Int(value)) }
        return "\(value)"
    }

    /// `PostScriptName size`, then `var=<n>` for a font with variation coordinates and `matrix` for a non-identity matrix:
    /// every component of a ``FontKey``.
    package static func describe(_ font: FontKey) -> String {
        var out = font.postScriptName + " " + number(font.size)
        if !font.variations.isEmpty { out += " var=\(font.variations.count)" }
        let m = font.matrix
        if !(m.a == 1 && m.b == 0 && m.c == 0 && m.d == 1 && m.tx == 0 && m.ty == 0) { out += " matrix" }
        return out
    }

    /// The rest of a cache key: ` w=<width>` when wrapping, and the options that differ from the defaults.
    package static func describe(width: Double?, options: TextLayoutOptions) -> String {
        var out = ""
        if let width { out += " w=" + number(width) }
        if let lines = options.maxLines { out += " lines=\(lines)" }
        if options.truncation != TextLayoutOptions().truncation { out += " trunc=\(options.truncation)" }
        if options.alignment != TextLayoutOptions().alignment { out += " align=\(options.alignment)" }
        return out
    }

    /// A plain string's entry: `"str"(font size w=… options…)`.
    package static func entry(_ string: String, font: FontKey, width: Double?, options: TextLayoutOptions) -> String {
        quoted(string) + "(" + describe(font) + describe(width: width, options: options) + ")"
    }

    /// A styled text's entry: its string, run count and each run's font (the first three), then width and options.
    package static func entry(_ text: StyledText, width: Double?, options: TextLayoutOptions) -> String {
        var fonts = ""
        for run in text.runs.prefix(3) { fonts += (fonts.isEmpty ? "" : ", ") + describe(run.style.font) }
        if text.runs.count > 3 { fonts += ", …" }
        return quoted(text.string) + "(styled \(text.runs.count) run\(text.runs.count == 1 ? "" : "s"): " + fonts
            + describe(width: width, options: options) + ")"
    }

    /// One frame's shape lookups for one text system.
    package struct Recorder {
        private(set) package var hits = 0
        private(set) package var misses = 0
        private var missed: [String] = []
        private var missedExtra = 0
        private var uncached: [String] = []
        private var uncachedExtra = 0

        package init() {}

        /// A lookup answered from the cache.
        package mutating func hit() { hits += 1 }

        /// A lookup that shaped; `entry` is the described key.
        package mutating func miss(_ entry: String) {
            misses += 1
            if missed.count < ShapingTrace.maxListed { missed.append(entry) } else { missedExtra += 1 }
        }

        /// A shape that no cache answers (the portable system's styled layout; `caretOffsets` is cached since `TS-F`).
        package mutating func bypass(_ entry: String) {
            if uncached.count < ShapingTrace.maxListed { uncached.append(entry) } else { uncachedExtra += 1 }
        }

        /// Ends the frame: writes its line when anything was looked up or bypassed, then clears the counts.
        package mutating func finish(frame: Int, system: String) {
            defer { self = Recorder() }
            guard hits + misses > 0 || !uncached.isEmpty else { return }
            var line = "shaping frame \(frame): hits \(hits) misses \(misses) [\(system)]"
            func list(_ entries: [String], _ extra: Int) -> String {
                var out = entries.joined(separator: ", ")
                if extra > 0 { out += ", +\(extra) more" }
                return out
            }
            if misses > 0 { line += " missed: " + list(missed, missedExtra) }
            if !uncached.isEmpty { line += " uncached: " + list(uncached, uncachedExtra) }
            ShapingTrace.emit(line)
        }
    }
}
