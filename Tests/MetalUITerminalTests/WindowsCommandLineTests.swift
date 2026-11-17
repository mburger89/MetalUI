import Testing
@testable import MetalUITerminal

// Ruling TRM-AX: what a Windows spawn hands CreateProcess, and the default-shell resolver (TRM-E). Pure, so
// they run on every platform; the Windows file round-trips the quoting through CommandLineToArgvW itself.

@Suite struct WindowsCommandLineTests {
    @Test(arguments: [
        ("plain", "plain"),
        ("", "\"\""),
        ("a b", "\"a b\""),
        ("tab\there", "\"tab\there\""),
        ("say \"hi\"", "\"say \\\"hi\\\"\""),
        ("C:\\Program Files\\x\\", "\"C:\\Program Files\\x\\\\\""),   // a trailing backslash is doubled before the closing quote
        ("a\\\"b", "\"a\\\\\\\"b\""),                                    // backslash-quote: both escaped
        ("trailing\\", "trailing\\"),                                    // no space, no quote: left alone
        ("C:\\dir\\file.txt", "C:\\dir\\file.txt"),
        ("\\\\server\\share x", "\"\\\\server\\share x\""),             // interior backslashes are literal
    ])
    func quoting(_ argument: String, _ expected: String) {
        #expect(WindowsCommandLine.quote(argument) == expected)
    }

    @Test func theCommandLineJoinsQuotedArguments() {
        #expect(WindowsCommandLine.commandLine(argv: ["cmd.exe", "/c", "echo", "hi there"]) == "cmd.exe /c echo \"hi there\"")
        #expect(WindowsCommandLine.commandLine(argv: []) == "")
    }

    @Test func theProgramNameFollowsTheFirstTokenRule() {
        // argv[0] is read without escapes, so it is only wrapped when it has a space.
        #expect(WindowsCommandLine.commandLine(argv: ["C:\\Program Files\\x\\y.exe", "a"]) == "\"C:\\Program Files\\x\\y.exe\" a")
        #expect(WindowsCommandLine.commandLine(argv: ["C:\\x\\y.exe"]) == "C:\\x\\y.exe")
    }

    @Test func theEnvironmentBlockIsSortedCaseInsensitivelyAndDoubleTerminated() {
        let block = WindowsCommandLine.environmentBlock(["b": "2", "A": "1", "Zed": "é"])
        let expected = Array("A=1\0b=2\0Zed=é\0\0".utf16)
        #expect(block == expected)
    }

    @Test func anEmptyEnvironmentIsTwoNuls() {
        #expect(WindowsCommandLine.environmentBlock([:]) == [0, 0])
    }

    // MARK: The default shell

    @Test func pwshBeatsPowershellBeatsComSpec() {
        let files: Set<String> = ["C:\\a\\powershell.exe", "C:\\b\\pwsh.exe", "C:\\Windows\\System32\\cmd.exe"]
        let path = "C:\\a;C:\\b;C:\\c"
        #expect(DefaultShell.windows(path: path, comSpec: "C:\\Windows\\System32\\cmd.exe", exists: files.contains) == "C:\\b\\pwsh.exe")
        let noPwsh = files.subtracting(["C:\\b\\pwsh.exe"])
        #expect(DefaultShell.windows(path: path, comSpec: "C:\\Windows\\System32\\cmd.exe", exists: noPwsh.contains) == "C:\\a\\powershell.exe")
        let onlyCmd: Set<String> = ["C:\\Windows\\System32\\cmd.exe"]
        #expect(DefaultShell.windows(path: path, comSpec: "C:\\Windows\\System32\\cmd.exe", exists: onlyCmd.contains) == "C:\\Windows\\System32\\cmd.exe")
        #expect(DefaultShell.windows(path: path, comSpec: "C:\\Windows\\System32\\cmd.exe", exists: { _ in false }) == nil)
        #expect(DefaultShell.windows(path: path, comSpec: nil, exists: onlyCmd.contains) == nil)
    }

    @Test func pathEntriesMayBeQuotedAndTrailingSlashed() {
        let files: Set<String> = ["C:\\Program Files\\PowerShell\\7\\pwsh.exe"]
        #expect(DefaultShell.windows(path: ";\"C:\\Program Files\\PowerShell\\7\\\";C:\\x", comSpec: nil, exists: files.contains)
                == "C:\\Program Files\\PowerShell\\7\\pwsh.exe")
    }

    @Test func aPathEarlierInTheListWinsForTheSameName() {
        let files: Set<String> = ["C:\\a\\pwsh.exe", "C:\\b\\pwsh.exe"]
        #expect(DefaultShell.windows(path: "C:\\b;C:\\a", comSpec: nil, exists: files.contains) == "C:\\b\\pwsh.exe")
    }

    @Test func posixUsesShellElseBinSh() {
        #expect(DefaultShell.posix(shell: "/bin/zsh") == "/bin/zsh")
        #expect(DefaultShell.posix(shell: nil) == "/bin/sh")
        #expect(DefaultShell.posix(shell: "") == "/bin/sh")
    }
}
