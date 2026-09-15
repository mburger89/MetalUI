#if os(macOS)
import AppKit
import MetalUICore

// SKELETON (lane 2 red run): the API the tests compile against, with inert
// bodies. No `MetalHostView` override exists yet, so the host view is a plain
// `NSView` to every client.

@MainActor protocol AccessibilityNotificationPosting: AnyObject {
    func post(_ notification: NSAccessibility.Notification, for element: Any)
}

@MainActor final class SystemAccessibilityNotificationPoster: AccessibilityNotificationPosting {
    func post(_ notification: NSAccessibility.Notification, for element: Any) {}
}

@MainActor protocol AccessibilityClientSignal: AnyObject {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void)
}

@MainActor final class VoiceOverSignal: AccessibilityClientSignal {
    func observe(_ handler: @escaping @MainActor (Bool) -> Void) {}
}

@MainActor final class AppKitAccessibilityBridge {
    weak var hostView: NSView?
    var poster: any AccessibilityNotificationPosting
    var onRequest: ((AccessibilityRequest) -> Bool)?
    private let signal: any AccessibilityClientSignal

    private(set) var isActive = false
    private(set) var tree = AccessibilityTree.empty
    private(set) var elements: [AccessibilityNodeID: AppKitAccessibilityElement] = [:]
    private(set) var parents: [AccessibilityNodeID: AccessibilityNodeID] = [:]
    private(set) var createdElementCount = 0
    private(set) var structuralPublishCount = 0
    private(set) var geometryPublishCount = 0

    init(signal: any AccessibilityClientSignal, poster: any AccessibilityNotificationPosting) {
        self.signal = signal
        self.poster = poster
    }

    func activateIfNeeded() {}
    func publish(_ tree: AccessibilityTree) {}
    func element(for id: AccessibilityNodeID) -> AppKitAccessibilityElement {
        AppKitAccessibilityElement(id: id, bridge: self)
    }
    func rootElements() -> [Any] { [] }
    func hitTest(screenPoint: NSPoint) -> Any? { nil }
    func focusedElement() -> Any? { nil }
    func screenFrame(forContentRect rect: Bounds<Pixels>) -> NSRect { .zero }
}

@MainActor final class AppKitAccessibilityElement: NSAccessibilityElement {
    let id: AccessibilityNodeID
    weak var bridge: AppKitAccessibilityBridge?
    private(set) var isDetached = false

    init(id: AccessibilityNodeID, bridge: AppKitAccessibilityBridge) {
        self.id = id
        self.bridge = bridge
        super.init()
    }
}
#endif
