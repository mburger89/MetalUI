/// Which of the two colour environments the host is presenting (spec §7.9).
///
/// It lives in `MetalUICore` rather than in `MetalUIPlatform` or `MetalUI`
/// because both of those need to name it and the dependency edge runs one way:
/// `MetalUIPlatform` *reports* it (`PlatformWindow.appearance`) and `MetalUI`
/// *consumes* it (`Theme.forAppearance(_:)`). A copy in each would be two types
/// that have to be kept in step by hand.
///
/// **Two cases and no `system` case.** "Follow the system" is not a third
/// appearance an element could paint — it is the *absence* of an override, and
/// it resolves to one of these two before any colour is chosen. A third case
/// would have to be mapped to one of the other two at every use site, which is
/// how a token ends up resolved differently in two places.
public enum Appearance: Sendable, Hashable, CaseIterable {
    case light
    case dark
}
