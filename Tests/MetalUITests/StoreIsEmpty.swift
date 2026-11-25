@testable import MetalUI

// The animation, lifecycle, timeline and state stores count their entries but have no `isEmpty`; these let the
// tests that ask "is it empty?" say so (and keep `count == 0` out of them, SwiftLint `empty_count`).
extension AnimationStore { var isEmpty: Bool { count < 1 } }
extension LifecycleStore { var isEmpty: Bool { count < 1 } }
extension TimelineStore { var isEmpty: Bool { count < 1 } }
extension StateTable { var isEmpty: Bool { count < 1 } }
