import Foundation

/// What `CreateProcess` wants from a Windows spawn (ruling `TRM-AX`), as pure functions so every platform
/// can test them. Nothing here touches the OS.
package enum WindowsCommandLine {
    /// One argument, quoted so `CommandLineToArgvW` (and the C runtime) reads back exactly `argument`.
    ///
    /// An argument with no space, tab, newline, vertical tab or double quote is left alone (an empty one
    /// becomes `""`). Otherwise it is wrapped in quotes; a run of backslashes before a quote (or before the
    /// closing quote) is doubled, and each quote gets a backslash.
    package static func quote(_ argument: String) -> String {
        if argument.isEmpty { return "\"\"" }
        let special: Set<Character> = [" ", "\t", "\n", "\u{0B}", "\""]
        if !argument.contains(where: { special.contains($0) }) { return argument }
        var result = "\""
        var backslashes = 0
        for character in argument.unicodeScalars {
            if character == "\\" {
                backslashes += 1
            } else if character == "\"" {
                result += String(repeating: "\\", count: backslashes * 2 + 1) + "\""
                backslashes = 0
            } else {
                result += String(repeating: "\\", count: backslashes)
                backslashes = 0
                result.unicodeScalars.append(character)
            }
        }
        result += String(repeating: "\\", count: backslashes * 2) + "\""
        return result
    }

    /// The command line for `argv`. `argv[0]` follows the first token's own rule (no escapes are read in it):
    /// it is quoted only when it holds a space or tab, and a name with a `"` cannot be expressed.
    package static func commandLine(argv: [String]) -> String {
        guard let first = argv.first else { return "" }
        let program = first.contains(where: { $0 == " " || $0 == "\t" }) && !first.hasPrefix("\"") ? "\"\(first)\"" : first
        return ([program] + argv.dropFirst().map(quote)).joined(separator: " ")
    }

    /// The environment block `CreateProcess` takes with `CREATE_UNICODE_ENVIRONMENT`: `NAME=value` entries
    /// sorted case-insensitively by name, each NUL-terminated, the whole block ended by one more NUL (two for an
    /// empty environment).
    package static func environmentBlock(_ env: [String: String]) -> [UInt16] {
        let entries = env.sorted { lhs, rhs in
            let l = Array(lhs.key.uppercased().utf16), r = Array(rhs.key.uppercased().utf16)
            return l == r ? lhs.key < rhs.key : l.lexicographicallyPrecedes(r)
        }
        var block: [UInt16] = []
        for (name, value) in entries {
            block += Array("\(name)=\(value)".utf16)
            block.append(0)
        }
        block.append(0)
        if env.isEmpty { block.append(0) }
        return block
    }
}

/// The shell MetalUI's demo and tests start by default (ruling `TRM-E`); not frozen API.
package enum DefaultShell {
    /// Windows: `pwsh.exe` found on `path`, else `powershell.exe`, else `comSpec` (`cmd.exe`), else `nil`.
    ///
    /// `path` is a `PATH` value (`;`-separated); `exists` says whether a file is there.
    package static func windows(path: String, comSpec: String?, exists: (String) -> Bool) -> String? {
        let directories = path.split(separator: ";", omittingEmptySubsequences: true).map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        for name in ["pwsh.exe", "powershell.exe"] {
            for directory in directories {
                let candidate = directory.hasSuffix("\\") || directory.hasSuffix("/") ? directory + name : directory + "\\" + name
                if exists(candidate) { return candidate }
            }
        }
        if let comSpec, !comSpec.isEmpty, exists(comSpec) { return comSpec }
        return nil
    }

    /// POSIX: `shell` (`$SHELL`) when set and non-empty, else `/bin/sh`.
    package static func posix(shell: String?) -> String {
        if let shell, !shell.isEmpty { return shell }
        return "/bin/sh"
    }
}
