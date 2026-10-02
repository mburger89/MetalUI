// `metalui` (ruling SC-A): `swift run metalui new <Name>` from a MetalUI
// checkout, or `swift run --package-path <checkout> metalui new <Name>` from
// anywhere. The work is `MetalUIScaffold`'s, where the tests reach it.
import Foundation
import MetalUIScaffold

let status = runScaffold(Array(CommandLine.arguments.dropFirst()),
                         workingDirectory: FileManager.default.currentDirectoryPath,
                         output: { print($0) },
                         error: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) })
exit(status)
