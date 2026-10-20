// The second process of the single-instance tests (item S7, ruling `SN-K`):
// `SDLSingleInstanceTests` launches it, like `MainQueueDrainCheck`.
//
//   SingleInstanceCheck primary <directory> <id>          claims, prints "primary", then holds the role until killed
//   SingleInstanceCheck forward <directory> <id> <args>…  claims with the arguments; exits 0 when they were forwarded
//
// `forward` exits 3 when it became primary, 2 when the claim was unavailable.
import Foundation
import MetalUISDL

/// Unbuffered, so a reader sees a line the moment it is said.
func say(_ text: String) { FileHandle.standardOutput.write(Data((text + "\n").utf8)) }
let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    say("usage: SingleInstanceCheck primary|forward <directory> <id> [arguments…]")
    exit(64)
}
let mode = arguments[1], directory = arguments[2], id = arguments[3]
let configuration = SingleInstance.Configuration(directory: directory)

switch mode {
case "primary":
    guard case .primary(let instance) = SingleInstance.claim(id: id, forwarding: [], configuration: configuration) else {
        say("not primary")
        exit(1)
    }
    say("primary")
    while true { Thread.sleep(forTimeInterval: 1); withExtendedLifetime(instance) {} }
case "forward":
    switch SingleInstance.claim(id: id, forwarding: Array(arguments.dropFirst(4)), configuration: configuration) {
    case .forwarded: say("forwarded"); exit(0)
    case .primary: say("primary"); exit(3)
    case .unavailable(let failure): say("unavailable \(failure)"); exit(2)
    }
default:
    say("unknown mode \(mode)")
    exit(64)
}
