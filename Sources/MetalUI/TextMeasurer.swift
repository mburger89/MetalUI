import MetalUICore
import MetalUILayout
import MetalUITextSystem

/// The frame's text system, carried by value through the environment so a
/// ``TextMeasurer`` can reach it from a `Component` (ruling GT-D). Internal: the
/// root stamps it and a `\.self` reset puts it back, as `theme`.
final class TextSystemBox {
    let system: any TextSystem
    init(_ system: any TextSystem) { self.system = system }
}

/// Measures a text without laying anything out — SwiftUI's
/// `GraphicsContext.resolve(_:)` with the environment as the carrier (rulings
/// GT-B, GT-C, GT-D; divergence 296).
///
/// Read it from the environment, resolve a ``Text`` or ``ProposalText``, ask
/// the resolved value for a size:
///
/// ```swift
/// @Environment(\.textMeasurer) var measurer
/// let size = measurer.resolve(Text("12.5 mm")).measure(in: Size(width: .infinity, height: .infinity))
/// ```
///
/// The answer is the size a `Text` is laid out at under the same proposal and
/// environment: it calls the function layout calls, through `resolveTextStyle`
/// over the environment at the reading element and the frame's text system.
/// It places no node, records no state and shapes only through the text
/// system's own caches. There is no public initialiser; the frame stamps one.
public struct TextMeasurer {
    let box: TextSystemBox?
    let environment: EnvironmentValues

    init(box: TextSystemBox?, environment: EnvironmentValues) {
        self.box = box
        self.environment = environment
    }

    /// What a memoized component that reads this measurer depends on (`CF-A`): the text system instance (the frame's
    /// box is new every frame) and the styles a default request resolves to here.
    var reading: TextMeasurerReading {
        TextMeasurerReading(
            system: box.map { ObjectIdentifier($0.system) },
            inherited: resolveTextStyle(TextStyleRequest(), in: environment),
            defaulted: resolveTextStyle(TextStyleRequest(font: .defaultFont), in: environment))
    }

    private var system: any TextSystem {
        guard let box else {
            preconditionFailure("EnvironmentValues.textMeasurer read where no frame stamped a text system: a measurer needs one (ruling GT-D)")
        }
        return box.system
    }

    /// Resolves `text` in this measurer's environment: its font, weight, italic
    /// and rich runs fixed now (SwiftUI's `GraphicsContext.resolve(_:)`).
    @MainActor
    public func resolve(_ text: Text) -> ResolvedText {
        resolved(content: text.content, own: text.styleRequest, rich: text.rich)
    }

    /// Resolves `text` in this measurer's environment (the proposal-layout
    /// spelling of ``resolve(_:)-(Text)``).
    @MainActor
    public func resolve(_ text: ProposalText) -> ResolvedText {
        resolved(content: text.content, own: text.styleRequest, rich: text.rich)
    }

    @MainActor
    private func resolved(content: TextContent, own: TextStyleRequest, rich: TextRichFields) -> ResolvedText {
        let system = self.system
        guard let plain = plainTextForm(content, own: own, rich: rich) else {
            return ResolvedText(system: system,
                                form: .rich(resolveRichText(content, own: own, rich: rich, in: environment,
                                                            system: system)))
        }
        let style = resolveTextStyle(plain.request, in: environment)
        return ResolvedText(system: system,
                            form: .plain(string: plain.string, key: system.resolveFont(style.descriptor), style: style))
    }

    /// A text with its style resolved, ready to be measured (SwiftUI's
    /// `GraphicsContext.ResolvedText`).
    public struct ResolvedText {
        enum Form {
            case plain(string: String, key: FontKey, style: ResolvedTextStyle)
            case rich(ResolvedRichText)
        }
        let system: any TextSystem
        let form: Form

        /// The size the text is laid out at under `proposal` (SwiftUI's
        /// `ResolvedText.measure(in:)`): a finite width wraps it, a finite height
        /// caps its lines, an infinite or non-positive-infinite axis is
        /// unbounded. The empty string is 0 by 0 (divergence 295).
        @MainActor
        public func measure(in proposal: Size<Pixels>) -> Size<Pixels> {
            let width = Double(proposal.width.value), height = Double(proposal.height.value)
            let asked = ProposedSize(width: width.isFinite ? width : nil, height: height.isFinite ? height : nil)
            let answer: LayoutMeasurement
            switch form {
            case .plain(let string, let key, let style):
                answer = proposalTextMeasurement(string, font: key, system: system, proposal: asked, style: style)
            case .rich(let rich):
                answer = richTextMeasurement(rich, system: system, proposal: asked)
            }
            return Size(width: Pixels(Float(answer.size.width)), height: Pixels(Float(answer.size.height)))
        }
    }
}

extension EnvironmentValues {
    /// The text measurer for the element reading it (MetalUI-only, divergence
    /// 296): get-only, the environment at the reading point plus the frame's text
    /// system. A value read from a bare `EnvironmentValues()` has no system and
    /// traps when it resolves a text (ruling GT-D).
    public var textMeasurer: TextMeasurer {
        TextMeasurer(box: textSystemBox, environment: self)
    }
}

/// The comparable reading of a ``TextMeasurer`` (`CF-A`, `EnvironmentReading`).
struct TextMeasurerReading: Equatable {
    let system: ObjectIdentifier?
    let inherited: ResolvedTextStyle
    let defaulted: ResolvedTextStyle
}
