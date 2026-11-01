import MetalUICore
import MetalUILayout

// `Section` and `pinnedViews:` for the lazy stacks (item R3-4, rulings `SP-G`...`SP-J`; probe
// `docs/probes/swiftui-scroll-position.swift` arms V, W, H, O).

/// Which of a lazy stack's section views stay at the scroll viewport's edge while their section is on screen,
/// SwiftUI's `PinnedScrollableViews` (`SP-G`).
public struct PinnedScrollableViews: OptionSet, Sendable {
    /// The raw bits.
    public let rawValue: Int

    /// The option set with these bits.
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Each section's header stays at the leading edge of the viewport while the viewport's leading edge is inside
    /// its section (probe V1: header 0 at 0 at offsets 100 and 230 where the unpinned control read -100, -230).
    public static let sectionHeaders = PinnedScrollableViews(rawValue: 1 << 0)

    /// Each section's footer stays at the trailing edge of the viewport while the viewport's trailing edge is
    /// inside its section.
    public static let sectionFooters = PinnedScrollableViews(rawValue: 1 << 1)
}

/// SwiftUI's `Section`: a header, content and a footer that a stack lays out in that order, and that a lazy
/// stack's `pinnedViews:` can pin (`SP-G`).
///
/// ```swift
/// ProposalScrollView {
///     LazyVStack(spacing: Pixels(0), pinnedViews: [.sectionHeaders]) {
///         ForEach(groups) { group in
///             Section {
///                 ForEach(group.rows) { RowView($0) }
///             } header: {
///                 HeaderView(group)
///             }
///         }
///     }
/// }
/// ```
///
/// A section is **transparent**: it takes the cursor indices of its three parts in order, adds no node and no
/// identity of its own, so in an ordinary stack it is its header, content and footer in sequence. Inside a
/// ``LazyVStack`` or ``LazyHStack`` whose content is otherwise lazy it is read as units - one per header member,
/// one per content element, one per footer member - so a section of 100 000 rows stays windowed. Not for
/// `List` (a `List` takes rows).
public struct Section<Header: ProposalElementGroup, Content: ProposalElementGroup,
                      Footer: ProposalElementGroup>: ProposalElementGroup {
    var header: Header
    var content: Content
    var footer: Footer

    /// A section of `content` with a header and a footer: SwiftUI's `Section(content:header:footer:)`, written
    /// `Section { rows } header: { ... } footer: { ... }`. (The value forms `Section(header: Text("x"))`, deprecated
    /// in SwiftUI, are not offered: a legacy `Text` is not proposal content; write the closure.)
    public init(@ProposalContentBuilder content: () -> Content,
                @ProposalContentBuilder header: () -> Header,
                @ProposalContentBuilder footer: () -> Footer) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    /// The layout phase's result: each part's own.
    public struct Layout {
        var header: Header.GroupLayout
        var content: Content.GroupLayout
        var footer: Footer.GroupLayout
    }

    /// The prepaint phase's result: each part's own.
    public struct Prepaint {
        var header: Header.GroupPrepaint
        var content: Content.GroupPrepaint
        var footer: Footer.GroupPrepaint
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Layout) {
        let (h, hl) = header.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        let (c, cl) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        let (f, fl) = footer.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (h + c + f, Layout(header: hl, content: cl, footer: fl))
    }

    public mutating func prepaintGroup(layout: inout Layout, pass: inout PrepaintPass) -> Prepaint {
        Prepaint(header: header.prepaintGroup(layout: &layout.header, pass: &pass),
                 content: content.prepaintGroup(layout: &layout.content, pass: &pass),
                 footer: footer.prepaintGroup(layout: &layout.footer, pass: &pass))
    }

    public mutating func paintGroup(layout: inout Layout, prepaint: inout Prepaint, pass: inout PaintPass) {
        header.paintGroup(layout: &layout.header, prepaint: &prepaint.header, pass: &pass)
        content.paintGroup(layout: &layout.content, prepaint: &prepaint.content, pass: &pass)
        footer.paintGroup(layout: &layout.footer, prepaint: &prepaint.footer, pass: &pass)
    }

    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                                    pass: inout LayoutPass) -> ([ProposalNodeID], Layout) {
        let (h, hl) = header.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        let (c, cl) = content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        let (f, fl) = footer.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (h + c + f, Layout(header: hl, content: cl, footer: fl))
    }
}

extension Section where Footer == EmptyGroup {
    /// A section with a header: SwiftUI's `Section(content:header:)`.
    public init(@ProposalContentBuilder content: () -> Content,
                @ProposalContentBuilder header: () -> Header) {
        self.init(content: content, header: header, footer: { EmptyGroup() })
    }

}

extension Section where Header == EmptyGroup {
    /// A section with a footer: SwiftUI's `Section(content:footer:)`.
    public init(@ProposalContentBuilder content: () -> Content,
                @ProposalContentBuilder footer: () -> Footer) {
        self.init(content: content, header: { EmptyGroup() }, footer: footer)
    }

}

extension Section where Header == EmptyGroup, Footer == EmptyGroup {
    /// A section of `content` alone: SwiftUI's `Section(content:)`.
    public init(@ProposalContentBuilder content: () -> Content) {
        self.init(content: content, header: { EmptyGroup() }, footer: { EmptyGroup() })
    }
}

// MARK: lazy reading

/// What part of its section a source is (`SP-H`).
enum LazySectionRole { case header, content, footer }

/// A unit source that belongs to a section: the inner source's units, tagged with the section's id (the index of
/// its first source) and the part, so a lazy stack can find a unit's section header or footer.
@MainActor
struct LazyRoleSource: LazyUnitSource {
    let inner: any LazyUnitSource
    let section: Int
    let role: LazySectionRole

    var lazyUnitCount: Int { inner.lazyUnitCount }
    func lazyUnitID(_ unit: Int) -> AnyHashable { inner.lazyUnitID(unit) }
    func beginLazyFrame(slot: GlobalElementID, pass: inout LayoutPass) { inner.beginLazyFrame(slot: slot, pass: &pass) }
    func realizeLazyUnit(_ unit: Int, globalIndex: Int, segment: Int, parent: GlobalElementID,
                         cursorBase: Int, pass: inout LayoutPass) -> LazyUnitBox {
        inner.realizeLazyUnit(unit, globalIndex: globalIndex, segment: segment, parent: parent,
                              cursorBase: cursorBase, pass: &pass)
    }
}

/// A group that is a section (`Section`), read by a `ForEach` of them.
@MainActor
protocol LazySectionContent {
    func lazyFlattenSection(into sources: inout [any LazyUnitSource]) -> Bool
}

extension Section: LazySectionContent {
    func lazyFlattenSection(into sources: inout [any LazyUnitSource]) -> Bool { lazyFlatten(into: &sources) }
}

/// A unit's id inside a `ForEach` of sections: the section's id, the part (source) of the section, and the
/// part's own id for the unit - unique across sections although a row id repeats in every one (`SP-H`).
struct LazySectionedUnitID: Hashable {
    let section: AnyHashable
    let part: Int
    let inner: AnyHashable
}

/// A `ForEach` over data whose elements are ``Section``s, read as the units of every section in order
/// (`SP-H`). The content closure runs once per element to count the units, each frame the container is laid
/// out: the figure is O(sections), never O(rows) - rows are the inner `ForEach`'s units, realised only inside
/// the window.
@MainActor
struct LazySectionForEachSource<Data: RandomAccessCollection, ID: Hashable, Content: ProposalElementGroup>: LazyUnitSource {
    let forEach: ForEach<Data, ID, Content>

    /// One section: its element id, its parts and the first unit of each part.
    struct Built {
        var key: ID
        var parts: [any LazyUnitSource]
        var starts: [Int]
        var count: Int { starts[starts.count - 1] }
    }
    let sections: [Built]
    /// Each section's first unit, ascending, with the total last.
    let prefix: [Int]

    init?(forEach: ForEach<Data, ID, Content>) {
        self.forEach = forEach
        var built: [Built] = []
        var prefix: [Int] = []
        var total = 0
        for element in forEach.data {
            guard let section = forEach.content(element) as? any LazySectionContent else { return nil }
            var parts: [any LazyUnitSource] = []
            guard section.lazyFlattenSection(into: &parts) else { return nil }
            var starts: [Int] = []
            var inner = 0
            for part in parts { starts.append(inner); inner += part.lazyUnitCount }
            starts.append(inner)
            prefix.append(total)
            total += inner
            built.append(Built(key: element[keyPath: forEach.idKeyPath], parts: parts, starts: starts))
        }
        prefix.append(total)
        self.sections = built
        self.prefix = prefix
    }

    var lazyUnitCount: Int { prefix[prefix.count - 1] }

    /// The section holding `unit` and the part and part-local unit in it.
    private func locate(_ unit: Int) -> (section: Int, part: Int, local: Int) {
        var low = 0, high = sections.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if prefix[middle] <= unit { low = middle } else { high = middle - 1 }
        }
        var section = low
        while section + 1 < sections.count, prefix[section + 1] <= unit { section += 1 }
        let within = unit - prefix[section]
        let starts = sections[section].starts
        var part = 0
        while part + 1 < sections[section].parts.count, starts[part + 1] <= within { part += 1 }
        return (section, part, within - starts[part])
    }

    func lazyUnitID(_ unit: Int) -> AnyHashable {
        let (section, part, local) = locate(unit)
        return AnyHashable(LazySectionedUnitID(section: AnyHashable(sections[section].key), part: part,
                                               inner: sections[section].parts[part].lazyUnitID(local)))
    }

    func lazyScrollID(_ unit: Int) -> AnyHashable {
        let (section, part, local) = locate(unit)
        let inner = sections[section].parts[part].lazyScrollID(local)
        // A header is the section's own target; a static member (footer) is none.
        if let tagged = sections[section].parts[part] as? LazyRoleSource, tagged.role == .header {
            return AnyHashable(sections[section].key)
        }
        return inner
    }

    func beginLazyFrame(slot: GlobalElementID, pass: inout LayoutPass) {
        pass.frame.stateTable.noteWindowedParent(slot)   // `LZ-H`; never `noteLoop`
    }

    func realizeLazyUnit(_ unit: Int, globalIndex: Int, segment: Int, parent: GlobalElementID,
                         cursorBase: Int, pass: inout LayoutPass) -> LazyUnitBox {
        let (index, part, local) = locate(unit)
        let built = sections[index]
        let slot = GlobalElementID(component: .positional(cursorBase), parent: parent)
        let needsKey = !(ID.self is DescriptionInjectiveID.Type)   // `FI-B`
        let scope = GlobalElementID.child(
            of: slot, at: index,
            name: ElementID(name: String(describing: built.key),
                            key: needsKey ? IdentityKey(AnyHashable(built.key)) : nil))
        pass.frame.stateTable.noteNamed(scope, at: index)
        pass.frame.forEachIdentityWork.elements += 1
        if needsKey { pass.frame.forEachIdentityWork.keyed += 1 }
        built.parts[part].beginLazyFrame(
            slot: GlobalElementID(component: .positional(part), parent: scope), pass: &pass)
        let box = built.parts[part].realizeLazyUnit(local, globalIndex: globalIndex, segment: part, parent: scope,
                                                    cursorBase: part, pass: &pass)
        return box
    }

    /// The sections' spans in the table, given this source's first unit (`SP-H`).
    func spans(startingAt first: Int) -> [LazySectionSpan] {
        sections.indices.compactMap { index in
            let built = sections[index]
            guard built.count > 0 else { return nil }
            let base = first + prefix[index]
            var header: Range<Int>?, footer: Range<Int>?
            func merged(_ old: Range<Int>?, _ new: Range<Int>) -> Range<Int> {
                old.map { $0.lowerBound..<new.upperBound } ?? new
            }
            for (part, source) in built.parts.enumerated() {
                guard let tagged = source as? LazyRoleSource else { continue }
                let range = (base + built.starts[part])..<(base + built.starts[part + 1])
                if tagged.role == .header { header = merged(header, range) }
                if tagged.role == .footer { footer = merged(footer, range) }
            }
            let end = base + built.count
            let header2 = header ?? (base..<base), footer2 = footer ?? (end..<end)
            return LazySectionSpan(header: header2, footer: footer2, all: base..<(base + built.count))
        }
    }
}

extension Section: LazyFlattenable {
    func lazyFlatten(into sources: inout [any LazyUnitSource]) -> Bool {
        var parts: [[any LazyUnitSource]] = [[], [], []]
        guard lazyFlattenMember(header, into: &parts[0]), lazyFlattenMember(content, into: &parts[1]),
              lazyFlattenMember(footer, into: &parts[2]) else { return false }
        let id = sources.count
        for (part, role) in zip(parts, [LazySectionRole.header, .content, .footer]) {
            for source in part { sources.append(source is LazyRoleSource ? source : LazyRoleSource(inner: source, section: id, role: role)) }
        }
        return true
    }
}

/// A source that holds sections of its own (a `ForEach` of them).
@MainActor
protocol LazySectionSpans {
    func sectionSpans(startingAt first: Int) -> [LazySectionSpan]
}

extension LazySectionForEachSource: LazySectionSpans {
    func sectionSpans(startingAt first: Int) -> [LazySectionSpan] { spans(startingAt: first) }
}

/// One section's units: the half-open ranges of global unit indices.
struct LazySectionSpan {
    var header: Range<Int>
    var footer: Range<Int>
    var all: Range<Int>
}

extension LazyUnitTable {
    /// The sections of the table, ascending by unit (`SP-H`); empty when no member is in a `Section`.
    func sectionSpans() -> [LazySectionSpan] {
        var order: [Int] = []
        var header: [Int: Range<Int>] = [:], footer: [Int: Range<Int>] = [:], all: [Int: Range<Int>] = [:]
        func merge(_ range: Range<Int>?, _ new: Range<Int>) -> Range<Int> {
            guard let range else { return new }
            return Swift.min(range.lowerBound, new.lowerBound)..<Swift.max(range.upperBound, new.upperBound)
        }
        var nested: [LazySectionSpan] = []
        for (position, source) in sources.enumerated() {
            if let forEachSource = source as? any LazySectionSpans {
                nested.append(contentsOf: forEachSource.sectionSpans(startingAt: starts[position]))
                continue
            }
            guard let tagged = source as? LazyRoleSource else { continue }
            let units = starts[position]..<starts[position + 1]
            if all[tagged.section] == nil { order.append(tagged.section) }
            all[tagged.section] = merge(all[tagged.section], units)
            if tagged.role == .header { header[tagged.section] = merge(header[tagged.section], units) }
            if tagged.role == .footer { footer[tagged.section] = merge(footer[tagged.section], units) }
        }
        let direct = order.compactMap { id in
            all[id].map { LazySectionSpan(header: header[id] ?? ($0.lowerBound..<$0.lowerBound),
                                          footer: footer[id] ?? ($0.upperBound..<$0.upperBound), all: $0) }
        }
        return (direct + nested).sorted { $0.all.lowerBound < $1.all.lowerBound }
    }
}
