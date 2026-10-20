// Single-instance launch on SDL (item S7; rulings `SN-A`..`SN-P`). Compiled only
// under the `SDL` trait; the trait-off stub in `SDLPlatform.swift` declares the
// same names so a call reports the trait's remedy (guard 1.6b).
#if SDL
import Foundation
import SDLBridge

/// The role of the one running instance of an application, and the way a second
/// launch hands its documents to it.
///
/// On Linux and Windows a file manager runs the application once per open, so a
/// second document starts a second process. Call ``claim(id:forwarding:configuration:)``
/// before any window exists: the first launch becomes the *primary* and keeps
/// the role while the returned value lives; a later launch forwards its
/// arguments to the primary over a local channel and is told so, and the caller
/// exits. The primary delivers the arguments through ``SDLPlatform/onOpenURLs``
/// (so ``App/open(_:)``'s routing, parking and `.onOpenURL` apply unchanged), on
/// the main actor, as if the operating system had sent an open event, and
/// raises one of its windows.
///
/// ```swift
/// let documents = CommandLine.arguments.dropFirst().filter { FileManager.default.fileExists(atPath: $0) }
/// guard let platform = try SDLPlatform.launchingSingleInstance(id: "com.example.MyApp",
///                                                              forwarding: Array(documents)) else { exit(0) }
/// ```
///
/// - Note: The channel is private to the user: a Unix domain socket in a 0700
///   directory (`$XDG_RUNTIME_DIR` by default) elected by an `flock` on Unix, a
///   named pipe and semaphore scoped to the user's session on Windows. A
///   crashed primary leaves nothing behind that blocks the next launch. A message
///   is at most 1 MiB, 1024 strings of 1...32768 bytes each; nothing received is
///   executed, expanded or opened. A claim blocks the caller up to the connect
///   and read timeouts (about four seconds in the worst case) before any window
///   exists.
///
/// AppKit needs none of this: LaunchServices hands a bundled application's open
/// events to the running instance. This type exists in the SDL build, which on
/// macOS is the development and test configuration.
public final class SingleInstance: @unchecked Sendable, Hashable {
    /// What ``claim(id:forwarding:configuration:)`` decided.
    public enum Outcome: Sendable {
        /// This process is the primary: keep the value, pass it in
        /// ``SDLPlatform/Options/singleInstance``.
        case primary(SingleInstance)
        /// The arguments reached the primary: the caller should exit.
        case forwarded
        /// No channel could be used; the caller runs as an independent instance
        /// (a second window, as before) rather than lose its documents (ruling `SN-F`).
        case unavailable(Failure)
    }

    /// Why a claim could neither take the role nor forward.
    public enum Failure: Error, Equatable, Sendable {
        /// The identifier is empty.
        case emptyID
        /// The role is held but nothing accepted the connection within the connect timeout.
        case noListener
        /// The primary refused the message (queue full, a limit exceeded) or closed without answering.
        case refused
        /// The channel's directory is not a private directory owned by this user.
        case insecureDirectory
        /// The channel's path would not fit a Unix socket address.
        case pathTooLong
        /// The other end of the channel is not this user's process.
        case insecure
        /// A system call failed; the associated value is `errno` (`GetLastError` on Windows).
        case io(Int32)
    }

    /// How a claim reaches the channel.
    public struct Configuration: Sendable {
        /// The channel's directory; `nil` for the default (`$XDG_RUNTIME_DIR`,
        /// else the user's temporary directory on macOS, else `/tmp/metalui-<uid>`).
        /// It must exist, be owned by this user and allow nobody else. Ignored on Windows.
        public var directory: String?
        /// How long a launch that lost the election waits for the primary to accept (default 2 s).
        public var connectTimeout: Duration
        /// How long a message may take to be read, and a forward to be answered (default 2 s).
        public var readTimeout: Duration
        /// Whether the primary raises a window when a message arrives (default `true`).
        public var raisesWindow: Bool
        /// The user id a connecting process must have; `nil` for this process's.
        /// A test hook for the peer check; ignored on Windows.
        public var expectedPeerUID: UInt32?

        public init(directory: String? = nil, connectTimeout: Duration = .seconds(2),
                    readTimeout: Duration = .seconds(2), raisesWindow: Bool = true,
                    expectedPeerUID: UInt32? = nil) {
            self.directory = directory
            self.connectTimeout = connectTimeout
            self.readTimeout = readTimeout
            self.raisesWindow = raisesWindow
            self.expectedPeerUID = expectedPeerUID
        }

        /// The defaults above.
        public static let `default` = Configuration()
    }

    /// Takes the primary role for `id`, or forwards `arguments` to the process that holds it.
    ///
    /// A relative path in `arguments` is made absolute against this process's working
    /// directory (the primary's is unrelated); a string with a URL scheme and `//`, and an
    /// absolute path, are sent as they are. An empty string names nothing and is dropped. The
    /// primary's own launch arguments are not delivered by the claim: open them with
    /// ``App/open(_:)`` as `docs/packaging.md` says.
    ///
    /// - Parameters:
    ///   - id: names the application, such as `"com.example.MyApp"`; any non-empty string.
    ///   - arguments: the documents and URLs to hand to the running instance if there is one.
    ///   - configuration: the directory, timeouts and the raise.
    public static func claim(id: String, forwarding arguments: [String],
                             configuration: Configuration = .default) -> Outcome {
        let strings = arguments.filter { !$0.isEmpty }.map(makeAbsolute)
        var instance: OpaquePointer?
        var error: Int32 = 0
        let status = withCStrings(strings) { pointers in
            mui_instance_claim(id, configuration.directory, pointers, UInt32(strings.count),
                               milliseconds(configuration.connectTimeout), milliseconds(configuration.readTimeout),
                               configuration.expectedPeerUID.map(Int64.init) ?? -1, &instance, &error)
        }
        switch Int(status) {
        case Int(MUI_INSTANCE_PRIMARY):
            guard let instance else { return .unavailable(.io(error)) }
            return .primary(SingleInstance(handle: instance, raisesWindow: configuration.raisesWindow))
        case Int(MUI_INSTANCE_FORWARDED): return .forwarded
        case Int(MUI_INSTANCE_EMPTY_ID): return .unavailable(.emptyID)
        case Int(MUI_INSTANCE_NO_LISTENER): return .unavailable(.noListener)
        case Int(MUI_INSTANCE_REFUSED): return .unavailable(.refused)
        case Int(MUI_INSTANCE_INSECURE_DIRECTORY): return .unavailable(.insecureDirectory)
        case Int(MUI_INSTANCE_PATH_TOO_LONG): return .unavailable(.pathTooLong)
        case Int(MUI_INSTANCE_INSECURE): return .unavailable(.insecure)
        default: return .unavailable(.io(error))
        }
    }

    // MARK: The held role

    private let handle: OpaquePointer
    let raisesWindow: Bool

    private init(handle: OpaquePointer, raisesWindow: Bool) {
        self.handle = handle
        self.raisesWindow = raisesWindow
    }

    // Stops the listener, removes the socket and releases the lock (ruling `SN-J`).
    deinit { mui_instance_release(handle) }

    public static func == (lhs: SingleInstance, rhs: SingleInstance) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    /// Registers the wake event with SDL; the platform calls it once it exists (ruling `SN-G`).
    func attach() { mui_instance_attach(handle) }

    /// The oldest queued message, or `nil`. Each is one forwarded batch, in connection order.
    func takeNext() -> [String]? {
        var strings: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        var count: UInt32 = 0
        guard mui_instance_next(handle, &strings, &count) else { return nil }
        defer { mui_instance_free_message(strings, count) }
        guard let strings else { return [] }
        return (0..<Int(count)).map { String(cString: strings[$0]!) }
    }

    /// Every queued message (a test's read-back).
    func takeMessages() -> [[String]] {
        var result: [[String]] = []
        while let next = takeNext() { result.append(next) }
        return result
    }

    /// The lock and socket paths (Windows: the semaphore and pipe names) for `id`
    /// in `directory`; `nil` when they do not fit.
    static func paths(id: String, directory: String?) -> (lock: String, socket: String)? {
        var lock = [CChar](repeating: 0, count: 1200), socket = [CChar](repeating: 0, count: 1200)
        guard mui_instance_paths(id, directory, &lock, lock.count, &socket, socket.count) else { return nil }
        return (text(lock), text(socket))
    }

    /// Wake events the event pump has consumed in this process (a test's count).
    static var wakesConsumed: Int { Int(mui_instance_wakes_consumed()) }

    /// The largest payload buffer a listener has asked for (a test's read-back).
    static var payloadHighWaterMark: Int { Int(mui_instance_payload_high_water()) }

    // MARK: Helpers

    private static func text(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func milliseconds(_ duration: Duration) -> Int32 {
        let parts = duration.components
        let total = parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000
        return Int32(clamping: max(0, total))
    }

    /// `argument` as the primary can use it: a URL (`scheme://`) or an absolute path
    /// stays; anything else is joined to this process's working directory. No file
    /// system access, no `~` or `$VAR` expansion (ruling `SN-I`).
    static func makeAbsolute(_ argument: String) -> String {
        if SDLPlatform.hasURLScheme(argument) || isAbsolutePath(argument) { return argument }
        var relative = Substring(argument)
        while relative.hasPrefix("./") { relative = relative.dropFirst(2) }
        let directory = FileManager.default.currentDirectoryPath
        return directory.hasSuffix("/") ? directory + relative : directory + "/" + relative
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
        if path.hasPrefix("/") { return true }
        #if os(Windows)
        if path.hasPrefix("\\\\") { return true }
        let scalars = Array(path.unicodeScalars)
        if scalars.count >= 3, scalars[0].isASCII, scalars[0].properties.isAlphabetic, scalars[1] == ":",
           scalars[2] == "\\" || scalars[2] == "/" { return true }
        #endif
        return false
    }

    private static func withCStrings<R>(_ strings: [String],
                                        _ body: (UnsafePointer<UnsafePointer<CChar>?>?) -> R) -> R {
        var pointers: [UnsafePointer<CChar>?] = []
        var owned: [UnsafeMutablePointer<CChar>] = []
        defer { owned.forEach { free($0) } }
        for string in strings {
            #if os(Windows)
            let copy = _strdup(string)!
            #else
            let copy = strdup(string)!
            #endif
            owned.append(copy)
            pointers.append(UnsafePointer(copy))
        }
        return pointers.withUnsafeBufferPointer { body($0.baseAddress) }
    }
}

extension SDLPlatform {
    /// A platform that is the application's one instance, or `nil` when this launch's
    /// `forwarding` reached the running one: the caller then exits.
    ///
    /// Equivalent to calling ``SingleInstance/claim(id:forwarding:configuration:)`` and
    /// passing a `.primary` in `options`. An `.unavailable` claim runs as an independent
    /// instance (ruling `SN-F`): losing the channel must not lose the user's document.
    ///
    /// - Parameters:
    ///   - id: names the application.
    ///   - forwarding: the documents and URLs this launch was asked to open.
    ///   - options: the platform's options; its `singleInstance` is replaced by the claim.
    public static func launchingSingleInstance(id: String, forwarding: [String],
                                               options: Options = .default) throws -> SDLPlatform? {
        var options = options
        switch SingleInstance.claim(id: id, forwarding: forwarding) {
        case .primary(let instance):
            options.singleInstance = instance
        case .forwarded:
            return nil
        case .unavailable:
            options.singleInstance = nil
        }
        return try SDLPlatform(options: options)
    }
}
#endif
