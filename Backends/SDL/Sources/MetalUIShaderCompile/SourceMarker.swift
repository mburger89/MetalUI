/// `SOURCE.sha256`: one `<sha256>  <file>` line per source, sorted bytewise by
/// name, LF (the python script's output, ruling `BS-I`).
package enum SourceMarker {
    /// The marker text for `sources`.
    package static func contents(of sources: [(name: String, bytes: [UInt8])]) -> String {
        sources.sorted { Array($0.name.utf8).lexicographicallyPrecedes(Array($1.name.utf8)) }
            .map { "\(SHA256.hexDigest(of: $0.bytes))  \($0.name)\n" }.joined()
    }

    /// What is wrong between `marker` and `sources`, each a named message; empty
    /// when every source's hash equals its line and no line stands alone (`BS-E`).
    package static func problems(marker: String, sources: [(name: String, bytes: [UInt8])]) -> [String] {
        var lines: [String: String] = [:]
        for line in marker.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let parts = line.components(separatedBy: "  ")
            if parts.count == 2 { lines[parts[1]] = parts[0] }
        }
        var problems: [String] = []
        for source in sources.sorted(by: { $0.name < $1.name }) {
            guard let recorded = lines[source.name] else {
                problems.append("\(source.name) has no line in SOURCE.sha256")
                continue
            }
            if SHA256.hexDigest(of: source.bytes) != recorded {
                problems.append("\(source.name) changed since SOURCE.sha256 was written")
            }
        }
        let names = Set(sources.map(\.name))
        for name in lines.keys.sorted() where !names.contains(name) {
            problems.append("SOURCE.sha256 lists \(name), which is not among the sources")
        }
        return problems
    }
}
