import MetalUICore
import MetalUILayout

// RED STUB (replaced by the implementation commit): the spellings exist and change nothing.

extension ElementGroup {
    public func presentationBackground(_ color: Color) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .transform { _ in })
    }
    @_disfavoredOverload
    public func presentationBackground(_ token: ColorToken) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .transform { _ in })
    }
    public func presentationBackground(_ material: Material) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .transform { _ in })
    }
    public func presentationBackground(_ gradient: LinearGradient) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .transform { _ in })
    }
    public func presentationBackground(_ gradient: RadialGradient) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .transform { _ in })
    }
    public func presentationBackground<Background: ElementGroup>(
        alignment: ProposalAlignment = .center, @ProposalContentBuilder content: () -> Background
    ) -> EnvironmentScope<Self> {
        EnvironmentScope(content: self, write: .transform { _ in })
    }
}
