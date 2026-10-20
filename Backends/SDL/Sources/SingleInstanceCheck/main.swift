// The second process of the single-instance tests (item S7, ruling `SN-K`):
// `SDLSingleInstanceTests` launches it, like `MainQueueDrainCheck`.
//
//   SingleInstanceCheck primary <directory> <id>          claims, prints "primary", then holds the role until killed
//   SingleInstanceCheck forward <directory> <id> <args>…  claims with the arguments; exits 0 when they were forwarded
//
// `forward` exits 3 when it became primary, 2 when the claim was unavailable.
import Foundation
import MetalUISDL

setvbuf(stdout, nil, _IOLBF, 0)
let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    print("usage: SingleInstanceCheck primary|forward <directory> <id> [arguments…]")
    exit(64)
}
let mode = arguments[1], directory = arguments[2], id = arguments[3]
let configuration = SingleInstance.Configuration(directory: directory)

switch mode {
case "primary":
    guard case .primary(let instance) = SingleInstance.claim(id: id, forwarding: [], configuration: configuration) else {
        print("not primary")
        exit(1)
    }
    print("primary")
    while true { sleep(1); withExtendedLifetime(instance) {} }
case "forward":
    switch SingleInstance.claim(id: id, forwarding: Array(arguments.dropFirst(4)), configuration: configuration) {
    case .forwarded: print("forwarded"); exit(0)
    case .primary: print("primary"); exit(3)
    case .unavailable(let failure): print("unavailable \(failure)"); exit(2)
    }
default:
    print("unknown mode \(mode)")
    exit(64)
}
