import Foundation

/// One note: what the sidebar lists and the detail edits.
///
/// A plain value that is `Codable` (the file format), `Identifiable` (what a
/// `List` and a `ForEach` need) and `Hashable`/`Equatable` (what `.equatable()`
/// compares to skip an unchanged row).
public struct Note: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    /// The day the note was made, as days since 1970-01-01 (a plain number so
    /// a test never reads a clock and the file holds no time zone).
    public var day: Int

    public init(id: UUID = UUID(), title: String, body: String, day: Int) {
        self.id = id
        self.title = title
        self.body = body
        self.day = day
    }

    /// The words of the body, by whitespace.
    public var wordCount: Int {
        body.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    }

    /// The `#tags` in the body, in order, without the `#` and without repeats.
    public var tags: [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for word in body.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) where word.hasPrefix("#") {
            let tag = String(word.dropFirst().prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" }))
            if !tag.isEmpty, seen.insert(tag).inserted { result.append(tag) }
        }
        return result
    }

    /// The first line of the body, cut to `limit` characters: the row's snippet.
    public func snippet(limit: Int = 40) -> String {
        let line = body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return line.count > limit ? String(line.prefix(limit)) + "..." : line
    }

    /// Whether the note matches `query`: a case-insensitive substring of the
    /// title or the body. An empty query matches every note.
    public func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        if needle.isEmpty { return true }
        return title.localizedCaseInsensitiveContains(needle) || body.localizedCaseInsensitiveContains(needle)
    }
}

/// The file's payload: a version, then the notes.
struct NoteFile: Codable {
    static let currentVersion = 1
    var version: Int
    var notes: [Note]
}

/// Why a file was refused.
public enum JotterFileError: Error, Equatable, CustomStringConvertible {
    /// The bytes are not a Jotter file.
    case notAJotterFile
    /// A file of a version this build does not read.
    case unsupportedVersion(Int)

    public var description: String {
        switch self {
        case .notAJotterFile: "That file is not a Jotter file."
        case .unsupportedVersion(let version): "Jotter files of version \(version) are not supported."
        }
    }
}
